//
//  VDP_NTSC.vhd
//   VDP_NTSC sync signal generator.
//
//  Copyright (C) 2006 Kunihiko Ohnaka
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
// Memo
//   Japanese comment lines are starts with "JP:".
//   JP: 日本語のコメント行は JP:を頭に付ける事にする
//
//-----------------------------------------------------------------------------
// Revision History
//
// 13th,October,2003 created by Kunihiko Ohnaka
// JP: VDPのコアの実装と表示デバイスへの出力を別ソースにした．
//
// ??th,August,2006 modified by Kunihiko Ohnaka
//   - Move the equalization pulse generator from
//     vdp.vhd.
//
// 29th,October,2006 modified by Kunihiko Ohnaka
//   - Insert the license text.
//   - Add the document part below.
//
// 23rd,March,2008 modified by t.hara
// JP: リファクタリング, NTSC と PAL のタイミング生成回路を統合
//
//-----------------------------------------------------------------------------
// Document
//
// JP: ESE-VDPコア(vdp.vhd)が生成したビデオ信号を、NTSC/PALの
// JP: タイミングに合った同期信号および映像信号に変換します。
// JP: ESE-VDPコアはNTSCモード時は NTSC/PALのタイミングで映像
// JP: 信号や垂直同期信号を生成するため、本モジュールでは
// JP: 水平同期信号に等価パルスを挿入する処理だけを行って
// JP: います。
//

module VDP_NTSC_PAL (
    input  logic         CLK21M,
    input  logic         RESET,
    // MODE
    input  logic         PALMODE,
    input  logic         INTERLACEMODE,
    // VIDEO INPUT
    input  logic [5:0]   VIDEORIN,
    input  logic [5:0]   VIDEOGIN,
    input  logic [5:0]   VIDEOBIN,
    input  logic         VIDEOVSIN_N,
    input  logic [10:0]  HCOUNTERIN,
    input  logic [10:0]  VCOUNTERIN,
    // VIDEO OUTPUT
    output logic [5:0]   VIDEOROUT,
    output logic [5:0]   VIDEOGOUT,
    output logic [5:0]   VIDEOBOUT,
    output logic         VIDEOHSOUT_N,
    output logic         VIDEOVSOUT_N
);

    // State declaration
    typedef enum logic [1:0] {
        SSTATE_A,
        SSTATE_B,
        SSTATE_C,
        SSTATE_D
    } TYPSSTATE;

    TYPSSTATE FF_SSTATE;
    logic     FF_HSYNC_N;

    logic [1:0]  W_MODE;
    logic [10:0] W_STATE_A1_FULL;
    logic [10:0] W_STATE_A2_FULL;
    logic [10:0] W_STATE_B_FULL;
    logic [10:0] W_STATE_C_FULL;

    // H_SYNC pulse generation
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_HSYNC_N <= 1'b0;
        end else begin
            if (HCOUNTERIN == 11'd1) begin
                FF_HSYNC_N <= 1'b0; // Pulse on
            end else if (HCOUNTERIN == 11'd101) begin
                FF_HSYNC_N <= 1'b1; // Pulse off
            end
        end
    end

    // Video output assignments
    assign VIDEOHSOUT_N = FF_HSYNC_N;
    assign VIDEOVSOUT_N = VIDEOVSIN_N;
    assign VIDEOROUT    = VIDEORIN;
    assign VIDEOGOUT    = VIDEOGIN;
    assign VIDEOBOUT    = VIDEOBIN;

endmodule
