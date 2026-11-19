// Generic 16k mapper
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

module mapper_generic16k (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);
  
    // Control signals for memory mapping
    wire cs, we;

    // Mapped if address is not in the lower or upper 16KB
    wire mapped  = ^cpu_bus.addr[15:14]; //0000-3fff & c000-ffff unmaped

    // Mapper is enabled if type is GENERIC16kb and there is a memory request
    assign cs = block_info.typ == MAPPER_GENERIC16KB && cpu_bus.mreq && mapped;


    // Bank registers hold the written value; the block is block < blocks ? block :
    // block & (blocks - 1) (openMSX RomBlocks::setRom), also for the reset banks.
    // 16 KB blocks, the image padded up.
    logic [7:0] bank[0:1][2];
    wire [11:0] nrBlocks  = {1'b0, block_info.rom_size[24:14]} + {11'd0, |block_info.rom_size[13:0]};
    wire [11:0] blockMask = nrBlocks - 12'd1;

    // Bank switching logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize bank values on reset
            bank[0] <= '{8'h00, 8'h01};
            bank[1] <= '{8'h00, 8'h01};
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req) begin
                bank[block_info.id][cpu_bus.addr[15]] <= cpu_bus.data;
            end
        end
    end

    // Calculate bank base and address mapping
    wire  [7:0] bank_reg  = bank[block_info.id][cpu_bus.addr[15]];
    wire  [7:0] bank_base = {4'd0, bank_reg} < nrBlocks ? bank_reg : bank_reg & blockMask[7:0];
    wire [26:0] ram_addr  = {5'b0, bank_base, cpu_bus.addr[13:0]};

    wire ram_valid = cs && cpu_bus.rd && ram_addr < {2'b00, block_info.rom_size};
    
    // Assign the final outputs for the mapper
    assign out.ram_cs  = ram_valid;
    assign out.addr    = ram_valid ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
