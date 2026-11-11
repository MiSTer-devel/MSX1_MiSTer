// system_memory
//
// Copyright (c) 2025-2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// System memory map: addresses below 2^BRAM_WIDTH live in BRAM, the rest in SDRAM at
// addr - 2^BRAM_WIDTH. Every channel goes through the same map, so CPU, upload, flash
// and NVRAM backup see the same byte at the same system address.
//   msx / upload -> BRAM port A or SDRAM ch1
//   flash        -> BRAM port B or SDRAM ch2   (writes, req held until done)
//   backup       -> BRAM port B or SDRAM ch3   (1-clk req pulse, read / write)
//   wave (OPL4)  -> BRAM port B or SDRAM ch4   (word read / byte write, req held until ack)
module system_memory #(parameter BRAM_WIDTH = 18) (
    input                   clk,
    memory_bus_if.ram_mp    memory_bus_msx,
    memory_bus_if.ram_mp    memory_bus_upload,
    memory_bus_if.ram_mp    memory_bus_flash,
    memory_bus_if.ram_mp    memory_bus_backup,
    memory_bus_if.device_mp memory_bus_sdram_ch1,
    memory_bus_if.device_mp memory_bus_sdram_ch2,
    memory_bus_if.device_mp memory_bus_sdram_ch3,
    wave_bus_if.ram_mp      wave_bus,
    wave_bus_if.device_mp   wave_bus_sdram_ch4,     // ack = ch4_done (level)
    input logic             upload
);

    function automatic logic in_bram(input logic [26:0] a);
        return (BRAM_WIDTH > 0) && (a >> BRAM_WIDTH) == '0;
    endfunction

    function automatic logic [26:0] sdram_addr(input logic [26:0] a);
        return (BRAM_WIDTH == 0) ? a : a - (27'd1 << BRAM_WIDTH);
    endfunction

    logic  [7:0] bram_data, bram_data_b;   // BRAM port A / B read data

    // ---------------- ch1: msx / upload ----------------
    logic [26:0] addr;
    logic  [7:0] data;
    logic  [7:0] q;
    logic        rnw;
    logic        cs;
    logic        bram_cs;
    logic        sdram_cs;

    assign addr = upload ? memory_bus_upload.addr   : memory_bus_msx.addr;
    assign rnw  = upload ? memory_bus_upload.rnw    : memory_bus_msx.rnw;
    assign cs   = upload ? memory_bus_upload.ram_cs : memory_bus_msx.ram_cs;
    assign data = upload ? memory_bus_upload.data   : memory_bus_msx.data;

    assign bram_cs  = cs &&  in_bram(addr);
    assign sdram_cs = cs && ~in_bram(addr);

    assign q = bram_cs ? bram_data : memory_bus_sdram_ch1.q;

    assign memory_bus_sdram_ch1.addr    = sdram_addr(addr);
    assign memory_bus_sdram_ch1.data    = data;
    assign memory_bus_sdram_ch1.rnw     = rnw;
    assign memory_bus_sdram_ch1.ram_cs  = sdram_cs;
    assign memory_bus_sdram_ch1.sram_cs = '0;

    assign memory_bus_upload.q           = memory_bus_upload.ram_cs ? q : '1;
    assign memory_bus_upload.sdram_ready = memory_bus_sdram_ch1.sdram_ready;
    assign memory_bus_upload.sdram_done  = memory_bus_sdram_ch1.sdram_done;

    assign memory_bus_msx.q              = memory_bus_msx.ram_cs    ? q : '1;
    assign memory_bus_msx.sdram_ready    = memory_bus_sdram_ch1.sdram_ready;
    assign memory_bus_msx.sdram_done     = memory_bus_sdram_ch1.sdram_done;

    // ---------------- ch2: flash ----------------
    wire flash_bram = in_bram(memory_bus_flash.addr);
    logic flash_cs_q = 1'b0, flash_bram_done = 1'b0;
    wire flash_bram_wr = memory_bus_flash.ram_cs && ~flash_cs_q && flash_bram && ~memory_bus_flash.rnw;

    always_ff @(posedge clk) begin
        flash_cs_q <= memory_bus_flash.ram_cs;
        if (~memory_bus_flash.ram_cs) flash_bram_done <= 1'b0;
        else if (flash_bram_wr)       flash_bram_done <= 1'b1;
    end

    assign memory_bus_sdram_ch2.addr    = sdram_addr(memory_bus_flash.addr);
    assign memory_bus_sdram_ch2.data    = memory_bus_flash.data;
    assign memory_bus_sdram_ch2.rnw     = memory_bus_flash.rnw;
    assign memory_bus_sdram_ch2.ram_cs  = memory_bus_flash.ram_cs && ~flash_bram;
    assign memory_bus_sdram_ch2.sram_cs = '0;

    assign memory_bus_flash.q           = flash_bram ? bram_data_b : memory_bus_sdram_ch2.q;
    assign memory_bus_flash.sdram_ready = flash_bram ? 1'b1            : memory_bus_sdram_ch2.sdram_ready;
    assign memory_bus_flash.sdram_done  = flash_bram ? flash_bram_done : memory_bus_sdram_ch2.sdram_done;

    // ---------------- ch3: NVRAM backup ----------------
    wire backup_bram    = in_bram(memory_bus_backup.addr);
    wire backup_bram_wr = memory_bus_backup.ram_cs && backup_bram && ~memory_bus_backup.rnw;

    assign memory_bus_sdram_ch3.addr    = sdram_addr(memory_bus_backup.addr);
    assign memory_bus_sdram_ch3.data    = memory_bus_backup.data;
    assign memory_bus_sdram_ch3.rnw     = memory_bus_backup.rnw;
    assign memory_bus_sdram_ch3.ram_cs  = memory_bus_backup.ram_cs && ~backup_bram;
    assign memory_bus_sdram_ch3.sram_cs = '0;

    // BRAM read data follows the (held) request address one clk later, as nvram_backup expects
    assign memory_bus_backup.q           = backup_bram ? bram_data_b : memory_bus_sdram_ch3.q;
    assign memory_bus_backup.sdram_ready = backup_bram ? 1'b1        : memory_bus_sdram_ch3.sdram_ready;
    assign memory_bus_backup.sdram_done  = backup_bram ? 1'b1        : memory_bus_sdram_ch3.sdram_done;

    // ---------------- ch4: OPL4 sample memory ----------------
    // SDRAM: request registered here. BRAM: the two bytes of the word one after another on
    // port B, in the clk that flash and backup leave free.
    typedef enum logic [2:0] {W_IDLE, W_BRAM_0, W_BRAM_1, W_BRAM_2, W_SDRAM, W_END} wstate_t;
    wstate_t     w_state = W_IDLE;
    logic        w_ack = 1'b0, w_sd_req = 1'b0, w_sd_we = 1'b0, w_done_q = 1'b0;
    logic [15:0] w_rdata;
    logic [26:0] w_sd_addr;
    logic  [7:0] w_sd_wdata;
    wire         b_flash  = memory_bus_flash.ram_cs && flash_bram;
    wire         b_wave   = ~b_flash && ~memory_bus_backup.ram_cs;    // port B free for the wave bus
    wire         w_bram   = in_bram(wave_bus.addr);
    wire  [26:0] w_baddr  = {wave_bus.addr[26:1], wave_bus.we ? wave_bus.addr[0] : w_state == W_BRAM_1};
    wire         w_bwr    = w_state == W_BRAM_0 && wave_bus.we && b_wave;

    assign wave_bus.ack             = w_ack;
    assign wave_bus.rdata           = w_rdata;
    assign wave_bus_sdram_ch4.req   = w_sd_req;
    assign wave_bus_sdram_ch4.we    = w_sd_we;
    assign wave_bus_sdram_ch4.addr  = w_sd_addr;
    assign wave_bus_sdram_ch4.wdata = w_sd_wdata;

    always_ff @(posedge clk) begin
        w_ack    <= 1'b0;
        w_done_q <= wave_bus_sdram_ch4.ack;
        case (w_state)
            W_IDLE: if (wave_bus.req && ~w_ack) begin
                if (w_bram) w_state <= W_BRAM_0;
                else begin
                    w_sd_addr  <= sdram_addr(wave_bus.addr);
                    w_sd_wdata <= wave_bus.wdata;
                    w_sd_we    <= wave_bus.we;
                    w_sd_req   <= 1'b1;
                    w_state    <= W_SDRAM;
                end
            end
            W_BRAM_0: if (b_wave) begin             // even byte address, or the write
                if (wave_bus.we) begin w_ack <= 1'b1; w_state <= W_END; end
                else w_state <= W_BRAM_1;
            end
            W_BRAM_1: begin                         // odd byte address, even byte comes out
                w_rdata[7:0] <= bram_data_b;
                w_state      <= b_wave ? W_BRAM_2 : W_BRAM_0;
            end
            W_BRAM_2: begin
                w_rdata[15:8] <= bram_data_b;
                w_ack         <= 1'b1;
                w_state       <= W_END;
            end
            W_SDRAM: if (w_done_q) begin
                w_rdata  <= wave_bus_sdram_ch4.rdata;
                w_ack    <= 1'b1;
                w_sd_req <= 1'b0;
                w_state  <= W_END;
            end
            W_END: if (~w_done_q && ~w_sd_req) w_state <= W_IDLE;
            default: w_state <= W_IDLE;
        endcase
    end

    // ---------------- BRAM ----------------
    // Port B is shared by flash, backup and the wave bus, in this order of priority. Flash
    // and backup are rare and are not used at the same time (MFRSD flash programming vs.
    // OSD SRAM save/load).
    wire        b_wsel  = b_wave && (w_state == W_BRAM_0 || w_state == W_BRAM_1);
    wire [26:0] b_addr  = b_flash ? memory_bus_flash.addr : b_wsel ? w_baddr : memory_bus_backup.addr;
    wire  [7:0] b_din   = b_flash ? memory_bus_flash.data : b_wsel ? wave_bus.wdata : memory_bus_backup.data;
    wire        b_wr    = flash_bram_wr || (backup_bram_wr && ~b_flash) || w_bwr;

    generate
        if (BRAM_WIDTH > 0) begin : with_bram
            dpram #(.addr_width(BRAM_WIDTH), .mem_name("SYSTEM")) system_ram (
                .clock(clk),
                .address_a(addr[BRAM_WIDTH-1:0]),
                .wren_a(!rnw && bram_cs),
                .data_a(data),
                .q_a(bram_data),
                .address_b(b_addr[BRAM_WIDTH-1:0]),
                .wren_b(b_wr),
                .data_b(b_din),
                .q_b(bram_data_b)
            );
        end else begin : no_bram
            assign bram_data   = 8'hFF;
            assign bram_data_b = 8'hFF;
        end
    endgenerate

endmodule
