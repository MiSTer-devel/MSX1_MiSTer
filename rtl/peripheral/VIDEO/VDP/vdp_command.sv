//
//  vdp_command.vhd
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
//  20th,March,2008
//      JP: VDP.VHD から分離 by t.hara
//

module VDP_COMMAND (
    input  logic            RESET,
    input  logic            CLK21M,
    input  logic            VDPMODEGRAPHIC4,
    input  logic            VDPMODEGRAPHIC5,
    input  logic            VDPMODEGRAPHIC6,
    input  logic            VDPMODEGRAPHIC7,
    input  logic            VDPMODEISHIGHRES,
    input  logic            VRAMWRACK,
    input  logic            VRAMRDACK,
    input  logic            VRAMREADINGR,
    input  logic            VRAMREADINGA,
    input  logic [7:0]      VRAMRDDATA,
    input  logic            REGWRREQ,
    input  logic            TRCLRREQ,
    input  logic [3:0]      REGNUM,
    input  logic [7:0]      REGDATA,
    output logic            PREGWRACK,
    output logic            PTRCLRACK,
    output logic            PVRAMWRREQ,
    output logic            PVRAMRDREQ,
    output logic [16:0]     PVRAMACCESSADDR,
    output logic [7:0]      PVRAMWRDATA,
    output logic [7:0]      PCLR,
    output logic            PCE,
    output logic            PBD,
    output logic            PTR,
    output logic [10:0]     PSXTMP,
    output logic [7:4]      CUR_VDP_COMMAND,
    output logic            PROWSTEP,     // pulse: block command went to the next row
    output logic            PMINORSTEP,   // pulse: LINE stepped its minor axis
    input  logic            REG_R25_CMD
);

    localparam logic [3:0] HMMC   = 4'b1111;
    localparam logic [3:0] YMMM   = 4'b1110;
    localparam logic [3:0] HMMM   = 4'b1101;
    localparam logic [3:0] HMMV   = 4'b1100;
    localparam logic [3:0] LMMC   = 4'b1011;
    localparam logic [3:0] LMCM   = 4'b1010;
    localparam logic [3:0] LMMM   = 4'b1001;
    localparam logic [3:0] LMMV   = 4'b1000;
    localparam logic [3:0] LINE   = 4'b0111;
    localparam logic [3:0] SRCH   = 4'b0110;
    localparam logic [3:0] PSET   = 4'b0101;
    localparam logic [3:0] POINT  = 4'b0100;
    localparam logic [3:0] STOP   = 4'b0000;

    localparam logic [2:0] IMPB210 = 3'b000;
    localparam logic [2:0] ANDB210 = 3'b001;
    localparam logic [2:0] ORB210  = 3'b010;
    localparam logic [2:0] EORB210 = 3'b011;
    localparam logic [2:0] NOTB210 = 3'b100;
  
    typedef enum logic [3:0] { 
        STIDLE, STCHKLOOP, STRDCPU, STWAITCPU, STRDVRAM, STWAITRDVRAM, 
        STPOINTWAITRDVRAM, STSRCHWAITRDVRAM, STPRERDVRAM, STWAITPRERDVRAM, 
        STWRVRAM, STWAITWRVRAM, STLINENEWPOS, STLINECHKLOOP, STSRCHCHKLOOP, 
        STEXECEND 
    } TYPSTATE;
    TYPSTATE STATE;

    logic  [8:0] SX, DX;
    logic  [9:0] SY, DY, NX, NY;
    logic        MM, EQ, DIX, DIY;
    logic  [7:0] CMR, CLR;
    logic  [9:0] DXTMP, NXTMP;
    logic        REGWRACK, TRCLRACK, CMRWR;
    logic        VRAMWRREQ, VRAMRDREQ;
    logic [16:0] VRAMACCESSADDR;
    logic  [7:0] VRAMWRDATA;
    logic        CE, BD, TR;
    logic [10:0] SXTMP;
    logic        W_VDPCMD_EN;
    
    logic  [2:0] CMR_LO;
    logic  [7:6] CMR_HI;

    logic        INITIALIZING, GRAPHIC4_OR_6, SRCHEQRSLT, NYLOOPEND, NXLOOPEND, DYEND, SYEND;
    logic  [1:0] MAXXMASK, RDXLOW;
    logic  [7:0] RDPOINT, LOGOPDESTCOL, COLMASK;
    logic  [8:0] VDPVRAMACCESSX;
    logic  [9:0] NXCOUNT, VDPVRAMACCESSY, YCOUNTDELTA, NX_MINUS_ONE;
    logic [10:0] XCOUNTDELTA;


    assign PREGWRACK = REGWRACK;
    assign PTRCLRACK = TRCLRACK;
    assign PVRAMWRREQ = W_VDPCMD_EN ? VRAMWRREQ : VRAMWRACK;
    assign PVRAMRDREQ = VRAMRDREQ;
    assign PVRAMACCESSADDR = VRAMACCESSADDR;
    assign PVRAMWRDATA = VRAMWRDATA;
    assign PCLR = CLR;
    assign PCE = CE;
    assign PBD = BD;
    assign PTR = TR;
    assign PSXTMP = SXTMP;
    assign CUR_VDP_COMMAND = CMR[7:4];

    // R25 CMD BIT
    // 0 = NORMAL
    // 1 = VDP COMMAND ON TEXT/GRAPHIC1/GRAPHIC2/GRAPHIC3/MOSAIC MODE
    assign W_VDPCMD_EN = (VDPMODEGRAPHIC4 || VDPMODEGRAPHIC5 || VDPMODEGRAPHIC6) ? VDPMODEGRAPHIC4 | VDPMODEGRAPHIC5 | VDPMODEGRAPHIC6 : VDPMODEGRAPHIC7 | REG_R25_CMD;

    always_ff @(posedge CLK21M or posedge RESET) begin
        if (RESET) begin
            STATE <= STIDLE;  // VERY IMPORTANT FOR XILINX SYNTHESIS TOOL(XST)
            INITIALIZING = 1'b0;
            NXCOUNT = '0;
            NXLOOPEND = 1'b0;
            XCOUNTDELTA = '0;
            YCOUNTDELTA = '0;
            COLMASK = '1;
            RDXLOW = 2'b00;
            SX <= '0;  // R32
            SY <= '0;  // R34
            DX <= '0;  // R36
            DY <= '0;  // R38
            NX <= '0;  // R40
            NY <= '0;  // R42
            CLR <= '0; // R44
            MM  <= 1'b0; // R45 BIT 0
            EQ  <= 1'b0; // R45 BIT 1
            DIX <= 1'b0; // R45 BIT 2
            DIY <= 1'b0; // R45 BIT 3
    //        MXS <= 1'b0; // R45 BIT 4
    //        MXD <= 1'b0; // R45 BIT 5
            CMR <= '0; // R46
            SXTMP <= '0;
            DXTMP <= '0;
            CMRWR <= 1'b0;
            REGWRACK <= 1'b0;
            VRAMWRREQ <= 1'b0;
            VRAMRDREQ <= 1'b0;
            VRAMWRDATA <= '0;
            TR <= 1'b1;  // TRANSFER READY
            CE <= 1'b0;  // COMMAND EXECUTING
            BD <= 1'b0;  // BORDER COLOR FOUND
            TRCLRACK <= 1'b0;
            VDPVRAMACCESSY = '0;
            VDPVRAMACCESSX = '0;
            VRAMACCESSADDR <= '0;
            PROWSTEP <= 1'b0;
            PMINORSTEP <= 1'b0;
        end else begin
            PROWSTEP <= 1'b0;
            PMINORSTEP <= 1'b0;
        
            GRAPHIC4_OR_6 = (VDPMODEGRAPHIC4 == 1'b1 || VDPMODEGRAPHIC6 == 1'b1);
        
            case (CMR[7:6])
                2'b11: begin
                    // BYTE COMMAND
                    if (GRAPHIC4_OR_6) begin
                        // GRAPHIC4,6 (SCREEN 5, 7)
                        NXCOUNT = {1'b0, NX[9:1]};
                        XCOUNTDELTA = DIX ? 11'b11111111110 : 11'b00000000010;
                    end else if (VDPMODEGRAPHIC5 == 1'b1) begin
                        // GRAPHIC5 (SCREEN 6)
                        NXCOUNT = {2'b00, NX[9:2]};
                        XCOUNTDELTA = DIX ? 11'b11111111100 : 11'b00000000100;
                    end else begin
                        // GRAPHIC7 (SCREEN 8) AND OTHER
                        NXCOUNT = NX;
                        XCOUNTDELTA = DIX ? 11'b11111111111 : 11'b00000000001;
                    end
                    COLMASK = '1;
                end
                // DOT COMMAND
                default: begin
                        NXCOUNT = NX;
                        XCOUNTDELTA = DIX ? 11'b11111111111 : 11'b00000000001;
                        if (GRAPHIC4_OR_6) begin
                            COLMASK = 8'h0F;
                        end else if (VDPMODEGRAPHIC5) begin
                            COLMASK = 8'h03;
                        end else begin
                            COLMASK = '1;
                        end
                end
            endcase

            YCOUNTDELTA = DIY ? 10'b1111111111 : 10'b0000000001;
            MAXXMASK = VDPMODEISHIGHRES ? 2'b10 : 2'b01; 

            // DETERMINE IF X-LOOP IS FINISHED
            case (CMR[7:4])
                HMMV, HMMC, LMMV, LMMC:
                    NXLOOPEND =  ((NXTMP == 10'd0) || ((DXTMP[9:8] & MAXXMASK) == MAXXMASK));
                YMMM:
                    NXLOOPEND =  ((DXTMP[9:8] & MAXXMASK) == MAXXMASK);
                HMMM, LMMM:
                    NXLOOPEND =  ((NXTMP == 10'd0) || ((SXTMP[9:8] & MAXXMASK) == MAXXMASK) || ((DXTMP[9:8] & MAXXMASK) == MAXXMASK));
                LMCM:
                    NXLOOPEND =  ((NXTMP == 10'd0) || ((SXTMP[9:8] & MAXXMASK) == MAXXMASK));
                SRCH:
                    NXLOOPEND =  ((SXTMP[9:8] & MAXXMASK) == MAXXMASK);
                default:
                    NXLOOPEND = 1'b1;
            endcase

            // RETRIEVE THE 'POINT' OUT OF THE BYTE THAT WAS MOST RECENTLY READ
            if (GRAPHIC4_OR_6) begin
                // SCREEN 5, 7
                RDPOINT = RDXLOW[0] ? {4'b0000, VRAMRDDATA[3:0]} : {4'b0000, VRAMRDDATA[7:4]};
            end else if (VDPMODEGRAPHIC5) begin
                // SCREEN 6
                case (RDXLOW)
                    2'b00:
                        RDPOINT = {6'b000000, VRAMRDDATA[7:6]};
                    2'b01:
                        RDPOINT = {6'b000000, VRAMRDDATA[5:4]};
                    2'b10:
                        RDPOINT = {6'b000000, VRAMRDDATA[3:2]};
                    2'b11:
                        ;
                endcase
            end else begin
                // SCREEN 8 AND OTHER MODES
                RDPOINT = VRAMRDDATA;
            end

            // PERFORM LOGICAL OPERATION ON MOST RECENTLY READ POINT AND
            // ON THE POINT TO BE WRITTEN.
            if (!CMR[3] || (VRAMWRDATA & COLMASK) != 8'd0)
                case(CMR[2:0])
                    IMPB210:
                        LOGOPDESTCOL = VRAMWRDATA & COLMASK;
                    ANDB210:
                        LOGOPDESTCOL = (VRAMWRDATA & COLMASK) & RDPOINT;
                    ORB210:
                        LOGOPDESTCOL = (VRAMWRDATA & COLMASK) | RDPOINT;
                    EORB210:
                        LOGOPDESTCOL = (VRAMWRDATA & COLMASK) ^ RDPOINT;
                    NOTB210:
                        LOGOPDESTCOL = ~(VRAMWRDATA & COLMASK);
                    default:
                        LOGOPDESTCOL = RDPOINT;
                endcase
            else
                LOGOPDESTCOL = RDPOINT;

            // PROCESS REGISTER UPDATE REQUEST, CLEAR 'TRANSFER READY' REQUEST
            // OR PROCESS ANY ONGOING COMMAND.
            if (REGWRREQ != REGWRACK) begin
                REGWRACK <= ~REGWRACK;
                case(REGNUM)
                    4'b0000:    //#32
                        SX[7:0] <= REGDATA;
                    4'b0001:    //#33
                        SX[8]   <= REGDATA[0];
                    4'b0010:    //#34
                        SY[7:0] <= REGDATA;
                    4'b0011:    //#35
                        SY[9:8] <= REGDATA[1:0];
                    4'b0100:    //#36
                        DX[7:0] <= REGDATA;
                    4'b0101:    //#37
                        DX[8]   <= REGDATA[0];
                    4'b0110:    //#38
                        DY[7:0] <= REGDATA;
                    4'b0111:    //#39
                        DY[9:8] <= REGDATA[1:0];
                    4'b1000:    //#40
                        NX[7:0] <= REGDATA;
                    4'b1001:    //#41
                        NX[9:8] <= REGDATA[1:0];
                    4'b1010:    //#42
                        NY[7:0] <= REGDATA;
                    4'b1011:    //#43
                        NY[9:8] <= REGDATA[1:0];
                    4'b1100: begin   //#44
                        CLR <= CE ? REGDATA & COLMASK : REGDATA;
                        TR <= 1'b0; //DATA IS TRANSFERRED FROM CPU TO VDP COLOR REGISTER
                    end
                    4'b1101: begin   //#45
                        MM  <= REGDATA[0];
                        EQ  <= REGDATA[1];
                        DIX <= REGDATA[2];
                        DIY <= REGDATA[3];
                        //MXD <= REGDATA[5];
                    end                                           
                    4'b1110: begin     //#46
                        // INITIALIZE THE NEW COMMAND
                        // NOTE THAT THIS WILL ABORT ANY ONGOING COMMAND!
                        CMR <= REGDATA;
                        CMRWR <= W_VDPCMD_EN;
                        STATE <= STIDLE;
                    end
                    4'b1111: ;
                endcase
            end else if (TRCLRREQ != TRCLRACK) begin
                // RESET THE DATA TRANSFER REGISTER (CPU HAS JUST READ THE COLOR REGISTER)
                TRCLRACK <= ~TRCLRACK;
                TR <= 1'b0;
            end else begin
                // PROCESS THE VDP COMMAND STATE
                case(STATE)
                STIDLE: begin
                    if (CMRWR) begin
                        // EXEC NEW VDP COMMAND
                        CMRWR <= 1'b0;
                        CE <= 1'b1;
                        BD <= 1'b0;
                        if (CMR[7:4] == LINE) begin
                            // LINE COMMAND REQUIRES SPECIAL SXTMP AND NXTMP SET-UP
                            NX_MINUS_ONE = NX - 1'b1;
                            SXTMP <= {2'b00, NX_MINUS_ONE[9:1]};
                            NXTMP <= '0;
                        end else begin
                            SXTMP <= (CMR[7:4] == YMMM) ? {2'b00, DX} : {2'b00, SX};
                            NXTMP <= NXCOUNT;
                        end
                        DXTMP <= {1'b0, DX};
                        INITIALIZING = 1'b1;
                        STATE <= STCHKLOOP;
                    end else begin
                        CE <= 1'b0;
                    end
                end
                STRDCPU:
                    if (!TR) begin // CPU HAS TRANSFERRED DATA TO (OR FROM) THE COLOR REGISTER
                        TR <= 1'b1; // VDP IS READY TO RECEIVE THE NEXT TRANSFER.
                        VRAMWRDATA <= CLR;
                        STATE <= CMR[6] ? STWRVRAM : STPRERDVRAM; // IT IS HMMC : LMMC
                    end 
                STWAITCPU:
                    if (!TR) begin 
                        // CPU HAS TRANSFERRED DATA TO (OR FROM) THE COLOR REGISTER
                        // VDP MAY READ THE NEXT VALUE INTO THE COLOR REGISTER
                        STATE <= STRDVRAM;
                    end
                STRDVRAM: begin
                    // APPLICABLE TO YMMM, HMMM, LMCM, LMMM, SRCH, POINT
                    VDPVRAMACCESSY = SY;
                    VDPVRAMACCESSX = SXTMP[8:0];
                    RDXLOW = SXTMP[1:0];
                    VRAMRDREQ <= ~VRAMRDACK;
                    case(CMR[7:4])
                        POINT:
                            STATE <= STPOINTWAITRDVRAM;
                        SRCH:
                            STATE <= STSRCHWAITRDVRAM;
                        default:
                            STATE <= STWAITRDVRAM;
                    endcase
                end
                STPOINTWAITRDVRAM:
                    // APPLICABLE TO POINT
                    if (VRAMRDREQ == VRAMRDACK) begin
                        CLR <= RDPOINT;
                        STATE <= STEXECEND;
                    end
                STSRCHWAITRDVRAM:
                    // APPLICABLE TO SRCH
                    if (VRAMRDREQ == VRAMRDACK) begin
                        SRCHEQRSLT = (RDPOINT != CLR);
                        if (EQ == SRCHEQRSLT) begin
                            BD <= 1'b1;
                            STATE <= STEXECEND;
                        end else begin
                            SXTMP <= SXTMP + XCOUNTDELTA;
                            STATE <= STSRCHCHKLOOP;
                        end
                    end
                STWAITRDVRAM:
                    // APPLICABLE TO YMMM, HMMM, LMCM, LMMM
                    if (VRAMRDREQ == VRAMRDACK) begin
                        SXTMP <= SXTMP + XCOUNTDELTA;
                        case(CMR[7:4])
                            LMMM: begin
                                VRAMWRDATA <= RDPOINT;
                                STATE <= STPRERDVRAM;
                            end
                            LMCM: begin
                                CLR <= RDPOINT;
                                TR <= 1'b1;
                                NXTMP <= NXTMP - 1'b1;
                                STATE <= STCHKLOOP;
                            end
                            default: begin
                                // REMAINING: YMMM, HMMM
                                VRAMWRDATA <= VRAMRDDATA;
                                STATE <= STWRVRAM;
                            end
                        endcase
                    end
                STPRERDVRAM: begin
                    // APPLICABLE TO LMMC, LMMM, LMMV, LINE, PSET
                    VDPVRAMACCESSY = DY;
                    VDPVRAMACCESSX = DXTMP[8:0];
                    RDXLOW = DXTMP[1:0];
                    VRAMRDREQ <= ~VRAMRDACK;
                    STATE <= STWAITPRERDVRAM;
                end
                STWAITPRERDVRAM:
                    // APPLICABLE TO LMMC, LMMM, LMMV, LINE, PSET
                    if (VRAMRDREQ == VRAMRDACK) begin
                        if (GRAPHIC4_OR_6)
                            // SCREEN 5, 7
                                VRAMWRDATA <= RDXLOW[0] ? {VRAMRDDATA[7:4], LOGOPDESTCOL[3:0]} : {LOGOPDESTCOL[3:0], VRAMRDDATA[3:0]};
                        else if (VDPMODEGRAPHIC5)
                            // SCREEN 6
                            case(RDXLOW)
                                2'b00:
                                    VRAMWRDATA <= {LOGOPDESTCOL[1:0], VRAMRDDATA[5:0]}; 
                                2'b01:
                                    VRAMWRDATA <= {VRAMRDDATA[7:6], LOGOPDESTCOL[1:0], VRAMRDDATA[3:0]}; 
                                2'b10:
                                    VRAMWRDATA <= {VRAMRDDATA[7:4], LOGOPDESTCOL[1:0], VRAMRDDATA[1:0]}; 
                                2'b11:
                                    VRAMWRDATA <= {VRAMRDDATA[7:2], LOGOPDESTCOL[1:0]}; 
                            endcase
                        else
                            // SCREEN 8 AND OTHER MODES
                            VRAMWRDATA <= LOGOPDESTCOL;
                        STATE <= STWRVRAM;
                    end    
                STWRVRAM: begin
                    // APPLICABLE TO HMMC, YMMM, HMMM, HMMV, LMMC, LMMM, LMMV, LINE, PSET
                    VDPVRAMACCESSY = DY;
                    VDPVRAMACCESSX = DXTMP[8:0];
                    VRAMWRREQ <= ~VRAMWRACK;
                    STATE <= STWAITWRVRAM;
                end
                STWAITWRVRAM:
                    // APPLICABLE TO HMMC, YMMM, HMMM, HMMV, LMMC, LMMM, LMMV, LINE, PSET
                    if (VRAMWRREQ == VRAMWRACK)
                        case(CMR[7:4])
                            PSET:
                                STATE <= STEXECEND;
                            LINE: begin
                                SXTMP <= SXTMP - NY;
                                if (MM)
                                    DY <= DY + YCOUNTDELTA;
                                else
                                    DXTMP <= DXTMP + XCOUNTDELTA[9:0];
                                STATE <= STLINENEWPOS;   
                            end
                            default: begin
                                DXTMP <= DXTMP + XCOUNTDELTA[9:0];
                                NXTMP <= NXTMP - 1'b1;
                                STATE <= STCHKLOOP;
                            end
                        endcase
                STLINENEWPOS: begin
                    // APPLICABLE TO LINE
                    if (SXTMP[10]) begin
                        PMINORSTEP <= 1'b1;
                        SXTMP <= {1'b0, (SXTMP[9:0] + NX)};
                        if (MM)
                            DXTMP <= DXTMP + XCOUNTDELTA[9:0];
                        else
                            DY <= DY + YCOUNTDELTA;
                    end
                    STATE <= STLINECHKLOOP;
                end
                STLINECHKLOOP: begin
                    // APPLICABLE TO LINE
                    if ((NXTMP == NX) || ((DXTMP[9:8] & MAXXMASK) == MAXXMASK))
                        STATE <= STEXECEND;
                    else begin
                        VRAMWRDATA <= CLR;
                        // COLOR MUST BE RE-MASKED, JUST IN CASE THAT SCREENMODE WAS CHANGED
                        CLR <= CLR & COLMASK;
                        STATE <= STPRERDVRAM; 
                    end
                    NXTMP <= NXTMP + 1'b1;
                end
                STSRCHCHKLOOP:
                    if (NXLOOPEND)
                        STATE <= STEXECEND;
                    else begin
                        // COLOR MUST BE RE-MASKED, JUST IN CASE THAT SCREENMODE WAS CHANGED
                        CLR <= CLR & COLMASK;
                        STATE <= STRDVRAM; 
                    end    
                STCHKLOOP: begin
                    //WHEN INITIALIZING = '1':
                    //APPLICABLE TO ALL COMMANDS
                    //WHEN INITIALIZING = '0':
                    //APPLICABLE TO HMMC, YMMM, HMMM, HMMV, LMMC, LMCM, LMMM, LMMV

                    //DETERMINE NYLOOPEND
                    DYEND = 1'b0;
                    SYEND = 1'b0;
                    if (DIY) begin
                        if ((DY == 10'd0) && (CMR[7:4] != LMCM))
                            DYEND = 1'b1;
                        if ((SY == 10'd0) && (CMR[5] != CMR[4]))
                            // BIT5 /= BIT4 IS TRUE FOR COMMANDS YMMM, HMMM, LMCM, LMMM
                            SYEND = 1'b1;
                    end
                    
                    NYLOOPEND = ((NY == 10'd1) || DYEND || SYEND);

                    if (~INITIALIZING && NXLOOPEND && NYLOOPEND)
                        STATE <= STEXECEND;
                    else begin
                        // COMMAND NOT YET FINISHED OR COMMAND INITIALIZING. DETERMINE NEXT/FIRST STEP
                        // COLOR MUST BE (RE-)MASKED, JUST IN CASE THAT SCREENMODE WAS CHANGED 
                        CLR <= CLR & COLMASK;
                        case(CMR[7:4])
                            HMMC:
                                STATE <= STRDCPU;
                            YMMM:
                                STATE <= STRDVRAM;
                            HMMM:
                                STATE <= STRDVRAM;
                            HMMV: begin
                                VRAMWRDATA <= CLR;
                                STATE <= STWRVRAM;
                            end
                            LMMC:
                                STATE <= STRDCPU;
                            LMCM:
                                STATE <= STWAITCPU;
                            LMMM:
                                STATE <= STRDVRAM;
                            LMMV, LINE, PSET: begin
                                VRAMWRDATA <= CLR;
                                STATE <= STPRERDVRAM;
                            end
                            SRCH:
                                STATE <= STRDVRAM;
                            POINT:
                                STATE <= STRDVRAM;
                            default:
                                STATE <= STEXECEND;
                        endcase
                    end

                    if (!INITIALIZING && NXLOOPEND) begin
                        PROWSTEP <= 1'b1;
                        NXTMP <= NXCOUNT;
                        SXTMP <= CMR[7:4] == YMMM ? {2'b00, DX} : {2'b00, SX};
                        DXTMP <= {1'b0, DX};
                        NY <= NY - 1'b1;
                        if (CMR[5] != CMR[4])
                            // BIT5 /= BIT4 IS TRUE FOR COMMANDS YMMM, HMMM, LMCM, LMMM
                            SY <= SY + YCOUNTDELTA;
                        if (CMR[7:4] != LMCM)
                            DY <= DY + YCOUNTDELTA;
                    end else 
                        SXTMP[10] <= 1'b0;
                    INITIALIZING = 1'b0;
                end
                default: begin
                    STATE <= STIDLE;
                    CE <= 1'b0;
                    CMR <= '0;
                end
                endcase
            end

            if (VDPMODEGRAPHIC4)
                VRAMACCESSADDR <= {VDPVRAMACCESSY[9:0], VDPVRAMACCESSX[7:1]};
            else if (VDPMODEGRAPHIC5)
                VRAMACCESSADDR <= {VDPVRAMACCESSY[9:0], VDPVRAMACCESSX[8:2]};
            else if (VDPMODEGRAPHIC6)
                VRAMACCESSADDR <= {VDPVRAMACCESSY[8:0], VDPVRAMACCESSX[8:1]};
            else 
                VRAMACCESSADDR <= {VDPVRAMACCESSY[8:0], VDPVRAMACCESSX[7:0]};
        end 
    end

endmodule
