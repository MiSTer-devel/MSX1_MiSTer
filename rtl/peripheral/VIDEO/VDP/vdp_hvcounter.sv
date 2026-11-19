//
//  vdp_hvcounter.vhd
//   horizontal and vertical counter of ESE-VDP.
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
//

module VDP_HVCOUNTER (
    input  logic          RESET,
    input  logic          CLK21M,

    output logic [10:0]   H_CNT,
    output logic [9:0]    V_CNT_IN_FIELD,
    output logic [10:0]   V_CNT_IN_FRAME,
    output logic          FIELD,
    output logic          H_BLANK,
    output logic          V_BLANK,

    input  logic          PAL_MODE,
    input  logic          INTERLACE_MODE,
    input  logic          Y212_MODE,
    input  logic [6:0]    OFFSET_Y
);

    // Flip-flop signals
    logic [10:0] FF_H_CNT;
    logic [9:0]  FF_V_CNT_IN_FIELD;
    logic        FF_FIELD;
    logic [10:0] FF_V_CNT_IN_FRAME;
    logic        FF_H_BLANK;
    logic        FF_V_BLANK;
    logic        FF_PAL_MODE;
    logic        FF_INTERLACE_MODE;

    // Wire signals
    logic        W_H_CNT_HALF;
    logic        W_H_CNT_END;
    logic [9:0]  W_FIELD_END_CNT;
    logic        W_FIELD_END;
    logic [1:0]  W_DISPLAY_MODE;
    logic [1:0]  W_LINE_MODE;
    logic        W_H_BLANK_START;
    logic        W_H_BLANK_END;
    logic        W_V_BLANKING_START;
    logic        W_V_BLANKING_END;
    logic [8:0]  W_V_SYNC_INTR_START_LINE;

    // Output assignments
    assign H_CNT = FF_H_CNT;
    assign V_CNT_IN_FIELD = FF_V_CNT_IN_FIELD;
    assign FIELD = FF_FIELD;
    assign V_CNT_IN_FRAME = FF_V_CNT_IN_FRAME;
    assign H_BLANK = FF_H_BLANK;
    assign V_BLANK = FF_V_BLANK;

    // V SYNCHRONIZE MODE CHANGE
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_PAL_MODE <= 1'b0;
            FF_INTERLACE_MODE <= 1'b0;
        end else if ((W_H_CNT_HALF || W_H_CNT_END) && W_FIELD_END && FF_FIELD) begin
            FF_PAL_MODE <= PAL_MODE;
            FF_INTERLACE_MODE <= INTERLACE_MODE;
        end
    end

    // HORIZONTAL COUNTER
    assign W_H_CNT_HALF = FF_H_CNT == toVector(CLOCKS_PER_LINE / 2 - 1);
    assign W_H_CNT_END  = FF_H_CNT == toVector(CLOCKS_PER_LINE - 1);

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_H_CNT <= '0;
        end else if (W_H_CNT_END) begin
            FF_H_CNT <= '0;
        end else begin
            FF_H_CNT <= FF_H_CNT + 1'b1;
        end
    end

    // VERTICAL COUNTER
    assign W_DISPLAY_MODE = {FF_INTERLACE_MODE, FF_PAL_MODE};

    always_comb begin
        case (W_DISPLAY_MODE)
            2'b00: W_FIELD_END_CNT = 10'd523;
            2'b10: W_FIELD_END_CNT = 10'd524;
            2'b01: W_FIELD_END_CNT = 10'd625;
            2'b11: W_FIELD_END_CNT = 10'd624;
            default: W_FIELD_END_CNT = 'X;
        endcase
    end

    assign W_FIELD_END = (FF_V_CNT_IN_FIELD == W_FIELD_END_CNT) ? 1'b1 : 1'b0;

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_V_CNT_IN_FIELD <= '0;
        end else if (W_H_CNT_HALF || W_H_CNT_END) begin
            if (W_FIELD_END) begin
                FF_V_CNT_IN_FIELD <= '0;
            end else begin
                FF_V_CNT_IN_FIELD <= FF_V_CNT_IN_FIELD + 1'b1;
            end
        end
    end

    // FIELD ID
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_FIELD <= 1'b0;
        end else if (W_H_CNT_HALF || W_H_CNT_END) begin
            if (W_FIELD_END) begin
                FF_FIELD <= ~FF_FIELD;
            end
        end
    end

    // VERTICAL COUNTER IN FRAME
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_V_CNT_IN_FRAME <= '0;
        end else if (W_H_CNT_HALF || W_H_CNT_END) begin
            if (W_FIELD_END && FF_FIELD) begin
                FF_V_CNT_IN_FRAME <= '0;
            end else begin
                FF_V_CNT_IN_FRAME <= FF_V_CNT_IN_FRAME + 1'b1;
            end
        end
    end

    // H BLANKING
    assign W_H_BLANK_START = W_H_CNT_END;
    assign W_H_BLANK_END = (FF_H_CNT == LEFT_BORDER) ? 1'b1 : 1'b0;

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_H_BLANK <= 1'b0;
        end else if (W_H_BLANK_START) begin
            FF_H_BLANK <= 1'b1;
        end else if (W_H_BLANK_END) begin
            FF_H_BLANK <= 1'b0;
        end
    end

    // V BLANKING
    assign W_LINE_MODE = {Y212_MODE, FF_PAL_MODE};

    always_comb begin
        case (W_LINE_MODE)
            2'b00: W_V_SYNC_INTR_START_LINE = V_BLANKING_START_192_NTSC[8:0];
            2'b10: W_V_SYNC_INTR_START_LINE = V_BLANKING_START_212_NTSC[8:0];
            2'b01: W_V_SYNC_INTR_START_LINE = V_BLANKING_START_192_PAL[8:0];
            2'b11: W_V_SYNC_INTR_START_LINE = V_BLANKING_START_212_PAL[8:0];
        endcase
    end

    assign W_V_BLANKING_END   = FF_V_CNT_IN_FIELD == {2'b00, OFFSET_Y + ((FF_PAL_MODE == 1'b0) ? LED_TV_Y_NTSC : LED_TV_Y_PAL), (FF_FIELD & FF_INTERLACE_MODE) };
    assign W_V_BLANKING_START = FF_V_CNT_IN_FIELD == {W_V_SYNC_INTR_START_LINE + ((FF_PAL_MODE == 1'b0) ? {2'b00, LED_TV_Y_NTSC} : {2'b00, LED_TV_Y_PAL}), (FF_FIELD && FF_INTERLACE_MODE)};

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_V_BLANK <= 1'b0;
        end else if (W_H_BLANK_END) begin
            if (W_V_BLANKING_END) begin
                FF_V_BLANK <= 1'b0;
            end else if (W_V_BLANKING_START) begin
                FF_V_BLANK <= 1'b1;
            end
        end
    end

endmodule
