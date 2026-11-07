// harry Fox mapper
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

module mapper_harryFox (
    cpu_bus_if.device_mp    cpu_bus,                // Interface for CPU communication
    input  MSX::block_info_t block_info,             // Active block (slot layout entry)
    output MSX::mapper_out_t out                     // Mapper output, merged in mappers.sv
);

    // Memory mapping control signals
    logic cs, mapper_en;

    // Mapper is enabled if it is 16kb
    assign mapper_en  = (block_info.typ == MAPPER_HARRY_FOX);

    // Chip select is valid if address is mapped and mapper is enabled
    assign cs         = mapper_en & cpu_bus.mreq;

    // Bank enable logic
    logic [2:0] bank[2][4];          // Storage for bank data, two entries for two different mapper IDs
    
    // Initialize or update bank and SRAM enable signals
    always @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize banks on reset
            bank[0]    <= '{'b100, 'b000, 'b001, 'b100};
            bank[1]    <= '{'b100, 'b000, 'b001, 'b100};
        end else if (cs && cpu_bus.wr && cpu_bus.req) begin
            case (cpu_bus.addr[15:12])
                4'h6: begin
                    bank[block_info.id][1] <= {1'b0, cpu_bus.data[0], 1'b0};
                    //$display("Write Hary Fox to  bank 1  %x address %x value %x",  {1'b0, cpu_bus.data[0], 1'b0}, cpu_bus.addr, cpu_bus.data);
                end
                4'h7: begin
                    bank[block_info.id][2] <= {1'b0, cpu_bus.data[0], 1'b1};
                    //$display("Write Hary Fox to  bank 2  %x address %x value %x",  {1'b0, cpu_bus.data[0], 1'b1}, cpu_bus.addr, cpu_bus.data);
                end
                default: ;
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
    assign out.data    = 8'hFF;

endmodule
