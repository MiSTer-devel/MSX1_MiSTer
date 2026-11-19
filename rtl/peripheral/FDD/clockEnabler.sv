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

// One clk enable at targetFreq on average: a phase accumulator, the period alternates between the
// two whole clock counts around clkFreq / targetFreq (500 kHz from 21.477 MHz: 42 and 43 clk; a
// fixed 42 ran 2.3 % fast)
module clockEnabler #(
    parameter int clkFreq = MSX::CLK_CORE_HZ,
    parameter int targetFreq = 1000000
)(
    input  logic                                 clk,
    output logic                                 en
);

    localparam int W = $clog2(clkFreq + 1);
    localparam logic [W-1:0] STEP = targetFreq;
    localparam logic [W-1:0] WRAP = clkFreq - targetFreq;

    logic [W-1:0] acc = '0;

    assign en = acc >= WRAP;

    always_ff @(posedge clk) acc <= en ? acc - WRAP : acc + STEP;

endmodule
