// MSX2 RAM mapper
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

module mapper_msx2_ram (
    cpu_bus_if.device_mp    cpu_bus,         // Interface for CPU communication
    input  MSX::block_info_t block_info,      // Active block (slot layout entry)
    output MSX::mapper_out_t out,             // Mapper output, merged in mappers.sv
    input [7:0]             data_to_mapper
);

    // PANASONIC_RAM = turbo R main RAM: in DRAM mode (S1990) the top 64 KB hold the ROM copy and
    // ignore writes (openMSX PanasonicMemory::isWritable)
    wire panasonic = block_info.typ == MAPPER_PANASONIC_RAM;
    wire cs = (block_info.typ == MAPPER_MSX2 || panasonic) && cpu_bus.mreq && (cpu_bus.wr || cpu_bus.rd);
    wire [8:0] segments = block_info.rom_size[22:14];
    wire       protect  = panasonic && block_info.dram && {1'b0, data_to_mapper} >= segments - 9'd4;

    // Output assignments
    assign out.ram_cs = cs;  // RAM chip select signal

    // Calculate the address by adding the offset to the base address (only if chip select is active)
    assign out.addr = cs ? {5'b0, data_to_mapper, cpu_bus.addr[13:0]} : {27{1'b1}};

    // Generate the Read/Not Write (rnw) signal based on the chip select and write signal
    assign out.rnw = ~(cs & cpu_bus.wr & ~protect);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
