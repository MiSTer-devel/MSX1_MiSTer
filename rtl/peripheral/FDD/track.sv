// track
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

// Head position of the two drives: a STEP pulse (falling edge) moves the head of the selected
// drive in the SDIR direction (1 = in). The stop is past the last track of a disk, as in a real
// drive (openMSX RealDrive: 85).
module track #(parameter int MAX_TRACK = 85)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        USEL,
    input  logic        STEPn,
    input  logic        SDIRn,
    output logic  [6:0] track           // head position of the selected drive
);
    logic [6:0] head[2];
    logic       last_STEPn;

    always_ff @(posedge clk) begin
        last_STEPn <= STEPn;
        if (reset) begin
            head <= '{7'd0, 7'd0};
        end else if (!STEPn && last_STEPn) begin
            if (SDIRn) begin
                if (head[USEL] < 7'(MAX_TRACK)) head[USEL] <= head[USEL] + 7'd1;
            end else begin
                if (head[USEL] != 7'd0) head[USEL] <= head[USEL] - 7'd1;
            end
        end
    end

    assign track = head[USEL];

endmodule
