// Kanji device
//
// Copyright (c) 2024-2025 Molekula
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
//

// As openMSX src/MSXKanji.cc: one address for both levels (written at D8h/D9h or DAh/DBh), the
// level of the last write, the 32-byte character counter incremented by a valid read of D9h/DBh.
// io_device param: bit 0 hangul (7-bit row), bit 1 lascom (unused), bits 3:2 level 2 access:
//   0 read     - the read port selects the level (DBh = level 2)
//   1 write    - the level of the last write (FS-A1ST / GT)
//   2 interlocked_write_read - as write, a read of the other level gives FFh, no increment
//                (FS-A1WX / WSX, Sanyo PHC-35J / 70FD)
//   3 only_level_1 - DAh/DBh act as D8h/D9h (FS-A1F / FX, HB-11, FS-4000, YIS-805/256)
// Addresses outside the font (ram_size, 16 kB units) read FFh. jis2_en: OCM IPL with a 384 kB BIOS.
module dev_kanji (
    cpu_bus_if.device_mp       cpu_bus,
    input  MSX::io_device_t    io_device[3],
    input  MSX::io_device_mem_ref_t io_memory[8],
    input                      jis2_en,             // JIS2 (DA-DBh) allowed (OCM: by IPL)
    output                     ram_cs,
    output              [26:0] ram_addr
);

    wire        hangul      = io_device[0].param[0];
    wire        lascom      = io_device[0].param[1];
    wire [26:0] memory      = io_memory[io_device[0].mem_ref].memory;
    wire  [7:0] memory_size = io_memory[io_device[0].mem_ref].memory_size;

    wire io_en       = cpu_bus.iorq && ~cpu_bus.m1;
    wire cs_io_match = (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire cs_enable   = io_device[0].enable && cs_io_match && io_en;

    kanji kanji_i (
        .clk(cpu_bus.clk),
        .reset(cpu_bus.reset),
        .data(cpu_bus.data),
        .cpu_addr(cpu_bus.addr[1:0]),
        .ram_base(memory),
        .ram_size(memory_size),
        .req(cpu_bus.req),
        .wr(cs_enable && cpu_bus.wr && cpu_bus.req),
        .rd(cs_enable && cpu_bus.rd),
        .hangul(hangul),
        .lascom(lascom),
        .level2_via(io_device[0].param[3:2]),
        .jis2_en(jis2_en),
        .ram_addr(ram_addr),
        .ram_cs(ram_cs)
    );

endmodule

module kanji (
    input              clk,
    input              reset,
    input        [7:0] data,
    input        [1:0] cpu_addr,
    input       [26:0] ram_base,
    input        [7:0] ram_size,
    input              req,
    input              wr,
    input              rd,
    input              hangul,
    input              lascom,
    input        [1:0] level2_via,
    input              jis2_en,
    output      [26:0] ram_addr,
    output             ram_cs
);

    localparam logic [1:0] VIA_READ = 2'd0, VIA_WRITE = 2'd1, VIA_INTERLOCKED = 2'd2, VIA_LEVEL1 = 2'd3;

    logic [17:0] adr;
    logic        write_level;
    logic [17:0] addr;
    logic        ram_en;

    wire  [1:0] port       = level2_via == VIA_LEVEL1 ? {1'b0, cpu_addr[0]} : cpu_addr;
    wire        read_level = port[1];
    wire        level      = level2_via == VIA_READ ? read_level : write_level;
    wire        valid      = !(level2_via == VIA_INTERLOCKED && read_level != write_level);
    wire [17:0] rd_addr    = {adr[17] | level, adr[16:0]};
    wire        in_font    = {4'd0, rd_addr} < {ram_size, 14'd0};
    wire  [6:0] row        = hangul ? data[6:0] : {1'b0, data[5:0]};

    assign ram_addr = ram_cs ? ram_base + 27'(addr) : '1;
    assign ram_cs   = rd && ram_en;

    always_ff @(posedge clk) begin
        if (reset) begin
            adr         <= '0;
            write_level <= 1'b0;
            ram_en      <= 1'b0;
        end else begin
            if (!rd) ram_en <= 1'b0;            // held to the end of the read: q is valid only with ram_cs
            if (req && wr) begin
                write_level <= port[1];
                if (!port[0]) adr <= (adr & 18'h3F800) | {7'd0, data[5:0], 5'd0};
                else          adr <= (adr & 18'h007E0) | {row, 11'd0};
            end
            if (req && rd && port[0] && valid) begin
                addr   <= rd_addr;
                ram_en <= in_font && (!level || jis2_en);
                adr    <= {adr[17:5], adr[4:0] + 5'd1};
            end
        end
    end

endmodule
