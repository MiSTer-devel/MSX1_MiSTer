// subslot 
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

module subslot (
    cpu_bus_if.device_mp    cpu_bus,                  // Interface for CPU communication
    input MSX::slot_expander_t slot_expander_conf[4], 
    input             [1:0] active_slot,              // Currently active slot
    input                   expander_force_en,        // Enable signals for the expander
    output            [7:0] data,           // Data output
    output            [1:0] active_subslot, // Currently active subslot
    output                  output_rq,     // Read of the register (data priority)
    output                  cs             // Any access to the register: hides the memory below
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

    assign output_rq = mapper_rd;
    assign cs        = mapper_cs;

endmodule
