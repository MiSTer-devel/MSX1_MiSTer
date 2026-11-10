// Reset staus device
//
// Copyright (c) 2024-2025 Molekula
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

// Port F4 (reset status): cleared only by a cold reset, so the BIOS can tell a warm boot
// (MSX2+ skips the logo); as OCM portF4_bit7 (pColdReset).
module dev_reset_status (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],
    input                   hard_reset,     // cold reset (power-up, MiSTer menu, pack upload)
    output            [7:0] data
);

    logic [7:0] status[3];
    wire io_en = cpu_bus.iorq && ~cpu_bus.m1;
    assign data = status[0] & status[1] & status[2];

    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : RESET_STATUS_DEV_INSTANCES
            if (i < MSX::N_RESET_STATUS) begin : inst
                wire cs_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
                wire cs_enable = io_device[i].enable && cs_active && io_en;

                reset_status latch_port_i (
                    .clk(cpu_bus.clk),
                    .reset(hard_reset),
                    .data(cpu_bus.data),
                    .wr(cs_enable && cpu_bus.wr && cpu_bus.req),
                    .rd(cs_enable && cpu_bus.rd),
                    .status(status[i]),
                    .inverted(io_device[i].param[0])
                );
            end else begin : none
                assign status[i] = 8'hFF;
            end
        end
    endgenerate

endmodule

module reset_status (
    input              clk,
    input              reset,
    input        [7:0] data,
    input              wr,
    input              rd,
    input              inverted,
    output       [7:0] status
);
    logic [7:0] r_status;
    // Sync reset: async reset loading a non-constant value was synthesized as latches
    always_ff @(posedge clk) begin
        if (reset) begin
            r_status <= inverted ? 8'hFF : 8'h00;
        end else if (wr) begin
            r_status <= inverted ? data | 8'h7F : (r_status & 8'h20) | (data & 8'hA0);
        end
    end

    assign status = rd ? r_status : 8'hFF;

endmodule
