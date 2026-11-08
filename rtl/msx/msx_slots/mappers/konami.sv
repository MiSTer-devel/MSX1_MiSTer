// Konami mapper
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

module mapper_konami (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);

    // Control signals for memory mapping
    wire cs, mapped;

    // Mapper is enabled if type is KONAMI and there is a memory request
    assign cs = (block_info.typ == MAPPER_KONAMI) & cpu_bus.mreq;

    // Address is mapped if it's between 0x4000 and 0xBFFF and within ROM size
    assign mapped = (cpu_bus.addr >= 16'h4000) && (cpu_bus.addr < 16'hC000) && (ram_addr < {2'b0, block_info.rom_size});

    // Bank registers for memory banking
    logic [7:0] bank1[2], bank2[2], bank3[2];

    // Bank switching logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize bank values on reset
            bank1 <= '{'h01, 'h01};  // Default bank 1 values
            bank2 <= '{'h02, 'h02};  // Default bank 2 values
            bank3 <= '{'h03, 'h03};  // Default bank 3 values
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req) begin
                // Bank switching logic based on address
                case (cpu_bus.addr[15:13])
                    3'b011: // 6000-7FFFh: Switch bank 1
                        bank1[block_info.id] <= cpu_bus.data;
                    3'b100: // 8000-9FFFh: Switch bank 2
                        bank2[block_info.id] <= cpu_bus.data;
                    3'b101: // A000-BFFFh: Switch bank 3
                        bank3[block_info.id] <= cpu_bus.data;
                    default: ; // No action for other address ranges
                endcase
            end
        end
    end

    // Bank selection logic based on address ranges
    wire [7:0] bank_base = (cpu_bus.addr[15:13] == 3'b010) ? 8'h00 :                 // Fixed bank for 4000-5FFFh
                           (cpu_bus.addr[15:13] == 3'b011) ? bank1[block_info.id] :  // Bank 1 for 6000-7FFFh
                           (cpu_bus.addr[15:13] == 3'b100) ? bank2[block_info.id] :  // Bank 2 for 8000-9FFFh
                                                             bank3[block_info.id];   // Bank 3 for A000-BFFFh

    // Generate RAM address based on bank and lower address bits
    wire [26:0] ram_addr = {6'b0, bank_base, cpu_bus.addr[12:0]};

    // Output enable signal (only if mapped and chip select is active)
    wire oe = cs && mapped && cpu_bus.rd;

    // Output assignments to the `out` interface
    assign out.addr   = oe ? ram_addr : '1;    // Output address, or '1 if not enabled
    assign out.ram_cs = oe;                    // RAM chip select signal

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
