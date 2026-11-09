// WD279x FDC
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
//

// Type III commands.
//   Read Address (C0h): the six bytes of the next ID field go to the CPU one byte time apart,
//     the sector register gets the track byte, CRC error as on the disk, record not found after
//     five index pulses.
//   Read Track (E0h): every byte the demodulator yields from index to index. It keeps its byte
//     sync through the gaps, so only the bytes before the first mark after the index are lost.
//   Write Track (F0h): DRQ at once, Lost Data and end when it is not serviced before the index;
//     then from index to index the CPU's bytes: MFM F5 = A1 (presets the CRC), F6 = C2, F7 = the
//     two CRC bytes; FM F7 = CRC, F8-FC and FE = marks with missing clocks; a byte the CPU did not
//     supply in time goes out as 00 with Lost Data. A write protected disk ends with status bit 6.
module wd279x_command_III
(
	input  logic        clk,
	input  logic        msclk,
	input  logic        interrupt,
	input  logic        MRn,
	input  logic        command_start,
	input  logic  [7:0] command,
	output logic  [7:0] status,
	output logic        INTRQ,
	input  logic        INTRQ_ACK,
	input  logic        DRQ,
	output logic        drq_set,         // 1 clk: the CPU may give the next byte
	output logic  [7:0] data_out,        // byte for the data register, with DRQ
	output logic        data_write,
	output logic  [7:0] sector_out,
	output logic        sector_write,

	input  logic        INDEXn,
	input  logic        READYn,
	input  logic        WPROTn,
	input  logic        DDENn,
	output logic        HLD,

	// demodulator
	input  logic  [7:0] IDAM_data[6],
	input  logic        IDAM_done,
	input  logic        IDAM_crc_ok,
	input  logic  [7:0] fdd_data,
	input  logic        fdd_rx,

	// modulator
	input  logic  [7:0] reg_data,
	input  logic        tx_req,
	output logic        wg,
	output logic        tx_wr,
	output logic        tx_a1,
	output logic        tx_c2,
	output logic        tx_mark,
	output logic        tx_crc,
	output logic  [7:0] tx_data,
	input  logic        byte_tick
);

	wire is_III = command[7:6] == 2'b11 && command[5:4] != 2'b01;	// C0, E0, F0 (D0 is type IV)
	wire cmd_ra = command[5:4] == 2'b00;
	wire cmd_rt = command[5:4] == 2'b10;
	wire cmd_wt = command[5:4] == 2'b11;

	typedef enum {
		S_IDLE, S_PREPARE, S_DELAY,
		S_RA_WAIT, S_RA_SEND, S_RA_END,
		S_RT_WAIT, S_RT_READ,
		S_WT_WAIT, S_WT_WRITE
	} state_t;
	state_t state;

	logic busy;
	logic reg_WRITE_PROTECTED, reg_RECORD_NOT_FOUND, reg_CRC_ERROR, reg_LOST_DATA;
	logic [4:0] wait_count;
	logic [2:0] index_count, ra_idx;
	logic       last_index;
	wire        index_edge = last_index && !INDEXn;

	assign busy = state != S_IDLE;
	assign status = !is_III ? 8'h00 :
	                {READYn, reg_WRITE_PROTECTED, 1'b0, reg_RECORD_NOT_FOUND, reg_CRC_ERROR, reg_LOST_DATA, DRQ, busy};

	always_ff @(posedge clk) begin
		{drq_set, data_write, sector_write, tx_wr, tx_a1, tx_c2, tx_mark, tx_crc} <= '0;
		last_index <= INDEXn;
		if (index_edge) index_count <= index_count + 3'd1;

		if (~MRn || interrupt) begin
			state <= S_IDLE;
			reg_WRITE_PROTECTED  <= 0;
			reg_RECORD_NOT_FOUND <= 0;
			reg_CRC_ERROR        <= 0;
			reg_LOST_DATA        <= 0;
			HLD   <= 0;
			INTRQ <= 0;
			wg    <= 0;
		end else begin
			if (INTRQ_ACK) INTRQ <= 0;
			case (state)
				S_IDLE:
					if (command_start && is_III) begin
						INTRQ <= 0;
						reg_WRITE_PROTECTED  <= 0;
						reg_RECORD_NOT_FOUND <= 0;
						reg_CRC_ERROR        <= 0;
						reg_LOST_DATA        <= 0;
						state <= S_PREPARE;
					end
				S_PREPARE:
					if (READYn) begin
						INTRQ <= 1;
						state <= S_IDLE;
					end else begin
						HLD        <= 1;
						wait_count <= command[2] ? 5'd15 : 5'd0;	// E: 15 ms head settle
						state      <= S_DELAY;
					end
				S_DELAY:
					if (wait_count != 5'd0) begin
						if (msclk) wait_count <= wait_count - 5'd1;
					end else begin
						index_count <= 3'd0;
						if (cmd_ra) state <= S_RA_WAIT;
						if (cmd_rt) state <= S_RT_WAIT;
						if (cmd_wt) begin
							if (!WPROTn) begin
								reg_WRITE_PROTECTED <= 1;
								INTRQ <= 1;
								state <= S_IDLE;
							end else begin
								drq_set <= 1;
								state   <= S_WT_WAIT;
							end
						end
					end

				// --- Read Address
				S_RA_WAIT:
					if (index_count > 3'd4) begin
						reg_RECORD_NOT_FOUND <= 1;
						INTRQ <= 1;
						state <= S_IDLE;
					end else if (IDAM_done) begin
						reg_CRC_ERROR <= !IDAM_crc_ok;
						sector_out    <= IDAM_data[0];
						sector_write  <= 1;
						data_out      <= IDAM_data[0];
						data_write    <= 1;
						ra_idx        <= 3'd1;
						state         <= S_RA_SEND;
					end
				S_RA_SEND:
					if (byte_tick) begin
						if (ra_idx < 3'd6) begin
							if (DRQ) reg_LOST_DATA <= 1;
							data_out   <= IDAM_data[ra_idx];
							data_write <= 1;
							ra_idx     <= ra_idx + 3'd1;
						end else
							state <= S_RA_END;
					end
				S_RA_END:
					if (!DRQ) begin						// the CPU took the last byte
						INTRQ <= 1;
						state <= S_IDLE;
					end

				// --- Read Track
				S_RT_WAIT:
					if (index_edge) state <= S_RT_READ;
				S_RT_READ:
					if (index_edge) begin
						INTRQ <= 1;
						state <= S_IDLE;
					end else if (fdd_rx) begin
						if (DRQ) reg_LOST_DATA <= 1;
						data_out   <= fdd_data;
						data_write <= 1;
					end

				// --- Write Track
				S_WT_WAIT:
					if (index_edge) begin
						if (DRQ) begin					// first byte not supplied before the index
							reg_LOST_DATA <= 1;
							INTRQ <= 1;
							state <= S_IDLE;
						end else begin
							wg    <= 1;
							state <= S_WT_WRITE;
						end
					end
				S_WT_WRITE:
					if (index_edge) begin
						wg    <= 0;
						INTRQ <= 1;
						state <= S_IDLE;
					end else if (tx_req) begin
						drq_set <= 1;
						tx_data <= reg_data;
						if (DRQ) begin					// not supplied in time: 00
							tx_wr         <= 1;
							tx_data       <= 8'h00;
							reg_LOST_DATA <= 1;
						end else if (!DDENn) begin		// MFM
							case (reg_data)
								8'hF5:   tx_a1  <= 1;
								8'hF6:   tx_c2  <= 1;
								8'hF7:   tx_crc <= 1;
								default: tx_wr  <= 1;
							endcase
						end else begin					// FM
							case (reg_data)
								8'hF7:   tx_crc  <= 1;
								8'hF8, 8'hF9, 8'hFA, 8'hFB, 8'hFC, 8'hFE: tx_mark <= 1;
								default: tx_wr   <= 1;
							endcase
						end
					end
				default: state <= S_IDLE;
			endcase
		end
	end
endmodule
