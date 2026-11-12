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

    // openMSX RomPlain (MIRRORED*): the ROM starts at page firstPage = 2 x offset_ram; page p
    // shows r = p - firstPage (unsigned) if r < blocks, else r & (blocks - 1). 64 KB = 8 blocks.
    wire  [3:0] n      = block_count == 4'd0 ? 4'd8 : block_count;
    wire  [3:0] r      = {1'b0, cpu_bus.addr[15:13]} - {1'b0, block_info.offset_ram, 1'b0};
    wire  [3:0] n_mask = n - 4'd1;
    wire  [2:0] prefix = (!r[3] && r < n) ? r[2:0] : r[2:0] & n_mask[2:0];

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
