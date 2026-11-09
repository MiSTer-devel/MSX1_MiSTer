//
// Z80 compatible microprocessor core
//
// Version : 0250 (+k05) (+m01)
//
// Copyright (c) 2001-2002 Daniel Wallner (jesus@opencores.org)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
// The latest version of this file can be found at:
//  http://www.opencores.org/cvsweb.shtml/t80/
//
// Limitations :
//
// File history :
//
//  0208 : First complete release
//  0211 : Fixed IM 1
//  0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
//  0235 : Added IM 2 fix by Mike Johnson
//  0238 : Added NoRead signal
//  0238b: Fixed instruction timing for POP and DJNZ
//  0240 : Added (IX/IY+d) states, removed op-codes from mode 2 and added all remaining mode 3 op-codes
//  0242 : Fixed I/O instruction timing, cleanup
//  0242a: 31st of August, 2003 by Kazuhiro Tsujikawa (tujikawa@hat.hi-ho.ne.jp)
//         Fixed INI, IND, INIR, INDR, OUTI, OUTD, OTIR, OTDR instructions
//  0248 : Added undocumented DDCB and FDCB opcodes by TobiFlex 2010.04.20
//  0249 : Added undocumented XY-Flags for CPI/CPD by TobiFlex 2012.07.22
//  0250 : Added R800 Multiplier by TobiFlex 2017.10.15
//
//  +k01 : Version alignment by KdL 2010.10.25
//  +k02 : Added R800_mode signal by KdL 2018.05.14
//  +k03 : Version alignment by KdL 2019.05.20
//  +k04 : Separation of T800 from T80 by KdL 2021.02.01, then reverted on 2023.05.15
//  +k05 : Version alignment by KdL 2023.05.15
//
//  +m01 : Revrite to systemVerilog by Molekula 2025.01.26, original: https://github.com/gnogni/ocm-pld-dev.git 95aa5e2179f28c0d8028e17203909804ce6ff66b

module TV80_MCode #(
    parameter		    Mode      = 0,
                        R800_MULU = 1,                                      // 0 => no MULU, 1=> R800 MULU
            		    Flag_C    = 0,
            		    Flag_N    = 1,
            		    Flag_P    = 2,
            		    Flag_X    = 3,
            		    Flag_H    = 4,
            		    Flag_Y    = 5,
            		    Flag_Z    = 6,
            	    	Flag_S    = 7
)(
    input         [7:0] IR,
    input         [1:0] ISet,
    input         [2:0] MCycle,
    input         [7:0] F,
    input               NMICycle,
    input               IntCycle,
    input         [1:0] XY_State,
    output logic  [2:0] MCycles,
    output logic  [2:0] TStates,
    output logic  [1:0] Prefix,                                             // None,CB,ED,DD/FD
    output logic        Inc_PC,
    output logic        Inc_WZ,
    output logic  [3:0] IncDec_16,                                          // BC,DE,HL,SP   0 is inc
    output logic        Read_To_Reg,
    output logic        Read_To_Acc,
    output        [3:0] Set_BusA_To,                                        // B,C,D,E,H,L,DI/DB,A,SP(L),SP(M),0,F
    output        [3:0] Set_BusB_To,                                        // B,C,D,E,H,L,DI,A,SP(L),SP(M),1,F,PC(L),PC(M),0
    output        [3:0] ALU_Op,                                             // ADD, ADC, SUB, SBC, AND, XOR, OR, CP, ROT, BIT, SET, RES, DAA, RLD, RRD, None
    output              ALU_cpi,                                            // for undoc XY-Flags
    output              Save_ALU,
    output              PreserveC,
    output              Arith16,
    output        [2:0] Set_Addr_To,                                        // aNone,aXY,aIOA,aSP,aBC,aDE,aZI
    output              IORQ,
    output              Jump,
    output              JumpE,
    output              JumpXY,
    output              Call,
    output              RstP,
    output              LDZ,
    output              LDW,
    output              LDSPHL,
    output        [2:0] Special_LD,                                         // A,I;A,R;I,A;R,A;None
    output              ExchangeDH,
    output              ExchangeRp,
    output              ExchangeAF,
    output              ExchangeRS,
    output              I_DJNZ,
    output              I_CPL,
    output              I_CCF,
    output              I_SCF,
    output              I_RETN,
    output              I_BT,
    output              I_BC,
    output              I_BTR,
    output              I_RLD,
    output              I_RRD,
    output              I_INRC,
    output              I_MULUB,
    output              I_MULU,
    output              SetDI,
    output              SetEI,
    output        [1:0] IMode,
    output              Halt,
    output              NoRead,
    output              Write,
    output              XYbit_undoc,
    input               R800_mode
);

    localparam          aNone = 3'b111;
    localparam          aBC   = 3'b000;
    localparam          aDE   = 3'b001;
    localparam          aXY   = 3'b010;
    localparam          aIOA  = 3'b100;
    localparam          aSP   = 3'b101;
    localparam          aZI   = 3'b110;

    function is_cc_true(
        input [7:0] FF,
        input [2:0] cc
    );
        begin
            if (Mode == 3) begin
                case(cc)
                    3'b000: is_cc_true = ~FF[7];                                // NZ
                    3'b001: is_cc_true =  FF[7];                                // Z
                    3'b010: is_cc_true = ~FF[4];                                // NC
                    3'b011: is_cc_true =  FF[4];                                // C
                    3'b100: is_cc_true =  '0;
                    3'b101: is_cc_true =  '0;
                    3'b110: is_cc_true =  '0;
                    3'b111: is_cc_true =  '0;
                endcase
            end else begin
                case(cc)
                    3'b000: is_cc_true = ~FF[Flag_Z];                           // NZ
                    3'b001: is_cc_true =  FF[Flag_Z];                           // Z
                    3'b010: is_cc_true = ~FF[Flag_C];                           // NC
                    3'b011: is_cc_true =  FF[Flag_C];                           // C
                    3'b100: is_cc_true = ~FF[Flag_P];                           // PO
                    3'b101: is_cc_true =  FF[Flag_P];                           // PE
                    3'b110: is_cc_true = ~FF[Flag_S];                           // P
                    3'b111: is_cc_true =  FF[Flag_S];                           // N
                endcase
            end
        end
    endfunction

    always_comb begin
        logic [2:0] DDD;
        logic [2:0] SSS;
        logic [1:0] DPair;
        logic [7:0] IRB;

        DDD   = IR[5:3];
        SSS   = IR[2:0];
        DPair = IR[5:4];
        IRB   = IR;

        MCycles = 3'b001;
        if (MCycle == 3'b001) begin
            TStates = 3'b100;
        end else begin
            TStates = 3'b011;
        end

        Prefix      = 2'b00;
        Inc_PC      = '0;
        Inc_WZ      = '0;
        IncDec_16   = 4'b0000;
        Read_To_Acc = '0;
        Read_To_Reg = '0;
        Set_BusB_To = 4'b0000;
        Set_BusA_To = 4'b0000;
        ALU_Op      = {1'b0, IR[5:3]};
        ALU_cpi     = '0;
        Save_ALU    = '0;
        PreserveC   = '0;
        Arith16     = '0;
        IORQ        = '0;
        Set_Addr_To = aNone;
        Jump        = '0;
        JumpE       = '0;
        JumpXY      = '0;
        Call        = '0;
        RstP        = '0;
        LDZ         = '0;
        LDW         = '0;
        LDSPHL      = '0;
        Special_LD  = 3'b000;
        ExchangeDH  = '0;
        ExchangeRp  = '0;
        ExchangeAF  = '0;
        ExchangeRS  = '0;
        I_DJNZ      = '0;
        I_CPL       = '0;
        I_CCF       = '0;
        I_SCF       = '0;
        I_RETN      = '0;
        I_BT        = '0;
        I_BC        = '0;
        I_BTR       = '0;
        I_RLD       = '0;
        I_RRD       = '0;
        I_INRC      = '0;
        I_MULUB     = '0;
        I_MULU      = '0;
        SetDI       = '0;
        SetEI       = '0;
        IMode       = 2'b11;
        Halt        = '0;
        NoRead      = '0;
        Write       = '0;
        XYbit_undoc = '0;

        case(ISet)
            2'b00: begin                                                // Unprefixed instructions
                case(IRB)
// 8 BIT LOAD GROUP
                    8'b01000000,
                    8'b01000001,
                    8'b01000010,
                    8'b01000011,
                    8'b01000100,
                    8'b01000101,
                    8'b01000111,
                    8'b01001000,
                    8'b01001001,
                    8'b01001010,
                    8'b01001011,
                    8'b01001100,
                    8'b01001101,
                    8'b01001111,
                    8'b01010000,
                    8'b01010001,
                    8'b01010010,
                    8'b01010011,
                    8'b01010100,
                    8'b01010101,
                    8'b01010111,
                    8'b01011000,
                    8'b01011001,
                    8'b01011010,
                    8'b01011011,
                    8'b01011100,
                    8'b01011101,
                    8'b01011111,
                    8'b01100000,
                    8'b01100001,
                    8'b01100010,
                    8'b01100011,
                    8'b01100100,
                    8'b01100101,
                    8'b01100111,
                    8'b01101000,
                    8'b01101001,
                    8'b01101010,
                    8'b01101011,
                    8'b01101100,
                    8'b01101101,
                    8'b01101111,
                    8'b01111000,
                    8'b01111001,
                    8'b01111010,
                    8'b01111011,
                    8'b01111100,
                    8'b01111101,
                    8'b01111111: begin                                  // LD r,r'
                        Set_BusB_To[2:0] = SSS;
                        ExchangeRp = '1;
                        Set_BusA_To[2:0] = DDD;
                        Read_To_Reg = '1;
                    end
                    8'b00000110,
                    8'b00001110,
                    8'b00010110,
                    8'b00011110,
                    8'b00100110,
                    8'b00101110,
                    8'b00111110:  begin                                  // LD r,n
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; Set_BusA_To[2:0] = DDD; Read_To_Reg = '1; end
                            default: ;
                        endcase
                    end
                    8'b01000110,
                    8'b01001110,
                    8'b01010110,
                    8'b01011110,
                    8'b01100110,
                    8'b01101110,
                    8'b01111110: begin                                  // LD r,(HL)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: Set_Addr_To = aXY;
                            3'd2: begin Set_BusA_To[2:0] = DDD; Read_To_Reg = '1; end
                            default: ;
                        endcase
                    end
                    8'b01110000,
                    8'b01110001,
                    8'b01110010,
                    8'b01110011,
                    8'b01110100,
                    8'b01110101,
                    8'b01110111: begin                                  // LD (HL),r
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: begin Set_Addr_To = aXY; Set_BusB_To[2:0] = SSS; Set_BusB_To[3] = '0; end
                            3'd2: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00110110: begin                                  // LD (HL),n
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; Set_Addr_To = aXY; Set_BusB_To[2:0] = SSS; Set_BusB_To[3] = '0; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00001010: begin                                  // LD A,(BC)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: Set_Addr_To = aBC;
                            3'd2: Read_To_Acc = '1;
                            default: ;
                        endcase
                    end
                    8'b00011010: begin                                  // LD A,(DE)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: Set_Addr_To = aDE;
                            3'd2: Read_To_Acc = '1;
                            default: ;
                        endcase
                    end
                    8'b00111010: begin                                  // LDD A,(HL) || LD A,(nn)
                        if (Mode == 3) begin
                            MCycles = 3'd2;
                            case (MCycle)                               // LDD A,(HL)
                                3'd1: Set_Addr_To = aXY;
                                3'd2: begin Read_To_Acc = '1; IncDec_16 = 4'b1110; end
                                default: ;
                            endcase
                        end else begin
                            MCycles = 3'd4;                             // LD A,(nn)
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; LDZ = '1; end
                                3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; end
                                3'd4: Read_To_Acc = '1;
                                default: ;
                            endcase
                        end
                    end
                    8'b00000010: begin                                  // LD (BC),A
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: begin Set_Addr_To = aBC; Set_BusB_To = 4'b0111; end
                            3'd2: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00010010: begin                                  // LD (DE),A
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: begin Set_Addr_To = aDE; Set_BusB_To = 4'b0111; end
                            3'd2: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00110010: begin                                  // LDD (HL),A || LD (nn),A
                        if (Mode == 3) begin
                            MCycles = 3'd2;
                            case (MCycle)                               // LDD A,(HL)
                                3'd1: begin Set_Addr_To = aXY; Set_BusB_To = 4'b0111; end
                                3'd2: begin Write = '1; IncDec_16 = 4'b1110; end
                                default: ;
                            endcase
                        end else begin
                            MCycles = 3'd4;                             // LD A,(nn)
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; LDZ = '1; end
                                3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; Set_BusB_To = 4'b0111; end
                                3'd4: Write = '1;
                                default: ;
                            endcase
                        end
                    end
// 16 BIT LOAD GROUP
                    8'b00000001,
                    8'b00010001,
                    8'b00100001,
                    8'b00110001: begin
                        MCycles = 3'd3;                                 // LD dd,nn
                        case (MCycle)
                            3'd2: begin
                                Inc_PC = '1;
                                Read_To_Reg = '1;
                                if (DPair == 2'b11) begin
                                    Set_BusA_To[3:0] = 4'b1000;
                                end else begin
                                    Set_BusA_To[2:1] = DPair;
                                    Set_BusA_To[0] = '1;
                                end
                            end
                            3'd3: begin
                                Inc_PC = '1;
                                Read_To_Reg = '1;
                                if( DPair == 2'b11) begin
                                    Set_BusA_To[3:0] = 4'b1001;
                                end else begin
                                        Set_BusA_To[2:1] = DPair;
                                        Set_BusA_To[0] = '0;
                                end
                            end
                            default: ;
                        endcase
                    end
                    8'b00101010: begin                                  // LDI A,(HL) || LD HL,(nn)
                        if (Mode == 3) begin
                            MCycles = 3'd2;
                            case (MCycle)                               // LDI A,(HL)
                                3'd1: Set_Addr_To = aXY;
                                3'd2: begin Read_To_Acc = '1; IncDec_16 = 4'b0110; end
                                default: ;
                            endcase
                        end else begin
                            MCycles = 3'd5;                             // LD HL,(nn)
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; LDZ = '1; end
                                3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; LDW = '1; end
                                3'd4: begin Set_BusA_To[2:0] = 3'b101; Read_To_Reg = '1; Inc_WZ = '1; Set_Addr_To = aZI; end // L
                                3'd5: begin Set_BusA_To[2:0] = 3'b100; Read_To_Reg = '1; end // H
                                default: ;
                            endcase
                        end
                    end
                    8'b00100010: begin                                  // LDI (HL),A || LD (nn),HL
                        if (Mode == 3) begin
                            MCycles = 3'd2;
                            case (MCycle)                               // LDI (HL),A
                                3'd1: begin Set_Addr_To = aXY; Set_BusB_To = 4'b0111; end
                                3'd2: begin Write = '1; IncDec_16 = 4'b0110; end
                                default: ;
                            endcase
                        end else begin
                            MCycles = 3'd5;                             // LD (nn),HL
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; LDZ = '1; end
                                3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; LDW = '1; Set_BusB_To = 4'b0101; end   // L
                                3'd4: begin Inc_WZ = '1; Set_Addr_To = aZI; Write = '1; Set_BusB_To = 4'b0100; end // H
                                3'd5: Write = '1;
                                default: ;
                            endcase
                        end
                    end
                    8'b11111001: begin                                  // LD SP,HL
                        TStates = 3'd6;
                        LDSPHL = '1;
                    end
                    8'b11000101,
                    8'b11010101,
                    8'b11100101,
                    8'b11110101: begin                                  // PUSH qq
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: begin
                                TStates     = 3'd5;
                                IncDec_16   = 4'b1111;
                                Set_Addr_To = aSP;
                                if (DPair == 2'b11) begin
                                    Set_BusB_To = 4'b0111;
                                end else begin
                                    Set_BusB_To[2:1] = DPair;
                                    Set_BusB_To[0]   = '0;
                                    Set_BusB_To[3]   = '0;
                                end
                            end
                            3'd2: begin
                                IncDec_16   = 4'b1111;
                                Set_Addr_To = aSP;
                                if (DPair == 2'b11) begin
                                    Set_BusB_To = 4'b1011;
                                end else begin
                                    Set_BusB_To[2:1] = DPair;
                                    Set_BusB_To[0]   = '1;
                                    Set_BusB_To[3]   = '0;
                                end
                                Write = '1;
                            end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b11000001,
                    8'b11010001,
                    8'b11100001,
                    8'b11110001: begin                                  // POP qq
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: Set_Addr_To = aSP;
                            3'd2: begin
                                IncDec_16   = 4'b0111;
                                Set_Addr_To = aSP;
                                Read_To_Reg = '1;
                                if (DPair == 2'b11) begin
                                    Set_BusA_To = 4'b1011;
                                end else begin
                                    Set_BusA_To[2:1] = DPair;
                                    Set_BusA_To[0]   = '1;
                                end
                            end
                            3'd3: begin
                                IncDec_16   = 4'b0111;
                                Read_To_Reg = '1;
                                if (DPair == 2'b11) begin
                                    Set_BusA_To = 4'b0111;
                                end else begin
                                    Set_BusA_To[2:1] = DPair;
                                    Set_BusA_To[0]   = '0;
                                end
                            end
                            default: ;
                        endcase
                    end
// EXCHANGE, BLOCK TRANSFER AND SEARCH GROUP
                    8'b11101011: begin                                  // EX DE,HL
                        if (Mode != 3) begin
                            ExchangeDH = '1;
                        end
                    end
                    8'b00001000: begin                                  // LD (nn),SP || EX AF,AF'
                        if (Mode == 3) begin
                            MCycles = 3'd5;
                            case (MCycle)                               // LD (nn),SP
                                3'd2: begin Inc_PC = '1; LDZ = '1; end
                                3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; LDW = '1; Set_BusB_To = 4'b1000; end
                                3'd4: begin Inc_WZ = '1; Set_Addr_To = aZI; Write = '1; Set_BusB_To = 4'b1001; end
                                3'd5: Write = '1;
                                default: ;
                            endcase
                        end else begin
                            if (Mode < 2 ) begin                        // EX AF,AF'
                                ExchangeAF = '1;
                            end
                        end
                    end
                    8'b11011001: begin                                  // RETI || EXX
                        if (Mode == 3) begin
                            MCycles = 3'd5;
                            case (MCycle)                               // RETI
                                3'd1: Set_Addr_To = aSP;
                                3'd2: begin IncDec_16 = 4'b0111; Set_Addr_To = aSP; LDZ = '1; end
                                3'd3: begin Jump = '1; IncDec_16 = 4'b0111; I_RETN = '1; SetEI = '1; end
                                default: ;
                            endcase
                        end else begin
                            if (Mode < 2 ) begin                        // EXX
                                ExchangeRS = '1;
                            end
                        end
                    end
                    8'b11100011: begin                                  // EX (SP),HL
                        if (Mode != 3) begin
                            MCycles = 3'd5;
                            case (MCycle)
                                3'd1: Set_Addr_To = aSP;
                                3'd2: begin Read_To_Reg = '1; Set_BusA_To = 4'b0101; Set_BusB_To = 4'b0101; Set_Addr_To = aSP; end
                                3'd3: begin IncDec_16 = 4'b0111;Set_Addr_To = aSP; TStates = 3'd4; Write = '1; end
                                3'd4: begin Read_To_Reg = '1; Set_BusA_To = 4'b0100; Set_BusB_To = 4'b0100; Set_Addr_To = aSP; end
                                3'd5: begin IncDec_16 = 4'b1111; TStates = 3'd5; Write = '1; end
                                default: ;
                            endcase
                        end
                    end
// 8 BIT ARITHMETIC AND LOGICAL GROUP
                    8'b10000000,
                    8'b10000001,
                    8'b10000010,
                    8'b10000011,
                    8'b10000100,
                    8'b10000101,
                    8'b10000111,
                    8'b10001000,
                    8'b10001001,
                    8'b10001010,
                    8'b10001011,
                    8'b10001100,
                    8'b10001101,
                    8'b10001111,
                    8'b10010000,
                    8'b10010001,
                    8'b10010010,
                    8'b10010011,
                    8'b10010100,
                    8'b10010101,
                    8'b10010111,
                    8'b10011000,
                    8'b10011001,
                    8'b10011010,
                    8'b10011011,
                    8'b10011100,
                    8'b10011101,
                    8'b10011111,
                    8'b10100000,
                    8'b10100001,
                    8'b10100010,
                    8'b10100011,
                    8'b10100100,
                    8'b10100101,
                    8'b10100111,
                    8'b10101000,
                    8'b10101001,
                    8'b10101010,
                    8'b10101011,
                    8'b10101100,
                    8'b10101101,
                    8'b10101111,
                    8'b10110000,
                    8'b10110001,
                    8'b10110010,
                    8'b10110011,
                    8'b10110100,
                    8'b10110101,
                    8'b10110111,
                    8'b10111000,
                    8'b10111001,
                    8'b10111010,
                    8'b10111011,
                    8'b10111100,
                    8'b10111101,
                    8'b10111111: begin                                  // ADD A,r, ADC A,r, SUB A,r, SBC A,r, AND A,r, OR A,r, XOR A,r, CP A,r
                        Set_BusB_To[2:0] = SSS;
                        Set_BusA_To[2:0] = 3'b111;
                        Read_To_Reg = '1;
                        Save_ALU    = '1;
                    end
                    8'b10000110,
                    8'b10001110,
                    8'b10010110,
                    8'b10011110,
                    8'b10100110,
                    8'b10101110,
                    8'b10110110,
                    8'b10111110: begin                                  // ADD A,(HL), ADC A,(HL), SUB A,(HL), SBC A,(HL), AND A,(HL), OR A,(HL), XOR A,(HL), CP A,(HL)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: Set_Addr_To = aXY;
                            3'd2: begin Read_To_Reg = '1; Save_ALU = '1;  Set_BusB_To[2:0] = SSS; Set_BusA_To[2:0] = 3'b111; end
                            default: ;
                        endcase
                    end
                    8'b11000110,
                    8'b11001110,
                    8'b11010110,
                    8'b11011110,
                    8'b11100110,
                    8'b11101110,
                    8'b11110110,
                    8'b11111110: begin                                  // ADD A,n, ADC A,n, SUB A,n, SBC A,n, AND A,n, OR A,n, XRO A,n, CP A,n
                        MCycles = 3'd2;
                        if (MCycle == 3'd2) begin
                            Inc_PC = '1;
                            Read_To_Reg = '1;
                            Save_ALU = '1;
                            Set_BusB_To[2:0] = SSS;
                            Set_BusA_To[2:0] = 3'b111;
                        end
                    end
                    8'b00110100: begin                                  // INC (HL)
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: Set_Addr_To = aXY;
                            3'd2: begin TStates = 3'd4; Set_Addr_To = aXY;  Read_To_Reg = '1; Save_ALU = '1; PreserveC = '1; ALU_Op = 4'b0000; Set_BusB_To = 4'b1010; Set_BusA_To[2:0] = DDD; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00000100,
                    8'b00001100,
                    8'b00010100,
                    8'b00011100,
                    8'b00100100,
                    8'b00101100,
                    8'b00111100: begin                                  // INC r
                        Set_BusB_To = 4'b1010;
                        Set_BusA_To[2:0]= DDD;
                        Read_To_Reg = '1;
                        Save_ALU = '1;
                        PreserveC = '1;
                        ALU_Op = 4'b0000;
                    end
                    8'b00110101: begin                                  // DEC (HL)
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: Set_Addr_To = aXY;
                            3'd2: begin TStates = 3'd4; Set_Addr_To = aXY;  ALU_Op = 4'b0010; Read_To_Reg = '1; Save_ALU = '1; PreserveC = '1;  Set_BusB_To = 4'b1010; Set_BusA_To[2:0] = DDD; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b00000101,
                    8'b00001101,
                    8'b00010101,
                    8'b00011101,
                    8'b00100101,
                    8'b00101101,
                    8'b00111101: begin                                  // DEC r
                        Set_BusB_To = 4'b1010;
                        Set_BusA_To[2:0]= DDD;
                        Read_To_Reg = '1;
                        Save_ALU = '1;
                        PreserveC = '1;
                        ALU_Op = 4'b0010;
                    end
// GENERAL PURPOSE ARITHMETIC AND CPU CONTROL GROUPS
                    8'b00100111: begin                                  // DAA
                        Set_BusA_To[2:0]= 3'b111;
                        Read_To_Reg = '1;
                        ALU_Op = 4'b1100;
                        Save_ALU = '1;
                    end
                    8'b00101111: begin                                  // CPL
                        I_CPL = '1;
                    end
                    8'b00111111: begin                                  // CCF
                        I_CCF = '1;
                    end
                    8'b00110111: begin                                  // SCF
                        I_SCF = '1;
                    end
                    8'b00000000: begin                                  // NMI || INT (IM2) || NOP
                        if (NMICycle) begin
                            // NMI: M1 + two 3 T writes of PC = 11 T (Zilog); 5 cycles made it 17 T
                            MCycles = 3'd3;
                            case (MCycle)                               // NMI
                                3'd1: begin TStates = 3'd5; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1101; end
                                3'd2: begin Write = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP;  Set_BusB_To = 4'b1100; end
                                3'd3: begin Write = '1; end
                                default: ;
                            endcase
                        end else begin
                            if (IntCycle) begin
                                MCycles = 3'd5;
                                // IM2: M1 (5 T + 2 wait) + 3 + 3 (push PC) + 3 + 3 (vector) = 19 T (Zilog)
                                case (MCycle)
                                    3'd1: begin TStates = 3'd5; LDZ = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1101; end
                                    3'd2: begin Write = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP;  Set_BusB_To = 4'b1100; end
                                    3'd3: begin Write = '1; end
                                    3'd4: begin Inc_PC = '1; LDZ = '1; end
                                    3'd5: Jump = '1;
                                    default: ;
                                endcase
                            end else begin                              // NOP
                                ;
                            end
                        end
                    end
                    8'b01110110: begin                                  // HALT
                        Halt = '1;
                    end
                    8'b11110011: begin                                  // DI
                        SetDI = '1;
                    end
                    8'b11111011: begin                                  // EI
                        SetEI = '1;
                    end
// 16 BIT ARITHMETIC GROUP
                    8'b00001001,
                    8'b00011001,
                    8'b00101001,
                    8'b00111001: begin                                  // ADD HL,ss
                    MCycles = 3'd3;
                        case (MCycle)
                            3'd2: begin
                                NoRead = '1;
                                ALU_Op = 4'b0000;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                Set_BusA_To[2:0] = 3'b101;
                                case (IR[5:4])
                                    2'b00,
                                    2'b01,
                                    2'b10: begin
                                        Set_BusB_To[2:1] = IR[5:4];
                                        Set_BusB_To[0] = '1;
                                    end
                                    default: begin
                                        Set_BusB_To = 4'b1000;
                                    end
                                endcase
                                TStates = 3'd4;
                                Arith16 = '1;
                            end
                            3'd3: begin
                                NoRead = '1;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                ALU_Op = 4'b0001;
                                Set_BusA_To[2:0] = 3'b100;
                                case (IR[5:4])
                                    2'b00,
                                    2'b01,
                                    2'b10: begin
                                        Set_BusB_To[2:1] = IR[5:4];
                                    end
                                    default : begin
                                        Set_BusB_To = 4'b1001;
                                    end
                                endcase
                                Arith16 = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b00000011,
                    8'b00010011,
                    8'b00100011,
                    8'b00110011:  begin                                 // INC ss
                        TStates = 3'd6;
                        IncDec_16[3:2] = 2'b01;
                        IncDec_16[1:0] = DPair;
                    end
                    8'b00001011,
                    8'b00011011,
                    8'b00101011,
                    8'b00111011:  begin                                 // DEC ss
                        TStates = 3'd6;
                        IncDec_16[3:2] = 2'b11;
                        IncDec_16[1:0] = DPair;
                    end
// ROTATE AND SHIFT GROUP
                    8'b00000111,
                    8'b00010111,
                    8'b00001111,
                    8'b00011111: begin                                  // RLCA || RLA || RRCA || RRA
                        Set_BusA_To[2:0] = 3'b111;
                        ALU_Op = 4'b1000;
                        Read_To_Reg = '1;
                        Save_ALU = '1;
                    end
// JUMP GROUP
                    8'b11000011: begin                                  // JP nn
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; LDZ = '1; end
                            3'd3: begin Inc_PC = '1; Jump = '1; end
                            default: ;
                        endcase
                    end
                    8'b11000010,
                    8'b11001010,
                    8'b11010010,
                    8'b11011010,
                    8'b11100010,
                    8'b11101010,
                    8'b11110010,
                    8'b11111010: begin                                  // LD ($FF00+C),A || LD (nn),A || LD A,($FF00+C) || LD A,(nn) || JP cc,nn
                        if (IR[5] && Mode == 3) begin
                            case (IRB[4:3])
                                2'b00: begin                            // LD ($FF00+C),A
                                    MCycles = 3'd2;
                                    case (MCycle)
                                        3'd1: begin Set_Addr_To = aBC; Set_BusB_To = 4'b0111; end
                                        3'd2: begin Write = '1; IORQ = '1; end
                                        default: ;
                                    endcase
                                end
                                2'b01: begin                            // LD (nn),A
                                    MCycles = 3'd4;
                                    case (MCycle)
                                        3'd2: begin Inc_PC = '1; LDZ = '1; end
                                        3'd3: begin Inc_PC = '1; Set_Addr_To = aZI; Set_BusB_To = 4'b0111; end
                                        3'd4: begin Write = '1; end
                                        default: ;
                                    endcase
                                end
                                2'b10: begin                            // LD A,($FF00+C)
                                    MCycles = 3'd2;
                                    case (MCycle)
                                        3'd1: Set_Addr_To = aBC;
                                        3'd2: begin Read_To_Acc = '1; IORQ = '1; end
                                        default: ;
                                    endcase
                                end
                                2'b11: begin                            // LD A,(nn)
                                    MCycles = 3'd4;
                                    case (MCycle)
                                        3'd2: begin Inc_PC = '1; LDZ = '1; end
                                        3'd3: begin Inc_PC = '1; Set_Addr_To = aZI; end
                                        3'd4: Read_To_Acc = '1;
                                        default: ;
                                    endcase
                                end
                            endcase
                        end else begin
                            MCycles = 3'd3;
                            case (MCycle)                               // JP cc,nn
                                3'd2: begin
                                    Inc_PC = '1;
                                    LDZ = '1;
                                end
                                3'd3: begin
                                    Inc_PC = '1;
                                    if (is_cc_true(F, IR[5:3])) begin
                                        Jump = '1;
                                    end
                                end
                                default: ;
                            endcase
                        end
                    end
                    8'b00011000: begin                                  // JR e
                        if (Mode != 2) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: Inc_PC = '1;
                                3'd3: begin NoRead = '1; JumpE = '1; TStates = 3'd5; end
                                default: ;
                            endcase
                        end
                    end
                    8'b00111000: begin                                  // JR C,e
                        if (Mode != 2) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin
                                    Inc_PC = '1;
                                    if (~F[Flag_C]) begin
                                        MCycles = 3'd2;
                                    end
                                end
                                3'd3: begin
                                    NoRead = '1;
                                    JumpE = '1;
                                    TStates = 3'd5;
                                end
                                default: ;
                            endcase
                        end
                    end
                    8'b00110000: begin                                  // JR NC,e
                        if (Mode != 2) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin
                                    Inc_PC = '1;
                                    if (F[Flag_C]) begin
                                        MCycles = 3'd2;
                                    end
                                end
                                3'd3: begin
                                    NoRead = '1;
                                    JumpE = '1;
                                    TStates = 3'd5;
                                end
                                default: ;
                            endcase
                        end
                    end
                    8'b00101000: begin                                  // JR Z,e
                        if (Mode != 2) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin
                                    Inc_PC = '1;
                                    if (~F[Flag_Z]) begin
                                        MCycles = 3'd2;
                                    end
                                end
                                3'd3: begin
                                    NoRead = '1;
                                    JumpE = '1;
                                    TStates = 3'd5;
                                end
                                default: ;
                            endcase
                        end
                    end
                    8'b00100000: begin                                  // JR NZ,e
                        if (Mode != 2) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin
                                    Inc_PC = '1;
                                    if (F[Flag_Z]) begin
                                        MCycles = 3'd2;
                                    end
                                end
                                3'd3: begin
                                    NoRead = '1;
                                    JumpE = '1;
                                    TStates = 3'd5;
                                end
                                default: ;
                            endcase
                        end
                    end
                    8'b11101001: begin                                  // JP (HL)
                        JumpXY = '1;
                    end
                    8'b00010000: begin                                  // DJNZ,e
                        if (Mode == 3) begin
                            I_DJNZ = '1;
                        end else begin
                            if (Mode < 2) begin
                                MCycles = 3'd3;
                                case (MCycle)
                                    3'd1: begin TStates = 3'd5; I_DJNZ = '1; Set_BusB_To = 4'b1010; Set_BusA_To[2:0] = 3'b000; Read_To_Reg = '1; Save_ALU = '1; ALU_Op = 4'b0010; end
                                    3'd2: begin I_DJNZ = '1; Inc_PC = '1; end
                                    3'd3: begin NoRead = '1; JumpE = '1; TStates = 3'd5; end
                                    default: ;
                                endcase
                            end
                        end
                    end
// CALL AND RETURN GROUP
                    8'b11001101: begin                                  // CALL nn
                        MCycles = 3'd5;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; LDZ = '1; end
                            3'd3: begin IncDec_16 = 4'b1111; Inc_PC = '1; TStates = 3'd4; Set_Addr_To = aSP; LDW = '1; Set_BusB_To = 4'b1101; end
                            3'd4: begin Write = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1100; end
                            3'd5: begin Write = '1; Call = '1; end
                            default: ;
                        endcase
                    end
                    8'b11000100,
                    8'b11001100,
                    8'b11010100,
                    8'b11011100,
                    8'b11100100,
                    8'b11101100,
                    8'b11110100,
                    8'b11111100: begin                                  // CALL cc,nn
                        MCycles = 3'd5;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; LDZ = '1; end
                            3'd3: begin
                                Inc_PC = '1;
                                LDW = '1;
                                if (is_cc_true(F, IR[5:3])) begin
                                    IncDec_16 = 4'b1111;
                                    Set_Addr_To = aSP;
                                    TStates = 3'd4;
                                    Set_BusB_To = 4'b1101;
                                end else begin
                                    MCycles = 3'd3;
                                end
                            end
                            3'd4: begin Write = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1100; end
                            3'd5: begin Write = '1; Call = '1; end
                            default: ;
                        endcase
                    end
                    8'b11001001: begin                                  // RET
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: begin TStates = 3'd5; Set_Addr_To = aSP; end
                            3'd2: begin IncDec_16 = 4'b0111; Set_Addr_To = aSP; LDZ = '1; end
                            3'd3: begin Jump = '1; IncDec_16 = 4'b0111; end
                            default: ;
                        endcase
                    end
                    8'b11000000,
                    8'b11001000,
                    8'b11010000,
                    8'b11011000,
                    8'b11100000,
                    8'b11101000,
                    8'b11110000,
                    8'b11111000: begin                                  // LD ($FF00+nn),A || ADD SP,n || LD A,($FF00+nn) || LD HL,SP+n || RET cc
                        if (IR[5] && Mode == 3) begin
                            case (IRB[4:3])
                                2'b00: begin                            // LD ($FF00+nn),A
                                    MCycles = 3'd3;
                                    case (MCycle)
                                        3'd2: begin Inc_PC = '1; Set_Addr_To = aIOA; Set_BusB_To = 4'b0111; end
                                        3'd3: begin Write = '1; end
                                        default: ;
                                    endcase
                                end
                                2'b01: begin                            // ADD SP,n
                                    MCycles = 3'd3;
                                    case (MCycle)
                                        3'd2: begin ALU_Op = 4'b0000; Inc_PC = '1; Read_To_Reg = '1; Save_ALU = '1; Set_BusA_To = 4'b1000; Set_BusB_To = 4'b0110; end
                                        3'd3: begin NoRead = '1; Read_To_Reg = '1; Save_ALU = '1; ALU_Op = 4'b0001; Set_BusA_To = 4'b1001; Set_BusB_To = 4'b1110; end
                                        default: ;
                                    endcase
                                end
                                2'b10: begin                            // LD A,($FF00+nn)
                                    MCycles = 3'd3;
                                    case (MCycle)
                                        3'd2: begin Inc_PC = '1; Set_Addr_To = aIOA; end
                                        3'd3: begin Read_To_Acc = '1; end
                                        default: ;
                                    endcase
                                end
                                2'b11: begin                            // LD HL,SP+n   -- Not correct !!!!!!!!!!!!!!!!!!!
                                    MCycles = 3'd5;
                                    case (MCycle)
                                        3'd2: begin Inc_PC = '1; LDZ = '1; end
                                        3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; LDW = '1; end
                                        3'd4: begin Set_BusA_To[2:0] = 3'b101; Read_To_Reg = '1; Inc_WZ = '1; Set_Addr_To = aZI; end
                                        3'd5: begin Set_BusA_To[2:0] = 3'b100; Read_To_Reg = '1; end
                                        default: ;
                                    endcase
                                end
                            endcase
                        end else begin
                            MCycles = 3'd3;
                            case (MCycle)                               // RET cc
                                3'd1: begin
                                    if (is_cc_true(F, IR[5:3])) begin
                                        Set_Addr_To = aSP;
                                    end else begin
                                        MCycles = 3'd1;
                                    end
                                    TStates = 3'd5;
                                end
                                3'd2: begin IncDec_16 = 4'b0111; Set_Addr_To = aSP; LDZ = '1; end
                                3'd3: begin Jump = '1; IncDec_16 = 4'b0111; end
                                default: ;
                            endcase
                        end
                    end
                    8'b11000111,
                    8'b11001111,
                    8'b11010111,
                    8'b11011111,
                    8'b11100111,
                    8'b11101111,
                    8'b11110111,
                    8'b11111111: begin                                  // RST p
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: begin TStates = 3'd5; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1101; end
                            3'd2: begin Write = '1; IncDec_16 = 4'b1111; Set_Addr_To = aSP; Set_BusB_To = 4'b1100; end
                            3'd3: begin Write = '1; RstP = '1; end
                            default: ;
                        endcase
                    end
// INPUT AND OUTPUT GROUP
                    8'b11011011: begin                                  // IN A,(n)
                        if (Mode != 3) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; Set_Addr_To = aIOA; end
                                3'd3: begin Read_To_Acc = '1; IORQ = '1; end
                                default: ;
                            endcase
                        end
                    end
                    8'b11010011: begin                                  // OUT (n),A
                        if (Mode != 3) begin
                            MCycles = 3'd3;
                            case (MCycle)
                                3'd2: begin Inc_PC = '1; Set_Addr_To = aIOA; Set_BusB_To = 4'b0111; end
                                3'd3: begin Write = '1; IORQ = '1; end
                                default: ;
                            endcase
                        end
                    end
// MULTIBYTE INSTRUCTIONS
                    8'b11001011: begin
                        if (Mode != 2) begin
                            Prefix = 2'b01;
                        end
                    end
                    8'b11101101: begin
                        if (Mode < 2) begin
                            Prefix = 2'b10;
                        end
                    end
                    8'b11011101,
                    8'b11111101: begin
                        if (Mode != 2) begin
                            Prefix = 2'b11;
                        end
                    end
						  default: ;
                endcase
            end
            2'b01: begin                                                // CB prefixed instructions
                Set_BusA_To[2:0] = IR[2:0];
                Set_BusB_To[2:0] = IR[2:0];
                case (IRB)
                    8'b00000000,
                    8'b00000001,
                    8'b00000010,
                    8'b00000011,
                    8'b00000100,
                    8'b00000101,
                    8'b00000111,
                    8'b00010000,
                    8'b00010001,
                    8'b00010010,
                    8'b00010011,
                    8'b00010100,
                    8'b00010101,
                    8'b00010111,
                    8'b00001000,
                    8'b00001001,
                    8'b00001010,
                    8'b00001011,
                    8'b00001100,
                    8'b00001101,
                    8'b00001111,
                    8'b00011000,
                    8'b00011001,
                    8'b00011010,
                    8'b00011011,
                    8'b00011100,
                    8'b00011101,
                    8'b00011111,
                    8'b00100000,
                    8'b00100001,
                    8'b00100010,
                    8'b00100011,
                    8'b00100100,
                    8'b00100101,
                    8'b00100111,
                    8'b00101000,
                    8'b00101001,
                    8'b00101010,
                    8'b00101011,
                    8'b00101100,
                    8'b00101101,
                    8'b00101111,
                    8'b00110000,
                    8'b00110001,
                    8'b00110010,
                    8'b00110011,
                    8'b00110100,
                    8'b00110101,
                    8'b00110111,
                    8'b00111000,
                    8'b00111001,
                    8'b00111010,
                    8'b00111011,
                    8'b00111100,
                    8'b00111101,
                    8'b00111111: begin                                  // RLC r || RL r || RRC r || RR r || SRA r || SRL r || SLA r || SLL r / SWAP r
                        if (XY_State == 2'b00) begin
                            if (MCycle == 3'd1) begin
                                ALU_Op = 4'b1000;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                            end
                        end else begin                                  // R/S (IX+d),Reg, undocumented
                            MCycles = 3'd3;
                            XYbit_undoc = '1;
                            case (MCycle)
                                3'd1,
                                3'd7: Set_Addr_To = aXY;                // TODO what 7
                                3'd2: begin ALU_Op = 4'b1000; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                                3'd3: Write = '1;
                                default: ;
                            endcase
                        end
                    end
                    8'b00000110,
                    8'b00010110,
                    8'b00001110,
                    8'b00011110,
                    8'b00101110,
                    8'b00111110,
                    8'b00100110,
                    8'b00110110: begin                                  // RLC (HL) || RL (HL) || RRC (HL) || RR (HL) || SRA (HL) || SRL (HL) || SLA (HL) || SLL (HL) / SWAP (HL)
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1,
                            3'd7: Set_Addr_To = aXY;                    // TODO what 7
                            3'd2: begin ALU_Op = 4'b1000; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b01000000,
                    8'b01000001,
                    8'b01000010,
                    8'b01000011,
                    8'b01000100,
                    8'b01000101,
                    8'b01000111,
                    8'b01001000,
                    8'b01001001,
                    8'b01001010,
                    8'b01001011,
                    8'b01001100,
                    8'b01001101,
                    8'b01001111,
                    8'b01010000,
                    8'b01010001,
                    8'b01010010,
                    8'b01010011,
                    8'b01010100,
                    8'b01010101,
                    8'b01010111,
                    8'b01011000,
                    8'b01011001,
                    8'b01011010,
                    8'b01011011,
                    8'b01011100,
                    8'b01011101,
                    8'b01011111,
                    8'b01100000,
                    8'b01100001,
                    8'b01100010,
                    8'b01100011,
                    8'b01100100,
                    8'b01100101,
                    8'b01100111,
                    8'b01101000,
                    8'b01101001,
                    8'b01101010,
                    8'b01101011,
                    8'b01101100,
                    8'b01101101,
                    8'b01101111,
                    8'b01110000,
                    8'b01110001,
                    8'b01110010,
                    8'b01110011,
                    8'b01110100,
                    8'b01110101,
                    8'b01110111,
                    8'b01111000,
                    8'b01111001,
                    8'b01111010,
                    8'b01111011,
                    8'b01111100,
                    8'b01111101,
                    8'b01111111: begin                                  // BIT b,r || BIT b,(IX+d)
                        if (XY_State == 2'b00) begin                    // BIT b,r
                            if (MCycle == 3'd1) begin
                                Set_BusB_To[2:0] = IR[2:0];
                                ALU_Op = 4'b1001;
                            end
                        end else begin                                  // BIT b,(IX+d), undocumented
                            MCycles = 3'd2;
                            XYbit_undoc = '1;
                            case (MCycle)
                                3'd1,
                                3'd7: Set_Addr_To = aXY;                // TODO what 7
                                3'd2: begin ALU_Op = 4'b1001; TStates = 3'd4; end
                                default: ;
                            endcase
                        end
                    end
                    8'b01000110,
                    8'b01001110,
                    8'b01010110,
                    8'b01011110,
                    8'b01100110,
                    8'b01101110,
                    8'b01110110,
                    8'b01111110: begin                                  // BIT b,(HL)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1,
                            3'd7: Set_Addr_To = aXY;                    // TODO what 7
                            3'd2: begin ALU_Op = 4'b1001; TStates = 3'd4; end
                            default: ;
                        endcase
                    end
                    8'b11000000,
                    8'b11000001,
                    8'b11000010,
                    8'b11000011,
                    8'b11000100,
                    8'b11000101,
                    8'b11000111,
                    8'b11001000,
                    8'b11001001,
                    8'b11001010,
                    8'b11001011,
                    8'b11001100,
                    8'b11001101,
                    8'b11001111,
                    8'b11010000,
                    8'b11010001,
                    8'b11010010,
                    8'b11010011,
                    8'b11010100,
                    8'b11010101,
                    8'b11010111,
                    8'b11011000,
                    8'b11011001,
                    8'b11011010,
                    8'b11011011,
                    8'b11011100,
                    8'b11011101,
                    8'b11011111,
                    8'b11100000,
                    8'b11100001,
                    8'b11100010,
                    8'b11100011,
                    8'b11100100,
                    8'b11100101,
                    8'b11100111,
                    8'b11101000,
                    8'b11101001,
                    8'b11101010,
                    8'b11101011,
                    8'b11101100,
                    8'b11101101,
                    8'b11101111,
                    8'b11110000,
                    8'b11110001,
                    8'b11110010,
                    8'b11110011,
                    8'b11110100,
                    8'b11110101,
                    8'b11110111,
                    8'b11111000,
                    8'b11111001,
                    8'b11111010,
                    8'b11111011,
                    8'b11111100,
                    8'b11111101,
                    8'b11111111: begin                                  // SET b,r || SET b,(IX+d),Reg,
                        if (XY_State == 2'b00) begin                    // SET b,r
                            if (MCycle == 3'd1) begin
                                ALU_Op = 4'b1010;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                            end
                        end else begin                                  // SET b,(IX+d),Reg, undocumented
                            MCycles = 3'd3;
                            XYbit_undoc = '1;
                            case (MCycle)
                                3'd1,
                                3'd7: Set_Addr_To = aXY;                // TODO what 7
                                3'd2: begin ALU_Op = 4'b1010; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                                3'd3: Write = '1;
                                default: ;
                            endcase
                        end
                    end
                    8'b11000110,
                    8'b11001110,
                    8'b11010110,
                    8'b11011110,
                    8'b11100110,
                    8'b11101110,
                    8'b11110110,
                    8'b11111110: begin                                  // SET b,(HL)
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1,
                            3'd7: Set_Addr_To = aXY;                    // TODO what 7
                            3'd2: begin ALU_Op = 4'b1010; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
                    8'b10000000,
                    8'b10000001,
                    8'b10000010,
                    8'b10000011,
                    8'b10000100,
                    8'b10000101,
                    8'b10000111,
                    8'b10001000,
                    8'b10001001,
                    8'b10001010,
                    8'b10001011,
                    8'b10001100,
                    8'b10001101,
                    8'b10001111,
                    8'b10010000,
                    8'b10010001,
                    8'b10010010,
                    8'b10010011,
                    8'b10010100,
                    8'b10010101,
                    8'b10010111,
                    8'b10011000,
                    8'b10011001,
                    8'b10011010,
                    8'b10011011,
                    8'b10011100,
                    8'b10011101,
                    8'b10011111,
                    8'b10100000,
                    8'b10100001,
                    8'b10100010,
                    8'b10100011,
                    8'b10100100,
                    8'b10100101,
                    8'b10100111,
                    8'b10101000,
                    8'b10101001,
                    8'b10101010,
                    8'b10101011,
                    8'b10101100,
                    8'b10101101,
                    8'b10101111,
                    8'b10110000,
                    8'b10110001,
                    8'b10110010,
                    8'b10110011,
                    8'b10110100,
                    8'b10110101,
                    8'b10110111,
                    8'b10111000,
                    8'b10111001,
                    8'b10111010,
                    8'b10111011,
                    8'b10111100,
                    8'b10111101,
                    8'b10111111: begin                                  // RES b,r || RES b,(IX+d),Reg, undocumented
                        if (XY_State == 2'b00) begin                    // RES b,r
                            if (MCycle == 3'd1) begin
                                ALU_Op = 4'b1011;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                            end
                        end else begin                                  // RES b,(IX+d),Reg, undocumented
                            MCycles = 3'd3;
                            XYbit_undoc = '1;
                            case (MCycle)
                                3'd1,
                                3'd7: Set_Addr_To = aXY;                // TODO what 7
                                3'd2: begin ALU_Op = 4'b1011; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                                3'd3: Write = '1;
                                default: ;
                            endcase
                        end
                    end
                    8'b10000110,
                    8'b10001110,
                    8'b10010110,
                    8'b10011110,
                    8'b10100110,
                    8'b10101110,
                    8'b10110110,
                    8'b10111110: begin                                  // RES b,(HL)
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1,
                            3'd7: Set_Addr_To = aXY;                    // TODO what 7
                            3'd2: begin ALU_Op = 4'b1011; Read_To_Reg = '1; Save_ALU = '1; Set_Addr_To = aXY; TStates = 3'd4; end
                            3'd3: Write = '1;
                            default: ;
                        endcase
                    end
				    default: ;
                endcase
            end
            default: begin                                              // ED prefixed instructions
                case(IRB)
// 8 BIT LOAD GROUP
                    8'b01010111: begin                                  // LD A,I
                        Special_LD = 3'b100;
                        TStates = 3'd5;
                    end
                    8'b01011111: begin                                  // LD A,R
                        Special_LD = 3'b101;
                        TStates = 3'd5;
                    end
                    8'b01000111: begin                                  // LD I,A
                        Special_LD = 3'b110;
                        TStates = 3'd5;
                    end
                    8'b01001111: begin                                  // LD R,A
                        Special_LD = 3'b111;
                        TStates = 3'd5;
                    end
// 16 BIT LOAD GROUP
                    8'b01001011,
                    8'b01011011,
                    8'b01101011,
                    8'b01111011: begin                                  // LD dd,(nn)
                        MCycles = 3'd5;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; LDZ = '1; end
                            3'd3: begin Set_Addr_To = aZI; Inc_PC = '1; LDW = '1; end
                            3'd4: begin
                                Read_To_Reg = '1;
                                if (IR[5:4] == 2'b11) begin
                                    Set_BusA_To = 4'b1000;
                                end else begin
                                    Set_BusA_To[2:1] = IR[5:4];
                                    Set_BusA_To[0] = '1;
                                end
                                Inc_WZ = '1;
                                Set_Addr_To = aZI;
                            end
                            3'd5: begin
                                Read_To_Reg = '1;
                                if (IR[5:4] == 2'b11) begin
                                    Set_BusA_To = 4'b1001;
                                end else begin
                                    Set_BusA_To[2:1] = IR[5:4];
                                    Set_BusA_To[0] = '0;
                                end
                            end
                            default: ;
                        endcase
                    end
                    8'b01000011,
                    8'b01010011,
                    8'b01100011,
                    8'b01110011: begin                                  // LD (nn),dd
                        MCycles = 3'd5;
                        case (MCycle)
                            3'd2: begin Inc_PC = '1; LDZ = '1; end
                            3'd3: begin
                                Set_Addr_To = aZI;
                                Inc_PC = '1;
                                LDW = '1;
                                if (IR[5:4] == 2'b11) begin
                                    Set_BusB_To = 4'b1000;
                                end else begin
                                    Set_BusB_To[2:1] = IR[5:4];
                                    Set_BusB_To[0] = '1;
                                    Set_BusB_To[3] = '0;
                                end
                            end
                            3'd4: begin
                                Inc_WZ = '1;
                                Set_Addr_To = aZI;
                                Write = '1;
                                if (IR[5:4] == 2'b11) begin
                                    Set_BusB_To = 4'b1001;
                                end else begin
                                    Set_BusB_To[2:1] = IR[5:4];
                                    Set_BusB_To[0] = '0;
                                    Set_BusB_To[3] = '0;
                                end
                            end
                            3'd5: begin
                                Write = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b10100000,
                    8'b10101000,
                    8'b10110000,
                    8'b10111000: begin                                  // LDI, LDD, LDIR, LDDR
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aXY;
                                IncDec_16 = 4'b1100;                    // BC
                            end
                            3'd2: begin
                                Set_BusB_To = 4'b0110;
                                Set_BusA_To[2:0] = 3'b111;
                                ALU_Op = 4'b0000;
                                Set_Addr_To = aDE;
                                if (~IR[3]) begin
                                    IncDec_16 = 4'b0110;                // IX
                                end else begin
                                    IncDec_16 = 4'b1110;
                                end
                            end
                            3'd3: begin
                                I_BT = '1;
                                TStates = 3'd5;
                                Write = '1;
                                if (~IR[3]) begin
                                    IncDec_16 = 4'b0101;                // DE
                                end else begin
                                    IncDec_16 = 4'b1101;
                                end
                            end
                            3'd4: begin
                                NoRead = '1;
                                TStates = 3'd5;
                            end
                            default: ;
                        endcase
                    end
                    8'b10100001,
                    8'b10101001,
                    8'b10110001,
                    8'b10111001: begin                                  // CPI, CPD, CPIR, CPDR
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aXY;
                                IncDec_16 = 4'b1100;                    // BC
                            end
                            3'd2: begin
                                Set_BusB_To = 4'b0110;
                                Set_BusA_To[2:0] = 3'b111;
                                ALU_Op = 4'b0111;
                                ALU_cpi = '1;
                                Save_ALU = '1;
                                PreserveC = '1;
                                if (~IR[3]) begin
                                    IncDec_16 = 4'b0110;                // IX
                                end else begin
                                    IncDec_16 = 4'b1110;
                                end
                            end
                            3'd3: begin
                                NoRead = '1;
                                I_BC = '1;
                                TStates = 3'd5;
                            end
                            3'd4: begin
                                NoRead = '1;
                                TStates = 3'd5;
                            end
                            default: ;
                        endcase
                    end
                    8'b01000100,
                    8'b01001100,
                    8'b01010100,
                    8'b01011100,
                    8'b01100100,
                    8'b01101100,
                    8'b01110100,
                    8'b01111100: begin                                  // NEG
                        ALU_Op = 4'b0010;
                        Set_BusB_To = 4'b0111;
                        Set_BusA_To = 4'b1010;
                        Read_To_Acc = '1;
                        Save_ALU = '1;
                    end
                    8'b01000110,
                    8'b01001110,
                    8'b01100110,
                    8'b01101110: begin                                  // IM 0
                        IMode = 2'b00;
                    end
                    8'b01010110,
                    8'b01110110: begin                                  // IM 1
                        IMode = 2'b01;
                    end
                    8'b01011110,
                    8'b01110111: begin                                  // IM 2
                        IMode = 2'b10;
                    end
// 16 bit arithmetic
                    8'b01001010,
                    8'b01011010,
                    8'b01101010,
                    8'b01111010: begin                                  // ADC HL,ss
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd2: begin
                                NoRead = '1;
                                ALU_Op = 4'b0001;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                Set_BusA_To[2:0] = 3'b101;
                                case(IR[5:4])
                                    2'd0,
                                    2'd1,
                                    2'd2: begin Set_BusB_To[2:1] = IR[5:4]; Set_BusB_To[0] = '1; end
                                    default: Set_BusB_To = 4'b1000;
                                endcase
                                TStates = 3'd4;
                            end
                            3'd3: begin
                                NoRead = '1;
                                ALU_Op = 4'b0001;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                Set_BusA_To[2:0] = 3'b100;
                                case(IR[5:4])
                                    2'd0,
                                    2'd1,
                                    2'd2: begin Set_BusB_To[2:1] = IR[5:4]; Set_BusB_To[0] = '0; end
                                    default: Set_BusB_To = 4'b1001;
                                endcase
                            end
                            default: ;
                        endcase
                    end
                    8'b01000010,
                    8'b01010010,
                    8'b01100010,
                    8'b01110010: begin                                  // SBC HL,ss
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd2: begin
                                NoRead = '1;
                                ALU_Op = 4'b0011;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                Set_BusA_To[2:0] = 3'b101;
                                case(IR[5:4])
                                    2'd0,
                                    2'd1,
                                    2'd2: begin Set_BusB_To[2:1] = IR[5:4]; Set_BusB_To[0] = '1; end
                                    default: Set_BusB_To = 4'b1000;
                                endcase
                                TStates = 3'd4;
                            end
                            3'd3: begin
                                NoRead = '1;
                                ALU_Op = 4'b0011;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                Set_BusA_To[2:0] = 3'b100;
                                case(IR[5:4])
                                    2'd0,
                                    2'd1,
                                    2'd2: begin Set_BusB_To[2:1] = IR[5:4]; Set_BusB_To[0] = '0; end
                                    default: Set_BusB_To = 4'b1001;
                                endcase
                            end
                            default: ;
                        endcase
                    end
                    8'b01101111: begin                                  // RLD
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd2: begin
                                NoRead = '1;
                                Set_Addr_To = aXY;
                            end
                            3'd3: begin
                                Read_To_Reg = '1;
                                Set_BusB_To[2:0] = 3'b110;
                                Set_BusA_To[2:0] = 3'b111;
                                ALU_Op = 4'b1101;
                                TStates = 3'd4;
                                Set_Addr_To = aXY;
                                Save_ALU = '1;
                            end
                            3'd4: begin
                                I_RLD = '1;
                                Write = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b01100111: begin                                  // RRD
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd2: begin
                                Set_Addr_To = aXY;
                            end
                            3'd3: begin
                                Read_To_Reg = '1;
                                Set_BusB_To[2:0] = 3'b110;
                                Set_BusA_To[2:0] = 3'b111;
                                ALU_Op = 4'b1110;
                                TStates = 3'd4;
                                Set_Addr_To = aXY;
                                Save_ALU = '1;
                            end
                            3'd4: begin
                                I_RRD = '1;
                                Write = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b01000101,
                    8'b01001101,
                    8'b01010101,
                    8'b01011101,
                    8'b01100101,
                    8'b01101101,
                    8'b01110101,
                    8'b01111101: begin                                  // RETI, RETN
                        MCycles = 3'd3;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aSP;
                            end
                            3'd2: begin
                                IncDec_16 = 4'b0111;
                                Set_Addr_To = aSP;
                                LDZ = '1;
                            end
                            3'd3: begin
                                Jump = '1;
                                IncDec_16 = 4'b0111;
                                I_RETN = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b01000000,
                    8'b01001000,
                    8'b01010000,
                    8'b01011000,
                    8'b01100000,
                    8'b01101000,
                    8'b01110000,
                    8'b01111000: begin                                  // IN r,(C)
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aBC;
                            end
                            3'd2: begin
                                IORQ = '1;
                                if (IR[5:3] != 3'b110) begin
                                    Read_To_Reg = '1;
                                    Set_BusA_To[2:0] = IR[5:3];
                                end
                                I_INRC = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b01000001,
                    8'b01001001,
                    8'b01010001,
                    8'b01011001,
                    8'b01100001,
                    8'b01101001,
                    8'b01110001,
                    8'b01111001: begin                                  // OUT (C),r ,  OUT (C),0
                        MCycles = 3'd2;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aBC;
                                Set_BusB_To[2:0] = IR[5:3];
                                if (IR[5:3] == 3'b110) begin
                                    Set_BusB_To[3] = '1;
                                end
                            end
                            3'd2: begin
                                Write = '1;
                                IORQ = '1;
                            end
                            default: ;
                        endcase
                    end
                    8'b10100010,
                    8'b10101010,
                    8'b10110010,
                    8'b10111010: begin                                  // INI, IND, INIR, INDR
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd1: begin
                                Set_Addr_To = aBC;
                                Set_BusB_To = 4'b1010;
                                Set_BusA_To = 4'b0000;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                ALU_Op = 4'b0010;
                            end
                            3'd2: begin
                                IORQ = '1;
                                Set_BusB_To = 4'b0110;
                                Set_Addr_To = aXY;
                            end
                            3'd3: begin
                                if (~IR[3]) begin
                                    IncDec_16 = 4'b0110;
                                end else begin
                                    IncDec_16 = 4'b1110;
                                end
                                TStates = 3'd4;
                                Write = '1;
                                I_BTR = '1;
                            end
                            3'd4: begin
                                NoRead = '1;
                                TStates = 3'd5;
                            end
                            default: ;
                        endcase
                    end
                    8'b10100011,
                    8'b10101011,
                    8'b10110011,
                    8'b10111011: begin                                  // OUTI, OUTD, OTIR, OTDR
                        MCycles = 3'd4;
                        case (MCycle)
                            3'd1: begin
                                TStates = 3'd5;
                                Set_Addr_To = aXY;
                                Set_BusB_To = 4'b1010;
                                Set_BusA_To = 4'b0000;
                                Read_To_Reg = '1;
                                Save_ALU = '1;
                                ALU_Op = 4'b0010;
                            end
                            3'd2: begin
                                Set_BusB_To = 4'b0110;
                                Set_Addr_To = aBC;
                            end
                            3'd3: begin
                                if (~IR[3]) begin
                                    IncDec_16 = 4'b0110;
                                end else begin
                                    IncDec_16 = 4'b1110;
                                end
                                IORQ = '1;
                                Write = '1;
                                I_BTR = '1;
                            end
                            3'd4: begin
                                NoRead = '1;
                                TStates = 3'd5;
                            end
                            default: ;
                        endcase
                    end
                    8'b11000001,
                    8'b11001001,
                    8'b11010001,
                    8'b11011001: begin                                  // R800 MULUB
                        if (R800_MULU && R800_mode) begin
                            MCycles = 3'd2;
                            case(MCycle)
                                3'd1: begin
                                    NoRead = '1;
                                    I_MULUB = '1;
                                    Set_BusB_To[2:0] = IR[5:3];
                                    Set_BusB_To[3] = '0;
                                end
                                3'd2: begin
                                    NoRead = '1;
                                    I_MULU = '1;
                                    Set_BusA_To[2:0] = 3'b100;
                                end
                                default:;
                            endcase
                        end
                    end
                    8'b11000011,
                    8'b11110011: begin                                  // R800 MULUW
                        if (R800_MULU && R800_mode) begin
                            MCycles = 3'd2;
                            case(MCycle)
                                3'd1: begin
                                    NoRead = '1;
                                    if (DPair == 2'b11) begin
                                        Set_BusB_To[3:0] = 4'b1000;
                                    end else begin
                                        Set_BusB_To[2:1] = DPair;
                                        Set_BusB_To[0] = '0;
                                        Set_BusB_To[3] = '0;
                                    end
                                    Set_BusA_To[2:0] = 3'b100;
                                end
                                3'd2: begin
                                    TStates = 3'd5;
                                    NoRead = '1;
                                    I_MULU = '1;
                                    Set_BusA_To[2:0] = 3'b100;
                                end
                                default:;
                            endcase
                        end
                    end
                    default: ;
                endcase
            end
        endcase

        if (Mode == 1) begin
            if (MCycle == 3'd1) begin
                ;
            end else begin
                TStates = 3'd3;
            end
        end

        if (Mode == 3) begin
            if (MCycle == 3'd1) begin
                ;
            end else begin
                TStates = 3'd4;
            end
        end

        if (Mode < 2) begin
            if (MCycle == 3'd6) begin
                Inc_PC = '1;
                if (Mode == 1) begin
                    Set_Addr_To = aXY;
                    TStates = 3'd4;
                    Set_BusB_To[2:0] = SSS;
                    Set_BusB_To[3] = '0;
                end
                if (IRB == 8'b00110110 || IRB == 8'b11001011) begin
                    Set_Addr_To = aNone;
                end
            end
            if (MCycle == 3'd7) begin
                if (Mode == 0) begin
                    TStates = 3'd5;
                end
                if (ISet != 2'b01) begin
                    Set_Addr_To = aXY;
                end
                Set_BusB_To[2:0] = SSS;
                Set_BusB_To[3] = '0;
                if (IRB == 8'b00110110 || ISet == 2'b01) begin
                    Inc_PC = '1;
                end else begin
                    NoRead = 1;
                end
            end
        end
    end

endmodule
