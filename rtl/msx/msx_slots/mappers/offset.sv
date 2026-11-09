// Offset mapper
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

module mapper_offset (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    input  MSX::block_info_t block_info,    // Active block (slot layout entry)
    output MSX::mapper_out_t out            // Mapper output, merged in mappers.sv
);
    // Chip select is valid if the mapper type is OFFSET and memory request (mreq) is active
    wire cs = (block_info.typ == MAPPER_OFFSET) && cpu_bus.mreq && (cpu_bus.rd || cpu_bus.wr);

    // Calculate address mapping
    wire [26:0] ram_addr  = {11'b0, block_info.offset_ram, cpu_bus.addr[13:0]};

    // Check if the calculated RAM address is within the valid range of the ROM size
    wire ram_valid = (ram_addr < {2'b00, block_info.rom_size}) && cs;

    // Output assignments
    assign out.ram_cs = ram_valid;  // RAM chip select signal

    // Calculate the address by adding the offset to the base address (only if chip select is active)
    assign out.addr   = ram_valid ? ram_addr : {27{1'b1}};

    // Generate the Read/Not Write (rnw) signal based on the chip select and write signal
    assign out.rnw    = ~(ram_valid && cpu_bus.wr);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
