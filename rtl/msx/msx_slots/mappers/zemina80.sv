// Zemina80 mapper
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

module mapper_zemina80 (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);
  
    // Control signals for memory mapping
    wire cs, we;

    // Mapper is enabled if type is KONAMI and there is a memory request
    assign cs = (block_info.typ == MAPPER_ZEMINA_80) & cpu_bus.mreq;

    assign we = cs && (cpu_bus.addr >= 16'h4000) && (cpu_bus.addr < 16'h4004) && cpu_bus.wr;

    // Bank registers: bit 8 = unmapped (pages 0 and 3), else the written value; the block is
    // wrapped when read, block < blocks ? block : block & (blocks - 1) (openMSX setRom), which
    // also covers the reset banks
    logic [8:0] bank[0:1][0:7];
    wire [12:0] nrBlocks  = {1'b0, block_info.rom_size[24:13]};
    wire [12:0] blockMask = nrBlocks - 13'd1;

    // Bank switching logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize bank values on reset
            bank[0] <= '{9'h100, 9'h100, 9'h000, 9'h001, 9'h002, 9'h003, 9'h100,  9'h100};
            bank[1] <= '{9'h100, 9'h100, 9'h000, 9'h001, 9'h002, 9'h003, 9'h100,  9'h100};
        end else begin
            if (we && cpu_bus.req) begin
                // Bank switching logic based on address
                    bank[block_info.id][3'd2 +  {1'b0,cpu_bus.addr[1:0]}] <= {1'b0, cpu_bus.data};
            end
        end
    end

    
    wire  [7:0] bank_reg, bank_base;
    wire        bank_unmaped, ram_valid;
    wire [26:0] ram_addr;
    
    // Calculate bank base and address mapping
    assign {bank_unmaped, bank_reg} = bank[block_info.id][cpu_bus.addr[15:13]];
    assign bank_base = {5'd0, bank_reg} < nrBlocks ? bank_reg : bank_reg & blockMask[7:0];
    assign ram_addr  = {6'b0, bank_base, cpu_bus.addr[12:0]};

    // Check if the calculated RAM address is within the valid range of the ROM size
    assign ram_valid = (ram_addr < {2'b00, block_info.rom_size}) && ~bank_unmaped && cs && cpu_bus.rd;

    // Assign the final outputs for the mapper
    assign out.ram_cs  = ram_valid;
    assign out.addr    = ram_valid ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
