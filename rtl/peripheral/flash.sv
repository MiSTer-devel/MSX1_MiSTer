// flash ROM
//
// Copyright (c) 2024 Molekula
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

module flash (
	input                 clk,
	input                 clk_sdram,
	flash_bus_if.flash_mp flash_bus,
	input                 sdram_ready,
	input                 sdram_done,
	output   logic [26:0] sdram_addr,
	output   logic  [7:0] sdram_din,
	output   logic        sdram_req,
	output                debug_erase
);
	/* verilator lint_off WIDTHEXPAND */
	logic  [2:0] index;
	logic  [7:0] cmd[5];
	logic [26:0] sdram_offset;   // flash_bus.base_addr: 0x10000 - block base (system address)

	assign debug_erase = erase;
	
	initial begin
		index = 3'd0;
		sdram_req = 0;
	end
	
	assign flash_bus.data_from_flash = ~flash_bus.ce               ? 8'hFF :
	                                  erase                        ? 8'h00 :
	 			                      ~state                       ? 8'hFF :
				                      flash_bus.addr[2:1] == 2'b00 ? 8'h20 : 
                                      flash_bus.addr[2:1] == 2'b01 ? 8'h7e : 
				                      flash_bus.addr[2:1] == 2'b10 ? 8'h00 : 
				                                                     8'h01 ;

	assign flash_bus.data_valid = flash_bus.ce & ~flash_bus.we & (state | erase);

	logic       erase_block = 0;
	logic [7:0] erase_block_num;
//	reg       erase_chip = 0;

	logic old_we;
	logic state;
	always_ff @(posedge clk) begin
		old_we <= flash_bus.we;
	end

	always_ff @(posedge clk) begin
		erase_block <= 0;
//			erase_chip  <= 0;
		if (~valid) index <= 0;
		if (flash_bus.we & ~old_we) begin
			sdram_offset <= flash_bus.base_addr;
			cmd[index] <= flash_bus.data_to_flash;
			index <= index + 1'b1;
			if (int_valid5) begin
				index <= 0;
				if (flash_bus.data_to_flash == 8'h30) begin 
					erase_block <= 1; 
					erase_block_num <= (flash_bus.addr > 23'hFFFF ? {1'b0,flash_bus.addr[22:16]} : {5'd0,flash_bus.addr[15:13]} ); 
				end
				//if (din == 8'h10) erase_chip  <= 1;
			end
			if (flash_bus.addr[11:1] != (index == 3'd1 | index == 3'd4 ? 11'h2aa : 11'h555) & ~(flash_bus.data_to_flash == 8'hF0 & index == 0) ) begin
				index <= 0;
			end	
		end
		if (reset) begin 
			index <= 0;
			state <= 0;
		end
		if (ident) begin 
			index <= 0;
			state <= 1;
		end
	end


	//TODO potřebuji valid ?
	wire reset            = valid & int_valid1 & cmd[0] == 8'hF0;
	wire doubleProgram    = valid & int_valid1 & cmd[0] == 8'h50;
	wire quadrupleProgram = valid & int_valid1 & cmd[0] == 8'h56;
	wire byteProgram      = valid & int_valid3 & cmd[2] == 8'hA0;
	wire ident            = valid & int_valid3 & cmd[2] == 8'h90;
    


	wire int_valid1 =              index > 3'd0 & (cmd[0] == 8'hF0 | cmd[0] == 8'h50 | cmd[0] == 8'h56 | cmd[0] == 8'hAA);
	wire int_valid2 = int_valid1 & index > 3'd1 & (cmd[1] == 8'h55);
	wire int_valid3 = int_valid2 & index > 3'd2 & (cmd[2] == 8'h80 | cmd[2] == 8'h90 | cmd[2] == 8'hA0);
	wire int_valid4 = int_valid3 & index > 3'd3 & (cmd[3] == 8'hAA);
	wire int_valid5 = int_valid4 & index > 3'd4 & (cmd[4] == 8'h55);	
	
	wire valid      = index == 3'd1 ? int_valid1 :
	                  index == 3'd2 ? int_valid2 :
					  index == 3'd3 ? int_valid3 :
					  index == 3'd4 ? int_valid4 :
					  index == 3'd5 ? int_valid5 :
					                  1'b0;
	
   //wire [7:0] num1 = {5'd0,addr[15:13]};
   //wire [7:0] num2 = addr[22:16] + 7;

	logic erase;
//write to SDRAM
	always_ff @(posedge clk) begin
		logic sdram_need_wr;
		logic [15:0] write_cnt;
		if (reset) sdram_req <= 0;
		if (sdram_req & sdram_done) begin
			sdram_req <= 0; //request se zpracovava
			write_cnt <= write_cnt - 1'b1;
			if (erase) begin
				if (write_cnt == 0) begin
					erase <= 0;
					write_cnt <= 0;
				end else begin
				//	write_cnt <= write_cnt - 1'b1;
				//if (erase) begin
					sdram_addr <= sdram_addr + 1'b1;
					sdram_need_wr <= 1;
				end
			end
		end
		if (sdram_need_wr & sdram_ready & ~sdram_req) begin
			sdram_need_wr <= 0;
			sdram_req <= 1;
		end
		if (erase_block) begin
			write_cnt <= 16'hFFFF;
			sdram_din <=  8'hFF;
			sdram_need_wr <= 1;
			sdram_addr <= (27'(erase_block_num) << 16) - sdram_offset;
			erase <= 1;
		end else 
		if ((quadrupleProgram || doubleProgram || byteProgram || write_cnt > 0) & flash_bus.we & ~old_we & flash_bus.ce ) begin
			//TODO Zkontrolovat zda je writable sector num1 a num2 vypocet
			sdram_addr <= 27'(flash_bus.addr) - sdram_offset;
			sdram_din <= flash_bus.data_to_flash;
			if (sdram_ready) begin
				sdram_req <= 1;
			end else begin
				sdram_need_wr <= 1;
			end
			if (quadrupleProgram) write_cnt <= 4;
			if (doubleProgram) write_cnt <= 2;
			if (byteProgram) write_cnt <= 1;
			if (erase_block) write_cnt <= 16'hFFFF;
		end
	end
/* verilator lint_on WIDTHEXPAND */	
endmodule
