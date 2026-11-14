//
//  vdp_sprite.vhd
//    Sprite module.
//
//  Copyright (C) 2004-2006 Kunihiko Ohnaka
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
//---------------------------------------------------------------------------
// Memo
//   Japanese comment lines are starts with "JP:".
//   JP: 日本語のコメント行は JP:を頭に付ける事にする
//
//---------------------------------------------------------------------------
// Revision History
//
// 29th,October,2006 modified by Kunihiko Ohnaka
//   - Insert the license text.
//   - Add the document part below.
//
// 26th,August,2006 modified by Kunihiko Ohnaka
//   - latch the base addresses every eight dot cycle
//     (DRAM RAS/CAS access emulation)
//
// 20th,August,2006 modified by Kunihiko Ohnaka
//   - Change the drawing algorithm.
//   - Add sprite collision checking function.
//   - Add sprite over-mapped checking function.
//   - Many bugs are fixed, and it works fine.
//   - (first release virsion)
//
// 17th,August,2004 created by Kunihiko Ohnaka
//   - Start new sprite module implementing.
//     * This module uses Block RAMs so that shrink the
//       circuit size.
//     * Separate sprite module from vdp.vhd.
//
//---------------------------------------------------------------------------
// Document
//
// JP: この実装ではBLOCKRAMを使い、消費するSLICEを節約するのが狙い。
// JP: この実装を使わない状態での vdp.vhdをコンパイルした時の
// JP: SLICE使用数は1900前後。
// JP: 2006/8/16。このスプライトを使わない最新版(Cyclone)では、
// JP:            2726LCだった.
// JP: 2006/8/19。このスプライトを使ったところ、2278LCまで減少。
// JP:
// JP: [用語]
// JP: ・ローカルプレーン番号
// JP:   あるライン上に並んでいるスプライト(プレーン)だけを抜き出して
// JP:   スプライトプレーン番号順に並べた時の順位。
// JP:   例えばあるラインにスプライトプレーン#1,#4,#5が存在する場合、
// JP:   それぞれのスプライトのローカルプレーン番号は#0,#1,#2となる。
// JP:   スプライトモード2でも横一列に最大8枚しか並ばないので、
// JP:   ローカルプレーン番号は最大で#7となる。
// JP:
// JP: ・画面描画帯域
// JP:    VDPの実機は8ドット(32クロック)で連続アドレス上のデータ4バイト
// JP:    (GRAPHIC6,7ではRAMのインターリーブアクセスによりバイト)
// JP:    のリードに加え、ランダムアドレスへの2サイクル(2バイト)の
// JP:    アクセスが加納
// JP:    それらのDRAMアクセスサイクルに以下のように名前を付ける。
// JP:     * 画面描画リードサイクル
// JP:     * スプライトY座標検査サイクル
// JP:     * ランダムアクセスサイクル
// JP:
// JP: ○似非VDPでのVRAMアクセスサイクル
// JP:    似非VDPでは旧式のDRAMではなくより高速なメモリを使用している。
// JP:    そのため、４クロックに1回確実にランダムアクセスを実行できる
// JP:    メモリを持っている事を前提としてコーディングします。
// JP:    また、Cyclone版似非MSXでは、16ビット幅のSDRAMを用いている
// JP:    ため、一回のアクセスで連続する16ビットのデータを読む事も可能
// JP:    です。
// JP:    似非VDPでは、D0～D7の下位8ビットをVRAMの前半64Kバイト、
// JP:    D8～D15の上位8ビットを後半64Kバイトにマッピングしています。
// JP:    このような変則的な割り当てをするのは、実機のVDPのメモリ
// JP:    マップをまねるためです。実際、4クロックで2バイトのメモリを
// JP:    読み出す帯域が必要になるのはGRAPHIC6,7のモードだけです。
// JP:    実機のVDPは、GRAPHIC6,7ではメモリのインターリーブを用い、
// JP:    (GRAPHIC7における)偶数ドットをVRAMの前半64Kバイトに
// JP:    わりあて、奇数ドットを後半64Kバイトに割り当てています。
// JP:    そのため、似非VDPでも前半64Kと後半64Kの同一アドレス上の
// JP:    データを１サイクル(4クロック)で読み出せる必要があるので
// JP:    このようなマッピングになっています。
// JP:    単純に言えば、SDRAMの16ビットアクセスを、実機のDRAMの
// JP:    インターリーブアクセスに見立てているということです。
// JP:
// JP:    いろいろな現象から、VDPの内部は8ドットサイクルで動いていると
// JP:    推測されています。8ドット、つまり32クロックのどうさをメモリ
// JP:    の帯域から推測すると、以下のようになります。
// JP:
// JP:     ドット ：<=0=><=1=><=2=><=3=><=4=><=5=><=6=><=7=>
// JP:   通常アクセス： A0   A1   A2   A3   A4  (A5)  A6  (A7)
// JP: インターリーブ： B0   B1   B2   B3
// JP:
// JP:    - 描画中
// JP:     ・A0～A3 (B0～B3)
// JP:        画面描画のために使用。B0～B3はインターリーブで同時に
// JP:        読み出せるデータで、GRAPHIC6,7でしか使わない。
// JP:     ・A4     スプライトY座標検査
// JP:     ・A6     VRAM R/W or VDPコマンド (2回に一回ずつ、交互に割り当てる)
// JP:
// JP:     - 非描画中(スプライト準備中)
// JP:      ・A0     スプライトX座標リード
// JP:      ・A1     スプライトパターン番号リード
// JP:      ・A2     スプライトパターン左リード
// JP:      ・A3     スプライトパターン右リード
// JP:      ・A4     スプライトカラーリード
// JP:      ・A6     VRAM R/W or VDPコマンド (2回に一回ずつ、交互に割り当てる)
// JP:
// JP:   A5とA7のスロットは実際には使用することもできるのですが、
// JP:   これを使ってしまうと実機よりも帯域が増えてしまうので、
// JP:   あえて使わずに残しています。
// JP:   また、非描画中のサイクルは、実機とは異なります。実機では
// JP:   64クロックで 2つのスプライトをまとめて処理する事で、DRAMの
// JP:   ページモードサイクルを有効利用できるようにしています。
// JP:   また、その64クロックの中にはVRAMやVDPコマンドに割くための
// JP:   スロットが無いので、64クロックサイクルの隙間にVRAMアク
// JP:   セスのための隙間を空けているのかもしれません。（未確認）
// JP:   似非VDPでもその動作を完全に真似する事は可能ですが、
// JP:   ソースが必要以上に複雑に見えてしまうのと、2のn乗サイクル
// JP:   からずれてしまうのがちょっぴり嫌だったので、上記のような
// JP:   きれいなサイクルにしています。
// JP:   どうしても実機と同じタイミングにしたいという方は
// JP:   チャレンジしてみてください。
// JP:
//
//
// Line pipeline (MSX2 core): as the V9938, the sprites of display line L are prepared on
// line L - 1. During the display period of line L - 1 the Y attributes are tested (sprite n
// in its 8-dot slot n) and in the border after it the attributes and patterns of the listed
// sprites are fetched (8 dots per sprite, X 264..327) and drawn into the line buffer, plane
// k while plane k + 1 is fetched, one pixel per clock. The draw ends 7 dots before the
// buffers swap at X 0 of line L, where the other buffer is read out and cleared.
// The ESE original drew the buffer during the whole display period of line L - 1 and had
// to test the Y attributes a line earlier (L - 2): a SAT write on line L - 2 came too late.

module VDP_SPRITE (
    input logic CLK21M,
    input logic RESET,

    input logic [1:0] DOTSTATE,
    input logic [2:0] EIGHTDOTSTATE,

    input logic [8:0] DOTCOUNTERX,
    input logic [8:0] DOTCOUNTERYP,
    input logic BWINDOW_Y,

    output logic PVDPS0SPCOLLISIONINCIDENCE,
    output logic PVDPS0SPOVERMAPPED,
    output logic [4:0] PVDPS0SPOVERMAPPEDNUM,
    output logic [8:0] PVDPS3S4SPCOLLISIONX,
    output logic [8:0] PVDPS5S6SPCOLLISIONY,
    input logic PVDPS0RESETREQ,
    output logic PVDPS0RESETACK,
    input logic PVDPS5RESETREQ,
    output logic PVDPS5RESETACK,

    input logic REG_R1_SP_SIZE,
    input logic REG_R1_SP_ZOOM,
    input logic [9:0] REG_R11R5_SP_ATR_ADDR,
    input logic [5:0] REG_R6_SP_GEN_ADDR,
    input logic REG_R8_COL0_ON,
    input logic REG_R8_SP_OFF,
    input logic [7:0] REG_R23_VSTART_LINE,
    input logic [2:0] REG_R27_H_SCROLL,
    input logic SPMODE2,
    input logic VRAMINTERLEAVEMODE,

    output logic SPVRAMACCESSING,

    input logic [7:0] PRAMDAT,
    output logic [16:0] PRAMADR,

    output logic SPCOLOROUT,
    output logic [3:0] SPCOLORCODE,
    input logic REG_R9_Y_DOTS
);
    // Signals declaration
    logic FF_SP_LINE_EN;            // sprites are processed on this line
    logic [8:0] FF_CUR_Y;

    logic FF_VDPS0RESETACK, FF_VDPS5RESETACK;

    // data of the plane just fetched, handed to the draw stage
    logic [8:0] SPINFORAMX_IN;
    logic [15:0] SPINFORAMPATTERN_IN;
    logic [3:0] SPINFORAMCOLOR_IN;
    logic SPINFORAMCC_IN;
    logic SPINFORAMIC_IN;

    typedef enum logic [1:0] {SPSTATE_IDLE, SPSTATE_YTEST, SPSTATE_PREPARE} TYPESPSTATE;
    TYPESPSTATE SPSTATE;

    //JP: スプライトプレーン番号×横方向表示枚数の配列
    typedef logic [4:0] SPRENDERPLANESTYPE [7:0];
    SPRENDERPLANESTYPE SPRENDERPLANES;

    logic [16:0] IRAMADR, FF_Y_TEST_VRAM_ADDR, IRAMADRPREPARE;
    logic [9:0] SPATTRTBLBASEADDR;
    logic [5:0] SPPTNGENETBLBASEADDR;
    logic [16:2] SPATTRIB_ADDR;
    logic [16:0] READVRAMADDRCREAD, READVRAMADDRPTREAD;

    // JP: Y座標検査中のプレーン番号
    logic [4:0] FF_Y_TEST_SP_NUM;
    logic [3:0] FF_Y_TEST_LISTUP_ADDR;
    logic FF_Y_TEST_EN;
    // JP: 下書きデータ準備中のローカルプレーン番号
    logic [2:0] SPPREPARELOCALPLANENUM;
    // JP: 下書きデータ準備中のプレーン番号
    logic [4:0] SPPREPAREPLANENUM;
    // JP: 下書きデータ準備中のスプライトのYライン番号(スプライトのどの部分を描画するか)
    logic [3:0] SPPREPARELINENUM;
    logic SPPREPAREXPOS;
    logic [7:0] SPPREPAREPATTERNNUM;
    logic SPPREPAREEND;

    // draw stage: read side (one pixel per clock)
    logic FF_DRAW_BUSY;
    logic [4:0] FF_DRAW_CNT;
    logic [8:0] SPDRAWX;
    logic [15:0] SPDRAWPATTERN;
    logic [3:0] SPDRAWCOLOR;
    logic SPDRAWCC, SPDRAWIC;
    logic FF_SPCC0FOUND;
    logic [2:0] FF_LASTCC0LOCALPLANENUM;
    // draw stage: write side (the clock after the read)
    logic FF_WR_PIX;
    logic [8:0] FF_WR_X;
    logic [3:0] FF_WR_COLOR;
    logic FF_WR_CC, FF_WR_IC, FF_WR_CC0FOUND;
    logic [2:0] FF_WR_LASTCC0;
    logic FF_FWD_HIT;                   // the read of the last clock hit the write of the same clock
    logic [7:0] FF_FWD_DATA;
    logic [7:0] W_DRAW_Q, W_DRAW_WDATA;
    logic W_DRAW_WE, W_DRAW_COLLISION;

    // JP: スプライト描画ラインバッファの制御信号
    logic [7:0] SPLINEBUFRADR_E, SPLINEBUFRADR_O, SPLINEBUFWADR_E, SPLINEBUFWADR_O;
    logic SPLINEBUFWE_E, SPLINEBUFWE_O;
    logic [7:0] SPLINEBUFDATA_IN_E, SPLINEBUFDATA_IN_O;
    logic [7:0] SPLINEBUFDATA_OUT_E, SPLINEBUFDATA_OUT_O;
    logic W_DRAW_E;                     // the even buffer is drawn, the odd one displayed

    logic SPLINEBUFDISPWE;
    logic [7:0] SPLINEBUFDISPX;
    logic [7:0] SPLINEBUFDISPDATA_OUT, SPLINEBUFDRAWDATA_OUT;

    logic SPWINDOWX;

    logic FF_SP_OVERMAP;
    logic [4:0] FF_SP_OVERMAP_NUM;

    logic [7:0] W_SPLISTUPY;
    logic W_TARGET_SP_EN, W_SP_OFF, W_SP_OVERMAP, W_ACTIVE;

    assign PVDPS0RESETACK        = FF_VDPS0RESETACK;
    assign PVDPS5RESETACK        = FF_VDPS5RESETACK;
    assign PVDPS0SPOVERMAPPED    = FF_SP_OVERMAP;
    assign PVDPS0SPOVERMAPPEDNUM = FF_SP_OVERMAP_NUM;

    // SPRITE LINE BUFFERS: during line YP one is read out and cleared for the display, the
    // other is drawn in the border for line YP + 1

    assign W_DRAW_E              = ~DOTCOUNTERYP[0];
    assign SPLINEBUFRADR_E       = W_DRAW_E ? SPDRAWX[7:0]        : SPLINEBUFDISPX;
    assign SPLINEBUFWADR_E       = W_DRAW_E ? FF_WR_X[7:0]        : SPLINEBUFDISPX;
    assign SPLINEBUFDATA_IN_E    = W_DRAW_E ? W_DRAW_WDATA        : '0;
    assign SPLINEBUFWE_E         = W_DRAW_E ? W_DRAW_WE           : SPLINEBUFDISPWE;
    assign SPLINEBUFDISPDATA_OUT = W_DRAW_E ? SPLINEBUFDATA_OUT_O : SPLINEBUFDATA_OUT_E;

    VDP_LINEBUF U_EVEN_LINE_BUF
    (
        .CLK(CLK21M),
        .RADR(SPLINEBUFRADR_E),
        .Q(SPLINEBUFDATA_OUT_E),
        .WE(SPLINEBUFWE_E),
        .WADR(SPLINEBUFWADR_E),
        .D(SPLINEBUFDATA_IN_E)
    );

    assign SPLINEBUFRADR_O       = W_DRAW_E ? SPLINEBUFDISPX      : SPDRAWX[7:0];
    assign SPLINEBUFWADR_O       = W_DRAW_E ? SPLINEBUFDISPX      : FF_WR_X[7:0];
    assign SPLINEBUFDATA_IN_O    = W_DRAW_E ? '0                  : W_DRAW_WDATA;
    assign SPLINEBUFWE_O         = W_DRAW_E ? SPLINEBUFDISPWE     : W_DRAW_WE;
    assign SPLINEBUFDRAWDATA_OUT = W_DRAW_E ? SPLINEBUFDATA_OUT_E : SPLINEBUFDATA_OUT_O;

    VDP_LINEBUF U_ODD_LINE_BUF
    (
        .CLK(CLK21M),
        .RADR(SPLINEBUFRADR_O),
        .Q(SPLINEBUFDATA_OUT_O),
        .WE(SPLINEBUFWE_O),
        .WADR(SPLINEBUFWADR_O),
        .D(SPLINEBUFDATA_IN_O)
    );

    assign SPPREPAREXPOS = EIGHTDOTSTATE == 3'b100;
    // JP: VRAMアクセスアドレスの出力
    assign IRAMADR = SPSTATE == SPSTATE_YTEST ? FF_Y_TEST_VRAM_ADDR : IRAMADRPREPARE;
    assign PRAMADR = VRAMINTERLEAVEMODE ? {IRAMADR[0], IRAMADR[16:1]} : IRAMADR[16:0];

    // State machine
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            SPSTATE <= SPSTATE_IDLE;
        end else if (DOTSTATE == 2'b10) begin
            case (SPSTATE)
                SPSTATE_IDLE: begin
                    if (DOTCOUNTERX == 9'd0)
                        SPSTATE <= SPSTATE_YTEST;
                end
                SPSTATE_YTEST: begin
                    if (DOTCOUNTERX == 9'd264)
                        SPSTATE <= SPSTATE_PREPARE;
                end
                SPSTATE_PREPARE: begin
                    if (SPPREPAREEND)
                        SPSTATE <= SPSTATE_IDLE;
                end
                default: SPSTATE <= SPSTATE_IDLE;
            endcase
        end
    end

    // the line the sprites are tested for: the sprite Y attribute is one less than its
    // first display line, so the display line after this one is compared with YP + R#23
    always_ff @(posedge CLK21M) begin
        if (DOTSTATE == 2'b01 && DOTCOUNTERX == 0) begin
            FF_CUR_Y <= DOTCOUNTERYP + {1'b0, REG_R23_VSTART_LINE};
        end
    end

    // VRAM ADDRESS GENERATOR
    always_ff @(posedge CLK21M) begin
        // LATCHING ADDRESS SIGNALS
        if (DOTSTATE == 2'b01 && DOTCOUNTERX == 0) begin
            SPPTNGENETBLBASEADDR <= REG_R6_SP_GEN_ADDR;
            if (SPMODE2)
                SPATTRTBLBASEADDR <= {REG_R11R5_SP_ATR_ADDR[9:2], 2'b00};
            else
                SPATTRTBLBASEADDR <= REG_R11R5_SP_ATR_ADDR[9:0];
        end
    end

    // VRAM ACCESS MASK
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            SPVRAMACCESSING <= 1'b0;
        end else if (DOTSTATE == 2'b10) begin
            case (SPSTATE)
                SPSTATE_IDLE: begin
                    if (DOTCOUNTERX == 9'd0)
                        SPVRAMACCESSING <= ~REG_R8_SP_OFF & W_ACTIVE;
                end
                SPSTATE_YTEST: begin
                    if (DOTCOUNTERX == 9'd264) //256 + 8
                        SPVRAMACCESSING <= FF_SP_LINE_EN;
                end
                SPSTATE_PREPARE: begin
                    if (SPPREPAREEND)
                        SPVRAMACCESSING <= 1'b0;
                end
                default: ;
            endcase
        end
    end

    // [Y_TEST]Yテスト用の信号
    assign W_SPLISTUPY = FF_CUR_Y[7:0] - PRAMDAT;

    // [Y_TEST]着目スプライトを現ラインに表示するかどうかの信号
    assign W_TARGET_SP_EN = (
        ((W_SPLISTUPY[7:3] == 5'b00000) && (REG_R1_SP_SIZE == 1'b0) && (REG_R1_SP_ZOOM == 1'b0)) ||
        ((W_SPLISTUPY[7:4] == 4'b0000) && (REG_R1_SP_SIZE == 1'b1) && (REG_R1_SP_ZOOM == 1'b0)) ||
        ((W_SPLISTUPY[7:4] == 4'b0000) && (REG_R1_SP_SIZE == 1'b0) && (REG_R1_SP_ZOOM == 1'b1)) ||
        ((W_SPLISTUPY[7:5] == 3'b000)  && (REG_R1_SP_SIZE == 1'b1) && (REG_R1_SP_ZOOM == 1'b1))
        ) ? 1'b1 : 1'b0;

    // [Y_TEST]これ以降のスプライトは表示禁止かどうかの信号
    assign W_SP_OFF = PRAMDAT == {4'b1101, SPMODE2, 3'b000};

    // Y_TEST]４つ（８つ）のスプライトが並んでいるかどうかの信号
    assign W_SP_OVERMAP = (FF_Y_TEST_LISTUP_ADDR[2] == 1'b1 && SPMODE2 == 1'b0) || FF_Y_TEST_LISTUP_ADDR[3];

    // [Y_TEST]表示中のラインか否か
    // Only lines whose Y-test target (YP + 1) is a display line, YP = -1..191 / -1..211, as
    // openMSX (the last border line and the display lines, the line after the display is
    // tested too): on other border lines the 8-bit FF_CUR_Y aliases (sprites at Y = 230 hit
    // YP -25..-18) and the arbiter grants no VRAM, so they collided on stale data (ghost S#0 C)
    function automatic logic active_line(input logic [8:0] yp, input logic y212);
        return (yp[8] && yp[7:0] == 8'd255) || (!yp[8] && yp[7:0] <= (y212 ? 8'd211 : 8'd191));
    endfunction
    assign W_ACTIVE = BWINDOW_Y && active_line(DOTCOUNTERYP, REG_R9_Y_DOTS);

    // [Y_TEST]Yテストステートでないことを示す信号
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_Y_TEST_EN <= 1'b0;
            FF_SP_LINE_EN <= 1'b0;
        end else if (DOTSTATE == 2'b01) begin
            if (DOTCOUNTERX == 9'd0) begin
                FF_Y_TEST_EN <= ~REG_R8_SP_OFF & W_ACTIVE;
                FF_SP_LINE_EN <= ~REG_R8_SP_OFF & W_ACTIVE;
            end else if (EIGHTDOTSTATE == 3'b110) begin
                if (W_SP_OFF == 1'b1 || (W_SP_OVERMAP && W_TARGET_SP_EN == 1'b1) || FF_Y_TEST_SP_NUM == 5'b11111) begin
                    FF_Y_TEST_EN <= 1'b0;
                end
            end
        end
    end

    // [Y_TEST]テスト対象のスプライト番号 (0～31)
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_Y_TEST_SP_NUM <= 5'b0;
        end else if (DOTSTATE == 2'b01) begin
            if (DOTCOUNTERX == 9'd0) begin
                FF_Y_TEST_SP_NUM <= 5'b0;
            end else if (EIGHTDOTSTATE == 3'b110) begin
                if (FF_Y_TEST_EN == 1'b1 && FF_Y_TEST_SP_NUM != 5'b11111) begin
                    FF_Y_TEST_SP_NUM <= FF_Y_TEST_SP_NUM + 1'b1;
                end
            end
        end
    end

    // [Y_TEST]表示するスプライトをリストアップするためのリストアップメモリアドレス 0～8
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_Y_TEST_LISTUP_ADDR <= 4'b0;
        end else if (DOTSTATE == 2'b01) begin
            if (DOTCOUNTERX == 9'd0) begin
                // INITIALIZE
                FF_Y_TEST_LISTUP_ADDR <= 4'b0;
            end else if (EIGHTDOTSTATE == 3'b110) begin
                // NEXT SPRITE [リストアップメモリが満杯になるまでインクリメント]
                if (FF_Y_TEST_EN == 1'b1 && W_TARGET_SP_EN == 1'b1 && W_SP_OVERMAP == 1'b0 && W_SP_OFF == 1'b0) begin
                    FF_Y_TEST_LISTUP_ADDR <= FF_Y_TEST_LISTUP_ADDR + 1'b1;
                end
            end
        end
    end

    // [Y_TEST]表示するスプライトをリストアップするためのリストアップメモリへの書き込み
    always_ff @(posedge CLK21M) begin
        if (DOTSTATE == 2'b01)
            if (DOTCOUNTERX == 9'd0)
                // INITIALIZE
                ;
            else if (EIGHTDOTSTATE == 3'b110) begin
                // NEXT SPRITE
                if (FF_Y_TEST_EN == 1'b1 && W_TARGET_SP_EN == 1'b1 && W_SP_OVERMAP == 1'b0 && W_SP_OFF == 1'b0) begin
                    SPRENDERPLANES[FF_Y_TEST_LISTUP_ADDR[2:0]] <= FF_Y_TEST_SP_NUM;
                end
            end
    end

    //[Y_TEST]４つ目（８つ目）のスプライトが並んだかどうかの信号
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_SP_OVERMAP <= 1'b0;
        end else if (PVDPS0RESETREQ != FF_VDPS0RESETACK) begin
            // S#0が読み込まれるまでクリアしない
            FF_SP_OVERMAP <= 1'b0;
        end else if (DOTSTATE == 2'b01)
            if (DOTCOUNTERX == 9'd0)
                // INITIALIZE
                ;
            else if (EIGHTDOTSTATE == 3'b110) begin
                if (FF_Y_TEST_EN == 1'b1 && W_TARGET_SP_EN == 1'b1 && W_SP_OVERMAP == 1'b1 && W_SP_OFF == 1'b0) begin
                    FF_SP_OVERMAP <= 1'b1;
                end
            end
    end

    // [Y_TEST]処理をあきらめたスプライト信号
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_SP_OVERMAP_NUM <= '1;
        end else if (PVDPS0RESETREQ != FF_VDPS0RESETACK) begin
            // S#0が読み込まれるまでクリアしない
            FF_SP_OVERMAP_NUM <= '1;
        end else if (DOTSTATE == 2'b01)
            if (DOTCOUNTERX == 9'd0)
                // INITIALIZE
                ;
            else if (EIGHTDOTSTATE == 3'b110) begin
                // JP: 調査をあきらめたスプライト番号が格納される。OVERMAPとは限らない。
                // JP: しかし、すでに OVERMAP で値が確定している場合は更新しない。
                if (FF_Y_TEST_EN == 1'b1 && W_TARGET_SP_EN == 1'b1 && W_SP_OVERMAP == 1'b1 && W_SP_OFF == 1'b0) begin
                    FF_SP_OVERMAP_NUM <= FF_Y_TEST_SP_NUM;
                end
            end
    end

    // Yテスト用の VRAM読み出しアドレス
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_Y_TEST_VRAM_ADDR <= 17'b0;
        end else if (DOTSTATE == 2'b11) begin
            FF_Y_TEST_VRAM_ADDR <= {SPATTRTBLBASEADDR, FF_Y_TEST_SP_NUM, 2'b00};
        end
    end

    // PREPARE SPRITE
    //
    // JP: 画面描画中           : 8ドット描画する間に1プレーン、スプライトのY座標を検査し、
    // JP:                        表示すべきスプライトをリストアップする。
    // JP: 画面非描画中         : リストアップしたスプライトの情報を集め、ラインバッファに描画
    // JP: 次の画面描画中       : ラインバッファに描画された絵を出力し、画面描画に混ぜる

    // READ TIMING OF SPRITE ATTRIBUTE TABLE

    assign SPATTRIB_ADDR = {SPATTRTBLBASEADDR, SPPREPAREPLANENUM};

    // Reading VRAM address for pattern table
    always_comb begin
        if (REG_R1_SP_SIZE == 1'b0) begin
            READVRAMADDRPTREAD = {SPPTNGENETBLBASEADDR, SPPREPAREPATTERNNUM[7:0], SPPREPARELINENUM[2:0]}; // 8x8 mode
        end else begin
            READVRAMADDRPTREAD = {SPPTNGENETBLBASEADDR, SPPREPAREPATTERNNUM[7:2], SPPREPAREXPOS, SPPREPARELINENUM[3:0]}; // 16x16 mode
        end
    end

    always_comb begin
        if (SPMODE2 == 1'b0) begin
            READVRAMADDRCREAD = {SPATTRIB_ADDR, 2'b11};
        end else begin
            READVRAMADDRCREAD = {SPATTRTBLBASEADDR[9:3], ~SPATTRTBLBASEADDR[2], SPPREPAREPLANENUM, SPPREPARELINENUM};
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            IRAMADRPREPARE <= 17'b0;
        end else if (DOTSTATE == 2'b11) begin
            case (EIGHTDOTSTATE)
                3'b000: IRAMADRPREPARE <= {SPATTRIB_ADDR, 2'b00}; // Y Read
                3'b001: IRAMADRPREPARE <= {SPATTRIB_ADDR, 2'b01}; // X Read
                3'b010: IRAMADRPREPARE <= {SPATTRIB_ADDR, 2'b10}; // Pattern Number Read
                3'b011, 3'b100: IRAMADRPREPARE <= READVRAMADDRPTREAD; // Pattern Read
                3'b101: IRAMADRPREPARE <= READVRAMADDRCREAD; // Color Read
                default: ;
            endcase
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            SPPREPARELOCALPLANENUM <= 3'b0;
            SPPREPAREEND <= 1'b0;
        end else if (DOTSTATE == 2'b01) begin
            if (SPSTATE == SPSTATE_PREPARE) begin
                case (EIGHTDOTSTATE)
                    3'b001: begin //Y READ
                        if (REG_R1_SP_ZOOM == 1'b0) begin
                            SPPREPARELINENUM <= W_SPLISTUPY[3:0];
                        end else begin
                            SPPREPARELINENUM <= W_SPLISTUPY[4:1];
                        end
                    end
                    3'b010: SPINFORAMX_IN <= {1'b0, PRAMDAT}; // X Read
                    3'b011: SPPREPAREPATTERNNUM <= PRAMDAT; // Pattern Number Read
                    3'b100: SPINFORAMPATTERN_IN[15:8] <= PRAMDAT; // Pattern Read (left)
                    3'b101: begin
                        if (REG_R1_SP_SIZE == 1'b0) begin
                            SPINFORAMPATTERN_IN[7:0] <= 8'b0; // 8x8 mode
                        end else begin
                            SPINFORAMPATTERN_IN[7:0] <= PRAMDAT; // 16x16 mode
                        end
                    end
                    3'b110: begin   // Color Read
                        SPINFORAMCOLOR_IN <= PRAMDAT[3:0]; // COLOR
                        SPINFORAMCC_IN <= (SPMODE2 == 1'b1) ? PRAMDAT[6] : 1'b0; //  CC   優先順位ビット (1: 優先順位無し, 0: 優先順位あり)
                        SPINFORAMIC_IN <= PRAMDAT[5] & SPMODE2; // IC   衝突検知ビット (1: 検知しない, 0: 検知する)

                        if (PRAMDAT[7] == 1'b1) begin
                            SPINFORAMX_IN <= SPINFORAMX_IN - 9'd32; // EC   32ドット左シフト (1: する, 0: しない)
                        end

                        // IF ALL OF THE SPRITES LIST-UPED ARE READED,
                        // THE SPRITES LEFT SHOULD NOT BE DRAWN.
                        if ({1'b0, SPPREPARELOCALPLANENUM} >= FF_Y_TEST_LISTUP_ADDR) begin
                            SPINFORAMPATTERN_IN <= 16'b0;
                        end
                    end
                    3'b111: begin
                        SPPREPARELOCALPLANENUM <= SPPREPARELOCALPLANENUM + 1'b1;
                        if (SPPREPARELOCALPLANENUM == 3'd7 || (SPPREPARELOCALPLANENUM == 3'd3 && SPMODE2 == 1'b0)) begin
                            SPPREPAREEND <= 1'b1;
                        end
                    end
                    default: ;
                endcase
            end else begin
                SPPREPARELOCALPLANENUM <= 3'b0;
                SPPREPAREEND <= 1'b0;
            end
        end
    end

    always_ff @(posedge CLK21M) begin
        if (DOTSTATE == 2'b01) begin
            if (SPSTATE == SPSTATE_PREPARE ) begin
                if (EIGHTDOTSTATE == 3'b111) begin
                    SPPREPAREPLANENUM <= SPRENDERPLANES[SPPREPARELOCALPLANENUM + 1];
                end
            end else begin
                SPPREPAREPLANENUM <= SPRENDERPLANES[0];
            end
        end
    end

    // DRAWING TO LINE BUFFER.
    //
    // A plane is taken over when its fetch ends (EIGHTDOTSTATE 7, DOTSTATE 01) and drawn
    // during the 32 clocks of the next fetch: pixel i is read from the buffer in clock i and
    // written back in clock i + 1 (32 pixels when zoomed). The last write of a zoomed plane
    // meets the first read of the next one: a read of the address written in the same clock
    // takes the written data (FF_FWD_*).

    // read side
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_DRAW_BUSY             <= 1'b0;
            FF_DRAW_CNT              <= 5'b0;
            SPDRAWX                  <= 9'b0;
            SPDRAWPATTERN            <= 16'b0;
            SPDRAWCOLOR              <= 4'b0;
            SPDRAWCC                 <= 1'b0;
            SPDRAWIC                 <= 1'b0;
            FF_SPCC0FOUND            <= 1'b0;
            FF_LASTCC0LOCALPLANENUM  <= 3'b0;
            FF_WR_PIX                <= 1'b0;
            FF_WR_X                  <= 9'b0;
            FF_WR_COLOR              <= 4'b0;
            FF_WR_CC                 <= 1'b0;
            FF_WR_IC                 <= 1'b0;
            FF_WR_CC0FOUND           <= 1'b0;
            FF_WR_LASTCC0            <= 3'b0;
        end else begin
            // the pixel read in this clock, for the write side
            FF_WR_PIX      <= FF_DRAW_BUSY && SPDRAWPATTERN[15] && !SPDRAWX[8] &&
                              (REG_R8_COL0_ON || SPDRAWCOLOR != 4'b0);
            FF_WR_X        <= SPDRAWX;
            FF_WR_COLOR    <= SPDRAWCOLOR;
            FF_WR_CC       <= SPDRAWCC;
            FF_WR_IC       <= SPDRAWIC;
            FF_WR_CC0FOUND <= FF_SPCC0FOUND;
            FF_WR_LASTCC0  <= FF_LASTCC0LOCALPLANENUM;

            if (SPSTATE == SPSTATE_PREPARE && DOTSTATE == 2'b01 && EIGHTDOTSTATE == 3'b111) begin
                // take over the plane just fetched
                FF_DRAW_BUSY  <= FF_SP_LINE_EN & ~REG_R8_SP_OFF;
                FF_DRAW_CNT   <= 5'b0;
                SPDRAWX       <= SPINFORAMX_IN;
                SPDRAWPATTERN <= SPINFORAMPATTERN_IN;
                SPDRAWCOLOR   <= SPINFORAMCOLOR_IN;
                SPDRAWCC      <= SPINFORAMCC_IN;
                SPDRAWIC      <= SPINFORAMIC_IN;
                // JP: CC='0'のスプライトが同一ライン上にまだ現れていない時は描画しない
                if (SPPREPARELOCALPLANENUM == 3'd0)
                    FF_SPCC0FOUND <= ~SPINFORAMCC_IN;
                else if (!SPINFORAMCC_IN)
                    FF_SPCC0FOUND <= 1'b1;
                if (!SPINFORAMCC_IN)
                    FF_LASTCC0LOCALPLANENUM <= SPPREPARELOCALPLANENUM;
            end else if (FF_DRAW_BUSY) begin
                if (REG_R1_SP_ZOOM == 1'b0 || FF_DRAW_CNT[0] == 1'b1) begin
                    SPDRAWPATTERN <= {SPDRAWPATTERN[14:0], 1'b0}; // Shift left
                end
                SPDRAWX     <= SPDRAWX + 1'b1;
                FF_DRAW_CNT <= FF_DRAW_CNT + 1'b1;
                if (FF_DRAW_CNT == (REG_R1_SP_ZOOM ? 5'd31 : 5'd15)) begin
                    FF_DRAW_BUSY <= 1'b0;
                end
            end
        end
    end

    // write side: the buffer content of the pixel read in the last clock
    always_ff @(posedge CLK21M) begin
        FF_FWD_HIT  <= W_DRAW_WE && FF_DRAW_BUSY && (FF_WR_X[7:0] == SPDRAWX[7:0]);
        FF_FWD_DATA <= W_DRAW_WDATA;
    end
    assign W_DRAW_Q = FF_FWD_HIT ? FF_FWD_DATA : SPLINEBUFDRAWDATA_OUT;

    // JP: ラインバッファの7ビット目は、何らかの色を描画した時に'1'になる。
    // JP: ラインバッファの6-4ビット目はそこに描画されているドットのローカルプレーン番号
    // JP: (色合成されているときは親となるCC='0'のスプライトのローカルプレーン番号)が入る。
    // JP: つまり、LASTCC0LOCALPLANENUMVがこの番号と等しいときはOR合成してよい事になる。
    always_comb begin
        W_DRAW_WE        = 1'b0;
        W_DRAW_WDATA     = {1'b1, FF_WR_LASTCC0, FF_WR_COLOR};
        W_DRAW_COLLISION = 1'b0;
        if (FF_WR_PIX) begin
            if (W_DRAW_Q[7] == 1'b0) begin
                // JP: 何も描かれていない(ビット7が'0')とき、このドットに初めての
                // JP: スプライトが描画される。ただし、CC='0'のスプライトが同一ライン上にまだ
                // JP: 現れていない時は描画しない
                if (FF_WR_CC0FOUND) begin
                    W_DRAW_WE = 1'b1;
                end
            end else if (FF_WR_CC == 1'b1 && W_DRAW_Q[6:4] == FF_WR_LASTCC0) begin
                // JP: 既に絵が描かれているが、CCが'1'でかつこのドットに描かれているスプライトの
                // JP: LOCALPLANENUMが LASTCC0LOCALPLANENUMVと等しい時は、ラインバッファから
                // JP: 下地データを読み、書きたい色と論理和を取リ、書き戻す。
                W_DRAW_WE    = 1'b1;
                W_DRAW_WDATA = W_DRAW_Q | {4'b0000, FF_WR_COLOR};
            end else if (FF_WR_IC == 1'b0) begin
                // Sprite collision occurred
                W_DRAW_COLLISION = 1'b1;
            end
        end
    end

    // STATUS REGISTER: S#0 C, S#3..S#6 (the last collision; X + 12, line + 7 as openMSX)
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_VDPS0RESETACK           <= 1'b0;
            FF_VDPS5RESETACK           <= 1'b0;
            PVDPS0SPCOLLISIONINCIDENCE <= 1'b0;
            PVDPS3S4SPCOLLISIONX       <= 9'b0;
            PVDPS5S6SPCOLLISIONY       <= 9'b0;
        end else begin
            if (PVDPS0RESETREQ != FF_VDPS0RESETACK) begin
                FF_VDPS0RESETACK           <= PVDPS0RESETREQ;
                PVDPS0SPCOLLISIONINCIDENCE <= 1'b0;
            end else if (W_DRAW_COLLISION) begin
                PVDPS0SPCOLLISIONINCIDENCE <= 1'b1;
            end
            if (PVDPS5RESETREQ != FF_VDPS5RESETACK) begin
                FF_VDPS5RESETACK     <= PVDPS5RESETREQ;
                PVDPS3S4SPCOLLISIONX <= 9'b0;
                PVDPS5S6SPCOLLISIONY <= 9'b0;
            end else if (W_DRAW_COLLISION) begin
                PVDPS3S4SPCOLLISIONX <= FF_WR_X + 9'd12;
                PVDPS5S6SPCOLLISIONY <= FF_CUR_Y + 9'd8;   // FF_CUR_Y is the display line - 1
            end
        end
    end


// JP: 画面へのレンダリング。VDPエンティティがDOTSTATE="11"の時に値を取得できるように、
// "01"のタイミングで出力する。
always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        SPLINEBUFDISPX <= 8'b0;
    end else if (DOTSTATE == 2'b10) begin
        // JP: DOTCOUNTERと実際の表示(カラーコードの出力)は8ドットずれている
        if (DOTCOUNTERX == 9'd8) begin
            SPLINEBUFDISPX <= {5'b00000, REG_R27_H_SCROLL};
        end else begin
            SPLINEBUFDISPX <= SPLINEBUFDISPX + 1'b1;
        end
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        SPWINDOWX <= 1'b0;
    end else if (DOTSTATE == 2'b10) begin
        // JP: DOTCOUNTERと実際の表示(カラーコードの出力)は8ドットずれている
        if (DOTCOUNTERX == 9'd8) begin
            SPWINDOWX <= 1'b1;
        end else if (SPLINEBUFDISPX == 8'hFF) begin
            SPWINDOWX <= 1'b0;
        end
    end
end

always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        SPLINEBUFDISPWE <= 1'b0;
    end else if (DOTSTATE == 2'b10) begin
        SPLINEBUFDISPWE <= 1'b0;
    end else if (DOTSTATE == 2'b11 && SPWINDOWX == 1'b1) begin
        // CLEAR DISPLAYED DOT
        SPLINEBUFDISPWE <= 1'b1;
    end
end

// JP: ウィンドウで表示をカットする
always_ff @(posedge CLK21M or posedge RESET) begin
    if (RESET) begin
        SPCOLOROUT  <= 1'b0; // JP:  0=透明, 1=スプライトドット
        SPCOLORCODE <= 4'b0; // JP:  SPCOLOROUT=1 の時のスプライトドット色番号
    end else if (DOTSTATE == 2'b01) begin
        if (SPWINDOWX == 1'b1) begin
            SPCOLOROUT  <= SPLINEBUFDISPDATA_OUT[7];
            SPCOLORCODE <= SPLINEBUFDISPDATA_OUT[3:0];
        end else begin
            SPCOLOROUT  <= 1'b0;
            SPCOLORCODE <= 4'b0;
        end
    end
end


endmodule
