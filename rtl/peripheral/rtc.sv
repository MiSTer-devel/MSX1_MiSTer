//
// rtc.vhd
//   REAL TIME CLOCK (MSX2 CLOCK-IC)
//   Version 1.00
//
// Copyright (c) 2008 Takayuki Hara
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
// Revrite to SystemVerilog 2024 Molekula

module rtc (
    input  logic                 clk21m,      // Clock signal
    input  logic                 reset,       // Reset signal

    input  logic                 setup,       // Setup signal
    input  logic [64:0]          rt,          // Real-time input

    input  logic                 clkena,      // Clock enable signal (10Hz)
    input  logic                 req,         // Request signal
    output logic                 ack,         // Acknowledge signal
    input  logic                 wrt,         // Write signal
    input  logic [15:0]          adr,         // Address bus
    output logic [7:0]           dbi,         // Data bus input
    input  logic [7:0]           dbo,         // Data bus output
    input  logic                 mem_init     // fill the backup memory with FFh (pack load)
);

    // Internal signals and registers
    logic                       ff_req;
    logic [3:0]                 ff_1sec_cnt;

    // Register signals
    logic [3:0]                 reg_ptr;
    logic [3:0]                 reg_mode;
    logic [3:0]                 reg_sec_l;
    logic [6:4]                 reg_sec_h;
    logic [3:0]                 reg_min_l;
    logic [6:4]                 reg_min_h;
    logic [3:0]                 reg_hou_l;
    logic [5:4]                 reg_hou_h;
    logic [2:0]                 reg_wee;
    logic [3:0]                 reg_day_l;
    logic [5:4]                 reg_day_h;
    logic [3:0]                 reg_mon_l;
    logic                       reg_mon_h;
    logic [3:0]                 reg_yea_l;
    logic [7:4]                 reg_yea_h;
    logic                       reg_1224;
    logic [1:0]                 reg_leap;

    // Wire signals
    logic [15:0]                w_adr_dec;
    logic [2:0]                 w_bank_dec;
    logic                       w_wrt;
    logic                       w_mem_we;
    logic [7:0]                 w_mem_addr;
    logic [7:0]                 w_mem_q;
    logic                       w_1sec;
    logic                       w_10sec;
    logic                       w_60sec;
    logic                       w_10min;
    logic                       w_60min;
    logic                       w_10hour;
    logic                       w_1224hour;
    logic                       w_10day;
    logic                       w_next_mon;
    logic                       w_10mon;
    logic                       w_1year;
    logic                       w_10year;
    logic                       w_100year;
    logic                       w_enable;

    // Address decoder
    always_comb begin
        case (reg_ptr)
            4'b0000: w_adr_dec = 16'b0000_0000_0000_0001;
            4'b0001: w_adr_dec = 16'b0000_0000_0000_0010;
            4'b0010: w_adr_dec = 16'b0000_0000_0000_0100;
            4'b0011: w_adr_dec = 16'b0000_0000_0000_1000;
            4'b0100: w_adr_dec = 16'b0000_0000_0001_0000;
            4'b0101: w_adr_dec = 16'b0000_0000_0010_0000;
            4'b0110: w_adr_dec = 16'b0000_0000_0100_0000;
            4'b0111: w_adr_dec = 16'b0000_0000_1000_0000;
            4'b1000: w_adr_dec = 16'b0000_0001_0000_0000;
            4'b1001: w_adr_dec = 16'b0000_0010_0000_0000;
            4'b1010: w_adr_dec = 16'b0000_0100_0000_0000;
            4'b1011: w_adr_dec = 16'b0000_1000_0000_0000;
            4'b1100: w_adr_dec = 16'b0001_0000_0000_0000;
            4'b1101: w_adr_dec = 16'b0010_0000_0000_0000;
            4'b1110: w_adr_dec = 16'b0100_0000_0000_0000;
            4'b1111: w_adr_dec = 16'b1000_0000_0000_0000;
        endcase

        case (reg_mode[1:0])
            2'b00: w_bank_dec = 3'b001;
            2'b01: w_bank_dec = 3'b010;
            2'b10,
            2'b11: w_bank_dec = 3'b100;
        endcase

        w_wrt = req & wrt;
    end

    // RTC register read
    always_comb begin
        dbi = (w_adr_dec[13] && adr[0]) ? {4'b1111, reg_mode} :
              (w_bank_dec[0] && w_adr_dec[0]  && adr[0]) ? {4'b1111,    reg_sec_l} :
              (w_bank_dec[0] && w_adr_dec[1]  && adr[0]) ? {5'b11110,   reg_sec_h} :
              (w_bank_dec[0] && w_adr_dec[2]  && adr[0]) ? {4'b1111,    reg_min_l} :
              (w_bank_dec[0] && w_adr_dec[3]  && adr[0]) ? {5'b11110,   reg_min_h} :
              (w_bank_dec[0] && w_adr_dec[4]  && adr[0]) ? {4'b1111,    reg_hou_l} :
              (w_bank_dec[0] && w_adr_dec[5]  && adr[0]) ? {6'b111100,  reg_hou_h} :
              (w_bank_dec[0] && w_adr_dec[6]  && adr[0]) ? {5'b11110,   reg_wee} :
              (w_bank_dec[0] && w_adr_dec[7]  && adr[0]) ? {4'b1111,    reg_day_l} :
              (w_bank_dec[0] && w_adr_dec[8]  && adr[0]) ? {6'b111100,  reg_day_h} :
              (w_bank_dec[0] && w_adr_dec[9]  && adr[0]) ? {4'b1111,    reg_mon_l} :
              (w_bank_dec[0] && w_adr_dec[10] && adr[0]) ? {7'b1111000, reg_mon_h} :
              (w_bank_dec[0] && w_adr_dec[11] && adr[0]) ? {4'b1111,    reg_yea_l} :
              (w_bank_dec[0] && w_adr_dec[12] && adr[0]) ? {4'b1111,    reg_yea_h} :
              (w_bank_dec[1] && w_adr_dec[11] && adr[0]) ? {6'b111100,  reg_leap} :
              (w_bank_dec[2] &&                  adr[0]) ? {4'b1111,    w_mem_q[3:0]} :
              8'b1111_1111;
    end

    // Request and ack
    always_ff @(posedge clk21m) begin
        if (reset)
            ff_req <= 1'b0;
        else
            ff_req <= req;
    end

    assign ack = ff_req;

    // Mode register [te bit]
    assign w_enable = clkena & reg_mode[3];

    // 1sec timer
    always_ff @(posedge clk21m) begin
        if (reset)
            ff_1sec_cnt <= 4'b1001;
        else begin
            if (w_wrt && adr[0] && w_bank_dec[1] && w_adr_dec[15] && dbo[1])
                ff_1sec_cnt <= 4'd9;
            else if (w_1sec)
                ff_1sec_cnt <= 4'd9;
            else if (w_enable)
                ff_1sec_cnt <= ff_1sec_cnt - 1'b1;
        end
    end

    assign w_1sec = (ff_1sec_cnt == 4'b0000) ? w_enable : 1'b0;

    // 10sec timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[0])
            reg_sec_l <= dbo[3:0];
        else if (w_1sec)
            if (w_10sec)
                reg_sec_l <= 4'b0000;
            else
                reg_sec_l <= reg_sec_l + 1'b1;
        if (setup)
            reg_sec_l <= rt[3:0];
    end

    assign w_10sec = reg_sec_l == 4'd9;

    // 60sec timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[1])
            reg_sec_h <= dbo[2:0];
        else if (w_1sec && w_10sec)
            if (w_60sec)
                reg_sec_h <= 3'b000;
            else
                reg_sec_h <= reg_sec_h + 1'b1;
        if (setup)
            reg_sec_h <= rt[6:4];
    end

    assign w_60sec = reg_sec_h == 3'd5;

    // 10min timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[2])
            reg_min_l <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec)
            if (w_10min)
                reg_min_l <= 4'b0000;
            else
                reg_min_l <= reg_min_l + 1'b1;
        if (setup)
            reg_min_l <= rt[11:8];
    end

    assign w_10min = reg_min_l == 4'd9;

    // 60min timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[3])
            reg_min_h <= dbo[2:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min)
            if (w_60min)
                reg_min_h <= 3'b000;
            else
                reg_min_h <= reg_min_h + 1'b1;
        if (setup)
            reg_min_h <= rt[14:12];
    end

    assign w_60min = reg_min_h == 3'd5;

    // 10hour timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[4])
            reg_hou_l <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min)
            if (w_10hour || w_1224hour)
                reg_hou_l <= 4'b0000;
            else
                reg_hou_l <= reg_hou_l + 1'b1;
        if (setup)
            reg_hou_l <= rt[19:16];
    end

    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[5])
            reg_hou_h <= dbo[1:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min)
            if (w_10hour)
                reg_hou_h <= reg_hou_h + 1'b1;
            else if (w_1224hour) begin
                    reg_hou_h[5] <= ~reg_hou_h[5];
                    reg_hou_h[4] <= 1'b0;
                 end
        if (setup)
            reg_hou_h <= rt[21:20];
    end

    assign w_10hour = reg_hou_l == 4'd9;
    assign w_1224hour = (~reg_1224 && reg_hou_h[4] && reg_hou_l == 4'd1)     ||
                        (reg_1224 && reg_hou_h == 2'b10 && reg_hou_l == 4'd3);

    // week day timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[6])
            reg_wee <= dbo[2:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour)
            if (reg_wee == 3'b110)
                reg_wee <= '0;
            else
                reg_wee <= reg_wee + 1'b1;
        if (setup)
            reg_wee <= rt[50:48];
    end

    // 10day timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[7])
            reg_day_l <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour)
            if (w_10day)
                reg_day_l <= 4'b0000;
            else if (w_next_mon)
                reg_day_l <= 4'b0001;
                else
                    reg_day_l <= reg_day_l + 1'b1;
        if (setup)
            reg_day_l <= rt[27:24];
    end

    assign w_10day = reg_day_l == 4'd9;

    // 1month timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[8])
            reg_day_h <= dbo[1:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour)
            if (w_next_mon)
                reg_day_h <= 2'b00;
            else if (w_10day)
                reg_day_h <= reg_day_h + 1'b1;
        if (setup)
            reg_day_h <= rt[29:28];
    end

    assign w_next_mon = (                                      reg_day_h == 2'b11 && reg_day_l == 4'b0001                     ) || // xx/31
                        (~reg_mon_h && reg_mon_l == 4'b0010 && reg_day_h == 2'b10 && reg_day_l == 4'b1001 && reg_leap == 2'b00) || // 02/29  (leap year)
                        (~reg_mon_h && reg_mon_l == 4'b0010 && reg_day_h == 2'b11 && reg_day_l == 4'b1000 && reg_leap != 2'b00) || // 02/28
                        (~reg_mon_h && reg_mon_l == 4'b0100 && reg_day_h == 2'b11 && reg_day_l == 4'b0000                     ) || // 04/30
                        (~reg_mon_h && reg_mon_l == 4'b0110 && reg_day_h == 2'b11 && reg_day_l == 4'b0000                     ) || // 06/30
                        (~reg_mon_h && reg_mon_l == 4'b1001 && reg_day_h == 2'b11 && reg_day_l == 4'b0000                     ) || // 09/30
                        ( reg_mon_h && reg_mon_l == 4'b0001 && reg_day_h == 2'b11 && reg_day_l == 4'b0000                     );   // 11/30
    
    // 10month timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[9])
            reg_mon_l <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour && w_next_mon)
            if (w_10mon)
                reg_mon_l <= 4'b0000;
            else if (w_1year)
                reg_mon_l <= 4'b0001;
                else
                    reg_mon_l <= reg_mon_l + 1'b1;
        if (setup)
            reg_mon_l <= rt[35:32];
    end

    assign w_10mon = reg_mon_l == 4'd9;

    // 1year timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[10])
            reg_mon_h <= dbo[0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour && w_next_mon)
            if (w_10mon)
                reg_mon_h <= 1'b1;
            else if (w_1year)
                reg_mon_h <= 1'b0;
        if (setup)
            reg_mon_h <= rt[36];
    end

    assign w_1year = reg_mon_h && reg_mon_l== 4'd2; //x12

    // 10year timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[11])
            reg_yea_l <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour && w_next_mon && w_1year)
            if (w_10year)
                reg_yea_l <= 4'b0000;
            else
                reg_yea_l <= reg_yea_l + 1'b1;
        if (setup)
            reg_yea_l <= rt[43:40];
    end

    assign w_10year = reg_yea_l == 4'd9;

    // 100year timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[0] && w_adr_dec[12])
            reg_yea_h <= dbo[3:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour && w_next_mon && w_1year && w_10year)
            if (w_100year)
                reg_yea_h <= 4'b0000;
            else
                reg_yea_h <= reg_yea_h + 1'b1;
        if (setup)
            reg_yea_h <= rt[47:44] + 4'b0010;
    end

    assign w_100year = reg_yea_h == 4'd9;

    // leap year timer
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[1] && w_adr_dec[11])
            reg_leap <= dbo[1:0];
        else if (w_1sec && w_10sec && w_60sec && w_10min && w_60min && w_1224hour && w_next_mon && w_1year)
            reg_leap <= reg_leap + 1'b1;
    end

    // 12hour mode/24 hour mode
    always_ff @(posedge clk21m) begin
        if (w_wrt && adr[0] && w_bank_dec[1] && w_adr_dec[10])
            reg_1224 <= dbo[0];
        if (setup)
            reg_1224 <= 1'b1;
    end

    // rtc register pointer
    always_ff @(posedge clk21m) begin
        if (reset)
            reg_ptr <= '0;
        else if (w_wrt && ~adr[0])
            reg_ptr <= dbo[3:0]; // register pointer
    end

    // rtc test register
    always_ff @(posedge clk21m) begin
        if (reset)
            reg_mode <= 4'b1000;
        else if (w_wrt && adr[0] && w_adr_dec[13])
            reg_mode <= dbo[3:0];
    end   


    // Backup memory emulation: banks 0-3 x 16 nibbles, one per byte (banks 2 and 3 are read).
    // Not saved; FFh after configuration and while mem_init is high (openMSX: new SRAM = FFh).
    logic [5:0] init_cnt = '0;
    always_ff @(posedge clk21m) init_cnt <= mem_init ? init_cnt + 1'd1 : '0;

    assign w_mem_addr = {2'b00, reg_mode[1:0], reg_ptr};
    assign w_mem_we = w_wrt && adr[0];

    ram_v u_mem (
        .clk(clk21m),
        .adr(mem_init ? init_cnt : w_mem_addr[5:0]),
        .we(mem_init || w_mem_we),
        .dbo(mem_init ? 8'hFF : dbo),
        .dbi(w_mem_q)
    );

endmodule

// 64 x 8, registered read
module ram_v (
  input  logic       clk,
  input  logic [5:0] adr,
  input  logic       we,
  input  logic [7:0] dbo,
  output logic [7:0] dbi
);

    logic [7:0] blkram[0:63];
    initial for (int i = 0; i < 64; i++) blkram[i] = 8'hFF;

    always_ff @(posedge clk) begin
        if (we) blkram[adr] <= dbo;
        dbi <= blkram[adr];
    end

endmodule
