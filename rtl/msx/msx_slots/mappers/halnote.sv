// Halnote mapper
//
// Copyright (c) 2023-2026 Molekula
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

// MSX-JE firmware of the Sony HB-F1XDJ / HB-F1XV, as openMSX src/memory/RomHalnote.cc.
// 1 MB ROM, 8 KB banks in 4000-BFFF, switched by writes to 4FFF, 6FFF, 8FFF, AFFF (block & 7Fh).
//   bit 7 of 4FFF: 16 KB SRAM in 0000-3FFF
//   bit 7 of 6FFF: sub-mapper in 7000-7FFF, two 2 KB pages (77FF, 7FFF) from ROM 80000h
// 0000-3FFF without the SRAM and C000-FFFF are unmapped. Reset: block 0 everywhere.
module mapper_halnote (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);

    wire cs = block_info.typ == MAPPER_HALNOTE && cpu_bus.mreq;

    logic [6:0] bank[4];
    logic [7:0] sub_bank[2];
    logic       sram_en, sub_en;

    wire reg_wr = cs && cpu_bus.wr && cpu_bus.req && cpu_bus.addr[10:0] == 11'h7FF;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank     <= '{7'd0, 7'd0, 7'd0, 7'd0};
            sub_bank <= '{8'd0, 8'd0};
            sram_en  <= 1'b0;
            sub_en   <= 1'b0;
        end else if (reg_wr) begin
            case (cpu_bus.addr[15:11])
                5'b01001: begin bank[0] <= cpu_bus.data[6:0]; sram_en <= cpu_bus.data[7]; end  // 4FFF
                5'b01101: begin bank[1] <= cpu_bus.data[6:0]; sub_en  <= cpu_bus.data[7]; end  // 6FFF
                5'b10001: bank[2] <= cpu_bus.data[6:0];                                       // 8FFF
                5'b10101: bank[3] <= cpu_bus.data[6:0];                                       // AFFF
                5'b01110: sub_bank[0] <= cpu_bus.data;                                        // 77FF
                5'b01111: sub_bank[1] <= cpu_bus.data;                                        // 7FFF
                default: ;
            endcase
        end
    end

    wire page12 = cpu_bus.addr[15:14] == 2'b01 || cpu_bus.addr[15:14] == 2'b10;
    wire is_sub = sub_en && cpu_bus.addr[15:12] == 4'h7;
    wire is_sram = sram_en && block_info.sram_size != 16'd0 && cpu_bus.addr[15:14] == 2'b00;

    wire rom_rd  = cs && cpu_bus.rd && page12;
    // Only with RD / WR: the memory latches rnw with the select
    wire sram_rw = cs && is_sram && (cpu_bus.rd || cpu_bus.wr);

    wire [6:0] blk = bank[{cpu_bus.addr[15], cpu_bus.addr[13]}];

    assign out.ram_cs  = rom_rd;
    assign out.sram_cs = sram_rw;
    assign out.main_cs = 1'b0;
    assign out.rnw     = !(sram_rw && cpu_bus.wr);
    assign out.addr    = sram_rw ? {13'd0, cpu_bus.addr[13:0]} :
                         !rom_rd ? {27{1'b1}} :
                         is_sub  ? {7'd0, 1'b1, sub_bank[cpu_bus.addr[11]], cpu_bus.addr[10:0]} :
                                   {7'd0, blk, cpu_bus.addr[12:0]};
    assign out.data    = 8'hFF;

endmodule
