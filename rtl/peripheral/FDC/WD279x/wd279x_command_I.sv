// WD279x FDC
//
// Copyright (c) 2025 Molekula
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

module wd279x_command_I
(
	input  logic        clk,         // sys clock
	input  logic        msclk,       // clock 1ms enable
	input  logic        interrupt,
	input  logic        MRn,	     // master reset
	input  logic        command_start,
	input  logic  [7:0] command,
	input  logic  [7:0] reg_data,
	output logic  [7:0] reg_data_out,
	output logic        reg_data_write,
	output logic  [7:0] status,
	output logic        INTRQ,
	input  logic        INTRQ_ACK,
	output logic 		STEPn,
	output logic 		SDIRn,
	input  logic 		INDEXn,
	input  logic 		READYn,
	input  logic 		WPROTn,
	input  logic 		TRK00n,
	output logic        HLD,


	input  logic  [7:0] track,
	output logic  [7:0] track_out,
	output logic  		track_write,

	input  logic		IDAM_valid,	
	input  logic  [7:0] IDAM_data[6]
);

	localparam ID_TRACK  = 0;
    localparam ID_SIDE   = 1;
    localparam ID_SECTOR = 2;
    localparam ID_LENGHT = 3;
    localparam ID_CRC1   = 4;
    localparam ID_CRC2   = 5;

	typedef enum {
		STATE_IDLE,
		STATE_STEP_A,
		STATE_STEP_BC,
		STATE_STEP_WAIT,
		STATE_VERIFY,
		STATE_VERIFY_II,
		STATE_VERIFY_III
	} step_state_t;

	step_state_t state;

	logic busy;
	
	logic reg_CRC_ERROR;
	logic reg_SEEK_ERROR;
	logic [7:0] track_rq;
	logic [4:0] wait_count;
	logic [2:0] index_count;
	logic       last_index;

	assign busy = state != STATE_IDLE;
	assign status = command[7] ? 8'h00 : {READYn, ~WPROTn, HLD, reg_SEEK_ERROR, reg_CRC_ERROR, ~TRK00n, ~INDEXn, busy};
	

	always_ff @(posedge clk) begin
		track_write <= 0;
		last_index <= INDEXn;
		if (last_index && !INDEXn) index_count <= index_count + 3'd1;
		if (~MRn || interrupt) begin
			STEPn <= 1;
			SDIRn <= 1;
			HLD <= 1;
			reg_CRC_ERROR <= 0;
			reg_SEEK_ERROR <= 0;
			INTRQ <= 0;
			state <= STATE_IDLE;
			reg_data_write <= 0;
		end else begin
			reg_data_write <= 0;
			if (INTRQ_ACK) INTRQ <= 0;
			case(state)
				STATE_IDLE: begin
					if (command_start) begin
						INTRQ <= 0;
						if (!command[7]) begin
							reg_CRC_ERROR <= 0;
							reg_SEEK_ERROR <= 0;
							HLD <= command[3];				// h = 1: load the head
							state <= STATE_STEP_BC;
							$display("Command I Track %X Command %x dataReg %X %t", track, command, reg_data, $time);
							case(command[6:5])
								2'b00: begin
									if (!command[4]) begin				// RESTORE
										track_out <= 8'hFF;
										track_rq      <= 0;
										track_write <= 1;
										reg_data_out <= '0;
										reg_data_write <= 1;
									end else begin						// SEEK
										track_rq      <= reg_data;
									end
									state           <= STATE_STEP_A;
								end
								2'b01: begin							// Step
									if (SDIRn) begin
										track_rq      <= track + 8'd1;
										track_out <= track + 8'd1;
									end else begin
										track_rq      <= track - 8'd1;
										track_out <= track - 8'd1;
									end
									track_write <= command[4];
								end
								2'b10: begin							// Step in
									SDIRn           <= 1;
									track_rq        <= track + 8'd1;
									track_out   <= track + 8'd1;
									track_write <= command[4];
								end
								2'b11: begin							// Step out
									SDIRn           <= 0;
									track_rq        <= track - 8'd1;
									track_out   <= track - 8'd1;
									track_write <= command[4];
								end
							endcase					
						end
					end
				end
				STATE_STEP_A: begin
					state <= STATE_STEP_BC;
					if (track == track_rq) begin
						state <= STATE_VERIFY;
					end else begin
						if (track_rq > track) begin
							SDIRn <= 1;
							track_out <= track_out + 8'd1;
						end else begin
							SDIRn <= 0;
							track_out <= track_out - 8'd1;
						end
						track_write <= 1;
					end
				end
				STATE_STEP_BC: begin
					if (!SDIRn && !TRK00n) begin
						track_out <= 0;
						track_write <= 1;
						state <= STATE_VERIFY;
					end else begin
						state <= STATE_STEP_WAIT;
						STEPn <= 0;
						case(command[1:0])
							2'b00: wait_count <= 6;
							2'b01: wait_count <= 12;
							2'b10: wait_count <= 20;
							2'b11: wait_count <= 30;
						endcase
					end
				end
				STATE_STEP_WAIT: begin
					STEPn <= 1;
					if (msclk) begin
						if (wait_count == 0) begin
							if (command[7:5] == 3'b000) // SEEK, RESTORE
								state <= STATE_STEP_A;
							else 
								state <= STATE_VERIFY;
						end else begin
							wait_count <= wait_count - 5'd1;
						end
					end
				end
				STATE_VERIFY: begin
					if (!command[2]) begin
						state <= STATE_IDLE;
						INTRQ <= 1;
					end else begin
						HLD <= 1;
						wait_count <= 15;
						state <= STATE_VERIFY_II;
					end
				end
				STATE_VERIFY_II: begin
					if (wait_count != 0) begin
						if (msclk) begin
							wait_count <= wait_count - 5'd1;
							index_count <= 0;
						end
					end else begin			// Lze kontrolovat
						if (index_count > 4) begin
							state <= STATE_IDLE;
							INTRQ <= 1;
							reg_SEEK_ERROR <= 1;
						end
						if (IDAM_valid && IDAM_data[ID_TRACK] == track_rq) begin
							state <= STATE_IDLE;
							INTRQ <= 1;
						end
					end
				end
				default: ;
			endcase
		end
	end
endmodule
