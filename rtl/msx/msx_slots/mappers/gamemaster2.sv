// Game Master 2 mapper
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

module mapper_gamemaster2 (
    cpu_bus_if.device_mp    cpu_bus,   // Interface for CPU communication
    output MSX::mapper_out_t out,       // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info // Active block (slot layout entry)
);

    // Memory mapping control signals
    wire cs, mapper_en, rom_mapped;

    // Enable mapper if the mapper type is GameMaster2
    assign mapper_en = (block_info.typ == MAPPER_GM2);

    // Determine if the ROM is mapped (address range 4000h - BFFFh)
    assign rom_mapped = cpu_bus.addr[15] ^ cpu_bus.addr[14];

    // Chip select (cs) is active if the mapper is enabled and the CPU is performing a memory request (mreq)
    assign cs = mapper_en && cpu_bus.mreq;

    // Bank registers for memory mapping
    logic [5:0] bank1, bank2, bank3;

    // Bank switching logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize banks after reset
            bank1 <= 6'h01;  // Default bank 1
            bank2 <= 6'h02;  // Default bank 2
            bank3 <= 6'h03;  // Default bank 3
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req) begin
                // Update bank registers based on the address range during a write
                case (cpu_bus.addr[15:12])
                    4'h6: bank1 <= cpu_bus.data[5:0];  // Bank 1 (6000h - 6FFFh)
                    4'h8: bank2 <= cpu_bus.data[5:0];  // Bank 2 (8000h - 8FFFh)
                    4'hA: bank3 <= cpu_bus.data[5:0];  // Bank 3 (A000h - AFFFh)
                    default: ;  // No action for other address ranges
                endcase
            end
        end
    end

    // Bank selection logic based on the CPU address range
    wire [5:0] bank_base = (cpu_bus.addr[15:13] == 3'b010) ? 6'h00 :  // Fixed bank for 4000h - 5FFFh
                           (cpu_bus.addr[15:13] == 3'b011) ? bank1 :  // Bank 1 (6000h - 7FFFh)
                           (cpu_bus.addr[15:13] == 3'b100) ? bank2 :  // Bank 2 (8000h - 9FFFh)
                                                             bank3 ;  // Bank 3 (A000h - BFFFh)

    // Generate RAM and SRAM addresses based on the selected bank and CPU address
    wire [26:0] ram_addr  = {10'b0, bank_base[3:0], cpu_bus.addr[12:0]};  // RAM address
    wire [26:0] sram_addr = {14'b0, bank_base[5],   cpu_bus.addr[11:0]};  // SRAM address

    // Enable SRAM if bit 4 of the bank register is set; otherwise, enable RAM for read operations
    wire sram_en = bank_base[4] && (cpu_bus.rd || cpu_bus.wr);
    wire ram_en  = ~sram_en && cpu_bus.rd && rom_mapped;

    // Output control signals
    assign out.sram_cs = cs && sram_en;  // SRAM chip select
    assign out.main_cs = 1'b0;
    assign out.ram_cs  = cs && ram_en;   // RAM chip select
    assign out.rnw     = ~(out.sram_cs && cpu_bus.wr && cpu_bus.addr[15:12] == 4'hB);  // Read/Write control signal
    assign out.addr    = cs ? (sram_en ? sram_addr : ram_addr) : {27{1'b1}};  // Address output, default to all 1s if not selected

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.data    = 8'hFF;

endmodule
