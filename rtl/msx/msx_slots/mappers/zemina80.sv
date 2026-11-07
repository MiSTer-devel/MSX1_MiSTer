// Zemina80 mapper
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

    // Bank registers for memory banking
    logic [8:0] bank[0:1][0:7];
    logic [7:0] block, nrBlocks, blockMask;
    logic [8:0] blockCompute;
    
    assign nrBlocks = block_info.rom_size[20:13];
    assign blockMask = nrBlocks  - 1'b1;
    assign block = cpu_bus.data < nrBlocks ? cpu_bus.data : cpu_bus.data & blockMask;
    assign blockCompute = block < nrBlocks ? {1'b0,block} : 9'h100;

    // Bank switching logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize bank values on reset
            bank[0] <= '{9'h100, 9'h100, 9'h000, 9'h001, 9'h002, 9'h003, 9'h100,  9'h100};
            bank[1] <= '{9'h100, 9'h100, 9'h000, 9'h001, 9'h002, 9'h003, 9'h100,  9'h100};
        end else begin
            if (we && cpu_bus.req) begin
                // Bank switching logic based on address
                    bank[block_info.id][3'd2 +  {1'b0,cpu_bus.addr[1:0]}] <= blockCompute;    
                    $display("Write Zemina 80 [%d] < %x  addr %x value %x ", 3'd2 +  {1'b0,cpu_bus.addr[1:0]}, blockCompute, cpu_bus.addr, cpu_bus.data);
            end
        end
    end

    
    wire  [7:0] bank_base;
    wire        bank_unmaped, ram_valid;
    wire [26:0] ram_addr;
    
    // Calculate bank base and address mapping
    assign {bank_unmaped, bank_base} = bank[block_info.id][cpu_bus.addr[15:13]];
    assign ram_addr = {6'b0, bank_base, cpu_bus.addr[12:0]};

    // Check if the calculated RAM address is within the valid range of the ROM size
    assign ram_valid = (ram_addr < {2'b00, block_info.rom_size}) && ~bank_unmaped && cs && cpu_bus.rd;

    // Assign the final outputs for the mapper
    assign out.ram_cs  = ram_valid;
    assign out.addr    = ram_valid ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
