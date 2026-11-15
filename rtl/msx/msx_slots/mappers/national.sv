// National mapper
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

module mapper_national (
    cpu_bus_if.device_mp    cpu_bus,                // Interface for CPU communication
    input  MSX::block_info_t block_info,             // Active block (slot layout entry)
    output MSX::mapper_out_t out                     // Mapper output, merged in mappers.sv
);

    
    // Memory mapping control signals
    wire cs, mapper_en;
    
    assign mapper_en  = (block_info.typ == MAPPER_NATIONAL);
    
    assign cs         = mapper_en & cpu_bus.mreq;
    
    logic [7:0]  bank[4], control;
    logic [23:0] sram_addr;

    // SRAM (openMSX RomNational, 4 KB): control bit 1, data at (A & 3FFFh) = 3FFDh, address
    // A & 0FFFh; the address increments when the access ends (stable for the memory access)
    wire sram_exists = block_info.sram_size != 16'd0;
    wire sram_acc    = cs && control[1] && sram_exists && cpu_bus.addr[13:0] == 14'h3FFD && (cpu_bus.rd || cpu_bus.wr);
    logic sram_acc_q = 1'b0;

    always_ff @(posedge cpu_bus.clk) begin
        sram_acc_q <= sram_acc;
        if (cpu_bus.reset) begin
            bank      <= '{'0, '0, '0, '0};
            control   <= '0;
            sram_addr <= '0;
        end else begin
            if (cs && cpu_bus.req && cpu_bus.wr) begin
                case (cpu_bus.addr)
                    16'h6000: bank[1] <= cpu_bus.data;
                    16'h6400: bank[0] <= cpu_bus.data;
                    16'h7000: bank[2] <= cpu_bus.data;
                    16'h7400: bank[3] <= cpu_bus.data;
                    16'h7FF9: control <= cpu_bus.data;
                    default:
                        if (control[1])
                            case (cpu_bus.addr[13:0])
                                14'h3FFA: sram_addr[23:16] <= cpu_bus.data;
                                14'h3FFB: sram_addr[15:8]  <= cpu_bus.data;
                                14'h3FFC: sram_addr[7:0]   <= cpu_bus.data;
                                default: ;
                            endcase
                endcase
            end
            if (sram_acc_q && !sram_acc)
                sram_addr <= sram_addr + 1'b1;
        end
    end

    // Bank select read back (openMSX RomNational): (address & 7FF9h) == 7FF0h, own slot only
    wire bank_rd  = cs && control[2] && cpu_bus.addr[14:3] == 12'hFFE && ~cpu_bus.addr[0] && cpu_bus.rd;
    // A bank past the ROM end wraps (16 KB blocks, image padded up; RomBlocks::setRom)
    wire [11:0] blocks    = {1'b0, block_info.rom_size[24:14]} + {11'd0, |block_info.rom_size[13:0]};
    wire [11:0] blk_mask  = blocks - 12'd1;
    wire  [7:0] bank_reg  = bank[cpu_bus.addr[15:14]];
    wire  [7:0] bank_base = {4'd0, bank_reg} < blocks ? bank_reg : bank_reg & blk_mask[7:0];
    wire [26:0] ram_addr  = {5'b0, bank_base, cpu_bus.addr[13:0]};

    // Assign the final outputs for the mapper
    assign out.sram_cs = sram_acc;
    assign out.main_cs = 1'b0;
    assign out.ram_cs  = ~sram_acc && ~bank_rd && cs && ram_addr < {2'b00, block_info.rom_size};
    assign out.rnw     = ~(sram_acc && cpu_bus.wr);
    assign out.data    = bank_rd ? bank[cpu_bus.addr[2:1]] : 8'hFF;

    assign out.addr    = sram_acc ? {15'b0, sram_addr[11:0]} : cs && ~bank_rd ? ram_addr : {27{1'b1}};

endmodule
