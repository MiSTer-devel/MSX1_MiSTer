//
// scc_wave.sv
//   Sound generator with wave table
//   Revision 1.00
//
// Copyright (c) 2006 Kazuhiro Tsujikawa (ESE Artists' factory)
// All rights reserved.
//
// Redistribution and use of this source code or any derivative works, are
// permitted provided that the following conditions are met:
//
// 1. Redistributions of source code must retain the above copyright notice,
//    this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright
//    notice, this list of conditions and the following disclaimer in the
//    documentation and/or other materials provided with the distribution.
// 3. Redistributions may not be sold, nor may they be used in a commercial
//    product or activity without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
// CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
// OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
// OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
// ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

//  2007/01/31  modified by t.hara
//  2023/05/24  rewriting from VHDL to SystemVerilog, added scc+ mode by Molekula

module scc_wave
(
   input                clk,
   input                clkena,
   input                reset,
   input                req,
   output               ack,
   input                wrt,
   input          [7:0] adr,
   input          [7:0] dbo,
   output         [7:0] dbi,
   output signed [14:0] wave,
   input                sccPlusChip,
   input                sccPlusMode
);

//scc registers
logic [11:0] reg_freq[5];
logic [11:0] reg_per[5];        // period played: reg_freq cut by deform bits 0/1 when written
logic  [3:0] reg_vol[5];
logic  [4:0] reg_ch_sel;
logic  [7:0] reg_mode_sel;

//internal register
logic  [4:0] ff_wr;             // frequency written: restart the current byte at the next clkena
logic  [4:0] ff_rst;            // ... and deform bit 5: restart the wave
logic  [4:0] ff_ptr[5];
logic  [2:0] ff_ch_num;
logic        ff_req_dl;
logic  [7:0] ff_wave_dat;
logic  [2:0] ff_ch_num_dl;
logic [14:0] ff_mix;
logic [14:0] ff_wave;

assign ack = ff_req_dl;
wire mode = sccPlusMode & sccPlusChip;

// Frequency write: new 12 bit value of the channel and the period it plays. Deform bit 1 keeps
// bits 7-0, bit 0 (without bit 1) bits 11-8 (openMSX SCC::setFreqVol).
wire  [2:0] freq_ch  = adr[3:1] > 3'd4 ? 3'd4 : adr[3:1];
wire [11:0] freq_new = adr[0] ? {dbo[3:0], reg_freq[freq_ch][7:0]} : {reg_freq[freq_ch][11:8], dbo};
wire [11:0] per_new  = reg_mode_sel[1] ? {4'd0, freq_new[7:0]} :
                       reg_mode_sel[0] ? {8'd0, freq_new[11:8]} : freq_new;

wire       access     = req & ~ff_req_dl;
wire       freq_wr    = access & wrt & adr[7:5] == {2'b10, mode} & adr[3:0] < 4'd10;
// Deformation register: SCC E0-FF, SCC+ C0-DF; a read writes FFh (openMSX SCC::readMem)
wire       deform_acc = access & adr[7:5] == {2'b11, ~sccPlusChip};
wire [7:0] deform_new = wrt ? dbo : 8'hFF;
// The rotation restarts when the deformation value changes or bit 5 restarts a wave
// (openMSX deformTimer.advance)
wire       rot_restart = (deform_acc & deform_new != reg_mode_sel) | (freq_wr & reg_mode_sel[5]);

// scc register access
always @(posedge clk) begin
   if (reset) begin
      reg_freq     <= '{12'd0, 12'd0, 12'd0, 12'd0, 12'd0};
      reg_per      <= '{12'd0, 12'd0, 12'd0, 12'd0, 12'd0};
      reg_vol      <= '{ 4'd0,  4'd0,  4'd0,  4'd0,  4'd0};
      reg_ch_sel   <= 5'd0;
      reg_mode_sel <= 8'd0;
      ff_wr        <= 5'd0;
      ff_rst       <= 5'd0;
      ff_req_dl    <= 1'd0;
   end else begin
      if (clkena) begin
         ff_wr  <= 5'd0;
         ff_rst <= 5'd0;
      end
      if (freq_wr) begin
         reg_freq[freq_ch] <= freq_new;
         reg_per[freq_ch]  <= per_new;
         ff_wr[freq_ch]    <= 1'b1;
         ff_rst[freq_ch]   <= reg_mode_sel[5];
      end
      if (access & wrt & adr[7:5] == {2'b10, mode}) begin
         case(adr[3:0])
            4'b1010: begin reg_vol[0] [3:0]  <= dbo[3:0]; end
            4'b1011: begin reg_vol[1] [3:0]  <= dbo[3:0]; end
            4'b1100: begin reg_vol[2] [3:0]  <= dbo[3:0]; end
            4'b1101: begin reg_vol[3] [3:0]  <= dbo[3:0]; end
            4'b1110: begin reg_vol[4] [3:0]  <= dbo[3:0]; end
            4'b1111: begin reg_ch_sel [4:0]  <= dbo[4:0]; end
            default: ;
         endcase
      end
      if (deform_acc) begin
         reg_mode_sel <= deform_new;
      end
      ff_req_dl <= req;
   end
end

// tone generator (openMSX SCC::generateChannels): a step every period + 1 ticks. A period of
// 8 or less holds the channel at its position. A frequency write restarts the current byte.
logic [11:0] ff_cnt[5];
logic  [4:0] ff_new;            // the channel takes a new sample: step or frequency write
always_comb
   for (int i = 0; i < 5; i++) ff_new[i] = clkena & (ff_wr[i] | (reg_per[i] > 12'd8 & ff_cnt[i] == 12'd0));

always @(posedge clk) begin
   if (reset) begin
      ff_ptr <= '{ 5'd0,  5'd0,  5'd0,  5'd0,  5'd0};
      ff_cnt <= '{12'd0, 12'd0, 12'd0, 12'd0, 12'd0};
   end else if (clkena) begin
      for (int i = 0; i < 5; i++) begin
         if (ff_wr[i]) begin
            ff_cnt[i] <= reg_per[i];
            if (ff_rst[i]) ff_ptr[i] <= 5'd0;
         end else if (reg_per[i] > 12'd8) begin
            if (ff_cnt[i] == 12'd0) begin
               ff_ptr[i] <= ff_ptr[i] + 5'd1;
               ff_cnt[i] <= reg_per[i];
            end else begin
               ff_cnt[i] <= ff_cnt[i] - 12'd1;
            end
         end
      end
   end
end

// Deform bits 7-6 (bit 7 only in the SCC, not the SCC+), openMSX SCC::setDeformRegHelper:
//   00 none, 01 all waves rotate, 10 waves 4-5 rotate, 11 waves 1-3 rotate.
// A rotating wave is write protected, with 11 all are. The rotation shows only to CPU reads
// (openMSX SCC::readWave), the sound is not affected. A wave moves by one every period + 1
// ticks; with 01 wave 4 of the SCC (and the SCC+ in SCC mode) moves at the channel 5 speed.
wire [1:0] rot_mode = {reg_mode_sel[7] & ~sccPlusChip, reg_mode_sel[6]};
wire [4:0] rotate   = rot_mode == 2'b01 ? 5'b11111 : rot_mode == 2'b10 ? 5'b11000 :
                      rot_mode == 2'b11 ? 5'b00111 : 5'b00000;
wire [4:0] wprot    = rot_mode == 2'b11 ? 5'b11111 : rotate;
wire       rot_4at5 = ~mode & reg_mode_sel[7:6] == 2'b01;

logic [11:0] rot_cnt[5];
logic  [4:0] rot_shift[5];
always @(posedge clk) begin
   if (reset | rot_restart) begin
      rot_cnt   <= '{12'd0, 12'd0, 12'd0, 12'd0, 12'd0};
      rot_shift <= '{ 5'd0,  5'd0,  5'd0,  5'd0,  5'd0};
   end else if (clkena) begin
      for (int i = 0; i < 5; i++) begin
         if (rot_cnt[i] >= ((i == 3 && rot_4at5) ? reg_per[4] : reg_per[i])) begin
            rot_cnt[i]   <= 12'd0;
            rot_shift[i] <= rot_shift[i] + 5'd1;
         end else begin
            rot_cnt[i]   <= rot_cnt[i] + 12'd1;
         end
      end
   end
end

// wave memory control
assign     dbi             = ram_ce ? ram_dbi : 8'hFF;
wire       ram_ce          = req & ram_adr < (mode ? 8'hA0 : 8'h80);
wire       ram_we          = ram_ce & ~ff_req_dl & wrt & ~wprot[ram_wave];
wire [2:0] ff_wawe_num_max = mode ? 3'd4 : 3'd3;
wire [2:0] ff_ch_num_max   = ff_ch_num > ff_wawe_num_max ? ff_wawe_num_max : ff_ch_num;
wire [7:0] w_wave_adr = {ff_ch_num_max, ff_ptr[ff_ch_num]};
wire       wave5_rd        = ~wrt & sccPlusChip & ~sccPlusMode & adr[7:5] == 3'b101;  // SCC mode: wave 5 reads wave 4
wire [7:0] ram_adr         = wave5_rd ? {3'b011,adr[4:0]} : adr;
wire [2:0] ram_wave        = wave5_rd ? 3'd4 : adr[7:5] > 3'd4 ? 3'd4 : adr[7:5];       // wave of the access
wire [4:0] ram_shift       = ~wrt & rotate[ram_wave] ? rot_shift[ram_wave] : 5'd0;
wire [7:0] ram_adr_rot     = {ram_adr[7:5], ram_adr[4:0] + ram_shift};

// Channel output latch (openMSX out[]): wave x volume is taken when the channel takes a new
// sample (ff_new). A volume change or a write to the sample being played waits for it; a
// disabled channel outputs 0 and stays silent after enabling until its next sample.
// lat_req is taken with the wave address (ff_ch_num) and follows the data (ff_lat2).
logic  [4:0] lat_req;
logic        ff_lat1, ff_lat2;
logic signed [11:0] out_mul[5];

always @(posedge clk) begin
   if (reset) begin
      lat_req <= 5'd0;
      ff_lat1 <= 1'b0;
      ff_lat2 <= 1'b0;
   end else begin
      for (int i = 0; i < 5; i++)
         if (ff_new[i])                lat_req[i] <= 1'b1;
         else if (ff_ch_num == 3'(i))  lat_req[i] <= 1'b0;
      ff_lat1 <= ff_ch_num <= 3'd4 ? lat_req[ff_ch_num] : 1'b0;
      ff_lat2 <= ff_lat1;
   end
end

// delay signal
always @(posedge clk) begin
   if (reset) begin
      ff_wave_dat   <= 8'd0;
      ff_ch_num_dl  <= 3'd0;
   end else begin
      ff_wave_dat   <= wave_dbi;
      ff_ch_num_dl  <= ff_ch_num;
   end
end

wire [2:0] ff_ch_num_dl_sel = ff_ch_num_dl - 3'd1;
wire       w_sel_ok         = ff_ch_num_dl_sel <= 3'd4;
wire [2:0] w_sel            = w_sel_ok ? ff_ch_num_dl_sel : 3'd0;
wire       w_ch_bit         = w_sel_ok & reg_ch_sel[w_sel];
wire [3:0] w_ch_vol         = reg_vol[w_sel];
wire signed [11:0] w_out    = ~w_ch_bit ? 12'sd0 : ff_lat2 ? w_mul : out_mul[w_sel];

always @(posedge clk) begin
   if (reset)
      out_mul <= '{12'sd0, 12'sd0, 12'sd0, 12'sd0, 12'sd0};
   else if (w_sel_ok)
      if (~w_ch_bit)    out_mul[w_sel] <= 12'sd0;
      else if (ff_lat2) out_mul[w_sel] <= w_mul;
end


always @(posedge clk) begin
   if (reset) 
      ff_ch_num <= 3'd0;
   else 
      if (ff_ch_num == 3'd5)
         ff_ch_num <= 3'd0;
      else
         ff_ch_num <= ff_ch_num + 3'd1;
end

// mixer
always @(posedge clk) begin
   if (reset)
      ff_mix <= 15'd0;
   else
      if (ff_ch_num_dl == 3'd0)
         ff_mix <= 15'd0;
      else
         ff_mix <= {w_out[11], w_out[11], w_out[11], w_out} + ff_mix;
end

// wave out
always @(posedge clk) begin
   if (reset)
      ff_wave <= 15'd0;
   else
      if (ff_ch_num_dl == 3'd0)
         ff_wave <= ff_mix;
end

assign wave = ff_wave;

// Clear waveform ram
logic [7:0] clear_cnt;
logic       clear_wr;
logic       clear_wave;
always @(posedge clk) begin
   logic old_reset;
   clear_wr <= 1'b0;
   if (clear_wr) clear_cnt <= clear_cnt - 8'b1;
   if (reset & ~old_reset) begin
      clear_cnt <= 8'h9F;
      clear_wave <= 1'b1;
   end
   else
      if (~clear_wr)
         if (clear_cnt != 8'hFF)
            clear_wr <= 1'b1;
         else 
            clear_wave <= 1'b0;
   old_reset <= reset;
end

wire [7:0] wave_dbi, ram_dbi;
wave_ram wavemem
(
   .adr_a(clear_wave ? clear_cnt : ram_adr_rot),
   .adr_b(w_wave_adr), 
   .clk(clk),
   .we_a(clear_wave ? clear_wr : ram_we),
   .data_a(clear_wave ? 8'hFF : dbo),
   .q_a(ram_dbi),
   .q_b(wave_dbi)
);

wire signed [11:0] w_mul;
scc_wave_mul u_mul
(
   .a(ff_wave_dat),
   .b(w_ch_vol),
   .c(w_mul)
);
endmodule

module wave_ram
(
   input  [7:0] adr_a,
   input  [7:0] adr_b,
   input        clk,
   input        we_a,
   input  [7:0] data_a,
   output [7:0] q_a,
   output [7:0] q_b
);

logic [7:0] blkram[256];
logic [7:0] iadr_a, iadr_b;

always @(posedge clk) begin
   if (we_a) begin
      blkram[adr_a] <= data_a;
   end
   iadr_b <= adr_b;
end

assign q_b = blkram[iadr_b];
assign q_a = blkram[adr_a];
endmodule

module scc_wave_mul
(
   input  signed  [7:0] a,
   input          [3:0] b,
   output signed [11:0] c
);

wire signed [12:0] w_mul = a * signed'({1'b0,b});
assign c = w_mul[11:0];
endmodule