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
	output  logic [27:0]	ram_a,
	input   [7:0]   ram_di,
	input   [63:0]  ram_di64,
	output  logic     ram_rd,
	input           buff_mem_ready,
	output          cas_out
);

typedef enum 
{
	STATE_SLLEP,
	STATE_INIT,
	STATE_SEARCH,
	STATE_PLAY_SILLENT,
	STATE_PLAY_SYNC,
	STATE_PLAY_DATA	
} player_state_t;

player_state_t  state = STATE_SLLEP;

wire[63:0] cas_sig = 64'h747d13ccbadea61f;

wire sig = cas_sig == ram_di64;

assign cas_out = output_bit & output_on;

logic output_on = 0;
logic header;
logic [10:0] counter;
always_ff @(posedge clk) begin
	
	ram_rd <= 0;

	if (rewind) begin
		state <= STATE_INIT;
	end else begin	
		case (state)
			STATE_SLLEP:	
				begin
				end
			STATE_INIT:	
				begin
					if (buff_mem_ready && ~ram_rd && enable) begin
						ram_a <= 28'h1700000;
						output_on <= 0;
						state <= STATE_SEARCH;
						ram_rd <= 1;
					end
				end	
			STATE_SEARCH: 
				begin
					if (buff_mem_ready && ~ram_rd) begin					
						if (sig) begin
							state <= STATE_PLAY_SILLENT;
							counter <= 1000;
							ram_a <= ram_a + 28'd8;
							ram_rd <= 1;
						end else begin
							state <= STATE_SLLEP;
						end
					end
				end
			STATE_PLAY_SILLENT: 
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
						header <= 0;
					end else
						header <= 1;
						if (byte_pos == 0) begin
							output_on <= 1;
							counter <= counter - 1'b1;
						end
				end
			STATE_PLAY_DATA:
				begin
					if (byte_pos == 0) begin
						if (buff_mem_ready && ~ram_rd) begin
							if (sig) begin
								state <= STATE_PLAY_SYNC;
                    			counter <= 1454;
								ram_a <= ram_a + 28'd8;
								ram_rd <= 1;
							end else begin
								ram_a <= ram_a + 1'd1;
								ram_rd <= 1;
							end
						end
					end
				end
		endcase
	end
end

// Send byte
logic [3:0] byte_pos = 0;
always_ff @(posedge clk) begin
logic [10:0] byte_out;
	if (byte_pos == 0) begin
		byte_out = header ? 11'b11111111111 : {2'b11, ram_di, 1'b0}; // 1'b0 startbit, 2'b11 stop bit
		byte_pos = 4'd11;
	end
	if (cnt == 0) begin
		send_bit = byte_out[0];
		if (ce_baud) begin
			byte_out = {1'b0, byte_out[10:1]};
			byte_pos = byte_pos - 1'b1;
		end
	end
end

// Send bit
logic send_bit;
logic output_bit;
always_ff @(posedge clk) begin
logic bit_out;
		if (ce_baud) begin
			if (cnt == 2'h0) begin
				output_bit = 1;
				bit_out = send_bit;
			end else 
				output_bit = (bit_out & ~cnt[0]) | (~bit_out & ~cnt[1]);
		end	
end

// Baud generator
logic [1:0] cnt = 2'h0;
logic ce_baud;
always_ff @(posedge clk) begin
	logic [10:0] baud_div;
	ce_baud = 0;
	if (ce_5m3 && play) begin
		if (baud_div == 11'h0) begin
			ce_baud = 1;
			baud_div = 11'd559;
			cnt = cnt + 1'b1;
		end else
			baud_div = baud_div - 1'b1;
	end
end

endmodule
