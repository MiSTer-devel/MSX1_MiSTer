//
//  vdp_interrupt.vhd
//   Interrupt controller of ESE-VDP.
//
//  Copyright (C) 2000-2006 Kunihiko Ohnaka
//  All rights reserved.
//                                     http://www.ohnaka.jp/ese-vdp/
//
//  本ソフトウェアおよび本ソフトウェアに基づいて作成された派生物は、以下の条件を
//  満たす場合に限り、再頒布および使用が許可されます。
//
//  1.ソースコード形式で再頒布する場合、上記の著作権表示、本条件一覧、および下記
//    免責条項をそのままの形で保持すること。
//  2.バイナリ形式で再頒布する場合、頒布物に付属のドキュメント等の資料に、上記の
//    著作権表示、本条件一覧、および下記免責条項を含めること。
//  3.書面による事前の許可なしに、本ソフトウェアを販売、および商業的な製品や活動
//    に使用しないこと。
//
//  本ソフトウェアは、著作権者によって「現状のまま」提供されています。著作権者は、
//  特定目的への適合性の保証、商品性の保証、またそれに限定されない、いかなる明示
//  的もしくは暗黙な保証責任も負いません。著作権者は、事由のいかんを問わず、損害
//  発生の原因いかんを問わず、かつ責任の根拠が契約であるか厳格責任であるか（過失
//  その他の）不法行為であるかを問わず、仮にそのような損害が発生する可能性を知ら
//  されていたとしても、本ソフトウェアの使用によって発生した（代替品または代用サ
//  ービスの調達、使用の喪失、データの喪失、利益の喪失、業務の中断も含め、またそ
//  れに限定されない）直接損害、間接損害、偶発的な損害、特別損害、懲罰的損害、ま
//  たは結果損害について、一切責任を負わないものとします。
//
//  Note that above Japanese version license is the formal document.
//  The following translation is only for reference.
//
//  Redistribution and use of this software or any derivative works,
//  are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the above copyright
//     notice, this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above
//     copyright notice, this list of conditions and the following
//     disclaimer in the documentation and/or other materials
//     provided with the distribution.
//  3. Redistributions may not be sold, nor may they be used in a
//     commercial product or activity without specific prior written
//     permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
//  "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
//  LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
//  FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
//  COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
//  BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
//  LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
//  ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.
//

module VDP_INTERRUPT (
    input  logic          RESET,
    input  logic          CLK21M,

    input  logic [10:0]   H_CNT,
    input  logic [7:0]    Y_CNT,
    input  logic          ACTIVE_LINE,
    input  logic          V_BLANKING_START,
    input  logic          CLR_VSYNC_INT,
    input  logic          CLR_HSYNC_INT,
    output logic          REQ_VSYNC_INT_N,
    output logic          REQ_HSYNC_INT_N,
    output logic          FH_LEVEL,
    input  logic [7:0]    REG_R19_HSYNC_INT_LINE,
    input  logic          REG_R0_HSYNC_INT_EN
);

    logic FF_VSYNC_INT_N;
    logic FF_HSYNC_INT_N;
    logic W_VSYNC_INTR_TIMING;
    logic FF_ACTIVE_LINE;
    logic [5:0] FF_HSCAN_CNT;
    logic W_HSCAN;
    logic FF_FH_LEVEL;

    assign REQ_VSYNC_INT_N = FF_VSYNC_INT_N;
    assign REQ_HSYNC_INT_N = FF_HSYNC_INT_N;
    assign FH_LEVEL        = FF_FH_LEVEL;

    // VSYNC INTERRUPT REQUEST: start of the left border of line 192 / 212 (openMSX VSCAN)
    assign W_VSYNC_INTR_TIMING = (H_CNT == LEFT_BORDER_OUT) ? 1'b1 : 1'b0;

    // HSCAN (openMSX): the right border of the R#19 line on the output, RIGHT_BORDER_DELAY
    // clocks after the line compare at the end of the pre-dot line (ACTIVE_LINE)
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_ACTIVE_LINE <= 1'b0;
            FF_HSCAN_CNT   <= '0;
        end else begin
            FF_ACTIVE_LINE <= ACTIVE_LINE;
            if (ACTIVE_LINE && !FF_ACTIVE_LINE && Y_CNT == REG_R19_HSYNC_INT_LINE)
                FF_HSCAN_CNT <= RIGHT_BORDER_DELAY;
            else if (FF_HSCAN_CNT != '0)
                FF_HSCAN_CNT <= FF_HSCAN_CNT - 1'b1;
        end
    end
    assign W_HSCAN = FF_HSCAN_CNT == 6'd1;

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_VSYNC_INT_N <= 1'b1;
        end else begin
            if (CLR_VSYNC_INT) begin
                // V-BLANKING INTERRUPT CLEAR
                FF_VSYNC_INT_N <= 1'b1;
            end else if (W_VSYNC_INTR_TIMING && V_BLANKING_START) begin
                // V-BLANKING INTERRUPT REQUEST
                FF_VSYNC_INT_N <= 1'b0;
            end
        end
    end

    // HSYNC INTERRUPT REQUEST
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_HSYNC_INT_N <= 1'b1;
        end else begin
            // FH is cleared by the CPU only (S#1 read, R#19 write, R#0 write with IE1), not at
            // vertical blanking, and latched only while IE1 is on (openMSX execHScan)
            if (CLR_HSYNC_INT) begin
                FF_HSYNC_INT_N <= 1'b1;
            end else if (W_HSCAN && REG_R0_HSYNC_INT_EN) begin
                FF_HSYNC_INT_N <= 1'b0;
            end
        end
    end

    // FH as read with IE1 off: 1 from the right border of the R#19 line to the next left
    // border, nothing latched (openMSX peekStatusReg, S#1)
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_FH_LEVEL <= 1'b0;
        end else if (W_HSCAN) begin
            FF_FH_LEVEL <= 1'b1;
        end else if (H_CNT == LEFT_BORDER_OUT) begin
            FF_FH_LEVEL <= 1'b0;
        end
    end

endmodule
