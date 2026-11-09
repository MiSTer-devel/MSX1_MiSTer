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
    input              jis2_en,
    output      [26:0] ram_addr,
    output             ram_cs
);

    logic [26:0] addr1, addr2, addr;
    logic        ram_en;

    assign ram_addr = ram_cs ? ram_base + addr : '1;
    assign ram_cs   = rd && ram_en;

    wire [6:0] hangul_data = hangul ? data[6:0] : {1'b0, data[5:0]};

    always_ff @(posedge clk) begin
        if (reset) begin
            addr1 <= 27'h00000;
            addr2 <= 27'h20000;
            ram_en <= 1'b0;
        end else begin
            ram_en <= 1'b0;
            addr2 <= addr2;

            if (req) begin
                if (wr) begin
                    case (cpu_addr)
                        2'd0: addr1 <= (addr1 & 27'h1f800) | (27'(data[5:0]) << 5 );
                        2'd1: addr1 <= (addr1 & 27'h007e0) | (27'(data[5:0]) << 11);
                        2'd2: addr2 <= (addr2 & 27'h3f800) | (27'(hangul_data) << 5 );
                        2'd3: addr2 <= (addr2 & 27'h207e0) | (27'(data[5:0]) << 11);
                    endcase
                end
                if (rd) begin
                    case (cpu_addr)
                        2'd0: ;
                        2'd1: begin
                            addr   <= addr1 & ({5'b0, ram_size, 14'd0} - 27'd1);
                            ram_en <= 1'b1;
                            addr1  <= (addr1 & ~27'h1f) | ((addr1 + 27'd1) & 27'h1f);
                        end
                        2'd2: ;
                        2'd3: begin
                            if (ram_size == 8'h10 && jis2_en) begin
                                addr   <= addr2;
                                ram_en <= 1'b1;
                            end
                            addr2 <= (addr2 & ~27'h1f) | ((addr2 + 27'd1) & 27'h1f);
                        end
                    endcase
                end
            end
        end
    end

endmodule
