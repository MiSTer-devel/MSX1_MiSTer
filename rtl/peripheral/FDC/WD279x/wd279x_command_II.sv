// WD279x FDC
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
//

// Type II commands: Read Sector (8x) and Write Sector (Ax).
// Write Sector after the matching ID: DRQ two byte times later, Lost Data and end when it is
// not serviced within 11 (MFM) / 8 (FM) byte times, the gate opens after 22 / 11, then 12 / 6
// sync bytes, A1 A1 A1 (MFM) and the data mark FB (F8 with a0), the data bytes (a byte the CPU
// did not supply in time goes out as 00 with Lost Data), the CRC and one gap byte, then the
// gate closes. With m the next sector follows.
// WD2795/7 (WD279_57): no side compare (bit 1 is U, the SSO output of wd279x), the sector length
// follows L through len_add.
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
	input  logic        DDENn,
	input  logic  [1:0] len_add,     // added to N of the ID for the data length (WD2795/7 L = 0: 1)
	output logic        HLD,

	output logic  [7:0] status,
	output logic        INTRQ,
	input  logic        INTRQ_ACK,
	input  logic        DRQ,
	output logic        drq_set,     // 1 clk: the CPU may give the next byte

	input  logic  [7:0] track,
	input  logic  [7:0] sector,
	output logic  [7:0] sector_out,
	output logic        sector_write,

	// write path (wd279x_modulator)
	input  logic  [7:0] reg_data,
	input  logic        tx_req,
	input  logic        tx_idle,
	input  logic        byte_tick,
	output logic        wg,
	output logic        tx_wr,
	output logic        tx_a1,
	output logic        tx_mark,
	output logic        tx_crc,
	output logic  [7:0] tx_data
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
		STATE_CRC_CHECK,
		STATE_CMD_END,
		STATE_WR_GAP,
		STATE_WR_SYNC,
		STATE_WR_MARK,
		STATE_WR_DATA,
		STATE_WR_CRC,
		STATE_WR_END
	} sector_state_t;

	sector_state_t state;

	logic busy;
	logic reg_CRC_ERROR;
	logic reg_LOST_DATA;
	logic reg_RECORD_NOT_FOUND;
	logic reg_WRITE_PROTECTED;
	logic reg_RECORD_TYPE;

	logic [4:0]  wait_count;
	logic [2:0]  index_count;
	logic        last_index;
	logic [1:0]  crc_count;
	logic [5:0]  gap_cnt;               // byte times after the ID field
	logic [3:0]  sync_cnt;
	logic [1:0]  mark_cnt;
	logic [10:0] wr_cnt;                // data bytes left (128 << N)
	logic        gap_sent;

	assign busy = state != STATE_IDLE;
	// bit 6: write protect (writes), bit 5: record type (reads) / write fault 0 (writes)
	assign status = command[7:6] != 2'b10 ? 8'h00 :
	                {READYn, reg_WRITE_PROTECTED, reg_RECORD_TYPE, reg_RECORD_NOT_FOUND, reg_CRC_ERROR, reg_LOST_DATA, DRQ, busy};
	assign enable_write_reg_data = state == STATE_READ;

	always_ff @(posedge clk) begin
		sector_write <= 0;
		{drq_set, tx_wr, tx_a1, tx_mark, tx_crc} <= '0;

		if (~MRn || interrupt) begin
			state <= STATE_IDLE;
			reg_CRC_ERROR <= 0;
			reg_LOST_DATA <= 0;
			reg_RECORD_NOT_FOUND <= 0;
			reg_WRITE_PROTECTED <= 0;
			reg_RECORD_TYPE <= 0;
			HLD <= 0;
			INTRQ <= 0;
			wg <= 0;
			gap_sent <= 0;
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
							reg_WRITE_PROTECTED <= 0;
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
						if (command[5] && !WPROTn) begin	// write on a protected disk
							INTRQ <= 1;
							state <= STATE_IDLE;
							reg_WRITE_PROTECTED <= 1;
						end
					end
				STATE_CHECK_II: begin
					if (index_count > 4) begin
						state <= STATE_IDLE;
						INTRQ <= 1;
						reg_RECORD_NOT_FOUND <= 1;
					end else
						if (IDAM_valid && !DAM_valid)
							if (IDAM_data[ID_TRACK] == track && IDAM_data[ID_SECTOR] == sector)
									if (WD279_57 == 1 ||  command[1] == 0 || IDAM_data[ID_SIDE][0] == command[3]) begin
										state   <= command[5] ? STATE_WR_GAP : STATE_WAIT_DAM;
										gap_cnt <= '0;
										wr_cnt  <= 11'd128 << 2'(IDAM_data[ID_LENGHT][1:0] + len_add);
									end
				end
				STATE_WAIT_DAM: begin
					if (~IDAM_valid) state <= STATE_CHECK_II;	// DAM timeout
					if (DAM_valid) begin
						reg_RECORD_TYPE <= DAM_deleted;
						state <= STATE_READ;
					end
				end
				STATE_READ: begin
					if (data_rx && DRQ) reg_LOST_DATA <= 1;		// the CPU did not take the previous byte
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

				// --- write: gap after the ID with the gate closed
				STATE_WR_GAP:
					if (byte_tick) begin
						gap_cnt <= gap_cnt + 6'd1;
						if (gap_cnt == 6'd1) drq_set <= 1;
						if (gap_cnt == (DDENn ? 6'd7 : 6'd10) && DRQ) begin
							reg_LOST_DATA <= 1;
							INTRQ <= 1;
							state <= STATE_IDLE;
						end
						if (gap_cnt == (DDENn ? 6'd10 : 6'd21)) begin
							wg       <= 1;
							sync_cnt <= DDENn ? 4'd6 : 4'd12;
							mark_cnt <= DDENn ? 2'd0 : 2'd3;
							state    <= STATE_WR_SYNC;
						end
					end
				STATE_WR_SYNC:
					if (tx_req) begin
						tx_wr    <= 1;
						tx_data  <= 8'h00;
						sync_cnt <= sync_cnt - 4'd1;
						if (sync_cnt == 4'd1) state <= STATE_WR_MARK;
					end
				STATE_WR_MARK:
					if (tx_req) begin
						if (mark_cnt != 2'd0) begin
							tx_a1    <= 1;
							mark_cnt <= mark_cnt - 2'd1;
						end else begin
							tx_mark <= 1;
							tx_data <= command[0] ? 8'hF8 : 8'hFB;
							state   <= STATE_WR_DATA;
						end
					end
				STATE_WR_DATA:
					if (tx_req) begin
						tx_wr <= 1;
						if (DRQ) begin					// not supplied in time
							tx_data       <= 8'h00;
							reg_LOST_DATA <= 1;
						end else
							tx_data <= reg_data;
						wr_cnt <= wr_cnt - 11'd1;
						if (wr_cnt == 11'd1) state <= STATE_WR_CRC;
						else                 drq_set <= 1;
					end
				STATE_WR_CRC:
					if (tx_req) begin
						tx_crc <= 1;
						state  <= STATE_WR_END;
					end
				STATE_WR_END:
					if (!gap_sent) begin
						if (tx_req) begin
							tx_wr    <= 1;
							tx_data  <= DDENn ? 8'hFF : 8'h4E;
							gap_sent <= 1;
						end
					end else if (tx_idle) begin			// the last byte is on the disk
						wg       <= 0;
						gap_sent <= 0;
						if (command[4]) begin			//Multiple
							sector_out   <= sector + 8'd1;
							sector_write <= 1;
							state        <= STATE_CHECK;
						end else begin
							INTRQ <= 1;
							state <= STATE_IDLE;
						end
					end
				default: ;
			endcase
		end
	end
endmodule

