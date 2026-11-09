// reset_sync
//
// Copyright (c) 2026 Molekula
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

// Reset synchronizer: asynchronous assert, synchronous release after STAGES clk edges.
// Asserts even while clk is stopped (e.g. PLL in reset), releases cleanly in the domain.
module reset_sync #(parameter STAGES = 2) (
    input  clk,
    input  arst,        // asynchronous, active high
    output rst          // synchronous release, active high
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    logic [STAGES-1:0] sync = '1;

    always_ff @(posedge clk or posedge arst) begin
        if (arst) sync <= '1;
        else      sync <= {sync[STAGES-2:0], 1'b0};
    end

    assign rst = sync[STAGES-1];
endmodule
