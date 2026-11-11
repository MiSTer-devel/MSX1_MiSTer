//
//  vdp_ssg.vhd
//   Synchronous Signal Generator of ESE-VDP.
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
//-----------------------------------------------------------------------------
//  30th,March,2008
//  JP: VDP.VHD から分離 by t.hara
//

module VDP_SSG (
    input logic RESET,
    input logic CLK21M,

    output logic [10:0] H_CNT,
    output logic [10:0] V_CNT,
    output logic [1:0] DOTSTATE,
    output logic [2:0] EIGHTDOTSTATE,
    output logic [8:0] PREDOTCOUNTER_X,
    output logic [8:0] PREDOTCOUNTER_Y,
    output logic [8:0] PREDOTCOUNTER_YP,
    output logic PREWINDOW_Y,
    output logic PREWINDOW_Y_SP,
    output logic FIELD,
    output logic WINDOW_X,
    output logic OWINDOW_X,             // output window without the border, fixed on the screen
    output logic OWINDOW_Y,
    output logic PVIDEODHCLK,
    output logic PVIDEODLCLK,
    output logic IVIDEOVS_N,

    output logic HD,
    output logic VD,
    output logic HSYNC,
    output logic ENAHSYNC,
    output logic V_BLANKING_START,

    input logic VDPR9PALMODE,
    input logic REG_R9_INTERLACE_MODE,
    input logic REG_R9_Y_DOTS,
    input logic [7:0] REG_R18_ADJ,
    input logic [7:0] REG_R19_HSYNC_INT_LINE,
    input logic [7:0] REG_R23_VSTART_LINE,
    input logic REG_R25_MSK,
    input logic [2:0] REG_R27_H_SCROLL,
    input logic REG_R25_YJK,
    input logic CENTERYJK_R25_N,
    input logic [6:0] OFFSET_Y
);

    // Internal signals and component instantiation
    logic [1:0] FF_DOTSTATE;
    logic [2:0] FF_EIGHTDOTSTATE;
    logic [8:0] FF_PRE_X_CNT;
    logic [8:0] FF_X_CNT;
    logic [8:0] FF_PRE_Y_CNT;
    logic [8:0] FF_MONITOR_LINE;
    logic FF_VIDEO_DH_CLK;
    logic FF_VIDEO_DL_CLK;
    logic [5:0] FF_PRE_X_CNT_START1;
    logic [8:0] FF_RIGHT_MASK;
    logic FF_WINDOW_X;

    // Wire signals
    logic [10:0] W_H_CNT;
    logic [10:0] W_V_CNT_IN_FRAME;
    logic [9:0] W_V_CNT_IN_FIELD;
    logic W_FIELD;
    logic W_H_BLANK;
    logic W_V_BLANK;
    logic [4:0] W_PRE_X_CNT_START0;
    logic [8:0] W_PRE_X_CNT_START2;
    logic W_HSYNC;
    logic [8:0] W_LEFT_MASK;
    logic [8:0] W_Y_ADJ;
    logic [1:0] W_LINE_MODE;
    logic W_V_BLANKING_START;
    logic W_V_BLANKING_END;
    logic FF_VR;

    // Component instantiation for VDP_HVCOUNTER
    VDP_HVCOUNTER u_hvcounter (
        .RESET(RESET),
        .CLK21M(CLK21M),
        .H_CNT(W_H_CNT),
        .V_CNT_IN_FIELD(W_V_CNT_IN_FIELD),
        .V_CNT_IN_FRAME(W_V_CNT_IN_FRAME),
        .FIELD(W_FIELD),
        .H_BLANK(W_H_BLANK),
        .V_BLANK(W_V_BLANK),
        .PAL_MODE(VDPR9PALMODE),
        .INTERLACE_MODE(REG_R9_INTERLACE_MODE),
        .Y212_MODE(REG_R9_Y_DOTS),
        .OFFSET_Y(OFFSET_Y)
    );

    // Port assignments
    assign H_CNT = W_H_CNT;
    assign V_CNT = W_V_CNT_IN_FRAME;
    assign DOTSTATE = FF_DOTSTATE;
    assign EIGHTDOTSTATE = FF_EIGHTDOTSTATE;
    assign FIELD = W_FIELD;
    assign WINDOW_X = FF_WINDOW_X;
    assign PVIDEODHCLK = FF_VIDEO_DH_CLK;
    assign PVIDEODLCLK = FF_VIDEO_DL_CLK;
    assign PREDOTCOUNTER_X = FF_PRE_X_CNT;
    assign PREDOTCOUNTER_Y = FF_PRE_Y_CNT;
    assign PREDOTCOUNTER_YP = FF_MONITOR_LINE;
    assign HD = W_H_BLANK;
    assign VD = FF_VR;
    assign HSYNC = (W_H_CNT[1:0] == 2'b10 && FF_PRE_X_CNT == 9'b111111111) ? 1'b1 : 1'b0;
    assign V_BLANKING_START = W_V_BLANKING_START;

    // DOT STATE
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_DOTSTATE <= 2'b00;
            FF_VIDEO_DH_CLK <= 1'b0;
            FF_VIDEO_DL_CLK <= 1'b0;
        end else begin
            if (W_H_CNT == CLOCKS_PER_LINE[10:0]-1'b1) begin
                FF_DOTSTATE <= 2'b00;
                FF_VIDEO_DH_CLK <= 1'b1;
                FF_VIDEO_DL_CLK <= 1'b1;
            end else begin
                case (FF_DOTSTATE)
                    2'b00: begin
                        FF_DOTSTATE <= 2'b01;
                        FF_VIDEO_DH_CLK <= 1'b0;
                        FF_VIDEO_DL_CLK <= 1'b1;
                    end
                    2'b01: begin
                        FF_DOTSTATE <= 2'b11;
                        FF_VIDEO_DH_CLK <= 1'b1;
                        FF_VIDEO_DL_CLK <= 1'b0;
                    end
                    2'b11: begin
                        FF_DOTSTATE <= 2'b10;
                        FF_VIDEO_DH_CLK <= 1'b0;
                        FF_VIDEO_DL_CLK <= 1'b0;
                    end
                    2'b10: begin
                        FF_DOTSTATE <= 2'b00;
                        FF_VIDEO_DH_CLK <= 1'b1;
                        FF_VIDEO_DL_CLK <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // 8DOT STATE
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_EIGHTDOTSTATE <= 3'b000;
        end else if (W_H_CNT[1:0] == 2'b11) begin
            if (FF_PRE_X_CNT == 9'd0) begin
                FF_EIGHTDOTSTATE <= 3'b000;
            end else begin
                FF_EIGHTDOTSTATE <= FF_EIGHTDOTSTATE + 1'b1;
            end
        end
    end

    // GENERATE DOTCOUNTER
    assign W_PRE_X_CNT_START0 = {REG_R18_ADJ[3], REG_R18_ADJ[3:0]} + 5'b11000; // (-8...7) - 8 = (-16...-1)

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_PRE_X_CNT_START1 <= 6'b0;
        end else begin
            FF_PRE_X_CNT_START1 <= {W_PRE_X_CNT_START0[4], W_PRE_X_CNT_START0} - {3'b000, REG_R27_H_SCROLL};
        end
    end

    assign W_PRE_X_CNT_START2[8:6] = {3{FF_PRE_X_CNT_START1[5]}};
    assign W_PRE_X_CNT_START2[5:0] = FF_PRE_X_CNT_START1;   

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_PRE_X_CNT <= 9'b0;
        end else if (W_H_CNT == compute_adjusted_value(REG_R25_MSK, CENTERYJK_R25_N, REG_R25_YJK, VDPR9PALMODE)) begin
                        FF_PRE_X_CNT <= W_PRE_X_CNT_START2;
                     end else if (W_H_CNT[1:0] == 2'b10) begin
                        FF_PRE_X_CNT <= FF_PRE_X_CNT + 1'b1;
        end 
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_X_CNT <= 9'b0;
        end else if (W_H_CNT == compute_adjusted_value(REG_R25_MSK, CENTERYJK_R25_N, REG_R25_YJK, VDPR9PALMODE)) begin
                       ;// HOLD
                     end else if (W_H_CNT[1:0] == 2'b10) begin
                        if (FF_PRE_X_CNT == 9'b111111111 )
                            // JP: FF_PRE_X_CNT が -1から0にカウントアップする時にFF_X_CNTを-8にする
                            FF_X_CNT <= 9'b111111000;        // -8
                        else
                            FF_X_CNT <= FF_X_CNT + 1'b1;
                     end
    end

    // V-SYNC Pulse Generation
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            IVIDEOVS_N <= 1'b1;
        end else if (W_V_CNT_IN_FIELD == 10'd6) begin
            // SSTATE = SSTATE_B
            IVIDEOVS_N <= 1'b0;
        end else if (W_V_CNT_IN_FIELD == 10'd12) begin
            // SSTATE = SSTATE_A
            IVIDEOVS_N <= 1'b1;
        end
    end

    // DISPLAY WINDOW
    // LEFT MASK (R25 MSK)
    // H_SCROLL = 0 --> 8
    // H_SCROLL = 1 --> 7
    // H_SCROLL = 2 --> 6
    // H_SCROLL = 3 --> 5
    // H_SCROLL = 4 --> 4
    // H_SCROLL = 5 --> 3
    // H_SCROLL = 6 --> 2
    // H_SCROLL = 7 --> 1

always_comb begin
    if (REG_R25_MSK == 1'b0) begin
        W_LEFT_MASK = 9'b0;
    end else begin
        W_LEFT_MASK = {5'b00000, ({1'b0,(~REG_R27_H_SCROLL)} + 1'b1)};
    end
end

always_ff @(posedge CLK21M) begin
    // MAIN WINDOW
    if (W_H_CNT[1:0] == 2'b01 && FF_X_CNT == W_LEFT_MASK) begin
        // WHEN DOTCOUNTER_X = 0
        FF_RIGHT_MASK <= 9'b100000000 - {6'b000000, REG_R27_H_SCROLL};
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        FF_WINDOW_X <= 1'b0;
    end else if (W_H_CNT[1:0] == 2'b01 && FF_X_CNT == W_LEFT_MASK) begin
        // WHEN DOTCOUNTER_X = 0
        FF_WINDOW_X <= 1'b1;
    end else if (W_H_CNT[1:0] == 2'b01 && FF_X_CNT == FF_RIGHT_MASK) begin
        // WHEN DOTCOUNTER_X = 256
        FF_WINDOW_X <= 1'b0;
    end
end

// Y coordinate calculation and window control

assign W_HSYNC = W_H_CNT[1:0] == 2'b10 && FF_PRE_X_CNT == 9'b111111111;
assign W_Y_ADJ = {REG_R18_ADJ[7], REG_R18_ADJ[7], REG_R18_ADJ[7],
                  REG_R18_ADJ[7], REG_R18_ADJ[7], REG_R18_ADJ[7:4]};

logic [8:0] PREDOTCOUNTER_YP_V;
always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        FF_PRE_Y_CNT        <= 9'b0;
        FF_MONITOR_LINE     <= 9'b0;
        PREWINDOW_Y         <= 1'b0;
    end else begin
        if (W_HSYNC == 1'b1) begin
            // JP: PREWINDOW_Xが 1になるタイミングと同じタイミングでY座標の計算
            if (W_V_BLANKING_END == 1'b1) begin
                case ({VDPR9PALMODE, REG_R9_Y_DOTS})
                    2'b00: FF_MONITOR_LINE <= 9'b111100110 + W_Y_ADJ; // TOP BORDER LINES = -26 for NTSC, no interlace
                    2'b01: FF_MONITOR_LINE <= 9'b111110000 + W_Y_ADJ; // TOP BORDER LINES = -16 for NTSC, interlace
                    2'b10: FF_MONITOR_LINE <= 9'b111001011 + W_Y_ADJ; // TOP BORDER LINES = -53 for PAL, no interlace
                    2'b11: FF_MONITOR_LINE <= 9'b111010101 + W_Y_ADJ; // TOP BORDER LINES = -43 for PAL, interlace
                endcase
                PREWINDOW_Y_SP <= 1'b1;
            end else begin
                // Increment Y coordinate
                if (PREDOTCOUNTER_YP_V == 9'd255) begin
                    PREDOTCOUNTER_YP_V = FF_MONITOR_LINE;
                end else begin
                    PREDOTCOUNTER_YP_V = FF_MONITOR_LINE + 1'b1;
                end

                if (PREDOTCOUNTER_YP_V == 9'b0) begin
                    ENAHSYNC <= 1'b1;
                    PREWINDOW_Y <= 1'b1;
                end else if ((REG_R9_Y_DOTS == 1'b0 && PREDOTCOUNTER_YP_V == 9'd192) ||
                            (REG_R9_Y_DOTS == 1'b1 && PREDOTCOUNTER_YP_V == 9'd212)) begin
                    PREWINDOW_Y     <= 1'b0;
                    PREWINDOW_Y_SP  <= 1'b0;
                end else if ((REG_R9_Y_DOTS == 1'b0 && VDPR9PALMODE == 1'b0 && PREDOTCOUNTER_YP_V == 9'd235) ||
                            (REG_R9_Y_DOTS == 1'b1 && VDPR9PALMODE == 1'b0 && PREDOTCOUNTER_YP_V == 9'd245) ||
                            (REG_R9_Y_DOTS == 1'b0 && VDPR9PALMODE == 1'b1 && PREDOTCOUNTER_YP_V == 9'd259) ||
                            (REG_R9_Y_DOTS == 1'b1 && VDPR9PALMODE == 1'b1 && PREDOTCOUNTER_YP_V == 9'd269)) begin
                    ENAHSYNC <= 1'b0;
                end
                FF_MONITOR_LINE <= PREDOTCOUNTER_YP_V;
            end
        end
        // Update PRE_Y_CNT with vertical start line offset
        FF_PRE_Y_CNT <= FF_MONITOR_LINE + {1'b0, REG_R23_VSTART_LINE};
    end
end

// S#2 VR as openMSX: 0 from the left border of the line before the display to the end of
// the display under the current LN (also with the display off); not the OFFSET_Y based
// output blanking. At LEFT_BORDER_OUT the monitor line still holds the line before.
always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        FF_VR <= 1'b1;
    end else if (W_H_CNT == LEFT_BORDER_OUT) begin
        FF_VR <= !(FF_MONITOR_LINE == 9'h1FE || FF_MONITOR_LINE == 9'h1FF ||
                   (!FF_MONITOR_LINE[8] && FF_MONITOR_LINE[7:0] < (REG_R9_Y_DOTS ? 8'd211 : 8'd191)));
    end
end

// Output window without the border (HBLANK / VBLANK of the core with the border off): the
// place of the picture with R#18 = 0, no scroll and no mask. It must not follow the picture:
// the scaler would hide every move by R#18 / R#27 and rescale a masked or scrolled line.
logic [6:0]  W_OWIN_X0;
logic [10:0] W_OWIN_BASE;
logic [8:0]  FF_OUT_LINE, W_OUT_LINE_NEXT;
assign W_OWIN_X0   = OFFSET_X + (VDPR9PALMODE ? LED_TV_X_PAL : LED_TV_X_NTSC);
assign W_OWIN_BASE = {2'b00, W_OWIN_X0, 2'b10};         // X counter load (R#25 MSK = 0)
assign W_OUT_LINE_NEXT = (FF_OUT_LINE == 9'd255) ? FF_OUT_LINE : FF_OUT_LINE + 9'd1;

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        OWINDOW_X   <= 1'b0;
        OWINDOW_Y   <= 1'b0;
        FF_OUT_LINE <= 9'b0;
    end else begin
        // WINDOW_X of an unadjusted line: 67 clocks after the load, 256 pixels
        if (W_H_CNT == W_OWIN_BASE + 11'd67)        OWINDOW_X <= 1'b1;
        else if (W_H_CNT == W_OWIN_BASE + 11'd1091) OWINDOW_X <= 1'b0;

        // the monitor line without R#18, stepped where W_HSYNC is on an unadjusted line
        if (W_H_CNT == W_OWIN_BASE + 11'd32) begin
            if (W_V_BLANKING_END) begin
                case ({VDPR9PALMODE, REG_R9_Y_DOTS})
                    2'b00: FF_OUT_LINE <= 9'b111100110;
                    2'b01: FF_OUT_LINE <= 9'b111110000;
                    2'b10: FF_OUT_LINE <= 9'b111001011;
                    2'b11: FF_OUT_LINE <= 9'b111010101;
                endcase
            end else begin
                if (W_OUT_LINE_NEXT == 9'd0)
                    OWINDOW_Y <= 1'b1;
                else if ((REG_R9_Y_DOTS == 1'b0 && W_OUT_LINE_NEXT == 9'd192) ||
                         (REG_R9_Y_DOTS == 1'b1 && W_OUT_LINE_NEXT == 9'd212))
                    OWINDOW_Y <= 1'b0;
                FF_OUT_LINE <= W_OUT_LINE_NEXT;
            end
        end
    end
end

// Generate V-BLANKING signals
always_comb begin 
    W_V_BLANKING_END = ((W_V_CNT_IN_FIELD == {2'b00, (OFFSET_Y + LED_TV_Y_NTSC), (W_FIELD & REG_R9_INTERLACE_MODE)} && ~VDPR9PALMODE) ||
                        (W_V_CNT_IN_FIELD == {2'b00, (OFFSET_Y + LED_TV_Y_PAL),  (W_FIELD & REG_R9_INTERLACE_MODE)} && VDPR9PALMODE)) ? 1'b1 : 1'b0;
    
    // End of the display (openMSX VSCAN): line 192 / 212 starts. The monitor line counts
    // up at H_CNT 219, so at LEFT_BORDER_OUT it still holds the last display line.
    W_V_BLANKING_START = (REG_R9_Y_DOTS == 1'b0 && FF_MONITOR_LINE == 9'd191) ||
                         (REG_R9_Y_DOTS == 1'b1 && FF_MONITOR_LINE == 9'd211);
end

endmodule
