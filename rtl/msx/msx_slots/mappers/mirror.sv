// Mirror mapper
//
// Copyright (c) 2024 Molekula
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

module mapper_mirror (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out
);

    wire cs = (block_info.typ == MAPPER_MIRROR) && cpu_bus.mreq && (cpu_bus.rd || cpu_bus.wr);

    // 8 KB blocks covering rom_size[15:0] (ceil); 64 KB wraps to 0
    wire  [3:0] block_count = {1'b0, block_info.rom_size[15:13]} + 4'(|block_info.rom_size[12:0]);

    // prefix = (page + 2*offset_ram) % block_count, as constant tables indexed by
    // {offset_ram, page}: pure LUT logic (Quartus builds a divider even for % const).
    // Entry i at bits [3*i +: 3]. Generated: ((i & 7) + 2*(i >> 3)) % n.
    localparam logic [95:0] MOD2 = 96'h208208208208208208208208;
    localparam logic [95:0] MOD3 = 96'h211088442211088442211088;
    localparam logic [95:0] MOD4 = 96'h21A21A68868821A21A688688;
    localparam logic [95:0] MOD5 = 96'h6888D12234448D111A444688;
    localparam logic [95:0] MOD6 = 96'h22C688B1A22C688B1A22C688;
    localparam logic [95:0] MOD7 = 96'hD634468D11AC446B1A1AC688;
    localparam logic [95:0] MOD8 = 96'hB1A23E688FAC23EB1AFAC688;

    wire  [4:0] idx = {block_info.offset_ram, cpu_bus.addr[15:13]};

    // block_count 0 (64 KB) behaves as 8 (identity); original % 0 was undefined.
    logic [2:0]  prefix;
    always_comb begin
        case (block_count)
            4'd1:    prefix = 3'd0;
            4'd2:    prefix = MOD2[3*idx +: 3];
            4'd3:    prefix = MOD3[3*idx +: 3];
            4'd4:    prefix = MOD4[3*idx +: 3];
            4'd5:    prefix = MOD5[3*idx +: 3];
            4'd6:    prefix = MOD6[3*idx +: 3];
            4'd7:    prefix = MOD7[3*idx +: 3];
            default: prefix = MOD8[3*idx +: 3];
        endcase
    end

    logic [15:0] ram_addr;
    assign ram_addr = {prefix, cpu_bus.addr[12:0]};

    assign out.ram_cs = cs;
    assign out.addr   = cs ? {11'b0, ram_addr} : {27{1'b1}};
    assign out.rnw    = ~(cs && cpu_bus.wr);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
