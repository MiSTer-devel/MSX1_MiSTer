// megaram.sv
//
// original megaram.vhd
//   Mega-ROM emulation, ASC8K(8Mbits), ASC16K/SCC+(16Mbits)
//   Revision 2.01
//
// Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//
//
//  modified by t.hara / KdL
//
// rewrite in Verilog and integrated MiserFpga project by Molekula 2024-2025
//

module mapper_megaram (
    cpu_bus_if.device_mp     cpu_bus,
    output MSX::mapper_out_t out,
    input  MSX::block_info_t block_info,
    output MSX::device_bus_t device_out,
    input                    ocm_slot1_mode,
    input              [1:0] ocm_slot2_mode
);

    logic       SccBankL[2], SccBankM[2];
    logic [7:0] SccBank0[2], SccBank1[2], SccBank2[2], SccBank3[2], SccModeA[2], SccModeB[2];

    logic [1:0] SccSel, mapsel;
    logic       cs, DecSccA, DecSccB, Dec1FFE;
    always_comb begin
        case(block_info.typ)
            MAPPER_MEGARAM:     mapsel = block_info.id ? ocm_slot2_mode : {ocm_slot1_mode, 1'b0};
            MAPPER_MEGASCC:     mapsel = 2'b10;
            MAPPER_MEGAASCII8:  mapsel = 2'b01;
            MAPPER_MEGAASCII16: mapsel = 2'b11;
            default: mapsel = 2'b00;
        endcase
    end

    assign cs = cpu_bus.mreq && mapsel != 2'b00;

    assign DecSccA = cpu_bus.addr[15:11] == 5'b10011 && ~SccModeB[block_info.id][5] && SccBank2[block_info.id][5:0] == 6'b111111;
    assign DecSccB = cpu_bus.addr[15:11] == 5'b10111 &&  SccModeB[block_info.id][5] && SccBank3[block_info.id][7];
    assign Dec1FFE = cpu_bus.addr[12:1] == 12'b111111111111;

    always_comb begin
        if (~cpu_bus.addr[8] && ~SccModeB[block_info.id][4] && ~mapsel[0] && (DecSccA || DecSccB)) begin
            SccSel = 2'b10; // memory access (scc_wave)
        end else if (
            (cpu_bus.addr[15:14] == 2'b01  &&  mapsel[0]                  &&                             ~cpu_bus.wr           ) ||   // 4000-7FFFh(R/-, ASC8K/16K)
            (cpu_bus.addr[15:14] == 2'b10  &&  mapsel[0]                  &&                             ~cpu_bus.wr           ) ||   // 8000-BFFFh(R/-, ASC8K/16K)
            (cpu_bus.addr[15:13] == 3'b010 &&  mapsel[0]                  &&  SccBank0[block_info.id][7]                       ) ||   // 4000-5FFFh(R/W, ASC8K/16K)
            (cpu_bus.addr[15:13] == 3'b100 &&  mapsel[0]                  &&  SccBank2[block_info.id][7]                       ) ||   // 8000-9FFFh(R/W, ASC8K/16K)
            (cpu_bus.addr[15:13] == 3'b101 &&  mapsel[0]                  &&  SccBank3[block_info.id][7]                       ) ||   // A000-BFFFh(R/W, ASC8K/16K)
            (cpu_bus.addr[15:13] == 3'b010 && ~SccModeA[block_info.id][6] &&                             ~cpu_bus.wr           ) ||   // 4000-5FFFh(R/-, SCC)
            (cpu_bus.addr[15:13] == 3'b011 &&                                                            ~cpu_bus.wr           ) ||   // 6000-7FFFh(R/-, SCC)
            (cpu_bus.addr[15:13] == 3'b100 && ~DecSccA                    &&                             ~cpu_bus.wr           ) ||   // 8000-9FFFh(R/-, SCC)
            (cpu_bus.addr[15:13] == 3'b101 && ~SccModeA[block_info.id][6] && ~DecSccB &&                 ~cpu_bus.wr           ) ||   // A000-BFFFh(R/-, SCC)
            (cpu_bus.addr[15:13] == 3'b010 &&  SccModeA[block_info.id][4]                                                      ) ||   // 4000-5FFFh(R/W) ESCC-RAM
            (cpu_bus.addr[15:13] == 3'b011 &&  SccModeA[block_info.id][4] && ~Dec1FFE                                          ) ||   // 6000-7FFDh(R/W) ESCC-RAM
            (cpu_bus.addr[15:14] == 2'b01  &&  SccModeB[block_info.id][4]                                                      ) ||   // 4000-7FFFh(R/W) SNATCHER
            (cpu_bus.addr[15:13] == 3'b100 &&  SccModeB[block_info.id][4]                                                      ) ||   // 8000-9FFFh(R/W) SNATCHER
            (cpu_bus.addr[15:13] == 3'b101 &&  SccModeB[block_info.id][4] && ~Dec1FFE                                          )      // A000-BFFDh(R/W) SNATCHER
         ) begin
            SccSel = 2'b01;
         end else begin
            SccSel = 2'b00;
         end
    end


    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Reset bank registers and disable SCC
            SccBank0    <= '{8'h00, 8'h00};
            SccBank1    <= '{8'h01, 8'h01};
            SccBank2    <= '{8'h02, 8'h02};
            SccBank3    <= '{8'h03, 8'h03};
            SccModeA    <= '{'0, '0};
            SccModeB    <= '{'0, '0};
            SccBankL    <= '{'0, '0};
            SccBankM    <= '{'0, '0};
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req && SccSel == 2'b00) begin
                if (~mapsel[0]) begin
                    if (~SccModeB[block_info.id][4]) begin
                        case(cpu_bus.addr[15:11])
                            5'b01010: // Mapped I/O port access on 5000-57FFh ... Bank register write
                                if (~SccModeA[block_info.id][6] && ~SccModeA[block_info.id][4]) SccBank0[block_info.id] <= cpu_bus.data;
                            5'b01110: // Mapped I/O port access on 7000-77FFh ... Bank register write
                                if (~SccModeA[block_info.id][6] && ~SccModeA[block_info.id][4]) SccBank1[block_info.id] <= cpu_bus.data;
                            5'b10010: // Mapped I/O port access on 9000-97FFh ... Bank register write
                                SccBank2[block_info.id] <= cpu_bus.data;
                            5'b10110: // Mapped I/O port access on B000-B7FFh ... Bank register write
                                if (~SccModeA[block_info.id][6] && ~SccModeA[block_info.id][4]) SccBank3[block_info.id] <= cpu_bus.data;
                            default: ;
                        endcase
                    end

                    if (Dec1FFE) begin
                        case(cpu_bus.addr[15:13])
                            3'b011: // Mapped I/O port access on 7FFE-7FFFh ... Register write
                                if (SccModeB[block_info.id][5:4] == 2'b00) SccModeA[block_info.id] <= cpu_bus.data;
                            3'b101: // Mapped I/O port access on BFFE-BFFFh ... Register write
                                if (~SccModeA[block_info.id][6] && ~SccModeA[block_info.id][4]) SccModeB[block_info.id] <= cpu_bus.data;
                            default:;
                        endcase
                    end
                end else begin
                    if (cpu_bus.addr[15:12] == 4'b0110) begin // Mapped I/O port access on 6000-6FFFh ... Bank register write
                        if (mapsel[1]) begin
                            if (~cpu_bus.addr[11]) begin  // ASC16K / 6000-67FFh
                               SccBankL[block_info.id] <= cpu_bus.data[6];
                               SccBank0[block_info.id] <= {cpu_bus.data[7], cpu_bus.data[5:0], 1'b0};
                               SccBank1[block_info.id] <= {cpu_bus.data[7], cpu_bus.data[5:0], 1'b1};
                            end
                        end else begin
                            if (cpu_bus.addr[11]) begin
                                SccBank1[block_info.id] <= cpu_bus.data; // ASC8K / 6800-6FFFh
                            end else begin
                                SccBank0[block_info.id] <= cpu_bus.data; // ASC8K / 6000-67FFh
                            end
                        end
                    end
                    if (cpu_bus.addr[15:12] == 4'b0111) begin // Mapped I/O port access on 7000-7FFFh ... Bank register write
                        if (mapsel[1]) begin
                            if (~cpu_bus.addr[11]) begin //ASC16K / 7000-77FFh
                               SccBankM[block_info.id] <= cpu_bus.data[6];
                               SccBank2[block_info.id] <= {cpu_bus.data[7], cpu_bus.data[5:0], 1'b0};
                               SccBank3[block_info.id] <= {cpu_bus.data[7], cpu_bus.data[5:0], 1'b1};
                            end
                        end else begin
                            if (cpu_bus.addr[11]) begin
                                SccBank3[block_info.id] <= cpu_bus.data; // ASC8K / 7800-7FFFh
                            end else begin
                                SccBank2[block_info.id] <= cpu_bus.data; // ASC8K / 7000-77FFh
                            end
                        end
                    end
                end
            end

        end
    end

    logic [26:0] ram_addr;

    always_comb begin
        case (cpu_bus.addr[14:13])
            2'b00: begin
                ram_addr[26:0] = {6'd0, SccBank2[block_info.id][7:0], cpu_bus.addr[12:0]};
            end
            2'b01: begin
                ram_addr[26:0] = {6'd0, SccBank3[block_info.id][7:0], cpu_bus.addr[12:0]};
            end
            2'b10: begin
                ram_addr[26:0] = {6'd0, SccBank0[block_info.id][7:0], cpu_bus.addr[12:0]};
            end
            2'b11: begin
                ram_addr[26:0] = {6'd0, SccBank1[block_info.id][7:0], cpu_bus.addr[12:0]};
            end
        endcase
        if (mapsel == 2'b01) begin
            ram_addr[20] = 1'b0;
        end else if (mapsel == 2'b11) begin
            ram_addr[20] = cpu_bus.addr[14] ? SccBankL[block_info.id] : SccBankM[block_info.id];
        end
    end

    // Stay inside the RAM block (1 or 2 MB); the OCM slot 1 ESE-SCC has 1 MB (emsx_top Scc1Adr)
    wire [26:0] size_mask = {2'b00, block_info.rom_size} - 27'd1;
    wire        ocm_slot1 = block_info.typ == MAPPER_MEGARAM && !block_info.id;
    wire [26:0] blk_addr  = ram_addr & size_mask & (ocm_slot1 ? 27'h00FFFFF : {27{1'b1}});

    assign device_out.en    = cs && SccSel[1];

    wire oe;

    assign oe         = cs && SccSel == 2'b01 && (cpu_bus.rd || cpu_bus.wr);

    assign out.addr   = oe ? blk_addr : {27{1'b1}};
    assign out.ram_cs = oe;
    assign out.rnw    = ~(cpu_bus.wr && oe);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;
    assign device_out.device_ref = 3'd0;
    assign device_out.we         = 1'b0;
    assign device_out.mode       = cs ? SccModeB[block_info.id][5] : 1'b1;  // SCC+ mode (BFFE bit 5)
    assign device_out.param      = 1'b1;                                     // SCC-I chip

endmodule
