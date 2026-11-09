// clockEnabler
//
// Copyright (c) 2025-2026 Molekula
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

module clockEnabler #(
    parameter int clkFreq = MSX::CLK_CORE_HZ,
    parameter int targetFreq = 1000000
)(
    input  logic                                 clk,
    output logic                                 en
);

    localparam int maxCount = clkFreq / targetFreq - 1;

    logic [$clog2(maxCount+1)-1:0] counter;

    always_comb begin
        en = counter == 0;
    end

    // Generování enable signálu
    always_ff @(posedge clk) begin
        if (counter > 0) begin
            counter <= counter - 1'b1;
        end else begin
            counter <= ($clog2(maxCount+1))'(maxCount);
        end
    end

endmodule
