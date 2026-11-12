//============================================================================
//  MSX1 CAS Player
//  Copyright (C) 2022 molekula
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================
// https://konamiman.github.io/MSX2-Technical-Handbook/md/Chapter5a.html#2-cassette-interface
module tape
(
	input           clk,
	input           ce_5m3,
	input           play,
	input           rewind,
	input 			enable,
	input   [26:0]  size,           // file size in bytes, 0 = unknown (plays on past the end)
	output  logic [27:0]	ram_a,
	input   [7:0]   ram_di,
	output  logic     ram_rd,
	input           buff_mem_ready,
	output          cas_out
);

// Signal: FSK 2400 Bd, 4 phases per bit (ce_baud = ce_5m3 / 560 = 9588 Hz).
// "0" = one cycle 2400 Hz, "1" = two cycles 4800 Hz. Frame: start 0, 8 data bits
// LSB first, 2 stop bits 1. Each CAS block (8-byte header in DDR3) is sent as
// a sync of ones followed by the data up to the next header; silence before the first.
// Headers may start at any byte (not every CAS file pads blocks to 8 bytes).
// After the last byte of the file the output goes silent.

typedef enum
{
	STATE_SLEEP,
	STATE_INIT,
	STATE_SEARCH,
	STATE_PLAY_SILENT,
	STATE_PLAY_SYNC,
	STATE_PLAY_DATA
} player_state_t;

player_state_t  state = STATE_SLEEP;

localparam logic [63:0] CAS_HEADER = 64'h747d13ccbadea61f;   // 1F A6 DE BA CC 13 7D 74

// Look-ahead window: the next 8 bytes of the image, win[7:0] is sent next; ram_a = byte after it
logic [63:0] win      = '0;
logic  [3:0] win_cnt  = 4'd0;
logic        rd_pend  = 1'b0;     // read of ram_a issued, byte not taken yet

wire [27:0] end_a     = MSX::DDR3_CAS + {1'b0, size};
wire        at_end    = size != '0 && ram_a == end_a;     // nothing more to fetch
wire        win_ready = win_cnt == 4'd8 || at_end;        // look-ahead complete
wire        sig       = win_cnt == 4'd8 && win == CAS_HEADER;
logic [1:0] cnt      = 2'h0;      // phase of the current bit
logic       ce_baud  = 1'b0;
logic [3:0] byte_pos = 4'd0;      // bits left in byte_out, 0 = load next byte
logic       output_on = 1'b0;
logic       output_bit = 1'b0;
logic [10:0] counter = '0;

// Next byte is a sync byte (all ones) during the sync and when the next header is reached
wire sync_byte = state == STATE_PLAY_SYNC || (state == STATE_PLAY_DATA && sig);
wire data_turn = state == STATE_PLAY_DATA && byte_pos == 0 && win_ready;
wire consume   = data_turn && ~sig && win_cnt != 4'd0;                // win[7:0] goes out
wire skip      = (data_turn && sig) || (state == STATE_SEARCH && sig);
// a data frame waits for a complete window; at the end of the file nothing is loaded
wire load      = byte_pos == 0 && (state != STATE_PLAY_DATA || (win_ready && (sig || win_cnt != 4'd0)));
wire fetching  = state == STATE_SEARCH || state == STATE_PLAY_SILENT || state == STATE_PLAY_SYNC || state == STATE_PLAY_DATA;

logic       out_en = 1'b0;      // output_on taken at a bit boundary: no partial first or last bit
assign cas_out = output_bit & out_en;

// Player: finds the first header, then keeps the window full and drops each header from it
always_ff @(posedge clk) begin

	ram_rd <= 0;

	if (rewind) begin
		state <= STATE_INIT;
	end else begin
		// window: drop a header, shift out a sent byte, or append a fetched byte
		if (skip)
			win_cnt <= 4'd0;
		else if (consume) begin
			win     <= {8'h00, win[63:8]};
			win_cnt <= win_cnt - 1'd1;
		end else if (fetching && buff_mem_ready && ~ram_rd) begin
			if (rd_pend) begin
				win[{win_cnt[2:0], 3'b000} +: 8] <= ram_di;
				win_cnt <= win_cnt + 1'd1;
				ram_a   <= ram_a + 1'd1;
				rd_pend <= 0;
			end else if (win_cnt != 4'd8 && ~at_end) begin
				ram_rd  <= 1;
				rd_pend <= 1;
			end
		end

		case (state)
			STATE_SLEEP: ;
			STATE_INIT:
				begin
					if (buff_mem_ready && ~ram_rd && enable) begin
						ram_a     <= MSX::DDR3_CAS;
						win_cnt   <= 4'd0;
						rd_pend   <= 0;
						output_on <= 0;
						state     <= STATE_SEARCH;
					end
				end
			STATE_SEARCH:
				begin
					if (win_ready) begin
						if (sig) begin
							state <= STATE_PLAY_SILENT;
							counter <= 1000;
						end else begin
							state <= STATE_SLEEP;
						end
					end
				end
			STATE_PLAY_SILENT:
				begin
					if (ce_baud) begin
						counter <= counter - 1'b1;
						if (counter == 0) begin
							state <= STATE_PLAY_SYNC;
							counter <= 1454;
						end
					end
				end
			STATE_PLAY_SYNC:
				begin
					if (counter == 0) begin
						state <= STATE_PLAY_DATA;
					end else if (byte_pos == 0) begin
						output_on <= 1;
						counter <= counter - 1'b1;
					end
				end
			STATE_PLAY_DATA:
				begin
					if (data_turn) begin
						if (sig) begin
							state <= STATE_PLAY_SYNC;
							counter <= 1454;
						end else if (win_cnt == 4'd0) begin   // end of the file
							output_on <= 0;
							state <= STATE_SLEEP;
						end
					end
				end
			default: ;
		endcase
	end
end

// Serializer: loads a frame when empty, shifts at the start of each bit.
// Shifts in ones: while a frame waits, the line stays at 1 (like extra stop bits).
logic [10:0] byte_out = '1;
always_ff @(posedge clk) begin
	if (load) begin
		byte_out <= sync_byte ? 11'b11111111111 : {2'b11, win[7:0], 1'b0};
		byte_pos <= 4'd11;
	end else if (byte_pos != 0 && cnt == 0 && ce_baud) begin
		byte_out <= {1'b1, byte_out[10:1]};
		byte_pos <= byte_pos - 1'b1;
	end
end

// Bit waveform: 1 at the start of each bit, then by phase
logic bit_out = 1'b1;
always_ff @(posedge clk) begin
	if (ce_baud) begin
		if (cnt == 2'h0) begin
			output_bit <= 1;
			bit_out <= byte_out[0];
			out_en <= output_on;
		end else
			output_bit <= bit_out ? ~cnt[0] : ~cnt[1];
	end
end

// Baud generator
logic [10:0] baud_div = '0;
always_ff @(posedge clk) begin
	ce_baud <= 0;
	if (ce_5m3 && play) begin
		if (baud_div == 11'h0) begin
			ce_baud <= 1;
			baud_div <= 11'd559;
			cnt <= cnt + 1'b1;
		end else
			baud_div <= baud_div - 1'b1;
	end
end

endmodule
