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
    logic [23:0] sram_addr_tmp;
    logic        sram_wr, sram_rd;

    wire sram_rq  =  cpu_bus.rd && control[1] && cpu_bus.addr[13:0] == 14'h3FFD;

    always_ff @(posedge cpu_bus.clk) begin
        
        if (!cpu_bus.wr) 
            sram_wr <= '0;
        
        if (!cpu_bus.rd) 
            sram_rd <= '0;

        if (cpu_bus.reset) begin
            bank      <= '{'0, '0, '0, '0};
            control   <= '0;
            sram_addr <= '0;
        end else if (cs && cpu_bus.req) begin
            if (cpu_bus.wr) begin
                case (cpu_bus.addr)
                    16'h6000:
                        bank[1] <= cpu_bus.data;
                    16'h6400:
                        bank[0] <= cpu_bus.data;
                    16'h7000:
                        bank[2] <= cpu_bus.data;
                    16'h7400:
                        bank[3] <= cpu_bus.data;
                    16'h7FF9:
                        control <= cpu_bus.data;
                    default:
                        if (control[1]) begin
                            case(cpu_bus.addr[13:0])
                            14'h3FFA: 
                                sram_addr <= {cpu_bus.data, sram_addr[15:0]};
                            14'h3FFB:
                                sram_addr <= {sram_addr[23:16],cpu_bus.data, sram_addr[7:0]};
                            14'h3FFC:
                                sram_addr <= {sram_addr[23:8], cpu_bus.data};
                            14'h3FFD: begin
                                sram_addr_tmp <= sram_addr;
                                sram_addr     <= sram_addr + 1'b1;
                                sram_wr       <= '1;
                            end
                            default:;
                            endcase
                        end
                endcase
            end
            if (sram_rq) begin
                sram_addr_tmp <= sram_addr;
                sram_addr     <= sram_addr + 1'b1;
                sram_rd       <= '1;
            end
        end
    end
    
    wire bank_rd  = control[2] && cpu_bus.addr[14:3] == 12'hFFF && ~cpu_bus.addr[0] && cpu_bus.rd;
    wire [26:0] ram_addr = {5'b0, bank[cpu_bus.addr[15:14]], cpu_bus.addr[13:0]};

    // Assign the final outputs for the mapper
    assign out.sram_cs = (sram_rd | sram_wr) && 0 ;                                     // TODO proč tu mám nulu
    assign out.main_cs = 1'b0;
    assign out.ram_cs  = ~sram_rq && ~bank_rd && cs;
    assign out.rnw     = ~sram_wr;
    assign out.data    = bank_rd ? bank[cpu_bus.addr[2:1]] : 8'hFF;

    assign out.addr    = cs && ~bank_rd ? (sram_rq ? {15'b0, sram_addr_tmp[11:0]} : ram_addr) : {27{1'b1}};

endmodule
