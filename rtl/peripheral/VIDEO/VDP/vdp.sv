//
//  vdp.vhd
//   Top VHDL Source of ESE-VDP.
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
// Contributors
//
//   Kazuhiro Tsujikawa
//     - Bug fixes
//   Alex Wulms
//     - Bug fixes
//     - Expansion and improvement of the VDP-Command engine
//     - Improvement of the TEXT2 mode.
//
//-----------------------------------------------------------------------------
// Memo
//   Japanese comment lines are starts with "JP:".
//   JP: 日本語のコメント行は JP:を頭に付ける事にする
//
//-----------------------------------------------------------------------------
// Revision History
//
// 3rd,June,2018 modified by KdL
//  - Improved the VGA up-scan converter
//
// 15th,March,2017 modified by KdL
//  - Improved ENAHSYNC, thanks to Grauw
//
// 27th,July,2014 modified by KdL
//  - Fixed H-SYNC interrupt reset control
//
// 23rd,January,2013 modified by KdL
//  - Fixed V-SYNC and H-SYNC interrupt
//  - Added an extra signal to force NTSC/PAL modes
//
// 29th,October,2006 modified by Kunihiko Ohnaka
//  - Added the license text
//  - Added the document part below
//
// 3rd,Sep,2006 modified by Kunihiko Ohnaka
//  - Fix several UNKNOWN REALITY problems
//  - Horizontal Sprite problem
//  - Overscan problem
//  - [NOP] zoom demo problem
//  - 'Star Wars Scroll' demo problem
//
// 20th,Aug,2006 modified by Kunihiko Ohnaka
//  - Separate SPRITE module
//  - Fixed the palette rewriting timing problem
//  - Added the interlace double resolution function (two page mode)
//
// 15th,Aug,2006 modified by Kunihiko Ohnaka
//  - Separate VDP_NTSC sync generator module
//  - Separate screen mode modules
//  - Fixed the sprite posision problem on GRAPHIC6
//
// 15th,Jan,2006 modified by Alex Wulms
// text 2 mode  : debug blink function
// high-res modi: debug 'screen off'
// text 1&2 mode: debug VdpR23 scroll and color "0000" handling
// all modi     : precalculate adjustx, adjusty once per line

// 1st,Jan,2006 modified by Alex Wulms
// Added the blink support to text 2 mode
//
// 16th,Aug,2005 modified by Kazuhiro Tsujikawa
// JP: TMS9918モードでVRAMインクリメントを下位14ビットに限定
//
// 8th,May,2005 modified by Kunihiko Ohnaka
// JP: VGAコンポーネントにInerlaceMode信号を伝えるようにした
//
// 26th,April,2005 modified by Kazuhiro Tsujikawa
// JP: VRAMとのデータバス(pRamDbi/pRamDbo)を単方向バス化(SDRAM対応)
//
// 8th,November,2004 modified by Kazuhiro Tsujikawa
// JP: Vsync/Hsync割り込み修正ミス訂正
//
// 3rd,November,2004 modified by Kazuhiro Tsujikawa
// JP: SCREEN6画面周辺色修正→MSX2タイトルロゴ対応
//
// 19th,September,2004 modified by Kazuhiro Tsujikawa
// JP: パターンネームテーブルのマスクを実装→ANMAデモ対応
// JP: MultiColorMode(SCREEN3)実装→マジラビデモ対応
//
// 12th,September,2004 modified by Kazuhiro Tsujikawa
// JP: VdpR0DispNum等をライン単位で反映→スペースマンボウでのチラツキ対策
//
// 11th,September,2004 modified by Kazuhiro Tsujikawa
// JP: 水平帰線割り込み修正→MGSEL(テンポ早送り)対策
//
// 22nd,August,2004 modified by Kazuhiro Tsujikawa
// JP: パレットのRead/Write衝突を修正→ガゼルでのチラツキ対策
//
// 21st,August,2004 modified by Kazuhiro Tsujikawa
// JP: R1/IE0(垂直帰線割り込み許可)の動作を修正→GALAGA対策
//
// 2nd,August,2004 modified by Kazuhiro Tsujikawa
// JP: Screen7/8でのスプライト読み込みアドレスを修正→Snatcher対策
//
// 31st,July,2004 modified by Kazuhiro Tsujikawa
// JP: Screen7/8でのVRAM読み込みアドレスを修正→Snatcher対策
//
// 24th,July,2004 modified by Kazuhiro Tsujikawa
// JP: スプライト32枚同時表示時の乱れを修正(248=256-8->preDotCounter_x_end)
//
// 18th,July,2004 modified by Kazuhiro Tsujikawa
// JP: Screen6のレンダリング部を作成
//
// 17th,July,2004 modified by Kazuhiro Tsujikawa
// JP: Screen7のレンダリング部を作成
//
// 29th,June,2004 modified by Kazuhiro Tsujikawa
// JP: Screen8のレンダリング部を修正
//
// 26th,June,2004 modified by Kazuhiro Tsujikawa
// JP: WebPackでコンパイルするとHMMC/LMMC/LMCMが動作しない不具合を修正
// JP: onehot sequencer(VdpCmdState) must be initialized by asyncronus RESET
//
// 22nd,June,2004 modified by Kazuhiro Tsujikawa
// JP: R1/IE0(垂直帰線割り込み許可)の動作を修正
// JP: Ys2でバノアの家に入れる様になった
//
// 13th,June,2004 modified by Kazuhiro Tsujikawa
// JP: 拡大スプライトが右に1ドットずれる不具合を修正
// JP: SCREEN5でスプライト右端32ドットが表示されない不具合を修正
// JP: SCREEN5で211ライン(最下)のスプライトが表示されない不具合を修正
// JP: 画面消去フラグ(VdpR1DispOn)を1ライン単位で反映する様に修正
//
// 21st,March,2004 modified by Alex Wulms
// Several enhancements to command engine:
//   Added PSET,LINE,SRCH,POINT
//   Added the screen 6,7,8 support
//   Improved the existing commands
//
// 15th,January,2004 modified by Kunihiko Ohnaka
// JP: VDPコマンドの実装を開始
// JP: HMMC,HMMM,YMMM,HMMV,LMMC,LMMM,LMMVを実装.まだ不具合あり.
//
// 12th,January,2004 modified by Kunihiko Ohnaka
// JP: コメントの修正
//
// 30th,December,2003 modified by Kazuhiro Tsujikawa
// JP: 起動時の画面モードをVDP_NTSCと VGAのどちらにするかを，外部入力で切替
// JP: DHClk/DLClkを一時的に復活させた
//
// 16th,December,2003 modified by Kunihiko Ohnaka
// JP: 起動時の画面モードをVDP_NTSCと VGAのどちらにするかを，vdp_package.vhd
// JP: 内で定義された定数で切替えるようにした．
//
// 10th,December,2003 modified by Kunihiko Ohnaka
// JP: TEXT MODE 2 (SCREEN0 WIDTH80)をサポート．
// JP: 初の横方向倍解像度モードである．一応将来対応できるように作って
// JP: きたつもりだったが，少し収まりが悪い部分があり，あまりきれいな
// JP: 対応になっていない部分もあります．
//
// 13th,October,2003 modified by Kunihiko Ohnaka
// JP: ESE-MSX基板では 2S300Eを複数用いる事ができるようにり，VDP単体で
// JP: 2S300Eや SRAMを占有する事が可能となった．
// JP: これに伴い以下のような変更を行う．
// JP: ・VGA出力対応(アップスキャンコンバート)
// JP: ・SCREEN7,8のタイミングを実機と同じに
//
// 15th,June,2003 modified by Kunihiko Ohnaka
// JP:水平帰線期間割り込みを実装してスペースマンボウを遊べるようにした．
// JP:GraphicMode3(Screen4)でYライン数が 212ラインにならなかったのを
// JP:修正したりした．
// JP:ただし，スペースマンボウで set adjust機能が動いていないような
// JP:感じで，表示がガクガクしてしまう．横方向の同時表示スプライト数も
// JP:足りていないように見える．原因不明．
//
// 15th,June,2003 modified by Kunihiko Ohnaka
// JP:長いブランクが空いてしまったが，Spartan-II E + IO基板でスプライトが
// JP:表示されるようになった．原因はおそらくコンパイラのバグで，ISE 5.2に
// JP:バージョンアップしたら表示されるようになった．
// JP:ついでに，スプライトモード2で横 8枚並ぶようにした(つもり)．
// JP:その他細かな修正が入っています．
//
// 15th,July,2002 modified by Kazuhiro Tsujikawa
// no comment;
//
// 5th,September,2019 modified by Oduvaldo Pavan Junior
// Fixed the lack of page flipping (R13) capability
//
// Added the undocumented feature where R1 bit #2 change the blink counter
// clock source from VSYNC to HSYNC
//
//-----------------------------------------------------------------------------
// Document
//
// JP: ESE-VDPのトップエンティティです。CPUとのインターフェース、
// JP: 画面描画タイミングの生成、VDPレジスタの実装などが含まれて
// JP: います。
//

import VDP_PACKAGE::*;

module VDP (
    input logic         CLK21M,
    input logic         RESET,
    input logic         REQ,
    output logic        ACK,
    input logic         WRT,
    input logic [15:0]  ADR,
    output logic [7:0]  DBI,
    input logic [7:0]   DBO,
    output logic        INT_N,
    output logic        PRAMOE_N,
    output logic        PRAMWE_N,
    output logic [16:0] PRAMADR,
    input logic [15:0]  PRAMDBI,
    output logic [7:0]  PRAMDBO,
    input logic         VDPSPEEDMODE,
    input logic         CENTERYJK_R25_N,
    output logic [5:0]  PVIDEOR,
    output logic [5:0]  PVIDEOG,
    output logic [5:0]  PVIDEOB,
    output logic        PVIDEODE,
    output logic        PVIDEOHS_N,
    output logic        PVIDEOVS_N,
    output logic        PVIDEOCS_N,
    output logic        PVIDEODHCLK,
    output logic        PVIDEODLCLK,
    output logic        HBLANK,
    output logic        VBLANK,
    input logic         NTSC_PAL_TYPE,
    input logic         FORCED_V_MODE,
    input logic         BORDER,
    input logic [4:0]   VDP_ID,
    input logic [6:0]   OFFSET_Y
);

// Internal signal declarations here

logic [10:0] H_CNT;
logic [10:0] V_CNT;

// DISPLAY POSITIONS, ADAPTED FOR ADJUST(X,Y)
logic [6:0] ADJUST_X;

// DOT STATE REGISTER
logic [1:0] DOTSTATE;
logic [2:0] EIGHTDOTSTATE;

// DISPLAY FIELD SIGNAL
logic FIELD;
logic HD;
logic VD;
logic ACTIVE_LINE;
logic V_BLANKING_START;

// FOR VSYNC INTERRUPT
logic VSYNCINT_N;
logic CLR_VSYNC_INT;
logic REQ_VSYNC_INT_N;

// FOR HSYNC INTERRUPT
logic HSYNCINT_N;
logic CLR_HSYNC_INT;
logic REQ_HSYNC_INT_N;
logic FH_LEVEL;
logic REQ_HSYNC_S1_N;     // S#1 FH as read: the latch with IE1 on, the line level with IE1 off

logic DVIDEOHS_N;

// DISPLAY AREA FLAGS
logic WINDOW;
logic WINDOW_X;
logic PREWINDOW_X;
logic PREWINDOW_Y;
logic PREWINDOW_Y_SP;
logic PREWINDOW;
logic PREWINDOW_SP;

// FOR FRAME ZONE
logic BWINDOW_X;
logic OWINDOW_X;
logic OWINDOW_Y;
logic BWINDOW_Y;
logic BWINDOW;
logic FF_HBLANK;
logic FF_VBLANK;

// DOT COUNTER - 8 (READING ADDR)
logic [8:0] PREDOTCOUNTER_X;
logic [8:0] PREDOTCOUNTER_Y;

// Y COUNTERS INDEPENDENT OF VERTICAL SCROLL REGISTER
logic [8:0] PREDOTCOUNTER_YP;

// VDP REGISTER ACCESS
logic [16:0] VDPVRAMACCESSADDR;
logic VDPVRAMREADINGR;
logic VDPVRAMREADINGA;
logic [2:0] VDPR0DISPNUM;
logic [7:0] VDPVRAMACCESSDATA;
logic [16:0] VDPVRAMACCESSADDRTMP;
logic VDPVRAMADDRSETREQ;
logic VDPVRAMADDRSETACK;
logic VDPVRAMWRREQ;
logic VDPVRAMWRACK;
logic [7:0] VDPVRAMRDDATA;
logic VDPVRAMRDREQ;
logic VDPVRAMRDACK;
logic VDPR9PALMODE;

// VDP REGISTER SIGNALS
logic REG_R0_HSYNC_INT_EN;
logic REG_R1_SP_SIZE;
logic REG_R1_SP_ZOOM;
logic REG_R1_BL_CLKS;
logic REG_R1_VSYNC_INT_EN;
logic REG_R1_DISP_ON;
logic [6:0] REG_R2_PT_NAM_ADDR;
logic [5:0] REG_R4_PT_GEN_ADDR;
logic [10:0] REG_R10R3_COL_ADDR;
logic [9:0] REG_R11R5_SP_ATR_ADDR;
logic [5:0] REG_R6_SP_GEN_ADDR;
logic [7:0] REG_R7_FRAME_COL;
logic REG_R8_SP_OFF;
logic REG_R8_COL0_ON;
logic REG_R9_PAL_MODE;
logic REG_R9_INTERLACE_MODE;
logic REG_R9_Y_DOTS;
logic [7:0] REG_R12_BLINK_MODE;
logic [7:0] REG_R13_BLINK_PERIOD;
logic [7:0] REG_R18_ADJ;
logic [7:0] REG_R19_HSYNC_INT_LINE;
logic [7:0] REG_R23_VSTART_LINE;
logic REG_R25_CMD;
logic REG_R25_YAE;
logic REG_R25_YJK;
logic REG_R25_MSK;
logic REG_R25_SP2;
logic [8:3] REG_R26_H_SCROLL;
logic [2:0] REG_R27_H_SCROLL;

// TEXT MODE SIGNALS
logic TEXT_MODE;
logic VDPMODETEXT1;
logic VDPMODETEXT1Q;
logic VDPMODETEXT2;
logic VDPMODEMULTI;
logic VDPMODEMULTIQ;
logic VDPMODEGRAPHIC1;
logic VDPMODEGRAPHIC2;
logic VDPMODEGRAPHIC3;
logic VDPMODEGRAPHIC4;
logic VDPMODEGRAPHIC5;
logic VDPMODEGRAPHIC6;
logic VDPMODEGRAPHIC7;
logic VDPMODEISHIGHRES;
logic VDPMODEISVRAMINTERLEAVE;

// FOR TEXT 1 AND 2
logic [16:0] PRAMADRT12;
logic [3:0] COLORCODET12;
logic TXVRAMREADEN;

// FOR GRAPHIC 1, 2, 3, AND MULTICOLOR
logic [16:0] PRAMADRG123M;
logic [3:0] COLORCODEG123M;

// FOR GRAPHIC 4, 5, 6, 7
logic [16:0] PRAMADRG4567;
logic [7:0] COLORCODEG4567;
logic [5:0] YJK_R;
logic [5:0] YJK_G;
logic [5:0] YJK_B;
logic YJK_EN;

// SPRITE SIGNALS
logic SPMODE2;
logic SPVRAMACCESSING;
logic [16:0] PRAMADRSPRITE;
logic SPRITECOLOROUT;
logic [3:0] COLORCODESPRITE;
logic VDPS0SPCOLLISIONINCIDENCE;
logic VDPS0SPOVERMAPPED;
logic [4:0] VDPS0SPOVERMAPPEDNUM;
logic [8:0] VDPS3S4SPCOLLISIONX;
logic [8:0] VDPS5S6SPCOLLISIONY;
logic SPVDPS0RESETREQ;
logic SPVDPS0RESETACK;
logic SPVDPS5RESETREQ;
logic SPVDPS5RESETACK;

// PALETTE REGISTERS
logic [3:0] PALETTEADDR_OUT;
logic [8:0] PALETTEDATARGB_OUT;

// VDP COMMAND SIGNALS
logic [7:0] VDPCMDCLR;
logic VDPCMDCE;
logic VDPCMDROWSTEP, VDPCMDMINORSTEP, VDP_CMD_XFER;
logic VDPCMDBD;
logic VDPCMDTR;
logic [10:0] VDPCMDSXTMP;
logic [3:0] VDPCMDREGNUM;
logic [7:0] VDPCMDREGDATA;
logic VDPCMDREGWRACK;
logic VDPCMDTRCLRACK;
logic VDPCMDVRAMWRACK;
logic VDPCMDVRAMRDACK;
logic VDPCMDVRAMREADINGR;
logic VDPCMDVRAMREADINGA;
logic [7:0] VDPCMDVRAMRDDATA;
logic VDPCMDREGWRREQ;
logic VDPCMDTRCLRREQ;
logic VDPCMDVRAMWRREQ;
logic VDPCMDVRAMRDREQ;
logic [16:0] VDPCMDVRAMACCESSADDR;
logic [7:0] VDPCMDVRAMWRDATA;

logic VDP_COMMAND_ACTIVE;
logic [7:4] CUR_VDP_COMMAND;

// VIDEO OUTPUT SIGNALS
logic [5:0] IVIDEOR;
logic [5:0] IVIDEOG;
logic [5:0] IVIDEOB;

logic [5:0] IVIDEOR_VDP;
logic [5:0] IVIDEOG_VDP;
logic [5:0] IVIDEOB_VDP;
logic IVIDEOVS_N;

logic [16:0] IRAMADR;
logic [7:0] PRAMDAT;
logic XRAMSEL;
logic [7:0] PRAMDATPAIR;

logic HSYNC;
logic ENAHSYNC;

// Constants
localparam integer VRAM_ACCESS_IDLE = 0;
localparam integer VRAM_ACCESS_DRAW = 1;
localparam integer VRAM_ACCESS_CPUW = 2;
localparam integer VRAM_ACCESS_CPUR = 3;
localparam integer VRAM_ACCESS_SPRT = 4;
localparam integer VRAM_ACCESS_VDPW = 5;
localparam integer VRAM_ACCESS_VDPR = 6;
localparam integer VRAM_ACCESS_VDPS = 7;

// Logic for PRAMADR, XRAMSEL, PRAMDAT, and PRAMDATPAIR
assign PRAMADR = IRAMADR;
assign XRAMSEL = IRAMADR[16];
assign PRAMDAT = (XRAMSEL == 1'b0) ? PRAMDBI[7:0] : PRAMDBI[15:8];
assign PRAMDATPAIR = (XRAMSEL == 1'b1) ? PRAMDBI[7:0] : PRAMDBI[15:8];

// DISPLAY COMPONENTS LOGIC
assign VDPR9PALMODE = (NTSC_PAL_TYPE == 1'b1) ? REG_R9_PAL_MODE : FORCED_V_MODE;

assign IVIDEOR = (BWINDOW == 1'b0) ? 6'b000000 : IVIDEOR_VDP;
assign IVIDEOG = (BWINDOW == 1'b0) ? 6'b000000 : IVIDEOG_VDP;
assign IVIDEOB = (BWINDOW == 1'b0) ? 6'b000000 : IVIDEOB_VDP;

VDP_NTSC_PAL U_VDP_NTSC_PAL (
    .CLK21M         (CLK21M),
    .RESET          (RESET),
    .PALMODE        (VDPR9PALMODE),
    .INTERLACEMODE  (REG_R9_INTERLACE_MODE),
    .VIDEORIN       (IVIDEOR),
    .VIDEOGIN       (IVIDEOG),
    .VIDEOBIN       (IVIDEOB),
    .VIDEOVSIN_N    (IVIDEOVS_N),
    .HCOUNTERIN     (H_CNT),
    .VCOUNTERIN     (V_CNT),
    .VIDEOROUT      (PVIDEOR),
    .VIDEOGOUT      (PVIDEOG),
    .VIDEOBOUT      (PVIDEOB),
    .VIDEOHSOUT_N   (PVIDEOHS_N),
    .VIDEOVSOUT_N   (PVIDEOVS_N)
);

assign PVIDEODE  = BWINDOW;

// THESE SIGNALS BELOW ARE OUTPUT DIRECTLY REGARDLESS OF DISPLAY MODE.
assign PVIDEOCS_N = ~(PVIDEOHS_N ^ PVIDEOVS_N);

assign HBLANK = FF_HBLANK;
assign VBLANK = FF_VBLANK;

// INTERRUPT
// VSYNC INTERRUPT
assign VSYNCINT_N = (REG_R1_VSYNC_INT_EN == 1'b0) ? 1'b1 : REQ_VSYNC_INT_N;

// HSYNC INTERRUPT
assign HSYNCINT_N = (REG_R0_HSYNC_INT_EN == 1'b0 || ENAHSYNC == 1'b0) ? 1'b1 : REQ_HSYNC_INT_N;

// INTERRUPT OUTPUT
assign INT_N = (VSYNCINT_N == 1'b0 || HSYNCINT_N == 1'b0) ? 1'b0 : 1'b1;

// VDP_INTERRUPT instantiation
VDP_INTERRUPT U_INTERRUPT (
    .RESET                  (RESET),
    .CLK21M                 (CLK21M),
    .H_CNT                  (H_CNT),
    .Y_CNT                  (PREDOTCOUNTER_Y[7:0]),
    .ACTIVE_LINE            (ACTIVE_LINE),
    .V_BLANKING_START       (V_BLANKING_START),
    .CLR_VSYNC_INT          (CLR_VSYNC_INT),
    .CLR_HSYNC_INT          (CLR_HSYNC_INT),
    .REQ_VSYNC_INT_N        (REQ_VSYNC_INT_N),
    .REQ_HSYNC_INT_N        (REQ_HSYNC_INT_N),
    .FH_LEVEL               (FH_LEVEL),
    .REG_R19_HSYNC_INT_LINE (REG_R19_HSYNC_INT_LINE),
    .REG_R0_HSYNC_INT_EN    (REG_R0_HSYNC_INT_EN)
);

assign REQ_HSYNC_S1_N = REG_R0_HSYNC_INT_EN ? REQ_HSYNC_INT_N : ~FH_LEVEL;

always_ff @(posedge CLK21M) begin
    if (PREDOTCOUNTER_X == 9'd255) begin
        ACTIVE_LINE <= 1'b1;
    end else begin
        ACTIVE_LINE <= 1'b0;
    end
end

// Instantiate components

VDP_SSG U_SSG (
    .RESET                  (RESET),
    .CLK21M                 (CLK21M),

    .H_CNT                  (H_CNT),
    .V_CNT                  (V_CNT),
    .DOTSTATE               (DOTSTATE),
    .EIGHTDOTSTATE          (EIGHTDOTSTATE),
    .PREDOTCOUNTER_X        (PREDOTCOUNTER_X),
    .PREDOTCOUNTER_Y        (PREDOTCOUNTER_Y),
    .PREDOTCOUNTER_YP       (PREDOTCOUNTER_YP),
    .PREWINDOW_Y            (PREWINDOW_Y),
    .PREWINDOW_Y_SP         (PREWINDOW_Y_SP),
    .FIELD                  (FIELD),
    .WINDOW_X               (WINDOW_X),
    .OWINDOW_X              (OWINDOW_X),
    .OWINDOW_Y              (OWINDOW_Y),
    .PVIDEODHCLK            (PVIDEODHCLK),
    .PVIDEODLCLK            (PVIDEODLCLK),
    .IVIDEOVS_N             (IVIDEOVS_N),

    .HD                     (HD),
    .VD                     (VD),
    .HSYNC                  (HSYNC),
    .ENAHSYNC               (ENAHSYNC),
    .V_BLANKING_START       (V_BLANKING_START),

    .VDPR9PALMODE           (VDPR9PALMODE),
    .REG_R9_INTERLACE_MODE  (REG_R9_INTERLACE_MODE),
    .REG_R9_Y_DOTS          (REG_R9_Y_DOTS),
    .REG_R18_ADJ            (REG_R18_ADJ),
    .REG_R23_VSTART_LINE    (REG_R23_VSTART_LINE),
    .REG_R25_MSK            (REG_R25_MSK),
    .REG_R27_H_SCROLL       (REG_R27_H_SCROLL),
    .REG_R25_YJK            (REG_R25_YJK),
    .CENTERYJK_R25_N        (CENTERYJK_R25_N),
    .OFFSET_Y               (OFFSET_Y)
);

// GENERATE BWINDOW
wire [31:0] CLOCKS_PER_LINE_minus_two = CLOCKS_PER_LINE-2;
always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        BWINDOW_X <= 1'b0;
    end else begin
        if (H_CNT == 11'd200) begin
            BWINDOW_X <= 1'b1;
        end else if (H_CNT == CLOCKS_PER_LINE_minus_two[10:0]) begin
            BWINDOW_X <= 1'b0;
        end
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        BWINDOW_Y <= 1'b0;
    end else begin
        if (REG_R9_INTERLACE_MODE == 1'b0) begin
            // Non-interlace mode
            // 3+3+16 = 19
            if ((V_CNT == 11'd40) || //20*2
                ((V_CNT == 11'd564 && VDPR9PALMODE == 1'b0)) || // 524+20*2
                ((V_CNT == 11'd666 && VDPR9PALMODE == 1'b1))) begin // 626+20*2
                BWINDOW_Y <= 1'b1;
            end else if ((V_CNT == 11'd524 && VDPR9PALMODE == 1'b0) || 
                         (V_CNT == 11'd626 && VDPR9PALMODE == 1'b1) || 
                         (V_CNT == 11'd0)) begin
                BWINDOW_Y <= 1'b0;
            end
        end else begin
            // Interlace mode
            if ((V_CNT == 11'd40) || //20*2
                // +1 SHOULD BE NEEDED.
                // BECAUSE ODD FIELD'S START IS DELAYED HALF LINE.
                // SO THE START POSITION OF DISPLAY TIME SHOULD BE
                // DELAYED MORE HALF LINE.
                ((V_CNT == 11'd566 && VDPR9PALMODE == 1'b0)) ||  // 525+20*2 + 1
                ((V_CNT == 11'd646 && VDPR9PALMODE == 1'b1))) begin // 625+20*2 + 1
                BWINDOW_Y <= 1'b1;
            end else if ((V_CNT == 11'd525 && VDPR9PALMODE == 1'b0) ||
                         (V_CNT == 11'd625 && VDPR9PALMODE == 1'b1) ||
                         (V_CNT == 11'd0)) begin
                BWINDOW_Y <= 1'b0;
            end
        end
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        BWINDOW   <= 1'b0;
        FF_HBLANK <= 1'b0;
        FF_VBLANK <= 1'b0;
    end else begin
        BWINDOW <= BWINDOW_X & BWINDOW_Y;
        if (BORDER == 1'b1) begin
            FF_HBLANK <= ~BWINDOW_X;
            FF_VBLANK <= ~BWINDOW_Y;
        end else begin
            FF_HBLANK <= ~OWINDOW_X;
            FF_VBLANK <= ~OWINDOW_Y;
        end
    end
end

// GENERATE PREWINDOW, WINDOW
assign WINDOW    = WINDOW_X & PREWINDOW_Y;
assign PREWINDOW = PREWINDOW_X & PREWINDOW_Y;

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        PREWINDOW_X <= 1'b0;
    end else begin
        if (H_CNT == compute_adjusted_value(REG_R25_MSK, CENTERYJK_R25_N, REG_R25_YJK, VDPR9PALMODE)) begin
            // Hold (no change)
        end else if (H_CNT[1:0] == 2'b10) begin
            if (PREDOTCOUNTER_X == 9'b111111111) begin
                // JP: PREDOTCOUNTER_X が -1から0にカウントアップする時にWINDOWを1にする
                PREWINDOW_X <= 1'b1;
            end else if (PREDOTCOUNTER_X == 9'b011111111) begin
                PREWINDOW_X <= 1'b0;
            end
        end
    end
end

//----------------------------------------------------------------------------
// main process
//----------------------------------------------------------------------------

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        VDPVRAMRDDATA   <= 8'b0; // equivalent to (OTHERS => '0')
        VDPVRAMREADINGA <= 1'b0;
    end else begin
        if (DOTSTATE == 2'b01) begin
            if (VDPVRAMREADINGR != VDPVRAMREADINGA) begin
                VDPVRAMRDDATA   <= PRAMDAT;
                VDPVRAMREADINGA <= ~VDPVRAMREADINGA;
            end
        end
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        VDPCMDVRAMRDDATA   <= 8'b0; // equivalent to (OTHERS => '0')
        VDPCMDVRAMRDACK    <= 1'b0;
        VDPCMDVRAMREADINGA <= 1'b0;
    end else begin
        if (DOTSTATE == 2'b01) begin
            if (VDPCMDVRAMREADINGR != VDPCMDVRAMREADINGA) begin
                VDPCMDVRAMRDDATA   <= PRAMDAT;
                VDPCMDVRAMRDACK    <= ~VDPCMDVRAMRDACK;
                VDPCMDVRAMREADINGA <= ~VDPCMDVRAMREADINGA;
            end
        end
    end
end

assign TEXT_MODE = VDPMODETEXT1 || VDPMODETEXT1Q || VDPMODETEXT2;

always_ff @(posedge CLK21M or posedge RESET) begin
    // VARIABLE equivalent in SystemVerilog: use a `logic` or a local variable inside the block
    logic [16:0] VDPVRAMACCESSADDRV;
    integer VRAMACCESSSWITCH;

    if (RESET) begin
        IRAMADR <= '1;     // (OTHERS => '1')
        PRAMDBO <= '0;     // (OTHERS => '0')
        PRAMOE_N <= 1'b1;
        PRAMWE_N <= 1'b1;

        VDPVRAMREADINGR <= 1'b0;

        VDPVRAMRDACK <= 1'b0;
        VDPVRAMWRACK <= 1'b0;
        VDPVRAMADDRSETACK <= 1'b0;
        VDPVRAMACCESSADDR <= '0;  // (OTHERS => '0')

        VDPCMDVRAMWRACK <= 1'b0;
        VDPCMDVRAMREADINGR <= 1'b0;
        VDP_CMD_XFER <= 1'b0;
    end else begin
        //------------------------------------------
        // MAIN STATE
        //------------------------------------------
        //
        // VRAM ACCESS ARBITER.
        //
        // VRAMアクセスタイミングを、EIGHTDOTSTATE によって制御している
        if (DOTSTATE == 2'b10) begin
            if ((PREWINDOW == 1'b1) && (REG_R1_DISP_ON == 1'b1) &&
                ((EIGHTDOTSTATE == 3'b000) || (EIGHTDOTSTATE == 3'b001) || (EIGHTDOTSTATE == 3'b010) ||
                 (EIGHTDOTSTATE == 3'b011) || (EIGHTDOTSTATE == 3'b100))) begin
                //  EIGHTDOTSTATE が 0～4 で、表示中の場合
                VRAMACCESSSWITCH = VRAM_ACCESS_DRAW;
            end else if ((PREWINDOW == 1'b1) && (REG_R1_DISP_ON == 1'b1) && (TXVRAMREADEN == 1'b1)) begin
                //  EIGHTDOTSTATE が 5～7 で、表示中で、テキストモードの場合
                VRAMACCESSSWITCH = VRAM_ACCESS_DRAW;
            end else if ((PREWINDOW_X == 1'b1) && (PREWINDOW_Y_SP == 1'b1) && (SPVRAMACCESSING == 1'b1) &&
                        (EIGHTDOTSTATE == 3'b101) && (TEXT_MODE == 1'b0)) begin
                // FOR SPRITE Y-TESTING
                VRAMACCESSSWITCH = VRAM_ACCESS_SPRT;
            end else if ((PREWINDOW_X == 1'b0) && (PREWINDOW_Y_SP == 1'b1) && (SPVRAMACCESSING == 1'b1) &&
                        (TEXT_MODE == 1'b0) &&
                        ((EIGHTDOTSTATE == 3'b000) || (EIGHTDOTSTATE == 3'b001) || (EIGHTDOTSTATE == 3'b010) ||
                        (EIGHTDOTSTATE == 3'b011) || (EIGHTDOTSTATE == 3'b100) || (EIGHTDOTSTATE == 3'b101))) begin
                // FOR SPRITE PREPARING
                VRAMACCESSSWITCH = VRAM_ACCESS_SPRT;
            end else if (VDPVRAMWRREQ != VDPVRAMWRACK) begin
                // VRAM WRITE REQUEST BY CPU
                VRAMACCESSSWITCH = VRAM_ACCESS_CPUW;
            end else if (VDPVRAMRDREQ != VDPVRAMRDACK) begin
                // VRAM READ REQUEST BY CPU
                VRAMACCESSSWITCH = VRAM_ACCESS_CPUR;
            // ELSIF( EIGHTDOTSTATE="111" )THEN
            end else begin
                // VDP COMMAND
                if (VDP_COMMAND_ACTIVE == 1'b1) begin
                    if (VDPCMDVRAMWRREQ != VDPCMDVRAMWRACK) begin
                        VRAMACCESSSWITCH = VRAM_ACCESS_VDPW;
                    end else if (VDPCMDVRAMRDREQ != VDPCMDVRAMRDACK) begin
                        VRAMACCESSSWITCH = VRAM_ACCESS_VDPR;
                    end else begin
                        VRAMACCESSSWITCH = VRAM_ACCESS_VDPS;
                    end
                end else begin
                    VRAMACCESSSWITCH = VRAM_ACCESS_VDPS;
                end
            end
        end else begin
            VRAMACCESSSWITCH = VRAM_ACCESS_DRAW;
        end

        // a real command access (uses a token of vdp_access_slots)
        VDP_CMD_XFER <= (VRAMACCESSSWITCH == VRAM_ACCESS_VDPW) || (VRAMACCESSSWITCH == VRAM_ACCESS_VDPR);

        //-----------------------------------------
        // VRAM ACCESS ADDRESS SWITCH
        //-----------------------------------------
        if (VRAMACCESSSWITCH == VRAM_ACCESS_CPUW) begin
            // VRAM WRITE BY CPU
            // JP: GRAPHIC6,7ではVRAM上のアドレスと RAM上のアドレスの関係が
            // JP: 他の画面モードと異るので注意
            if ((VDPMODEGRAPHIC6 == 1'b1) || (VDPMODEGRAPHIC7 == 1'b1)) begin
                IRAMADR <= {VDPVRAMACCESSADDR[0], VDPVRAMACCESSADDR[16:1]};
            end else begin
                IRAMADR <= VDPVRAMACCESSADDR;
            end
            if ((VDPMODETEXT1 == 1'b1) || (VDPMODETEXT1Q == 1'b1) || (VDPMODEMULTI == 1'b1) || (VDPMODEMULTIQ == 1'b1) ||
                (VDPMODEGRAPHIC1 == 1'b1) || (VDPMODEGRAPHIC2 == 1'b1)) begin
                VDPVRAMACCESSADDR[13:0] <= VDPVRAMACCESSADDR[13:0] + 1'b1;
            end else begin
                VDPVRAMACCESSADDR <= VDPVRAMACCESSADDR + 1'b1;
            end
            PRAMDBO <= VDPVRAMACCESSDATA;
            PRAMOE_N <= 1'b1;
            PRAMWE_N <= 1'b0;
            VDPVRAMWRACK <= ~VDPVRAMWRACK;
        end else if (VRAMACCESSSWITCH == VRAM_ACCESS_CPUR) begin
            // VRAM READ BY CPU
            if (VDPVRAMADDRSETREQ != VDPVRAMADDRSETACK) begin
                VDPVRAMACCESSADDRV = VDPVRAMACCESSADDRTMP;
                // CLEAR VRAM ADDRESS SET REQUEST SIGNAL
                VDPVRAMADDRSETACK <= ~VDPVRAMADDRSETACK;
            end else begin
                VDPVRAMACCESSADDRV = VDPVRAMACCESSADDR;
            end

            // JP: GRAPHIC6,7ではVRAM上のアドレスと RAM上のアドレスの関係が
            // JP: 他の画面モードと異るので注意
            if ((VDPMODEGRAPHIC6 == 1'b1) || (VDPMODEGRAPHIC7 == 1'b1)) begin
                IRAMADR <= {VDPVRAMACCESSADDRV[0], VDPVRAMACCESSADDRV[16:1]};
            end else begin
                IRAMADR <= VDPVRAMACCESSADDRV;
            end
            if ((VDPMODETEXT1 == 1'b1) || (VDPMODETEXT1Q == 1'b1) || (VDPMODEMULTI == 1'b1) || (VDPMODEMULTIQ == 1'b1) ||
                (VDPMODEGRAPHIC1 == 1'b1) || (VDPMODEGRAPHIC2 == 1'b1)) begin
                VDPVRAMACCESSADDR[13:0] <= VDPVRAMACCESSADDRV[13:0] + 1'b1;
            end else begin
                VDPVRAMACCESSADDR <= VDPVRAMACCESSADDRV + 1'b1;
            end
            PRAMDBO <= '0;  // (OTHERS => '0')
            PRAMOE_N <= 1'b0;
            PRAMWE_N <= 1'b1;
            VDPVRAMRDACK <= ~VDPVRAMRDACK;
            VDPVRAMREADINGR <= ~VDPVRAMREADINGA;
        end else if (VRAMACCESSSWITCH == VRAM_ACCESS_VDPW) begin
            // VRAM WRITE BY VDP COMMAND
            // VDP COMMAND WRITE VRAM.
            // JP: GRAPHIC6,7ではアドレスと RAM上の位置が他の画面モードと
            // JP: 異るので注意
            if ((VDPMODEGRAPHIC6 == 1'b1) || (VDPMODEGRAPHIC7 == 1'b1)) begin
                IRAMADR <= {VDPCMDVRAMACCESSADDR[0], VDPCMDVRAMACCESSADDR[16:1]};
            end else begin
                IRAMADR <= VDPCMDVRAMACCESSADDR;
            end
            PRAMDBO <= VDPCMDVRAMWRDATA;
            PRAMOE_N <= 1'b1;
            PRAMWE_N <= 1'b0;
            VDPCMDVRAMWRACK <= ~VDPCMDVRAMWRACK;
        end else if (VRAMACCESSSWITCH == VRAM_ACCESS_VDPR) begin
            // VRAM READ BY VDP COMMAND
            // JP: GRAPHIC6,7ではアドレスと RAM上の位置が他の画面モードと
            // JP: 異るので注意
            if ((VDPMODEGRAPHIC6 == 1'b1) || (VDPMODEGRAPHIC7 == 1'b1)) begin
                IRAMADR <= {VDPCMDVRAMACCESSADDR[0], VDPCMDVRAMACCESSADDR[16:1]};
            end else begin
                IRAMADR <= VDPCMDVRAMACCESSADDR;
            end
            PRAMDBO <= '0;  // (OTHERS => '0')
            PRAMOE_N <= 1'b0;
            PRAMWE_N <= 1'b1;
            VDPCMDVRAMREADINGR <= ~VDPCMDVRAMREADINGA;
        end else if (VRAMACCESSSWITCH == VRAM_ACCESS_SPRT) begin
            // VRAM READ BY SPRITE MODULE
            IRAMADR <= PRAMADRSPRITE;
            PRAMOE_N <= 1'b0;
            PRAMWE_N <= 1'b1;
            PRAMDBO <= '0;  // (OTHERS => '0')
        end else begin
            // VRAM_ACCESS_DRAW
            // VRAM READ FOR SCREEN IMAGE BUILDING
            case (DOTSTATE)
                2'b10: begin
                    PRAMDBO <= '0;  // (OTHERS => '0')
                    PRAMOE_N <= 1'b0;
                    PRAMWE_N <= 1'b1;
                    if (TEXT_MODE == 1'b1) begin
                        IRAMADR <= PRAMADRT12;
                    end else if ((VDPMODEGRAPHIC1 == 1'b1) || (VDPMODEGRAPHIC2 == 1'b1) || (VDPMODEGRAPHIC3 == 1'b1) ||
                                (VDPMODEMULTI == 1'b1) || (VDPMODEMULTIQ == 1'b1)) begin
                        IRAMADR <= PRAMADRG123M;
                    end else if ((VDPMODEGRAPHIC4 == 1'b1) || (VDPMODEGRAPHIC5 == 1'b1) || (VDPMODEGRAPHIC6 == 1'b1) ||
                                (VDPMODEGRAPHIC7 == 1'b1)) begin
                        IRAMADR <= PRAMADRG4567;
                    end
                end
                2'b01: begin
                    PRAMDBO <= '0;  // (OTHERS => '0')
                    PRAMOE_N <= 1'b0;
                    PRAMWE_N <= 1'b1;
                    if ((VDPMODEGRAPHIC6 == 1'b1) || (VDPMODEGRAPHIC7 == 1'b1)) begin
                        IRAMADR <= PRAMADRG4567;
                    end
                end
                default: ;
            endcase

            if ((DOTSTATE == 2'b11) && (VDPVRAMADDRSETREQ != VDPVRAMADDRSETACK)) begin
                VDPVRAMACCESSADDR <= VDPVRAMACCESSADDRTMP;
                VDPVRAMADDRSETACK <= ~VDPVRAMADDRSETACK;
            end
        end
    end
end

//---------------------------------------------------------------------
// COLOR DECODING
//---------------------------------------------------------------------

VDP_COLORDEC U_VDP_COLORDEC (
    .RESET              (RESET),
    .CLK21M             (CLK21M),

    .DOTSTATE           (DOTSTATE),

    .PPALETTEADDR_OUT   (PALETTEADDR_OUT),
    .PALETTEDATARGB_OUT (PALETTEDATARGB_OUT),
    .VDPMODETEXT1       (VDPMODETEXT1),
    .VDPMODETEXT1Q      (VDPMODETEXT1Q),
    .VDPMODETEXT2       (VDPMODETEXT2),
    .VDPMODEMULTI       (VDPMODEMULTI),
    .VDPMODEMULTIQ      (VDPMODEMULTIQ),
    .VDPMODEGRAPHIC1    (VDPMODEGRAPHIC1),
    .VDPMODEGRAPHIC2    (VDPMODEGRAPHIC2),
    .VDPMODEGRAPHIC3    (VDPMODEGRAPHIC3),
    .VDPMODEGRAPHIC4    (VDPMODEGRAPHIC4),
    .VDPMODEGRAPHIC5    (VDPMODEGRAPHIC5),
    .VDPMODEGRAPHIC6    (VDPMODEGRAPHIC6),
    .VDPMODEGRAPHIC7    (VDPMODEGRAPHIC7),

    .WINDOW             (WINDOW),
    .SPRITECOLOROUT     (SPRITECOLOROUT),
    .COLORCODET12       (COLORCODET12),
    .COLORCODEG123M     (COLORCODEG123M),
    .COLORCODEG4567     (COLORCODEG4567),
    .COLORCODESPRITE    (COLORCODESPRITE),
    .P_YJK_R            (YJK_R),
    .P_YJK_G            (YJK_G),
    .P_YJK_B            (YJK_B),
    .P_YJK_EN           (YJK_EN),

    .PVIDEOR_VDP        (IVIDEOR_VDP),
    .PVIDEOG_VDP        (IVIDEOG_VDP),
    .PVIDEOB_VDP        (IVIDEOB_VDP),

    .REG_R1_DISP_ON     (REG_R1_DISP_ON),
    .REG_R7_FRAME_COL   (REG_R7_FRAME_COL),
    .REG_R8_COL0_ON     (REG_R8_COL0_ON),
    .REG_R25_YJK        (REG_R25_YJK)
);

//---------------------------------------------------------------------------
// MAKE COLOR CODE
//---------------------------------------------------------------------------

VDP_TEXT12 U_VDP_TEXT12 (
    .CLK21M             (CLK21M),
    .RESET              (RESET),
    .DOTSTATE           (DOTSTATE),
    .DOTCOUNTERX        (PREDOTCOUNTER_X),
    .DOTCOUNTERY        (PREDOTCOUNTER_Y),         // 2021/July/1st Modified by t.hara
    .DOTCOUNTERYP       (PREDOTCOUNTER_YP),
    .VDPMODETEXT1       (VDPMODETEXT1),
    .VDPMODETEXT1Q      (VDPMODETEXT1Q),
    .VDPMODETEXT2       (VDPMODETEXT2),
    .REG_R1_BL_CLKS     (REG_R1_BL_CLKS),
    .REG_R7_FRAME_COL   (REG_R7_FRAME_COL),
    .REG_R12_BLINK_MODE (REG_R12_BLINK_MODE),
    .REG_R13_BLINK_PERIOD (REG_R13_BLINK_PERIOD),
    .REG_R2_PT_NAM_ADDR (REG_R2_PT_NAM_ADDR),
    .REG_R4_PT_GEN_ADDR (REG_R4_PT_GEN_ADDR),
    .REG_R10R3_COL_ADDR (REG_R10R3_COL_ADDR),
    .PRAMDAT            (PRAMDAT),
    .PRAMADR            (PRAMADRT12),
    .TXVRAMREADEN       (TXVRAMREADEN),
    .PCOLORCODE         (COLORCODET12)
);

VDP_GRAPHIC123M U_VDP_GRAPHIC123M (
    .CLK21M             (CLK21M),
    .RESET              (RESET),
    .DOTSTATE           (DOTSTATE),
    .EIGHTDOTSTATE      (EIGHTDOTSTATE),
    .DOTCOUNTERX        (PREDOTCOUNTER_X),
    .DOTCOUNTERY        (PREDOTCOUNTER_Y),
    .VDPMODEMULTI       (VDPMODEMULTI),
    .VDPMODEMULTIQ      (VDPMODEMULTIQ),
    .VDPMODEGRAPHIC1    (VDPMODEGRAPHIC1),
    .VDPMODEGRAPHIC2    (VDPMODEGRAPHIC2),
    .VDPMODEGRAPHIC3    (VDPMODEGRAPHIC3),
    .REG_R2_PT_NAM_ADDR (REG_R2_PT_NAM_ADDR),
    .REG_R4_PT_GEN_ADDR (REG_R4_PT_GEN_ADDR),
    .REG_R10R3_COL_ADDR (REG_R10R3_COL_ADDR),
    .REG_R26_H_SCROLL   (REG_R26_H_SCROLL),
    .REG_R27_H_SCROLL   (REG_R27_H_SCROLL),
    .PRAMDAT            (PRAMDAT),
    .PRAMADR            (PRAMADRG123M),
    .PCOLORCODE         (COLORCODEG123M)
);

VDP_GRAPHIC4567 U_VDP_GRAPHIC4567 (
    .CLK21M             (CLK21M),
    .RESET              (RESET),
    .DOTSTATE           (DOTSTATE),
    .EIGHTDOTSTATE      (EIGHTDOTSTATE),
    .DOTCOUNTERX        (PREDOTCOUNTER_X),
    .DOTCOUNTERY        (PREDOTCOUNTER_Y),
    .VDPMODEGRAPHIC4    (VDPMODEGRAPHIC4),
    .VDPMODEGRAPHIC5    (VDPMODEGRAPHIC5),
    .VDPMODEGRAPHIC6    (VDPMODEGRAPHIC6),
    .VDPMODEGRAPHIC7    (VDPMODEGRAPHIC7),
    .REG_R1_BL_CLKS     (REG_R1_BL_CLKS),
    .REG_R2_PT_NAM_ADDR (REG_R2_PT_NAM_ADDR),
    .REG_R13_BLINK_PERIOD (REG_R13_BLINK_PERIOD),
    .REG_R26_H_SCROLL   (REG_R26_H_SCROLL),
    .REG_R27_H_SCROLL   (REG_R27_H_SCROLL),
    .REG_R25_YAE        (REG_R25_YAE),
    .REG_R25_YJK        (REG_R25_YJK),
    .REG_R25_SP2        (REG_R25_SP2),
    .PRAMDAT            (PRAMDAT),
    .PRAMDATPAIR        (PRAMDATPAIR),
    .PRAMADR            (PRAMADRG4567),
    .PCOLORCODE         (COLORCODEG4567),
    .P_YJK_R            (YJK_R),
    .P_YJK_G            (YJK_G),
    .P_YJK_B            (YJK_B),
    .P_YJK_EN           (YJK_EN)
);

//---------------------------------------------------------------------------
// SPRITE MODULE
//---------------------------------------------------------------------------

VDP_SPRITE U_SPRITE (
    .CLK21M                     (CLK21M),
    .RESET                      (RESET),
    .DOTSTATE                   (DOTSTATE),
    .EIGHTDOTSTATE              (EIGHTDOTSTATE),
    .DOTCOUNTERX                (PREDOTCOUNTER_X),
    .DOTCOUNTERYP               (PREDOTCOUNTER_YP),
    .BWINDOW_Y                  (PREWINDOW_Y_SP),   // same Y window as the VRAM arbiter
    .PVDPS0SPCOLLISIONINCIDENCE (VDPS0SPCOLLISIONINCIDENCE),
    .PVDPS0SPOVERMAPPED         (VDPS0SPOVERMAPPED),
    .PVDPS0SPOVERMAPPEDNUM      (VDPS0SPOVERMAPPEDNUM),
    .PVDPS3S4SPCOLLISIONX       (VDPS3S4SPCOLLISIONX),
    .PVDPS5S6SPCOLLISIONY       (VDPS5S6SPCOLLISIONY),
    .PVDPS0RESETREQ             (SPVDPS0RESETREQ),
    .PVDPS0RESETACK             (SPVDPS0RESETACK),
    .PVDPS5RESETREQ             (SPVDPS5RESETREQ),
    .PVDPS5RESETACK             (SPVDPS5RESETACK),
    .REG_R1_SP_SIZE             (REG_R1_SP_SIZE),
    .REG_R1_SP_ZOOM             (REG_R1_SP_ZOOM),
    .REG_R11R5_SP_ATR_ADDR      (REG_R11R5_SP_ATR_ADDR),
    .REG_R6_SP_GEN_ADDR         (REG_R6_SP_GEN_ADDR),
    .REG_R8_COL0_ON             (REG_R8_COL0_ON),
    .REG_R8_SP_OFF              (REG_R8_SP_OFF),
    .REG_R23_VSTART_LINE        (REG_R23_VSTART_LINE),
    .REG_R27_H_SCROLL           (REG_R27_H_SCROLL),
    .SPMODE2                    (SPMODE2),
    .VRAMINTERLEAVEMODE         (VDPMODEISVRAMINTERLEAVE),
    .SPVRAMACCESSING            (SPVRAMACCESSING),
    .PRAMDAT                    (PRAMDAT),
    .PRAMADR                    (PRAMADRSPRITE),
    .SPCOLOROUT                 (SPRITECOLOROUT),
    .SPCOLORCODE                (COLORCODESPRITE),
    .REG_R9_Y_DOTS              (REG_R9_Y_DOTS)
);

//---------------------------------------------------------------------------
// VDP REGISTER ACCESS
//---------------------------------------------------------------------------

VDP_REGISTER U_VDP_REGISTER (
    .RESET                  (RESET),
    .CLK21M                 (CLK21M),

    .REQ                    (REQ),
    .ACK                    (ACK),
    .WRT                    (WRT),
    .ADR                    (ADR),
    .DBI                    (DBI),
    .DBO                    (DBO),

    .DOTSTATE               (DOTSTATE),

    .VDPCMDTRCLRACK         (VDPCMDTRCLRACK),
    .VDPCMDREGWRACK         (VDPCMDREGWRACK),
    .HSYNC                  (HSYNC),

    .VDPS0SPCOLLISIONINCIDENCE (VDPS0SPCOLLISIONINCIDENCE),
    .VDPS0SPOVERMAPPED      (VDPS0SPOVERMAPPED),
    .VDPS0SPOVERMAPPEDNUM   (VDPS0SPOVERMAPPEDNUM),
    .SPVDPS0RESETREQ        (SPVDPS0RESETREQ),
    .SPVDPS0RESETACK        (SPVDPS0RESETACK),
    .SPVDPS5RESETREQ        (SPVDPS5RESETREQ),
    .SPVDPS5RESETACK        (SPVDPS5RESETACK),

    .VDPCMDTR               (VDPCMDTR),
    .VD                     (VD),
    .HD                     (HD),
    .VDPCMDBD               (VDPCMDBD),
    .FIELD                  (FIELD),
    .VDPCMDCE               (VDPCMDCE),
    .VDPS3S4SPCOLLISIONX    (VDPS3S4SPCOLLISIONX),
    .VDPS5S6SPCOLLISIONY    (VDPS5S6SPCOLLISIONY),
    .VDPCMDCLR              (VDPCMDCLR),
    .VDPCMDSXTMP            (VDPCMDSXTMP),

    .VDPVRAMACCESSDATA      (VDPVRAMACCESSDATA),
    .VDPVRAMACCESSADDRTMP   (VDPVRAMACCESSADDRTMP),
    .VDPVRAMADDRSETREQ      (VDPVRAMADDRSETREQ),
    .VDPVRAMADDRSETACK      (VDPVRAMADDRSETACK),
    .VDPVRAMWRREQ           (VDPVRAMWRREQ),
    .VDPVRAMWRACK           (VDPVRAMWRACK),
    .VDPVRAMRDDATA          (VDPVRAMRDDATA),
    .VDPVRAMRDREQ           (VDPVRAMRDREQ),
    .VDPVRAMRDACK           (VDPVRAMRDACK),

    .VDPCMDREGNUM           (VDPCMDREGNUM),
    .VDPCMDREGDATA          (VDPCMDREGDATA),
    .VDPCMDREGWRREQ         (VDPCMDREGWRREQ),
    .VDPCMDTRCLRREQ         (VDPCMDTRCLRREQ),

    .PALETTEADDR_OUT        (PALETTEADDR_OUT),

    .PALETTEDATARGB_OUT     (PALETTEDATARGB_OUT),
    .CLR_VSYNC_INT          (CLR_VSYNC_INT),
    .CLR_HSYNC_INT          (CLR_HSYNC_INT),
    .REQ_VSYNC_INT_N        (REQ_VSYNC_INT_N),
    .REQ_HSYNC_INT_N        (REQ_HSYNC_S1_N),

    .REG_R0_HSYNC_INT_EN    (REG_R0_HSYNC_INT_EN),
    .REG_R1_SP_SIZE         (REG_R1_SP_SIZE),
    .REG_R1_SP_ZOOM         (REG_R1_SP_ZOOM),
    .REG_R1_BL_CLKS         (REG_R1_BL_CLKS),
    .REG_R1_VSYNC_INT_EN    (REG_R1_VSYNC_INT_EN),
    .REG_R1_DISP_ON         (REG_R1_DISP_ON),
    .REG_R2_PT_NAM_ADDR     (REG_R2_PT_NAM_ADDR),
    .REG_R4_PT_GEN_ADDR     (REG_R4_PT_GEN_ADDR),
    .REG_R10R3_COL_ADDR     (REG_R10R3_COL_ADDR),
    .REG_R11R5_SP_ATR_ADDR  (REG_R11R5_SP_ATR_ADDR),
    .REG_R6_SP_GEN_ADDR     (REG_R6_SP_GEN_ADDR),
    .REG_R7_FRAME_COL       (REG_R7_FRAME_COL),
    .REG_R8_SP_OFF          (REG_R8_SP_OFF),
    .REG_R8_COL0_ON         (REG_R8_COL0_ON),
    .REG_R9_PAL_MODE        (REG_R9_PAL_MODE),
    .REG_R9_INTERLACE_MODE  (REG_R9_INTERLACE_MODE),
    .REG_R9_Y_DOTS          (REG_R9_Y_DOTS),
    .REG_R12_BLINK_MODE     (REG_R12_BLINK_MODE),
    .REG_R13_BLINK_PERIOD   (REG_R13_BLINK_PERIOD),
    .REG_R18_ADJ            (REG_R18_ADJ),
    .REG_R19_HSYNC_INT_LINE (REG_R19_HSYNC_INT_LINE),
    .REG_R23_VSTART_LINE    (REG_R23_VSTART_LINE),
    .REG_R25_CMD            (REG_R25_CMD),
    .REG_R25_YAE            (REG_R25_YAE),
    .REG_R25_YJK            (REG_R25_YJK),
    .REG_R25_MSK            (REG_R25_MSK),
    .REG_R25_SP2            (REG_R25_SP2),
    .REG_R26_H_SCROLL       (REG_R26_H_SCROLL),
    .REG_R27_H_SCROLL       (REG_R27_H_SCROLL),

    .VDPMODETEXT1           (VDPMODETEXT1),
    .VDPMODETEXT1Q          (VDPMODETEXT1Q),
    .VDPMODETEXT2           (VDPMODETEXT2),
    .VDPMODEMULTI           (VDPMODEMULTI),
    .VDPMODEMULTIQ          (VDPMODEMULTIQ),
    .VDPMODEGRAPHIC1        (VDPMODEGRAPHIC1),
    .VDPMODEGRAPHIC2        (VDPMODEGRAPHIC2),
    .VDPMODEGRAPHIC3        (VDPMODEGRAPHIC3),
    .VDPMODEGRAPHIC4        (VDPMODEGRAPHIC4),
    .VDPMODEGRAPHIC5        (VDPMODEGRAPHIC5),
    .VDPMODEGRAPHIC6        (VDPMODEGRAPHIC6),
    .VDPMODEGRAPHIC7        (VDPMODEGRAPHIC7),
    .VDPMODEISHIGHRES       (VDPMODEISHIGHRES),
    .SPMODE2                (SPMODE2),
    .VDPMODEISVRAMINTERLEAVE (VDPMODEISVRAMINTERLEAVE),

    .FORCED_V_MODE          (FORCED_V_MODE),
    .VDP_ID                 (VDP_ID)
);

//---------------------------------------------------------------------------
// VDP COMMAND
//---------------------------------------------------------------------------

VDP_COMMAND U_VDP_COMMAND (
    .RESET               (RESET),
    .CLK21M              (CLK21M),
    .VDPMODEGRAPHIC4     (VDPMODEGRAPHIC4),
    .VDPMODEGRAPHIC5     (VDPMODEGRAPHIC5),
    .VDPMODEGRAPHIC6     (VDPMODEGRAPHIC6),
    .VDPMODEGRAPHIC7     (VDPMODEGRAPHIC7),
    .VDPMODEISHIGHRES    (VDPMODEISHIGHRES),
    .VRAMWRACK           (VDPCMDVRAMWRACK),
    .VRAMRDACK           (VDPCMDVRAMRDACK),
    .VRAMREADINGR        (VDPCMDVRAMREADINGR),
    .VRAMREADINGA        (VDPCMDVRAMREADINGA),
    .VRAMRDDATA          (VDPCMDVRAMRDDATA),
    .REGWRREQ            (VDPCMDREGWRREQ),
    .TRCLRREQ            (VDPCMDTRCLRREQ),
    .REGNUM              (VDPCMDREGNUM),
    .REGDATA             (VDPCMDREGDATA),
    .PREGWRACK           (VDPCMDREGWRACK),
    .PTRCLRACK           (VDPCMDTRCLRACK),
    .PVRAMWRREQ          (VDPCMDVRAMWRREQ),
    .PVRAMRDREQ          (VDPCMDVRAMRDREQ),
    .PVRAMACCESSADDR     (VDPCMDVRAMACCESSADDR),
    .PVRAMWRDATA         (VDPCMDVRAMWRDATA),
    .PCLR                (VDPCMDCLR),
    .PCE                 (VDPCMDCE),
    .PBD                 (VDPCMDBD),
    .PTR                 (VDPCMDTR),
    .PSXTMP              (VDPCMDSXTMP),
    .CUR_VDP_COMMAND     (CUR_VDP_COMMAND),
    .PROWSTEP            (VDPCMDROWSTEP),
    .PMINORSTEP          (VDPCMDMINORSTEP),
    .REG_R25_CMD         (REG_R25_CMD)
);

// Command engine VRAM access timing as openMSX (vdp_access_slots.sv)
VDP_ACCESS_SLOTS U_VDP_ACCESS_SLOTS (
    .RESET               (RESET),
    .CLK21M              (CLK21M),

    .H_CNT               (H_CNT),
    .DISP_LINE           (PREWINDOW_Y & REG_R1_DISP_ON),
    .SPRITES             (~REG_R8_SP_OFF),
    .BITMAP              (VDPMODEGRAPHIC4 | VDPMODEGRAPHIC5 | VDPMODEGRAPHIC6 | VDPMODEGRAPHIC7),
    .TEXT                (TEXT_MODE),

    .VDP_COMMAND         (CUR_VDP_COMMAND),
    .CE                  (VDPCMDCE),
    .XFER                (VDP_CMD_XFER),
    .ROWSTEP             (VDPCMDROWSTEP),
    .MINORSTEP           (VDPCMDMINORSTEP),

    .VDPSPEEDMODE        (VDPSPEEDMODE),
    .ACTIVE              (VDP_COMMAND_ACTIVE)
);

endmodule
