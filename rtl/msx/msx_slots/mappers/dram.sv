// MSX turbo R ROM readable from the main RAM (DRAM mode)
//
// Copyright (c) 2026 Molekula
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

// Behaviour as openMSX src/memory/RomDRAM.cc + PanasonicMemory::getRomBlock. ROM mode: a plain ROM
// page (offset_ram). DRAM mode (S1990 register 6 bit 6 = 0): the page reads the main RAM at
// size - 64 KB + (mapper_param + offset_ram) x 16 KB, where the BIOS put its copy of the ROM
// (FS-A1ST: BIOS 0-1, Sub ROM 2, Kanji driver 3). Writes are ignored in both modes.
module mapper_dram (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,    // Active block (slot layout entry)
    output MSX::mapper_out_t out            // Mapper output, merged in mappers.sv
);

    wire cs   = block_info.typ == MAPPER_DRAM && cpu_bus.mreq && cpu_bus.rd;
    wire dram = block_info.dram && block_info.main_ram_size >= 17'd8;   // main RAM of 64 KB at least

    wire  [1:0] page      = block_info.mapper_param + block_info.offset_ram;
    wire [26:0] dram_addr = 27'({block_info.main_ram_size - 17'd8, 13'd0}) + {11'd0, page, cpu_bus.addr[13:0]};
    wire [26:0] rom_addr  = {11'd0, block_info.offset_ram, cpu_bus.addr[13:0]};
    wire        rom_valid = rom_addr < {2'b00, block_info.rom_size};

    wire main_rd = cs && dram;
    wire rom_rd  = cs && !dram && rom_valid;

    assign out.main_cs = main_rd;
    assign out.ram_cs  = rom_rd;
    assign out.addr    = main_rd ? dram_addr : rom_rd ? rom_addr : {27{1'b1}};
    assign out.rnw     = 1'b1;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
