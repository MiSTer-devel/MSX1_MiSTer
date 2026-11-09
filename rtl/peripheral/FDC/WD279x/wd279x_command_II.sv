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

module wd279x_command_II  #(parameter WD279_57=1) 
(
	input  logic        clk,         // sys clock
	input  logic        msclk,       // clock 1ms enable
	input  logic        interrupt,
	input  logic        MRn,	     // master reset
	input  logic        command_start,
	input  logic  [7:0] command,
	input  logic        IDAM_valid,
	input  logic  [7:0] IDAM_data[6],
	input  logic        DAM_valid,
	input  logic        DAM_deleted,
	input  logic 	    DAM_CRC_valid,	
	input  logic        data_rx,
	output logic        enable_write_reg_data,

	input  logic 		INDEXn,
	input  logic        READYn,
	input  logic		WPROTn,
	output logic        SSO,
	output logic        HLD,

	output logic  [7:0] status,
	output logic        INTRQ,
	input  logic        INTRQ_ACK,
	input  logic        DRQ,	  
	
	input  logic  [7:0] track,
	input  logic  [7:0] sector,
	output logic  [7:0] sector_out,
	output logic        sector_write
);

	localparam ID_TRACK  = 0;
    localparam ID_SIDE   = 1;
    localparam ID_SECTOR = 2;
    localparam ID_LENGHT = 3;
    localparam ID_CRC1   = 4;
    localparam ID_CRC2   = 5;

	typedef enum {
		STATE_IDLE,
		STATE_PREPARE,
		STATE_CHECK,
		STATE_CHECK_II,
		STATE_WAIT_DAM,
		STATE_READ,
		STATE_WRITE,
		STATE_CRC_CHECK,
		STATE_CMD_END
		
	} sector_state_t;

	sector_state_t state;

	logic busy;
	logic reg_CRC_ERROR;
	logic reg_LOST_DATA;
	logic reg_RECORD_NOT_FOUND;
	//logic reg_WRITE_PROTECTED;
	logic reg_RECORD_TYPE;

	logic [4:0] wait_count;
	logic [2:0] index_count;
	logic       last_index;
	logic [1:0] crc_count;

	assign SSO = 0; //TODO: Implement SSO for WD2795/7

	assign busy = state != STATE_IDLE;
	assign status = command[7:6]            != 2'b10 ? 8'h00 : {READYn, 1'b0, reg_RECORD_TYPE, reg_RECORD_NOT_FOUND, reg_CRC_ERROR, reg_LOST_DATA, DRQ, busy};
	assign enable_write_reg_data = state == STATE_READ;

	always_ff @(posedge clk) begin
		sector_write <= 0;

		if (~MRn || interrupt) begin
			state <= STATE_IDLE;
			reg_CRC_ERROR <= 0;
			reg_LOST_DATA <= 0;
			reg_RECORD_NOT_FOUND <= 0;
//			reg_WRITE_PROTECTED <= 0;
			reg_RECORD_TYPE <= 0;
			HLD <= 0;
			INTRQ <= 0;
			if (WD279_57) SSO <= 0;
		end else begin
			last_index <= INDEXn;
			if (last_index && !INDEXn) index_count <= index_count + 3'd1;
			if (INTRQ_ACK) INTRQ <= 0;
			case(state)
				STATE_IDLE: begin
					if (command_start) begin
						INTRQ <= 0;
						if (command[7:6] == 2'b10) begin
							$display("Command II m(%d) Track Side sector: %X %X %X %t", command[4], track, command[3], sector, $time);
							reg_CRC_ERROR <= 0;
							reg_LOST_DATA <= 0;
							reg_RECORD_NOT_FOUND <= 0;
							//reg_WRITE_PROTECTED <= 0;
							reg_RECORD_TYPE <= 0;
							state <= STATE_PREPARE;
						end
					end
				end
				STATE_PREPARE: begin
					if (READYn) begin
						state <= STATE_IDLE;
						INTRQ <= 1;
					end else begin
						if (WD279_57) begin
							SSO <= command[1];
						end
						HLD <= 1;
						state <= STATE_CHECK;
						wait_count <= command[2] ? 5'd15 : 5'd0 ;		//WAIT 15ms or 0ms
					end				
				end
				STATE_CHECK:
					if (wait_count > 0) begin
						if (msclk) wait_count <= wait_count - 5'd1;
					end else begin
						state <= STATE_CHECK_II;
						index_count <= 0;
						if (command[5]) begin				 // Write ?
							if (!WPROTn) begin
								INTRQ <= 1;
								state <= STATE_IDLE;
								//reg_WRITE_PROTECTED <= 1;
							end
						end
					end
				STATE_CHECK_II: begin
					if (index_count > 4) begin
						state <= STATE_IDLE;
						INTRQ <= 1;
						reg_RECORD_NOT_FOUND <= 1;
						//$display("RECORD_NOT_FOUND");
					end else
						if (IDAM_valid && !DAM_valid)
							if (IDAM_data[ID_TRACK] == track && IDAM_data[ID_SECTOR] == sector)
									if (WD279_57 == 1 ||  command[1] == 0 || IDAM_data[ID_SIDE][0] == command[3]) begin
										state <= STATE_WAIT_DAM;
										//$display("RECORD FOUND");
									end
				end
				STATE_WAIT_DAM: begin
					if (~IDAM_valid) state <= STATE_CHECK_II;	// DAM timeout
					if (DAM_valid) begin
						reg_RECORD_TYPE <= DAM_deleted;
						state <= command[5] ? STATE_WRITE : STATE_READ;
					end
				end
				STATE_READ: begin
					if (!DAM_valid) begin
						state <= STATE_CRC_CHECK;
						crc_count <= 2;
					end
				end
				STATE_CRC_CHECK: begin
					if (crc_count > 0 ) begin
						if (data_rx) crc_count <= crc_count - 2'd1;
					end else begin
						if (DAM_CRC_valid) begin
							if (command[4]) begin			//Multiple
								sector_out <= sector + 8'd1;
								sector_write <= 1;
								//$display("Command II m(%d) Track Side sector: %X %X %X NEXT", command[4], track, command[3], sector + 1);
								state <= STATE_CHECK;
							end else begin
								state <= STATE_CMD_END;
							end
						end else begin
							reg_CRC_ERROR <= 1;
							INTRQ <= 1;
							state <= STATE_IDLE;
						end
					end
				end
				STATE_CMD_END:
					if (!DRQ) begin				// Konec prikazu az po precteni posledniho byte.
						INTRQ <= 1;
						state <= STATE_IDLE;
					end
				default: ;
			endcase
		end
	end
endmodule

