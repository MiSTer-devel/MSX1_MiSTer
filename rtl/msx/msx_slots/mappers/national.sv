// National mapper
//
// Copyright (c) 2024 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
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
    assign out.ram_cs  = ~sram_rq && ~bank_rd && cs;
    assign out.rnw     = ~sram_wr;
    assign out.data    = bank_rd ? bank[cpu_bus.addr[2:1]] : 8'hFF;

    assign out.addr    = cs && ~bank_rd ? (sram_rq ? {15'b0, sram_addr_tmp[11:0]} : ram_addr) : {27{1'b1}};

endmodule
