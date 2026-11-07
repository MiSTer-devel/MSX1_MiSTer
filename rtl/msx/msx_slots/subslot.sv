// subslot 
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

module subslot (
    cpu_bus_if.device_mp    cpu_bus,                  // Interface for CPU communication
    input MSX::slot_expander_t slot_expander_conf[4], 
    input             [1:0] active_slot,              // Currently active slot
    input                   expander_force_en,        // Enable signals for the expander
    output            [7:0] data,           // Data output
    output            [1:0] active_subslot, // Currently active subslot
    output                  output_rq      // Chip select signal
);

    // Array to store mapper slot data for 4 slots
    logic [7:0] mapper_slot[3:0];

    // Chip select is active when the address is 0xFFFF, the expander is enabled for the active slot, and there's a memory request
    wire mapper_cs = (cpu_bus.addr == 16'hFFFF) && cpu_bus.mreq && (slot_expander_conf[active_slot].en || expander_force_en);
    
    // Write enable is active when chip select and write request are active
    wire mapper_wr = mapper_cs && cpu_bus.wr && cpu_bus.req;
    
    // Read enable is active when chip select and read request are active
    wire mapper_rd = mapper_cs && cpu_bus.rd;// && ~expander_wo;

    // Sync reset: async reset loading a non-constant init was synthesized as latches
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Initialize mapper_slot array on reset
            mapper_slot[0] <= slot_expander_conf[0].init;
            mapper_slot[1] <= slot_expander_conf[1].init;
            mapper_slot[2] <= slot_expander_conf[2].init;
            mapper_slot[3] <= slot_expander_conf[3].init;
        end else if (mapper_wr) begin
            // Write to the currently active slot
            mapper_slot[active_slot] <= cpu_bus.data;
        end
    end

    // Block selection based on the address (2 bits representing blocks of memory)
    wire [1:0] block = cpu_bus.addr[15:14];

    // If a read is requested, return the inverted value from the active slot, otherwise return 0xFF
    assign data = mapper_rd ? ~mapper_slot[active_slot] : 8'hFF;

    // Select the active subslot based on the block and the current mapper_slot value
    assign active_subslot = mapper_slot[active_slot][(3'd2 * block) +: 2];  

    // Chip select output signal
    assign output_rq = mapper_rd;

endmodule
