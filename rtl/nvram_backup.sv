// nvram_backup
//
// Copyright (c) 2023-2026 Molekula
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

module nvram_backup
(
   input                      clk,                  // Clock signal
   input MSX::lookup_SRAM_t   lookup_SRAM[4],       // Lookup table for SRAM access
   input                      load_req,             // Request to load data
   input                      save_req,             // Request to save data

   // SD config
   input                [3:0] img_mounted,          // Indicates mounted images
   input                      img_readonly,         // Indicates read-only mode
   input               [31:0] img_size,             // Size of the image

   // SD block level access
   output logic        [31:0] sd_lba[4],            // Logical Block Address for SD
   output logic         [3:0] sd_rd = 4'd0,         // SD read enable
   output logic         [3:0] sd_wr = 4'd0,         // SD write enable
   input                [3:0] sd_ack,               // SD acknowledgement
   input                      sd_buff_wr,           // SD buffer write enable
   input               [13:0] sd_buff_addr,         // SD buffer address
   input                [7:0] sd_buff_dout,         // Data out from SD buffer
   output logic         [7:0] sd_buff_din[4],       // Data into SD buffer

   // RAM access
   output logic        [26:0] ram_addr,             // RAM address
   output logic               ram_req,              // RAM request enable
   output logic               ram_rnw,              // RAM read/not-write enable
   input                      ram_ready,            // RAM ready signal
   input                [7:0] ram_dout,             // Data out from RAM
   output logic         [7:0] ram_din               // Data into RAM
);

logic [31:0] image_size[4];
logic  [3:0] image_mounted; 
logic        store_new_size;
logic [3:0]  request_load, request_save;
logic [1:0]  num;
logic        wr, rd;
logic        done;
logic        last_load_req, last_save_req;
logic [8:0]  buff_addr;
logic [20:0] block_count;
logic [31:0] lba_start;
logic        last_ack;

typedef enum logic [1:0] {
    STATE_SLEEP, 
    STATE_BUFF_WR, 
    STATE_SD_IO, 
    STATE_SRAM_WR
} state_t;

state_t      state;

// SD buffer data read
wire [7:0] buff_data;
assign sd_buff_din[0] = buff_data;
assign sd_buff_din[1] = buff_data;
assign sd_buff_din[2] = buff_data;
assign sd_buff_din[3] = buff_data;

// RAM address calculation
assign ram_addr = lookup_SRAM[num].addr + {sd_lba[num][16:0], buff_addr};

initial begin
   last_ack = 1'b0;
end

always_ff @(posedge clk) begin
   if (img_mounted[0]) begin 
      image_mounted[0] <= ~img_readonly; 
      image_size[0] <= img_size; 
   end 
   if (img_mounted[1]) begin 
      image_mounted[1] <= ~img_readonly; 
      image_size[1] <= img_size; 
   end 
   if (img_mounted[2]) begin 
      image_mounted[2] <= ~img_readonly; 
      image_size[2] <= img_size; 
   end 
   if (img_mounted[3]) begin 
      image_mounted[3] <= ~img_readonly; 
      image_size[3] <= img_size; 
   end 
   if (store_new_size) 
      image_size[num] <= {3'b0, lookup_SRAM[num].size, 13'b0};
end

always_ff @(posedge clk) begin
   last_load_req <= load_req;
   last_save_req <= save_req;

   if (~last_load_req & load_req)
      request_load <= 4'b1111;

   if (~last_save_req & save_req)
      request_save <= 4'b1111;

   if (done) begin
      wr <= 1'b0;
      rd <= 1'b0;
      if (wr) request_save[num] <= 1'b0;
      if (rd) request_load[num] <= 1'b0;
   end
   
   if (~wr & ~rd) begin
      if (request_save[num]) begin
         wr <= 1'b1;
      end else if (request_load[num]) begin
         rd <= 1'b1;
      end else begin
         num <= (num == 2'b11) ? 2'd0 : num + 2'b1;
      end
   end
end

always_ff @(posedge clk) begin
   done <= 1'b0;
   store_new_size <= 1'b0;
   
   if (ram_req) begin
      ram_req <= 1'b0;
      buff_addr <= buff_addr + (rd ? 9'd1 : 9'd0);
   end else begin
      case(state)
         STATE_SLEEP: begin
            ram_rnw <= 1'b1;
            if ((rd | wr) & ~done) begin
               if (lookup_SRAM[num].size > 16'h00 && image_mounted[num] && (wr || (rd && image_size[num] > 0))) begin
                  sd_lba[num] <= 32'd0;
                  block_count <= 21'(lookup_SRAM[num].size) << 1;
                  buff_addr <= 9'd0;
                  if (wr) begin
                     state <= STATE_BUFF_WR;
                     ram_req <= 1'b1;
                  end
                  if (rd) begin
                     state <= STATE_SD_IO;
                     sd_rd[num] <= 1'b1;
                  end
               end else begin
                  done <= 1'b1;
               end
            end
         end

         STATE_BUFF_WR: begin
            if (ram_ready) begin
               buff_addr <= buff_addr + 1'b1;
               ram_req <= 1'b1;
               if (buff_addr == 9'b111111111) begin
                  ram_req <= 1'b0;
                  sd_wr[num] <= 1'b1;
                  state <= STATE_SD_IO;
               end
            end
         end

         STATE_SD_IO: begin
            if (~sd_ack[num] & last_ack) begin
               if (wr) begin
                  sd_wr[num] <= 1'b0;
                  if (sd_lba[num][20:0] < block_count - 21'd1) begin
                     sd_lba[num] <= sd_lba[num] + 1'b1;
                     state <= STATE_BUFF_WR;
                     ram_req <= 1'b1;
                  end else begin
                     done <= 1'b1;
                     store_new_size <= wr;
                     state <= STATE_SLEEP;
                  end
               end else begin
                  sd_rd[num] <= 1'b0;
                  ram_req <= 1'b1;
                  ram_rnw <= 1'b0;
                  state <= STATE_SRAM_WR;
               end
            end
         end

         STATE_SRAM_WR: begin
            if (ram_ready) begin
               ram_req <= 1'b1;
               if (buff_addr == 9'b111111111) begin
                  if (sd_lba[num][20:0] < block_count - 21'd1) begin
                     sd_lba[num] <= sd_lba[num] + 1'b1;
                     state <= STATE_SD_IO;
                     sd_rd[num] <= rd;
                  end else begin
                     state <= STATE_SLEEP;
                     done <= 1'b1;
                  end
               end
            end
         end

         default: ;
      endcase
      last_ack <= sd_ack[num];
   end   
end

// Instantiate DPRAM
dpram #(.addr_width(9)) NVRAMbuff
(
   .clock(clk),
   .address_a(sd_buff_addr[8:0]),
   .wren_a(sd_buff_wr),
   .data_a(sd_buff_dout),
   .q_a(buff_data),
   .address_b(buff_addr),
   .wren_b(state == STATE_BUFF_WR),
   .data_b(ram_dout),
   .q_b(ram_din)
);

endmodule
