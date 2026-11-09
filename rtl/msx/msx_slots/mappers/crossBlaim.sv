// CrossBlaim mapper
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

module mapper_crossBlaim (
    cpu_bus_if.device_mp    cpu_bus,                // Interface for CPU communication
    input  MSX::block_info_t block_info,             // Active block (slot layout entry)
    output MSX::mapper_out_t out                     // Mapper output, merged in mappers.sv
);

    // Memory mapping control signals
    logic cs, mapper_en;

    // Mapper is enabled if it is 16kb
    assign mapper_en  = (block_info.typ == MAPPER_CROSS_BLAIM);

    // Chip select is valid if address is mapped and mapper is enabled
    assign cs         = mapper_en & cpu_bus.mreq;

    // Bank enable logic
    logic [2:0] bank[2][4];          // Storage for bank data, two entries for two different mapper IDs
    
    // Initialize or update bank and SRAM enable signals
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize banks and SRAM enable on reset
            bank[0]    <= '{'b001, 'b000, 'b001, 'b001};
            bank[1]    <= '{'b001, 'b000, 'b001, 'b001};
        end else if (cs & cpu_bus.wr & cpu_bus.req) begin
            case (cpu_bus.data[1:0])
                2'd0, 2'd1 :
                    bank[block_info.id] <= '{'b001, 'b000, 'b001, 'b001};
                2'd2:
                    bank[block_info.id] <= '{'b100, 'b000, 'b010, 'b100};
                2'd3:
                    bank[block_info.id] <= '{'b100, 'b000, 'b011, 'b100};
                endcase
        end
    end

    // Calculate bank base and address mapping
    wire [1:0] bank_base;
    wire       bank_unmaped;
    
    assign {bank_unmaped, bank_base} = bank[block_info.id][cpu_bus.addr[15:14]];
    
    wire [26:0] ram_addr  = {11'b0, bank_base, cpu_bus.addr[13:0]};

    // Check if the calculated RAM address is within the valid range of the ROM size
    wire ram_valid = (ram_addr < {2'b00, block_info.rom_size}) && ~bank_unmaped && cs && cpu_bus.rd;

    // Assign the final outputs for the mapper
    assign out.ram_cs  = ram_valid;
    assign out.addr    = ram_valid ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
