//
//  vdp_package.vhd
//   Package file of ESE-VDP.
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
// Memo
//   Japanese comment lines are starts with "JP:".
//   JP: 日本語のコメント行は JP:を頭に付ける事にする
//
//-----------------------------------------------------------------------------
// Revision History
//
// 29th,October,2006 modified by Kunihiko Ohnaka
//   - Insert the license text.
//   - Add the document part below.
//
//-----------------------------------------------------------------------------
// Document
//
// JP: ESE-VDPのパッケージファイルです。
// JP: ESE-VDPに含まれるモジュールのコンポーネント宣言や、定数宣言、
// JP: 型変換用の関数などが定義されています。
//

package VDP_PACKAGE;

    // VDP ID
    // localparam logic [4:0] VDP_ID = 5'b00000;  // V9938
    // localparam logic [4:0] VDP_ID = 5'b00010;  // V9958
    // logic [4:0] VDP_ID;  // managed by Switched I/O ports

    // display start position ( when adjust=(0,0) )
    // [from V9938 Technical Data Book]
    // Horizontal Display Parameters
    //  [non TEXT]
    //   * Total Display      1368 clks  - a
    //   * Right Border         59 clks  - b
    //   * Right Blanking       27 clks  - c
    //   * H-Sync Pulse Width  100 clks  - d
    //   * Left Blanking       102 clks  - e
    //   * Left Border          56 clks  - f
    // OFFSET_X is the position when preDotCounter_x is -8. So,
    //    => (d+e+f-8*4-8*4)/4 => (100+102+56)/4 - 16 => 48 + 1 = 49
    //
    // Vertical Display Parameters (NTSC)
    //                            [192 Lines]  [212 Lines]
    //                            [Even][Odd]  [Even][Odd]
    //   * V-Sync Pulse Width          3    3       3    3 lines - g
    //   * Top Blanking               13 13.5      13 13.5 lines - h
    //   * Top Border                 26   26      16   16 lines - i
    //   * Display Time              192  192     212  212 lines - j
    //   * Bottom Border            25.5   25    15.5   15 lines - k
    //   * Bottom Blanking             3    3       3    3 lines - l
    // OFFSET_Y is the start line of Top Border (192 Lines Mode)
    //    => l+g+h => 3 + 3 + 13 = 19
    //

    // NUMBER OF CLOCKS PER LINE, MUST BE A MULTIPLE OF 4
    localparam int CLOCKS_PER_LINE = 1368;  // 342*4

    // LEFT-TOP POSITION OF VISIBLE AREA
    localparam logic signed [6:0] OFFSET_X = 7'b0110001;  // 49
    // localparam logic [6:0] OFFSET_Y = 7'b0010011;  // 19
    // logic [6:0] OFFSET_Y;  // managed by Switched I/O ports

    localparam logic signed [6:0] LED_TV_X_NTSC = -7'sd3;
    localparam logic signed [6:0] LED_TV_Y_NTSC = 7'sd19;
    localparam logic signed [6:0] LED_TV_X_PAL  = -7'sd2;
    localparam logic signed [6:0] LED_TV_Y_PAL  = 7'sd14;

    // localparam int DISPLAY_OFFSET_NTSC = 0;
    // localparam int DISPLAY_OFFSET_PAL = 27;

    // localparam int SCAN_LINE_OFFSET_192 = 24;
    // localparam int SCAN_LINE_OFFSET_212 = 14;

    // localparam int LAST_LINE_NTSC = 262;  // 262 & 262.5 => 3 + 13 + 26 + 192 + 25 + 3
    // localparam int LAST_LINE_PAL = 313;  // 312.5 & 313 => 3 + 13 + 53 + 192 + 49 + 3

    // localparam int FIRST_LINE_192_NTSC = DISPLAY_OFFSET_NTSC + SCAN_LINE_OFFSET_192;
    // localparam int FIRST_LINE_212_NTSC = DISPLAY_OFFSET_NTSC + SCAN_LINE_OFFSET_212;
    // localparam int FIRST_LINE_192_PAL = DISPLAY_OFFSET_PAL + SCAN_LINE_OFFSET_192;
    // localparam int FIRST_LINE_212_PAL = DISPLAY_OFFSET_PAL + SCAN_LINE_OFFSET_212;

    localparam logic [10:0] LEFT_BORDER = 11'd235;
    // Left border start on the video output (picture from H_CNT 257 with R#18 = 0), the
    // openMSX reference point (tick 202) for VBLANK, VR and the end of the FH window
    localparam logic [10:0] LEFT_BORDER_OUT = 11'd201;
    // Clocks from PREDOTCOUNTER_X = 255 (ACTIVE_LINE) to the right border on the output
    localparam logic [5:0] RIGHT_BORDER_DELAY = 6'd40;
    // localparam int DISPLAY_AREA = 1024;

    // localparam int VISIBLE_AREA_SX = LEFT_BORDER;
    // localparam int VISIBLE_AREA_EX = CLOCKS_PER_LINE;

    // localparam int H_BLANKING_START = CLOCKS_PER_LINE - 59 - 27 + 1;

    localparam int V_BLANKING_START_192_NTSC = 240;
    localparam int V_BLANKING_START_212_NTSC = 242;
    localparam int V_BLANKING_START_192_PAL = 263;
    localparam int V_BLANKING_START_212_PAL = 273;

    function logic [10:0] toVector(
        input int value
    );

        return value[10:0];
    endfunction

    function logic signed [10:0] compute_adjusted_value(
        input logic REG_R25_MSK,
        input logic CENTERYJK_R25_N,
        input logic REG_R25_YJK,
        input logic VDPR9PALMODE
    );
        logic signed [6:0] adjusted_value;
        logic use_4_offset;

        // Výpočet základní hodnoty
        adjusted_value = OFFSET_X + (VDPR9PALMODE ? LED_TV_X_PAL : LED_TV_X_NTSC) - $signed({4'b0000, REG_R25_MSK & ~CENTERYJK_R25_N, 2'b00});

        // Určíme, jestli přidáme 4
        use_4_offset = (REG_R25_YJK && CENTERYJK_R25_N);

        if (use_4_offset) begin
            adjusted_value = adjusted_value + $signed(7'd4);
        end

        return {2'b00, adjusted_value[6:0], 2'b10};
endfunction

endpackage : VDP_PACKAGE

