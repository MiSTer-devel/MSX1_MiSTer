// Zemina90 mapper
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

// Zemina 90-in-1 cartridge
//
//  90 in 1 uses Port &H77 for mapping:
//    bits 0-5: selected 16KB page
//    bits 6-7: addressing mode...
//      00 = same page at 4000-7FFF and 8000-BFFF (normal mode)
//      01 = same page at 4000-7FFF and 8000-BFFF (normal mode)
//      10 = [page AND 3E] at 4000-7FFF, [page AND 3E OR 01] at 8000-BFFF
//           (32KB mode)
//      11 = same page at 4000-7FFF and 8000-BFFF, but 8000-BFFF has high 8KB
//           and low 8KB swapped (Namco mode)

module mapper_zemina90 (
    cpu_bus_if.device_mp    cpu_bus,         // Interface for CPU communication
    input  MSX::block_info_t block_info,      // Active block (slot layout entry)
    output MSX::mapper_out_t out,             // Mapper output, merged in mappers.sv
    input [7:0]             data_to_mapper
);

    // Mapped if address is not in the lower or upper 16KB
    wire mapped  = ^cpu_bus.addr[15:14];                                                    //0000-3fff & c000-ffff unmaped

	 
	 wire cs      = (block_info.typ == MAPPER_ZEMINA_90) && cpu_bus.mreq && cpu_bus.rd && mapped;
    
    // Output assignments
    assign out.ram_cs = cs;  // RAM chip select signal

    
    wire  [6:0]  page = {data_to_mapper[5:0], 1'b0};
    logic [6:0]  addr;

    always_comb begin 
		addr = 7'd0;
        case (data_to_mapper[7:6])
            2'b00, 2'b01: begin
                case (cpu_bus.addr[15:13])
                    3'b010: addr = page;
                    3'b011: addr = page | 7'd1;
                    3'b100: addr = page;
                    3'b101: addr = page | 7'd1;
						  default:;
                endcase
            end
            2'b10: begin
                case (cpu_bus.addr[15:13])
                    3'b010: addr = page & ~7'h2;
                    3'b011: addr = page & ~7'h2;
                    3'b100: addr = page |  7'd2;
                    3'b101: addr = page |  7'd2;
						  default:;
                endcase
            end
            2'b11: begin
                case (cpu_bus.addr[15:13])
                    3'b010: addr = page;
                    3'b011: addr = page | 7'd1;
                    3'b100: addr = page | 7'd1;
                    3'b101: addr = page;
						  default:;
                endcase
				end
        endcase
    end

    // Calculate the address by adding the offset to the base address (only if chip select is active)
    assign out.addr = cs ? {7'b0, addr, cpu_bus.addr[12:0]} : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
