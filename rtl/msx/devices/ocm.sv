// OCM device
//
// Copyright (c) 2024-2025 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//


// OCM (1chipMSX) system device, after OCM-PLD swioports.vhd (MSX_MiSTer):
// - IPL phase: from reset until the first write to PPI port A8h (ipl_en, OCM ff_ldbios_n);
// - switched I/O ports 40h-4Fh, ID 212 (1chipMSX) and ID 008 (5.37 MHz turbo);
// - virtual DIP-SW (ff_dip_req, OCM order: 0 turbo, 2:1 display, 3 slot1, 5:4 slot2,
//   6 mapper 4096 kB, 7 MegaSD), lock mask, smart commands, warm / cold reset request.
// Not implemented: LEDs, display modes, audio presets, VDP options (values are kept
// and read back only).
module dev_ocm
(
    cpu_bus_if.device_mp     cpu_bus,
    clock_bus_if.base_mp     clock_bus,
    input  MSX::io_device_t  io_device[3],          // [0]: OCM_BOOT present
    input              [7:0] ff_dip_req,            // DIP-SW from OSD, 1 = on
    output logic       [7:0] data,
    output logic             ipl_en,                // IPL ROM visible (mapper OCM_IPL)
    output                   jis2_en,               // kanji JIS2 (DA-DBh): 1 without OCM
    output                   mapper_limit,          // 1 = RAM mapper limited to 2048 kB
    output                   megaSD_enable,
    output logic             Slot1Mode,             // 1 = internal SCC-I in slot 1
    output logic       [1:0] Slot2Mode,             // 00 ext, 10 SCC-I, 01 ASCII8K, 11 ASCII16K
    output                   rst_key_lock,
    output logic             swio_reset             // reset request (smart commands 251-254)
);

    localparam logic [7:0] ID212 = 8'b0010_1011;    // port 40h read value, written as D4h
    localparam logic [7:0] ID008 = 8'b1111_0111;    // written as 08h
    localparam logic [7:0] OCM_PLD_XY = 8'd38;      // OCM-PLD v3.8
    localparam logic [1:0] OCM_PLD_Z  = 2'd0;
    localparam logic [4:0] SWIO_REV   = 5'd9;
    localparam logic       DEF_KMAP   = 1'b1;       // default keyboard: 1 = non-Japanese

    wire present = io_device[0].enable;
    wire io_sel  = present && cpu_bus.iorq && ~cpu_bus.m1 && cpu_bus.addr[7:4] == 4'h4;
    wire io_wr   = io_sel && cpu_bus.wr && cpu_bus.req;
    wire [3:0] port = cpu_bus.addr[3:0];
    wire [7:0] dbo  = cpu_bus.data;

    logic [7:0] io40_n, io41_id212_n, io42_id212, io43_id212, io44_id212, ff_dip_ack;
    logic [7:0] vram_slot_ids;
    logic [3:0] CustomSpeed;
    logic [2:0] OpllVol, SccVol, PsgVol, MstrVol;
    logic       Mapper_req, Mapper_ack, MegaSD_req, MegaSD_ack;
    logic       io41_id008_n, tPanaRedir, tMegaSD, VdpSpeedMode, swioKmap, RstReq_sta;
    logic       JIS2_ena, portF4_mode;
    logic       warm;                               // current / pending reset is a warm one

    wire id212 = io40_n == ID212;
    wire cmd_wr = io_wr && port == 4'h1 && id212;   // smart command
    wire [7:0] slot_cmd  = dbo - 8'd13;             // commands 13..20: io42[5:3]
    wire [3:0] speed_cmd = 4'd12 - dbo[3:0];        // commands 4..10: CustomSpeed 1000..0010

    assign mapper_limit  = ~Mapper_ack;
    assign megaSD_enable = MegaSD_ack;
    assign rst_key_lock  = io43_id212[5];
    assign jis2_en       = ~present || JIS2_ena;     // IPL: 0 for a 384 kB BIOS (JIS1 only)

    // IPL phase: reset .. first write to A8h
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset)
            ipl_en <= present;
        else if (cpu_bus.iorq && ~cpu_bus.m1 && cpu_bus.wr && cpu_bus.req && cpu_bus.addr[7:0] == 8'hA8)
            ipl_en <= 1'b0;
    end

    // Reset request: held long enough for the CPU (clock enable) to see it.
    // 'warm' stays set through the reset, cleared once the reset is over.
    logic [7:0] rst_cnt;
    always_ff @(posedge cpu_bus.clk) begin
        if (cmd_wr && (dbo == 8'd251 || dbo == 8'd252 || dbo == 8'd253 || dbo == 8'd254)) begin
            swio_reset <= 1'b1;
            rst_cnt    <= '1;
            warm       <= dbo != 8'd251;
        end else if (swio_reset) begin
            if (rst_cnt == '0) swio_reset <= 1'b0;
            else               rst_cnt    <= rst_cnt - 1'b1;
        end else if (~cpu_bus.reset) begin
            warm <= 1'b0;
        end
    end

    initial begin
        swio_reset   = 1'b0;
        warm         = 1'b0;
        io41_id212_n = '1;
        Slot1Mode    = 1'b0;
        Slot2Mode    = 2'b00;
        JIS2_ena     = 1'b1;
    end

    // Slot modes follow the virtual DIP-SW at 10 Hz (OCM 'virtual DIP-SW assignment')
    always_ff @(posedge clock_bus.clk) begin
        if (clock_bus.ce_10hz) begin
            Slot1Mode    <= io42_id212[3];
            Slot2Mode[1] <= io42_id212[4];
            Slot2Mode[0] <= io42_id212[5];
        end
    end

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            io40_n        <= '1;
            vram_slot_ids <= 8'h10;
            if (~warm) begin                        // cold reset
                io42_id212   <= ff_dip_req;
                ff_dip_ack   <= ff_dip_req;
                io43_id212   <= '0;
                io44_id212   <= '0;
                OpllVol      <= 3'b111;
                SccVol       <= 3'b111;
                PsgVol       <= 3'b111;
                MstrVol      <= 3'b000;
                CustomSpeed  <= 4'b0010;
                tMegaSD      <= 1'b1;
                tPanaRedir   <= 1'b0;
                VdpSpeedMode <= 1'b0;
                Mapper_req   <= ff_dip_req[6];
                Mapper_ack   <= ff_dip_req[6];
                MegaSD_req   <= ff_dip_req[7];
                MegaSD_ack   <= ff_dip_req[7];
                io41_id008_n <= 1'b1;
                swioKmap     <= DEF_KMAP;
            end else begin                          // warm reset: requested states take effect
                io42_id212[6] <= Mapper_req;
                Mapper_ack    <= Mapper_req;
                io42_id212[7] <= MegaSD_req;
                MegaSD_ack    <= MegaSD_req;
            end
        end else begin
            RstReq_sta <= Mapper_req != io42_id212[6] || MegaSD_req != io42_id212[7];

            // Physical DIP-SW (OSD) changes, unless locked
            if (ff_dip_req[0] != ff_dip_ack[0] && ~io43_id212[0]) begin   // turbo
                io41_id008_n  <= 1'b1;
                io42_id212[0] <= ff_dip_req[0];
                ff_dip_ack[0] <= ff_dip_req[0];
            end
            for (int i = 1; i <= 2; i++)                                   // display
                if (ff_dip_req[i] != ff_dip_ack[i] && ~io43_id212[1]) begin
                    io42_id212[i] <= ff_dip_req[i];
                    ff_dip_ack[i] <= ff_dip_req[i];
                end
            if (ff_dip_req[3] != ff_dip_ack[3] && ~io43_id212[3]) begin   // slot 1
                io42_id212[3] <= ff_dip_req[3];
                ff_dip_ack[3] <= ff_dip_req[3];
            end
            for (int i = 4; i <= 5; i++)                                   // slot 2
                if (ff_dip_req[i] != ff_dip_ack[i] && ~io43_id212[4]) begin
                    io42_id212[i] <= ff_dip_req[i];
                    ff_dip_ack[i] <= ff_dip_req[i];
                end
            if (ff_dip_req[6] != ff_dip_ack[6] && ~io43_id212[6]) begin   // mapper
                Mapper_req    <= ff_dip_req[6];
                ff_dip_ack[6] <= ff_dip_req[6];
            end
            if (ff_dip_req[7] != ff_dip_ack[7] && ~io43_id212[7]) begin   // MegaSD
                MegaSD_req    <= ff_dip_req[7];
                ff_dip_ack[7] <= ff_dip_req[7];
            end

            // Port 40h: device ID
            if (io_wr && port == 4'h0)
                case (dbo)
                    8'h08:   io40_n <= ID008;
                    8'hD4:   io40_n <= ID212;
                    default: io40_n <= '1;
                endcase

            // Port 41h ID008: 5.37 MHz turbo (write_n)
            if (io_wr && port == 4'h1 && io40_n == ID008) begin
                if (~tPanaRedir) begin
                    io41_id008_n  <= dbo[0];
                    io42_id212[0] <= 1'b0;
                end else begin
                    io41_id008_n  <= 1'b1;
                    io42_id212[0] <= ~dbo[0];
                end
            end

            // Port 41h ID212: smart commands
            if (cmd_wr) begin
                io41_id212_n <= ~dbo;
                case (dbo)
                    8'd1:  tPanaRedir <= 1'b0;
                    8'd2:  tPanaRedir <= 1'b1;
                    8'd3:  begin io41_id008_n <= 1'b1; io42_id212[0] <= 1'b0; end
                    8'd4, 8'd5, 8'd6, 8'd7, 8'd8, 8'd9, 8'd10: begin       // custom speed 1..7
                        io41_id008_n  <= 1'b1;
                        io42_id212[0] <= 1'b1;
                        CustomSpeed   <= speed_cmd;
                    end
                    8'd11: tMegaSD <= 1'b0;
                    8'd12: tMegaSD <= 1'b1;
                    8'd13, 8'd14, 8'd15, 8'd16, 8'd17, 8'd18, 8'd19, 8'd20:
                           io42_id212[5:3] <= slot_cmd[2:0];               // slot 1 / slot 2 modes
                    8'd21: swioKmap <= 1'b0;
                    8'd22: swioKmap <= 1'b1;
                    8'd23: io42_id212[2:1] <= 2'b00;
                    8'd24: io42_id212[2:1] <= 2'b10;
                    8'd25: io42_id212[2:1] <= 2'b01;
                    8'd26: io42_id212[2:1] <= 2'b11;
                    8'd27: VdpSpeedMode <= 1'b0;
                    8'd28: VdpSpeedMode <= 1'b1;
                    8'd29: MegaSD_req <= 1'b0;
                    8'd30: MegaSD_req <= 1'b1;
                    8'd36: begin                                            // mute
                        OpllVol <= 3'b000; SccVol <= 3'b000; PsgVol <= 3'b000; MstrVol <= 3'b000;
                    end
                    8'd37: begin                                            // original volume
                        OpllVol <= 3'b110; SccVol <= 3'b110; PsgVol <= 3'b011; MstrVol <= 3'b000;
                    end
                    8'd38: begin                                            // default volume
                        OpllVol <= 3'b111; SccVol <= 3'b111; PsgVol <= 3'b111; MstrVol <= 3'b000;
                    end
                    // odd code = locked, even = unlocked
                    8'd41, 8'd42: io43_id212[0]   <= dbo[0];              // turbo lock
                    8'd43, 8'd44: io43_id212[1]   <= dbo[0];              // display lock
                    8'd45, 8'd46: io43_id212[2]   <= dbo[0];              // audio / CMT lock
                    8'd47, 8'd48: io43_id212[3]   <= dbo[0];              // slot 1 lock
                    8'd49, 8'd50: io43_id212[4]   <= dbo[0];              // slot 2 lock
                    8'd51, 8'd52: io43_id212[4:3] <= {2{dbo[0]}};         // slot 1 + 2 lock
                    8'd53, 8'd54: io43_id212[5]   <= dbo[0];              // reset key lock
                    8'd55, 8'd56: io43_id212[6]   <= dbo[0];              // mapper lock
                    8'd57, 8'd58: io43_id212[7]   <= dbo[0];              // MegaSD lock
                    8'd59: io43_id212 <= '1;
                    8'd60: io43_id212 <= '0;
                    8'd176, 8'd177, 8'd178, 8'd179, 8'd180, 8'd181, 8'd182, 8'd183: MstrVol <= ~dbo[2:0];
                    8'd184, 8'd185, 8'd186, 8'd187, 8'd188, 8'd189, 8'd190, 8'd191: PsgVol  <= dbo[2:0];
                    8'd192, 8'd193, 8'd194, 8'd195, 8'd196, 8'd197, 8'd198, 8'd199: SccVol  <= dbo[2:0];
                    8'd200, 8'd201, 8'd202, 8'd203, 8'd204, 8'd205, 8'd206, 8'd207: OpllVol <= dbo[2:0];
                    8'd251, 8'd253: ;                                       // reset: see swio_reset
                    8'd252: Mapper_req <= 1'b0;                             // 2048 kB + warm reset
                    8'd254: Mapper_req <= 1'b1;                             // 4096 kB + warm reset
                    8'd255: begin                                           // system restore
                        io42_id212[5:0] <= ff_dip_req[5:0];
                        ff_dip_ack[5:0] <= ff_dip_req[5:0];
                        io43_id212      <= '0;
                        io44_id212      <= '0;
                        OpllVol <= 3'b111; SccVol <= 3'b111; PsgVol <= 3'b111; MstrVol <= 3'b000;
                        CustomSpeed     <= 4'b0010;
                        tMegaSD         <= 1'b1;
                        tPanaRedir      <= 1'b0;
                        VdpSpeedMode    <= 1'b0;
                        Mapper_req      <= ff_dip_req[6];
                        MegaSD_req      <= ff_dip_req[7];
                        io41_id008_n    <= 1'b1;
                        swioKmap        <= DEF_KMAP;
                    end
                    default: io41_id212_n <= '1;                            // not implemented
                endcase
            end

            // Ports 42h-4Fh ID212 (write_n)
            if (io_wr && id212)
                case (port)
                    4'h2: begin
                        io41_id008_n    <= 1'b1;
                        io42_id212[5:0] <= ~dbo[5:0];
                        Mapper_req      <= ~dbo[6];
                        MegaSD_req      <= ~dbo[7];
                    end
                    4'h3: io43_id212 <= ~dbo;
                    4'h4: io44_id212 <= ~dbo;
                    4'h5: begin PsgVol <= ~dbo[2:0]; MstrVol <= dbo[6:4]; end
                    4'h6: begin OpllVol <= ~dbo[2:0]; SccVol <= ~dbo[6:4]; end
                    4'hD: vram_slot_ids <= ~dbo;
                    4'hE: if (ipl_en) JIS2_ena    <= ~dbo[7];               // reserved to IPL
                    4'hF: if (ipl_en) portF4_mode <= ~dbo[7];
                    default: ;
                endcase
        end
    end

    wire [2:0] speed_lev = 3'b001 - CustomSpeed[2:0];   // custom speed level 1..7

    // Port read
    always_comb begin
        data = 8'hFF;
        if (io_sel && cpu_bus.rd) begin
            if (port == 4'h0)
                data = io40_n;
            else if (io40_n == ID008 && port == 4'h3)
                data = 8'h00;
            else if (id212)
                case (port)
                    4'h1: data = io41_id212_n;
                    4'h2: data = io42_id212;
                    4'h3: data = io43_id212;
                    4'h4: data = io44_id212;
                    4'h5: data = {&MstrVol, ~MstrVol, ~|PsgVol, PsgVol};
                    4'h6: data = {~|SccVol, SccVol, ~|OpllVol, OpllVol};
                    4'h7: data = {MegaSD_req, Mapper_req, VdpSpeedMode, tPanaRedir, tMegaSD, speed_lev};
                    4'h8: data = {1'b1, RstReq_sta, 1'b0, 1'b0, 1'b0, 1'b0, swioKmap, ~io41_id008_n};
                    4'hC: data = ff_dip_req;
                    4'hD: data = vram_slot_ids;
                    4'hE: data = OCM_PLD_XY;
                    4'hF: data = {DEF_KMAP, OCM_PLD_Z, SWIO_REV};
                    default: ;
                endcase
        end
    end

endmodule
