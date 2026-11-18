//
//  vdp_register.vhd
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
//----------------------------------------------------------------------------
//  23rd,March,2008
//      JP: VDP.VHD から分離 by t.hara
//
//  28th,March,2008
//      added "S#0 bit6 5th sprite (9th sprite) flag support" by t.hara
//
//  29th,March,2008
//      added V9958 registers (R25,R26,R27) by t.hara
//
//  26th,January,2017
//      patch yuukun status R0 S#5 timing
//
//  5th,September,2019 modified by Oduvaldo Pavan Junior
//      Fixed the lack of page flipping (R13) capability
//
//      Added the undocumented feature where R1 bit #2 change the blink counter
//      clock source from VSYNC to HSYNC
//
//  30th,May,2021 by t.hara
//      In the register writing by address auto-increment mode,
//      the bug that the address is incremented even if it exceeds R#47 is corrected.
//
//  2nd,June,2021 by t.hara
//      Fixed behavior of address auto-increment.
//      Fixed the write operation to the invalid register.
//

module VDP_REGISTER (
    input logic RESET,
    input logic CLK21M,

    input logic REQ,
    output logic ACK,
    input logic WRT,
    input logic [15:0] ADR,
    output logic [7:0] DBI,
    input logic [7:0] DBO,

    input logic [1:0] DOTSTATE,

    input logic VDPCMDTRCLRACK,
    input logic VDPCMDREGWRACK,
    input logic HSYNC,

    input logic VDPS0SPCOLLISIONINCIDENCE,
    input logic VDPS0SPOVERMAPPED,
    input logic [4:0] VDPS0SPOVERMAPPEDNUM,
    output logic SPVDPS0RESETREQ,
    input logic SPVDPS0RESETACK,
    output logic SPVDPS5RESETREQ,
    input logic SPVDPS5RESETACK,

    input logic VDPCMDTR,
    input logic VD,
    input logic HD,
    input logic VDPCMDBD,
    input logic FIELD,
    input logic VDPCMDCE,
    input logic [8:0] VDPS3S4SPCOLLISIONX,
    input logic [8:0] VDPS5S6SPCOLLISIONY,
    input logic [7:0] VDPCMDCLR,
    input logic [10:0] VDPCMDSXTMP,

    output logic [7:0] VDPVRAMACCESSDATA,
    output logic [16:0] VDPVRAMACCESSADDRTMP,
    output logic VDPVRAMADDRSETREQ,
    input logic VDPVRAMADDRSETACK,
    output logic VDPVRAMWRREQ,
    input logic VDPVRAMWRACK,
    input logic [7:0] VDPVRAMRDDATA,
    output logic VDPVRAMRDREQ,
    input logic VDPVRAMRDACK,

    output logic [3:0] VDPCMDREGNUM,
    output logic [7:0] VDPCMDREGDATA,
    output logic VDPCMDREGWRREQ,
    output logic VDPCMDTRCLRREQ,

    input logic [3:0] PALETTEADDR_OUT,

    output logic [8:0] PALETTEDATARGB_OUT,
    // INTERRUPT
    output logic CLR_VSYNC_INT,
    output logic CLR_HSYNC_INT,
    input logic REQ_VSYNC_INT_N,
    input logic REQ_HSYNC_INT_N,

    // REGISTER VALUE
    output logic REG_R0_HSYNC_INT_EN,
    output logic REG_R1_SP_SIZE,
    output logic REG_R1_SP_ZOOM,
    output logic REG_R1_BL_CLKS,
    output logic REG_R1_VSYNC_INT_EN,
    output logic REG_R1_DISP_ON,
    output logic [6:0] REG_R2_PT_NAM_ADDR,
    output logic [5:0] REG_R4_PT_GEN_ADDR,
    output logic [10:0] REG_R10R3_COL_ADDR,
    output logic [9:0] REG_R11R5_SP_ATR_ADDR,
    output logic [5:0] REG_R6_SP_GEN_ADDR,
    output logic [7:0] REG_R7_FRAME_COL,
    output logic REG_R8_SP_OFF,
    output logic REG_R8_COL0_ON,
    output logic REG_R9_PAL_MODE,
    output logic REG_R9_INTERLACE_MODE,
    output logic REG_R9_Y_DOTS,
    output logic [7:0] REG_R12_BLINK_MODE,
    output logic [7:0] REG_R13_BLINK_PERIOD,
    output logic [7:0] REG_R18_ADJ,
    output logic [7:0] REG_R19_HSYNC_INT_LINE,
    output logic [7:0] REG_R23_VSTART_LINE,
    output logic REG_R25_CMD,
    output logic REG_R25_YAE,
    output logic REG_R25_YJK,
    output logic REG_R25_MSK,
    output logic REG_R25_SP2,
    output logic [8:3] REG_R26_H_SCROLL,
    output logic [2:0] REG_R27_H_SCROLL,

    // MODE
    output logic VDPMODETEXT1,
    output logic VDPMODETEXT1Q,
    output logic VDPMODETEXT2,
    output logic VDPMODEMULTI,
    output logic VDPMODEMULTIQ,
    output logic VDPMODEGRAPHIC1,
    output logic VDPMODEGRAPHIC2,
    output logic VDPMODEGRAPHIC3,
    output logic VDPMODEGRAPHIC4,
    output logic VDPMODEGRAPHIC5,
    output logic VDPMODEGRAPHIC6,
    output logic VDPMODEGRAPHIC7,
    output logic VDPMODEISHIGHRES,
    output logic SPMODE2,
    output logic VDPMODEISVRAMINTERLEAVE,

    // SWITCHED I/O SIGNALS
    input logic FORCED_V_MODE,
    input logic [4:0] VDP_ID
);

    logic FF_ACK;
    logic VDPP1IS1STBYTE;
    logic VDPP2IS1STBYTE;
    logic [7:0] VDPP0DATA;
    logic [7:0] VDPP1DATA;
    logic [5:0] VDPREGPTR;
    logic VDPREGWRPULSE;
    logic [3:0] VDPR15STATUSREGNUM;
    logic VSYNCINTACK;
    logic HSYNCINTACK;
    logic [3:0] VDPR16PALNUM;
    logic [5:0] VDPR17REGNUM;
    logic VDPR17INCREGNUM;
    logic [7:0] PALETTEADDR;
    logic PALETTEWE;
    logic [8:0] PALETTEDATARGB_IN;
    logic [3:0] PALETTEWRNUM;
    logic FF_PALETTE_WR_REQ;
    logic FF_PALETTE_WR_ACK;
    logic FF_PALETTE_IN;
    logic [6:0] FF_R2_PT_NAM_ADDR;
    logic FF_R9_2PAGE_MODE;
    logic [1:0] REG_R1_DISP_MODE;
    logic FF_R1_DISP_ON;
    logic [1:0] FF_R1_DISP_MODE;
    logic FF_R25_SP2;
    logic [8:3] FF_R26_H_SCROLL;
    logic [3:0] REG_R18_VERT;
    logic [3:0] REG_R18_HORZ;
    logic [3:1] REG_R0_DISP_MODE;
    logic [3:1] FF_R0_DISP_MODE;
    logic FF_SPVDPS0RESETREQ;

    logic W_EVEN_DOTSTATE;
    logic W_IS_BITMAP_MODE;

    assign ACK = FF_ACK;
    assign SPVDPS0RESETREQ = FF_SPVDPS0RESETREQ;

    assign VDPMODEGRAPHIC1         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00000;
    assign VDPMODETEXT1            = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00001;
    assign VDPMODEMULTI            = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00010;
    assign VDPMODEGRAPHIC2         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00100;
    assign VDPMODETEXT1Q           = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00101;
    assign VDPMODEMULTIQ           = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b00110;
    assign VDPMODEGRAPHIC3         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b01000;
    assign VDPMODETEXT2            = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b01001;
    assign VDPMODEGRAPHIC4         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b01100;
    assign VDPMODEGRAPHIC5         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b10000;
    assign VDPMODEGRAPHIC6         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b10100;
    assign VDPMODEGRAPHIC7         = {REG_R0_DISP_MODE, REG_R1_DISP_MODE[0], REG_R1_DISP_MODE[1]} == 5'b11100;
    assign VDPMODEISHIGHRES        = (REG_R0_DISP_MODE[3:2] == 2'b10) && (REG_R1_DISP_MODE == 2'b00);
    assign SPMODE2                 = (REG_R1_DISP_MODE == 2'b00) && (REG_R0_DISP_MODE[3] || REG_R0_DISP_MODE[2]);
    assign VDPMODEISVRAMINTERLEAVE = (REG_R0_DISP_MODE[3] && REG_R0_DISP_MODE[1]);





    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_ACK <= 1'b0;
        end else begin
            FF_ACK <= REQ;
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            REG_R1_DISP_ON      <= 1'b0;
            REG_R0_DISP_MODE    <= 3'b000;
            REG_R1_DISP_MODE    <= 2'b00;
            REG_R25_SP2         <= 1'b0;
        end else if (HSYNC) begin
            REG_R1_DISP_ON      <= FF_R1_DISP_ON;
            REG_R0_DISP_MODE    <= FF_R0_DISP_MODE;
            REG_R1_DISP_MODE    <= FF_R1_DISP_MODE;
            if (VDP_ID != 5'b00000) begin
                REG_R25_SP2         <= FF_R25_SP2;
            end
        end
    end

    // R#26 at once, as openMSX: the fetch takes it per 8-dot group, a write within a line
    // scrolls the rest of the line
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET)                       REG_R26_H_SCROLL <= '0;
        else if (VDP_ID != 5'b00000)     REG_R26_H_SCROLL <= FF_R26_H_SCROLL;
    end

    assign W_IS_BITMAP_MODE = (REG_R0_DISP_MODE == 3'b011 || REG_R0_DISP_MODE[3]);

    always_ff @(posedge CLK21M) begin
        if (W_IS_BITMAP_MODE && FF_R9_2PAGE_MODE) begin
            REG_R2_PT_NAM_ADDR <= (FF_R2_PT_NAM_ADDR & 7'b1011111) | {1'b0, FIELD, 5'b00000};
        end else begin
            REG_R2_PT_NAM_ADDR <= FF_R2_PT_NAM_ADDR;
        end
    end

    // PALETTE REGISTER
    assign PALETTEADDR = (FF_PALETTE_IN) ? {4'b0000, PALETTEWRNUM} : {4'b0000, PALETTEADDR_OUT};
    assign PALETTEWE = (FF_PALETTE_IN) ? 1'b1 : 1'b0;
    assign W_EVEN_DOTSTATE = (DOTSTATE == 2'b00 || DOTSTATE == 2'b11);

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_PALETTE_IN <= 1'b0;
        end else if (W_EVEN_DOTSTATE == 1'b0) begin
            if (FF_PALETTE_WR_REQ != FF_PALETTE_WR_ACK) begin
                FF_PALETTE_IN <= 1'b1;
            end
        end else begin
            FF_PALETTE_IN <= 1'b0;
        end
    end

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            FF_PALETTE_WR_ACK <= 1'b0;
        end else if (W_EVEN_DOTSTATE == 1'b0) begin
            if (FF_PALETTE_WR_REQ != FF_PALETTE_WR_ACK) begin
                FF_PALETTE_WR_ACK <= ~FF_PALETTE_WR_ACK;
            end
        end
    end

    PALETE_RAM U_PALETTEMEMRGB (
        .ADR(PALETTEADDR),
        .CLK(CLK21M),
        .WE(PALETTEWE),
        .DBO(PALETTEDATARGB_IN),
        .DBI(PALETTEDATARGB_OUT),
        .RESET(RESET)
    );

    // PROCESS OF CPU READ REQUEST
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            DBI <= '0;
        end else if (REQ == 1'b1 && WRT == 1'b0) begin
            case (ADR[1:0])
                2'b00: DBI <= VDPVRAMRDDATA; // PORT#0 (0x98): READ VRAM
                2'b01: begin // PORT#1 (0x99): READ STATUS REGISTER
                    case (VDPR15STATUSREGNUM)
                        4'b0000: DBI <= {~REQ_VSYNC_INT_N, VDPS0SPOVERMAPPED, VDPS0SPCOLLISIONINCIDENCE, VDPS0SPOVERMAPPEDNUM}; // READ S#0
                        4'b0001: DBI <= {2'b00, VDP_ID, ~REQ_HSYNC_INT_N}; // READ S#1
                        4'b0010: DBI <= {VDPCMDTR, VD, HD, VDPCMDBD, 2'b11, FIELD, VDPCMDCE};  // READ S#2
                        4'b0011: DBI <= VDPS3S4SPCOLLISIONX[7:0];  // READ S#3
                        // S#4 = FEh | X8, S#6 = FCh | Y8 as openMSX (OCM-PLD 52e6710 sets 1s too)
                        4'b0100: DBI <= {7'b1111111, VDPS3S4SPCOLLISIONX[8]};  // READ S#4
                        4'b0101: DBI <= VDPS5S6SPCOLLISIONY[7:0];  // READ S#5
                        4'b0110: DBI <= {7'b1111110, VDPS5S6SPCOLLISIONY[8]};  // READ S#6
                        4'b0111: DBI <= VDPCMDCLR;  // READ S#7: THE COLOR REGISTER
                        4'b1000: DBI <= VDPCMDSXTMP[7:0];  // READ S#8: SXTMP LSB
                        4'b1001: DBI <= {7'b1111111, VDPCMDSXTMP[8]};  // READ S#9: SXTMP MSB
                        default: DBI <= '0;
                    endcase
                end
                default: DBI <= '1; // PORT#2, #3: NOT SUPPORTED IN READ MODE
            endcase
        end
    end

    // HSYNC INTERRUPT RESET CONTROL
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            CLR_HSYNC_INT <= 1'b0;
        end else if (REQ == 1'b1 && WRT == 1'b0) begin
            if (ADR[1:0] == 2'b01 && VDPR15STATUSREGNUM == 4'b0001) begin
                CLR_HSYNC_INT <= 1'b1; // CLEAR HSYNC INTERRUPT BY READ S#1
            end else begin
                CLR_HSYNC_INT <= 1'b0;
            end
        end else if (VDPREGWRPULSE == 1'b1) begin
            // FH is cleared when R#0 turns IE1 off (it is latched only while IE1 is on); an R#19
            // write or R#0 with IE1 on keeps it (openMSX VDP::changeRegister)
            if (VDPREGPTR == 6'b000000 && VDPP1DATA[4] == 1'b0) begin
                CLR_HSYNC_INT <= 1'b1;
            end else begin
                CLR_HSYNC_INT <= 1'b0;
            end
        end else begin
            CLR_HSYNC_INT <= 1'b0;
        end
    end

    // VSYNC INTERRUPT RESET CONTROL
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            CLR_VSYNC_INT <= 1'b0;
        end else if (REQ == 1'b1 && WRT == 1'b0) begin
            if (ADR[1:0] == 2'b01 && VDPR15STATUSREGNUM == 4'b0000) begin
                CLR_VSYNC_INT <= 1'b1; // CLEAR VSYNC INTERRUPT BY READ S#0
            end else begin
                CLR_VSYNC_INT <= 1'b0;
            end
        end else begin
            CLR_VSYNC_INT <= 1'b0;
        end
    end

    assign REG_R18_ADJ = {REG_R18_VERT, REG_R18_HORZ};

    // PROCESS OF CPU WRITE REQUEST
    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            VDPP1DATA               <= '0;
            VDPP1IS1STBYTE          <= 1'b1;
            VDPP2IS1STBYTE          <= 1'b1;
            VDPREGWRPULSE           <= 1'b0;
            VDPREGPTR               <= '0;
            VDPVRAMWRREQ            <= 1'b0;
            VDPVRAMRDREQ            <= 1'b0;
            VDPVRAMADDRSETREQ       <= 1'b0;
            VDPVRAMACCESSADDRTMP    <= '0;
            VDPVRAMACCESSDATA       <= '0;
            FF_R0_DISP_MODE         <= '0;
            REG_R0_HSYNC_INT_EN     <= 1'b0;
            FF_R1_DISP_MODE         <= '0;
            REG_R1_SP_SIZE          <= 1'b0;
            REG_R1_SP_ZOOM          <= 1'b0;
            REG_R1_BL_CLKS          <= 1'b0;
            REG_R1_VSYNC_INT_EN     <= 1'b0;
            FF_R1_DISP_ON           <= 1'b0;
            FF_R2_PT_NAM_ADDR       <= '0;
            REG_R12_BLINK_MODE      <= '0;
            REG_R13_BLINK_PERIOD    <= '0;
            REG_R7_FRAME_COL        <= '0;
            REG_R8_SP_OFF           <= 1'b0;
            REG_R8_COL0_ON          <= 1'b0;
            REG_R9_PAL_MODE         <= FORCED_V_MODE;
            FF_R9_2PAGE_MODE        <= 1'b0;
            REG_R9_INTERLACE_MODE   <= 1'b0;
            REG_R9_Y_DOTS           <= 1'b0;
            VDPR15STATUSREGNUM      <= '0;
            VDPR16PALNUM            <= '0;
            VDPR17REGNUM            <= '0;
            VDPR17INCREGNUM         <= 1'b0;
            REG_R18_VERT            <= '0;
            REG_R18_HORZ            <= '0;
            REG_R19_HSYNC_INT_LINE  <= '0;
            REG_R23_VSTART_LINE     <= '0;
            REG_R25_CMD             <= 1'b0;
            REG_R25_YAE             <= 1'b0;
            REG_R25_YJK             <= 1'b0;
            REG_R25_MSK             <= 1'b0;
            FF_R25_SP2              <= 1'b0;
            FF_R26_H_SCROLL         <= '0;
            REG_R27_H_SCROLL        <= '0;
            VDPCMDREGNUM            <= '0;
            VDPCMDREGDATA           <= '0;
            VDPCMDREGWRREQ          <= 1'b0;
            VDPCMDTRCLRREQ          <= 1'b0;
            PALETTEDATARGB_IN       <= '0;
            FF_PALETTE_WR_REQ       <= 1'b0;
            PALETTEWRNUM            <= '0;
        end else if (REQ == 1'b1 && WRT == 1'b0) begin
            // READ REQUEST
            case (ADR[1:0])
                2'b00: VDPVRAMRDREQ <= ~VDPVRAMRDACK; // PORT#0 (0x98): READ VRAM
                2'b01: begin // PORT#1 (0x99): READ STATUS REGISTER
                    VDPP1IS1STBYTE <= 1'b1;
                    case (VDPR15STATUSREGNUM)
                        4'b0000: FF_SPVDPS0RESETREQ <= ~SPVDPS0RESETACK; // READ S#0
                        4'b0001: begin end // READ S#1
                        4'b0101: SPVDPS5RESETREQ <= ~SPVDPS5RESETACK; // READ S#5
                        4'b0111: VDPCMDTRCLRREQ <= ~VDPCMDTRCLRACK; // READ S#7: THE COLOR REGISTER
                        default: begin end
                    endcase
                end
                default: begin end // PORT#3: NOT SUPPORTED IN READ MODE
            endcase
        end else if (REQ == 1'b1 && WRT == 1'b1) begin
            // WRITE REQUEST
            case (ADR[1:0])
                2'b00: begin // PORT#0 (0x98): WRITE VRAM
                    VDPVRAMACCESSDATA <= DBO;
                    VDPVRAMWRREQ <= ~VDPVRAMWRACK;
                end
                2'b01: begin // PORT#1 (0x99): REGISTER WRITE OR VRAM ADDR SETUP
                    if (VDPP1IS1STBYTE == 1'b1) begin
                        // FIRST BYTE; BUFFER IT
                        VDPP1IS1STBYTE <= 1'b0;
                        VDPP1DATA <= DBO;
                    end else begin
                        // SECOND BYTE; PROCESS BOTH BYTES
                        VDPP1IS1STBYTE <= 1'b1;
                        case (DBO[7:6])
                            2'b01: begin // SET VRAM ACCESS ADDRESS (WRITE)
                                VDPVRAMACCESSADDRTMP[7:0] <= VDPP1DATA;
                                VDPVRAMACCESSADDRTMP[13:8] <= DBO[5:0];
                                VDPVRAMADDRSETREQ <= ~VDPVRAMADDRSETACK;
                            end
                            2'b00: begin // SET VRAM ACCESS ADDRESS (READ)
                                VDPVRAMACCESSADDRTMP[7:0] <= VDPP1DATA;
                                VDPVRAMACCESSADDRTMP[13:8] <= DBO[5:0];
                                VDPVRAMADDRSETREQ <= ~VDPVRAMADDRSETACK;
                                VDPVRAMRDREQ <= ~VDPVRAMRDACK;
                            end
                            2'b10: begin // DIRECT REGISTER SELECTION
                                VDPREGPTR <= DBO[5:0];
                                VDPREGWRPULSE <= 1'b1;
                            end
                            2'b11: begin // DIRECT REGISTER SELECTION ??
                                VDPREGPTR <= DBO[5:0];
                                VDPREGWRPULSE <= 1'b1;
                            end
                            default: begin end
                        endcase
                    end
                end
                2'b10: begin // PORT#2: PALETTE WRITE
                    if (VDPP2IS1STBYTE == 1'b1) begin
                        PALETTEDATARGB_IN[2:0] <= DBO[2:0];
                        PALETTEDATARGB_IN[8:6] <= DBO[6:4];
                        VDPP2IS1STBYTE <= 1'b0;
                    end else begin
                        // パレットはRGBのデータが揃った時に一度に書き換える。
                        // (実機で動作を確認した)
                        PALETTEDATARGB_IN[5:3] <= DBO[2:0];
                        PALETTEWRNUM <= VDPR16PALNUM;
                        FF_PALETTE_WR_REQ <= ~FF_PALETTE_WR_ACK;
                        VDPP2IS1STBYTE <= 1'b1;
                        VDPR16PALNUM <= VDPR16PALNUM + 1'b1;
                    end
                end
                2'b11: begin // PORT#3: INDIRECT REGISTER WRITE
                    if (VDPR17REGNUM != 6'b010001) begin
                        // REGISTER 17 CANNOT BE MODIFIED. ALL OTHERS ARE OK
                        VDPREGWRPULSE <= 1'b1;
                    end
                    VDPP1DATA <= DBO;
                    VDPREGPTR <= VDPR17REGNUM;
                    if (VDPR17INCREGNUM) begin
                        VDPR17REGNUM <= VDPR17REGNUM + 1'b1;
                    end
                end
                default: begin end
            endcase
        end else if (VDPREGWRPULSE == 1'b1) begin
            // WRITE TO REGISTER (IF PREVIOUSLY REQUESTED)
            VDPREGWRPULSE <= 1'b0;
            if (VDPREGPTR[5] == 1'b0) begin
                // IT IS NOT A COMMAND ENGINE REGISTER:
                case (VDPREGPTR[4:0])
                    5'b00000: begin // #00
                        FF_R0_DISP_MODE <= VDPP1DATA[3:1];
                        REG_R0_HSYNC_INT_EN <= VDPP1DATA[4];
                    end
                    5'b00001: begin // #01
                        REG_R1_SP_ZOOM <= VDPP1DATA[0];
                        REG_R1_SP_SIZE <= VDPP1DATA[1];
                        REG_R1_BL_CLKS <= VDPP1DATA[2];
                        FF_R1_DISP_MODE <= VDPP1DATA[4:3];
                        REG_R1_VSYNC_INT_EN <= VDPP1DATA[5];
                        FF_R1_DISP_ON <= VDPP1DATA[6];
                    end
                    5'b00010: begin // #02
                        FF_R2_PT_NAM_ADDR <= VDPP1DATA[6:0];
                    end
                    5'b00011: begin // #03
                        REG_R10R3_COL_ADDR[7:0] <= VDPP1DATA;
                    end
                    5'b00100: begin // #04
                        REG_R4_PT_GEN_ADDR <= VDPP1DATA[5:0];
                    end
                    5'b00101: begin // #05
                        REG_R11R5_SP_ATR_ADDR[7:0] <= VDPP1DATA;
                    end
                    5'b00110: begin // #06
                        REG_R6_SP_GEN_ADDR <= VDPP1DATA[5:0];
                    end
                    5'b00111: begin // #07
                        REG_R7_FRAME_COL <= VDPP1DATA;
                    end
                    5'b01000: begin // #08
                        REG_R8_SP_OFF <= VDPP1DATA[1];
                        REG_R8_COL0_ON <= VDPP1DATA[5];
                    end
                    5'b01001: begin // #09
                        REG_R9_PAL_MODE <= VDPP1DATA[1];
                        FF_R9_2PAGE_MODE <= VDPP1DATA[2];
                        REG_R9_INTERLACE_MODE <= VDPP1DATA[3];
                        REG_R9_Y_DOTS <= VDPP1DATA[7];
                    end
                    5'b01010: begin // #10
                        REG_R10R3_COL_ADDR[10:8] <= VDPP1DATA[2:0];
                    end
                    5'b01011: begin // #11
                        REG_R11R5_SP_ATR_ADDR[9:8] <= VDPP1DATA[1:0];
                    end
                    5'b01100: begin // #12
                        REG_R12_BLINK_MODE <= VDPP1DATA;
                    end
                    5'b01101: begin // #13
                        REG_R13_BLINK_PERIOD <= VDPP1DATA;
                    end
                    5'b01110: begin // #14
                        VDPVRAMACCESSADDRTMP[16:14] <= VDPP1DATA[2:0];
                        VDPVRAMADDRSETREQ <= ~VDPVRAMADDRSETACK;
                    end
                    5'b01111: begin // #15
                        VDPR15STATUSREGNUM <= VDPP1DATA[3:0];
                    end
                    5'b10000: begin // #16
                        VDPR16PALNUM <= VDPP1DATA[3:0];
                        VDPP2IS1STBYTE <= 1'b1;
                    end
                    5'b10001: begin // #17
                        VDPR17REGNUM <= VDPP1DATA[5:0];
                        VDPR17INCREGNUM <= ~VDPP1DATA[7];
                    end
                    5'b10010: begin // #18
                        REG_R18_VERT <= VDPP1DATA[7:4];
                        REG_R18_HORZ <= VDPP1DATA[3:0];
                    end
                    5'b10011: begin // #19
                        REG_R19_HSYNC_INT_LINE <= VDPP1DATA;
                    end
                    5'b10111: begin // #23
                        REG_R23_VSTART_LINE <= VDPP1DATA;
                    end
                    5'b11001: begin // #25
                        if (VDP_ID != 5'b00000) begin
                            REG_R25_CMD <= VDPP1DATA[6];
                            REG_R25_YAE <= VDPP1DATA[4];
                            REG_R25_YJK <= VDPP1DATA[3];
                            REG_R25_MSK <= VDPP1DATA[1];
                            FF_R25_SP2 <= VDPP1DATA[0];
                        end
                    end
                    5'b11010: begin // #26
                        if (VDP_ID != 5'b00000) begin
                            FF_R26_H_SCROLL <= VDPP1DATA[5:0];
                        end
                    end
                    5'b11011: begin // #27
                        if (VDP_ID != 5'b00000) begin
                            REG_R27_H_SCROLL <= VDPP1DATA[2:0];
                        end
                    end
                    default: begin end
                endcase
            end else if (VDPREGPTR[4] == 1'b0) begin
                // REGISTERS FOR VDP COMMAND
                VDPCMDREGNUM <= VDPREGPTR[3:0];
                VDPCMDREGDATA <= VDPP1DATA;
                VDPCMDREGWRREQ <= ~VDPCMDREGWRACK;
            end
        end
    end
endmodule
