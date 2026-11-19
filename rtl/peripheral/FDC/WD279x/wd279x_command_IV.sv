// WD279x FDC
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

module wd279x_command_IV 
(
	input  logic        clk,         // sys clock
	output logic        interrupt,
	input  logic        MRn,	     // master reset
	input  logic        command_start,
	input  logic  [7:0] command,
	output logic  [7:0] status,
	output logic        INTRQ,
	input  logic        INTRQ_ACK,
	input  logic 		INDEXn,
	input  logic        READYn,
	input  logic 		WPROTn,
	input  logic 		TRK00n,
	input  logic        HLD
);

	assign status = command[7:4] != 4'hD ? 8'h00 : {READYn, ~WPROTn, HLD, 1'b0, 1'b0, ~TRK00n, ~INDEXn, 1'b0};

	logic last_READY;
	always_ff @(posedge clk) begin
		last_READY <= READYn;
		interrupt <= 0;
		
		if (~MRn) begin
			INTRQ <= 0;
		end else begin
			if (command_start) INTRQ <= 0;

			if (INTRQ_ACK) INTRQ <= 0;

			if (command[7:4] == 4'hD) begin
				if (command_start) begin
					INTRQ <= command[3];
					interrupt <= 1;
				end
				if (command[0] && !READYn && last_READY) INTRQ <= 1;
				if (command[1] && READYn && !last_READY) INTRQ <= 1;
				if (command[2] && !INDEXn) INTRQ <= 1;
			end
		end
	end
endmodule

