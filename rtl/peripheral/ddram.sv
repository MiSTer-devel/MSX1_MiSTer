//
// ddram.v
//
// DE10-nano DDR3 memory interface
//
// Copyright (c) 2017 Sorgelig
//
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version. 
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
// ------------------------------------------
//

// 8-bit version

module ddram (
    input         reset,
	input         DDRAM_CLK,

	input         		DDRAM_BUSY,
	output logic  [7:0] DDRAM_BURSTCNT,
	output logic [28:0] DDRAM_ADDR,
	input        [63:0] DDRAM_DOUT,
	input               DDRAM_DOUT_READY,
	output logic        DDRAM_RD,
	output logic [63:0] DDRAM_DIN,
	output logic  [7:0] DDRAM_BE,
	output logic        DDRAM_WE,

	input  [27:0] addr,        // 256MB at the end of 1GB
	output  [7:0] dout,        // data output to cpu
	input   [7:0] din,         // data input from cpu
	input         we,          // cpu requests write
	input         rd,          // cpu requests read
	output        ready,       // dout is valid. Ready to accept new read/write.
	output [63:0] dout64
);

typedef enum logic [1:0] {INIT, IDLE, READ} state_t;

// A request is latched when it arrives and issued once DDRAM_BUSY (Avalon waitrequest)
// is low: a request during BUSY used to be lost while ready stayed 1.
logic   old_rd, old_we;
logic   rd_rq, wr_rq, cache_en;
logic   rd_pend = 0, wr_pend = 0;
logic  [7:0] cached;
logic  [7:0] ram_q;
logic [27:0] ram_address;
logic [63:0] ram_cache;
logic  [7:0] wr_data;

state_t state;

assign ready      = state == IDLE && ~rd_pend && ~wr_pend;
assign dout     = ram_q;
assign dout64   = ram_cache;

assign rd_rq    = ~old_rd && rd;
assign wr_rq    = ~old_we && we;

assign cache_en = (ram_address[27:3] == addr[27:3]) && ((cached & (8'd1 << addr[2:0])) != 8'd0);

always @(posedge DDRAM_CLK)
begin
	
	logic old_reset;
	
	old_reset <= reset;
	old_rd <= rd;
	old_we <= we;

	// latch requests: a read hit is served at once, a miss or a write waits for the bus
	if(wr_rq) begin
		wr_pend                            <= 1;
		wr_data                            <= din;
		ram_cache[{addr[2:0], 3'b000} +:8] <= din;
		ram_address                        <= addr;
		cached                             <= ((ram_address[27:3] == addr[27:3]) ? cached : 8'h00) | (8'd1<<addr[2:0]);
	end
	else if(rd_rq) begin
		if(cache_en) ram_q <= ram_cache[{addr[2:0], 3'b000} +:8];
		else begin
			rd_pend     <= 1;
			cached      <= 0;
			ram_address <= addr;
		end
	end

	// read data may arrive while BUSY is high
	if(state == READ && DDRAM_DOUT_READY) begin
		ram_q     <= DDRAM_DOUT[{ram_address[2:0], 3'b000} +:8];
		ram_cache <= DDRAM_DOUT;
		cached    <= 8'hFF;
		state     <= IDLE;
	end

	if(!DDRAM_BUSY) begin
		DDRAM_RD <= 0;
		DDRAM_WE <= 0;

		case(state)
			INIT: begin
					state <= IDLE;
			end
			IDLE: begin
				if(wr_pend) begin
					wr_pend                                   <= 0;
					DDRAM_BURSTCNT                            <= 1;
					DDRAM_WE                                  <= 1;
					DDRAM_BE                                  <= (8'd1<<ram_address[2:0]);
					DDRAM_DIN[{ram_address[2:0], 3'b000} +:8] <= wr_data;
					DDRAM_ADDR                                <= {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
				end
				else if(rd_pend) begin
					rd_pend        <= 0;
					DDRAM_BURSTCNT <= 1;
					DDRAM_RD       <= 1;
					DDRAM_BE       <= 8'hFF;
					DDRAM_ADDR     <= {4'b0011, ram_address[27:3]}; // RAM at 0x30000000
					state          <= READ;
				end
			end
			default: ;
		endcase
	end

	if(old_reset && ~reset) begin
		state   <= INIT;
		cached  <= 0;
		rd_pend <= 0;
		wr_pend <= 0;
	end
end

endmodule
