//
//  vdp_text12.vhd
//    Imprementation of Text Mode 1,2.
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
// Contributors
//
//   Alex Wulms
//     - Improvement of the TEXT2 mode such as 'blink function'.
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
// 12th,August,2006 created by Kunihiko Ohnaka
// JP: VDPのコアの実装とスクリーンモードの実装を分離した
//
// 13th,March,2008
// Fixed Blink by caro
//
// 22nd,March,2008
// JP: タイミング緩和と、リファクタリング by t.hara
//
// 11th,September,2019 modified by Oduvaldo Pavan Junior
// Fixed the lack of page flipping (R13) capability
//
// Added the undocumented feature where R1 bit #2 change the blink counter
// clock source from VSYNC to HSYNC
//
//-----------------------------------------------------------------------------
// Document
//
// JP: TEXTモード1,2のメイン処理回路です。
//
//-----------------------------------------------------------------------------
//

module VDP_TEXT12 (
    input logic           CLK21M,
    input logic           RESET,
    input logic [1:0]     DOTSTATE,
    input logic [8:0]     DOTCOUNTERX,
    input logic [8:0]     DOTCOUNTERY,
    input logic [8:0]     DOTCOUNTERYP,
    input logic           VDPMODETEXT1,
    input logic           VDPMODETEXT1Q,
    input logic           VDPMODETEXT2,
    input logic           REG_R1_BL_CLKS,
    input logic [7:0]     REG_R7_FRAME_COL,
    input logic [7:0]     REG_R12_BLINK_MODE,
    input logic [7:0]     REG_R13_BLINK_PERIOD,
    input logic [6:0]     REG_R2_PT_NAM_ADDR,
    input logic [5:0]     REG_R4_PT_GEN_ADDR,
    input logic [10:0]    REG_R10R3_COL_ADDR,
    input logic [7:0]     PRAMDAT,
    output logic [16:0]   PRAMADR,
    output logic          TXVRAMREADEN,
    output logic [3:0]    PCOLORCODE
);

    logic [4:0]           DOTCOUNTER24;
    logic                 TXWINDOWX, TXPREWINDOWX;
    logic [16:0]          LOGICALVRAMADDRNAM, LOGICALVRAMADDRGEN, LOGICALVRAMADDRCOL;
    logic [11:0]          TXCHARCOUNTER, TXCHARCOUNTERSTARTOFLINE;
    logic [6:0]           TXCHARCOUNTERX;
    logic [7:0]           PATTERNNUM, PREPATTERN, PREBLINK, PATTERN, BLINK;
    logic                 TXCOLORCODE;
    logic [7:0]           TXCOLOR;
    logic [3:0]           FF_BLINK_CLK_CNT, FF_BLINK_PERIOD_CNT;
    logic                 FF_BLINK_STATE;
    logic [3:0]           W_BLINK_CNT_MAX;
    logic                 W_BLINK_SYNC;
    logic                 ITXVRAMREADEN, ITXVRAMREADEN2;

    // JP: RAMは DOTSTATEが"10","00"の時にアドレスを出して"01"でアクセスする。
    // JP: EIGHTDOTSTATEで見ると、
    // JP:  0-1     READ PATTERN NUM.
    // JP:  1-2     READ PATTERN
    // JP: となる。


    assign TXCHARCOUNTER = TXCHARCOUNTERSTARTOFLINE + {5'd0, TXCHARCOUNTERX};

    assign LOGICALVRAMADDRNAM = (VDPMODETEXT1 || VDPMODETEXT1Q) ? 
        {REG_R2_PT_NAM_ADDR, TXCHARCOUNTER[9:0]} : 
        {REG_R2_PT_NAM_ADDR[6:2], TXCHARCOUNTER};

    assign LOGICALVRAMADDRGEN = {REG_R4_PT_GEN_ADDR, PATTERNNUM, DOTCOUNTERY[2:0]};

    assign LOGICALVRAMADDRCOL = {REG_R10R3_COL_ADDR[10:3], TXCHARCOUNTER[11:3]};

    assign TXVRAMREADEN = (VDPMODETEXT1 || VDPMODETEXT1Q) ? 
        ITXVRAMREADEN : 
        (VDPMODETEXT2) ? (ITXVRAMREADEN || ITXVRAMREADEN2) : '0;

    assign TXCOLOR = (VDPMODETEXT2 && FF_BLINK_STATE && BLINK[7]) ? 
        REG_R12_BLINK_MODE : 
        REG_R7_FRAME_COL;

    assign PCOLORCODE = (TXWINDOWX && TXCOLORCODE) ? 
        TXCOLOR[7:4] : 
        (TXWINDOWX && !TXCOLORCODE) ? TXCOLOR[3:0] : REG_R7_FRAME_COL[3:0];

    // TIMING GENERATOR
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            DOTCOUNTER24 <= '0;
        end else if (DOTSTATE == 2'b10) begin
            if (DOTCOUNTERX == 12) begin
                // JP: DOTCOUNTERは"10"のタイミングでは既にカウントアップしているので注意
                DOTCOUNTER24 <= '0;
            end else begin
                // THE DOTCOUNTER24(2 DOWNTO 0) COUNTS UP 0 TO 5,
                // AND THE DOTCOUNTER24(4 DOWNTO 3) COUNTS UP 0 TO 3.
                if (DOTCOUNTER24[2:0] == 3'b101) begin
                    DOTCOUNTER24[4:3] <= DOTCOUNTER24[4:3] + 1'b1;
                    DOTCOUNTER24[2:0] <= '0;
                end else begin
                    DOTCOUNTER24[2:0] <= DOTCOUNTER24[2:0] + 1'b1;
                end
            end
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            TXPREWINDOWX <= 0;
        end else if (DOTSTATE == 2'b10) begin
            if (DOTCOUNTERX == 12) begin
                TXPREWINDOWX <= 1;
            end else if (DOTCOUNTERX == 240+12) begin
                TXPREWINDOWX <= 0;
            end
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            TXWINDOWX <= 0;
        end else if (DOTSTATE == 2'b01) begin
            if (DOTCOUNTERX == 16) begin
                TXWINDOWX <= 1;
            end else if (DOTCOUNTERX == 240+16) begin
                TXWINDOWX <= 0;
            end
        end
    end

    //
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            PATTERNNUM <= 8'b0;
            PRAMADR <= 17'b0;
            ITXVRAMREADEN <= 1'b0;
            ITXVRAMREADEN2 <= 1'b0;
            TXCHARCOUNTERX <= 7'b0;
            PREBLINK <= 8'b0;
            TXCHARCOUNTERSTARTOFLINE <= 12'b0;
        end else begin
            case (DOTSTATE)
                2'b11: begin
                    if (TXPREWINDOWX) begin
                        // VRAM READ ADDRESS OUTPUT.
                        case (DOTCOUNTER24[2:0])
                            3'b000: if (DOTCOUNTER24[4:3] == 2'b00) begin
                                        // READ COLOR TABLE(TEXT2 BLINK)
                                        // IT IS USED ONLY ONE TIME PER 8 CHARACTERS.
                                        PRAMADR <= LOGICALVRAMADDRCOL;
                                        ITXVRAMREADEN2 <= 1'b1;
                                    end
                            3'b001: begin
                                // READ PATTERN NAME TABLE
                                PRAMADR <= LOGICALVRAMADDRNAM;
                                ITXVRAMREADEN <= 1'b1;
                                TXCHARCOUNTERX <= TXCHARCOUNTERX + 1'b1;
                            end
                            3'b010: begin
                                // READ PATTERN GENERATOR TABLE
                                PRAMADR <= LOGICALVRAMADDRGEN;
                                ITXVRAMREADEN <= 1'b1;
                            end
                            3'b100: begin
                                // READ PATTERN NAME TABLE
                                // IT IS USED IF VDPMODE IS TEST2.
                                PRAMADR <= LOGICALVRAMADDRNAM;
                                ITXVRAMREADEN2 <= 1'b1;
                                if (VDPMODETEXT2) TXCHARCOUNTERX <= TXCHARCOUNTERX + 1'b1;
                            end
                            3'b101: begin
                                // READ PATTERN GENERATOR TABLE
                                // IT IS USED IF VDPMODE IS TEST2.
                                PRAMADR <= LOGICALVRAMADDRGEN;
                                ITXVRAMREADEN2 <= 1'b1;
                            end
                            default:
                                ;
                        endcase
                    end
                end
                2'b10: begin
                    ITXVRAMREADEN <= 1'b0;
                    ITXVRAMREADEN2 <= 1'b0;
                end
                2'b00: begin
                    if (DOTCOUNTERX == 9'd11) begin
                        TXCHARCOUNTERX <= 7'b0;
                        if (DOTCOUNTERYP == 9'd0) TXCHARCOUNTERSTARTOFLINE <= 12'b0;
                    end else if (DOTCOUNTERX == 9'd251 && DOTCOUNTERYP[2:0] == 3'b111) begin
                        TXCHARCOUNTERSTARTOFLINE <= TXCHARCOUNTERSTARTOFLINE + {5'd0, TXCHARCOUNTERX};
                    end
                end
                2'b01: begin
                    case (DOTCOUNTER24[2:0])
                        3'b001: if (DOTCOUNTER24[4:3] == 2'b00) PREBLINK <= PRAMDAT; // READ COLOR TABLE(TEXT2 BLINK) IT IS USED ONLY ONE TIME PER 8 CHARACTERS.
                        3'b010: PATTERNNUM <= PRAMDAT; // READ PATTERN NAME TABLE
                        3'b011: PREPATTERN <= PRAMDAT; // READ PATTERN GENERATOR TABLE
                        3'b101: PATTERNNUM <= PRAMDAT; // READ PATTERN NAME TABLE IT IS USED IF VDPMODE IS TEST2.
                        3'b000: if (VDPMODETEXT2) PREPATTERN <= PRAMDAT; // READ PATTERN GENERATOR TABLE IT IS USED IF VDPMODE IS TEST2.
                        default: ;
                    endcase
                end
                default: ;
            endcase
        end
    end

    // 
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            PATTERN <= 8'b0;
            TXCOLORCODE <= 1'b0;
            BLINK <= 8'b0;
        end else begin
            // COLOR CODE DECISION
            // JP: "01"と"10"のタイミングでかラーコードを出力してあげれば、
            // JP: VDPエンティティの方でパレットをデコードして色を出力してくれる。
            // JP: "01"と"10"で同じ色を出力すれば横256ドットになり、違う色を
            // JP: 出力すれば横512ドット表示となる。
            case (DOTSTATE)
                2'b00: begin
                    if (DOTCOUNTER24[2:0] == 3'b100)
                        // LOAD NEXT 8 DOT DATA
                        // JP: キャラクタの描画は DOTCOUNTER24が、
                        // JP:   "0:4"から"1:3"の6ドット
                        // JP:   "1:4"から"2:3"の6ドット
                        // JP:   "2:4"から"3:3"の6ドット
                        // JP:   "3:4"から"0:3"の6ドット
                        // JP: で行われるので"100"のタイミングでロードする
                        PATTERN <= PREPATTERN;
                    else if (DOTCOUNTER24[2:0] == 3'b001 && VDPMODETEXT2)
                        // JP: TEXT2では"001"のタイミングでもロードする。
                        PATTERN <= PREPATTERN;
                    
                    if (DOTCOUNTER24[2:0] == 3'b100 || DOTCOUNTER24[2:0] == 3'b001)
                        //EVALUATE BLINK SIGNAL
                        if (DOTCOUNTER24[4:0] == 5'b00100) BLINK <= PREBLINK;
                        else  BLINK <= {BLINK[6:0], 1'b0};
                end
                2'b01: begin
                    // パターンに応じてカラーコードを決定
                    TXCOLORCODE <= PATTERN[7];
                    // パターンをシフト
                    PATTERN <= {PATTERN[6:0], 1'b0};
                end
                2'b10: if (VDPMODETEXT2) begin
                    TXCOLORCODE <= PATTERN[7];
                    // パターンをシフト
                    PATTERN <= {PATTERN[6:0], 1'b0};
                end
                default: ;
            endcase
        end
    end

    // Blink timing generation
    assign W_BLINK_CNT_MAX = (FF_BLINK_STATE == 1'b0) ? REG_R13_BLINK_PERIOD[3:0] : REG_R13_BLINK_PERIOD[7:4];
    assign W_BLINK_SYNC = ((DOTCOUNTERX == 9'd0) && (DOTCOUNTERYP == 9'd0) && (DOTSTATE == 2'b00) && (REG_R1_BL_CLKS == 1'b0)) ||
                          ((DOTCOUNTERX == 9'd0) && (DOTSTATE == 2'b00) && (REG_R1_BL_CLKS == 1'b1));

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_BLINK_CLK_CNT <= 4'b0;
            FF_BLINK_STATE <= 1'b0;
            FF_BLINK_PERIOD_CNT <= 4'b0;
        end else if (W_BLINK_SYNC) begin
            if (FF_BLINK_CLK_CNT == 4'b1001) begin
                FF_BLINK_CLK_CNT <= 4'b0;
                FF_BLINK_PERIOD_CNT <= FF_BLINK_PERIOD_CNT + 1'b1;
            end else begin
                FF_BLINK_CLK_CNT <= FF_BLINK_CLK_CNT + 1'b1;
            end

            if (FF_BLINK_PERIOD_CNT >= W_BLINK_CNT_MAX) begin
                FF_BLINK_PERIOD_CNT <= 4'b0;
                if (REG_R13_BLINK_PERIOD[7:4] == 4'b0000) begin
                    // WHEN ON PERIOD IS 0, THE PAGE SELECTED SHOULD BE ALWAYS ODD / R#2
                    FF_BLINK_STATE <= 1'b0;
                end else if (REG_R13_BLINK_PERIOD[3:0] == 4'b0000) begin
                    // WHEN OFF PERIOD IS 0 AND ON NOT, THE PAGE SELECT SHOULD BE ALWAYS THE R#2 EVEN PAIR
                    FF_BLINK_STATE <= 1'b1;
                end else begin
                    // NEITHER ARE 0, SO JUST KEEP SWITCHING WHEN PERIOD ENDS
                    FF_BLINK_STATE <= ~FF_BLINK_STATE;
                end
            end
        end
    end

endmodule
