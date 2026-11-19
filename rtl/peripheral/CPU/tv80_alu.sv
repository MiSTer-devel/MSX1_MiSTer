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
//  0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
//  0238 : Fixed zero flag for 16 bit SBC and ADC
//  0240 : Added GB operations
//  0242 : Cleanup
//  0247 : Cleanup
//  0249 : Added undocumented XY-Flags for CPI/CPD by TobiFlex 2012.07.22
//  0250 : Version alignment by KdL 2017.10.23
//
//  +k01 : Version alignment by KdL 2010.10.25
//  +k02 : Version alignment by KdL 2018.05.14
//  +k03 : Version alignment by KdL 2019.05.20
//  +k04 : Separation of T800 from T80 by KdL 2021.02.01, then reverted on 2023.05.15
//  +k05 : Version alignment by KdL 2023.05.15
//
//  +m01 : Revrite to systemVerilog by Molekula 2025.01.26, original: https://github.com/gnogni/ocm-pld-dev.git 95aa5e2179f28c0d8028e17203909804ce6ff66b

module TV80_ALU #(
    parameter		    Mode   = 0,
            		    Flag_C = 0,
            		    Flag_N = 1,
            		    Flag_P = 2,
            		    Flag_X = 3,
            		    Flag_H = 4,
            		    Flag_Y = 5,
            		    Flag_Z = 6,
            		    Flag_S = 7
)(
    input               Arith16,
    input               Z16,
    input               ALU_cpi,
    input         [3:0] ALU_Op,
    input         [5:0] IR,
    input         [1:0] ISet,
    input         [7:0] BusA,
    input         [7:0] BusB,
    input         [7:0] F_In,
    input               R800,           // BIT keeps S, P/V, C, X, Y (openMSX bit_N_R / bit_N_xhl)
    input         [1:0] MP_YX,          // Z80 BIT (HL) / (IX+d): bits 13, 11 of MEMPTR (DDCB: of IX+d)
    input               XY_Ind,         // DDCB: X / Y of every BIT form from MP_YX
    output logic  [7:0] Q,
    output logic  [7:0] F_Out

);

    `define AddSub(WIDTH, A, B, Sub, Carry_In) ({1'b0, A} + {1'b0, (Sub)?~B:B } + {WIDTH'h0,Carry_In})
    wire        HalfCarry_v;
    wire        UseCarry;
    wire        Carry7_v;
    wire        Carry_v;
    wire        OverFlow_v;
    wire  [7:0] Q_v;
    wire  [4:0] Q_cpi;
    wire  [7:0] BitMask;

    assign BitMask = 8'b00000001 << IR[5:3];
    assign UseCarry = ~ALU_Op[2] && ALU_Op[0];

    assign {HalfCarry_v, Q_v[3:0]} = `AddSub(4, BusA[3:0], BusB[3:0], ALU_Op[1], ALU_Op[1] ^ (UseCarry & F_In[Flag_C]));
    assign {Carry7_v   , Q_v[6:4]} = `AddSub(3, BusA[6:4], BusB[6:4], ALU_Op[1], HalfCarry_v);
    assign {Carry_v    , Q_v[7]  } = `AddSub(1, BusA[7:7], BusB[7:7], ALU_Op[1], Carry7_v);
    assign  Q_cpi[4:0]             = `AddSub(4, BusA[3:0], BusB[3:0], 1'b1, HalfCarry_v);
    assign OverFlow_v = Carry_v ^ Carry7_v;


    logic [7:0] Q_t;
    logic [8:0] DAA_Q;
    always_comb begin
        Q_t   = '0;
        DAA_Q = '0;
        F_Out = F_In;
        casez (ALU_Op)
            4'b0???: begin
                F_Out[Flag_N] = '0;
                F_Out[Flag_C] = '0;
                casez (ALU_Op[2:0])
                    3'b00?: begin                                   // ADD, ADC
                        Q_t = Q_v;
                        F_Out[Flag_C] = Carry_v;
                        F_Out[Flag_H] = HalfCarry_v;
                        F_Out[Flag_P] = OverFlow_v;
                    end
                    3'b01?,
                    3'b111: begin                                   // SUB, SBC, CP
                        Q_t = Q_v;
                        F_Out[Flag_N] = '1;
                        F_Out[Flag_C] = ~Carry_v;
                        F_Out[Flag_H] = ~HalfCarry_v;
                        F_Out[Flag_P] = OverFlow_v;
                    end
                    3'b100: begin                                   // AND
                        Q_t = BusA & BusB;
                        F_Out[Flag_H] = '1;
                    end
                    3'b101: begin                                   // XOR
                        Q_t = BusA ^ BusB;
                        F_Out[Flag_H] = '0;
                    end
                    3'b110: begin                                   // OR
                        Q_t = BusA | BusB;
                        F_Out[Flag_H] = '0;
                    end
                endcase
                if (ALU_Op[2:0] == 3'b111) begin                    // CP
                    if (ALU_cpi) begin                              // CPI
                        F_Out[Flag_X] = Q_cpi[3];
                        F_Out[Flag_Y] = Q_cpi[1];
                    end else begin
                        F_Out[Flag_X] = BusB[3];
                        F_Out[Flag_Y] = BusB[5];
                    end
                end else begin
                    F_Out[Flag_X] = Q_t[3];
                    F_Out[Flag_Y] = Q_t[5];
                end
                if (Q_t == '0) begin
                    F_Out[Flag_Z] = '1;
                    if (Z16) begin
                        F_Out[Flag_Z] = F_In[Flag_Z];               // 16 bit ADC,SBC
                    end
                end else begin
                    F_Out[Flag_Z] = '0;
                end
                F_Out[Flag_S] = Q_t[7];
                casez (ALU_Op[2:0])
                    3'b0??,
                    3'b111: ;                                       // ADD, ADC, SUB, SBC, CP
                    default: begin
                        F_Out[Flag_P] = ~(^Q_t);
                    end
                endcase
                if (Arith16) begin
                    F_Out[Flag_S] = F_In[Flag_S];
                    F_Out[Flag_Z] = F_In[Flag_Z];
                    F_Out[Flag_P] = F_In[Flag_P];
                end
            end
            4'b1100: begin                                          // DAA
                F_Out[Flag_H] = F_In[Flag_H];
                F_Out[Flag_C] = F_In[Flag_C];
                DAA_Q = {1'b0, BusA};
                if (~F_In[Flag_N]) begin
                    if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin    // After addition Alow > 9 or H = 1
                        if (DAA_Q[3:0] > 4'd9) begin
                            F_Out[Flag_H] = '1;
                        end else begin
                            F_Out[Flag_H] = '0;
                        end
                        DAA_Q = DAA_Q + 9'd6;
                    end
                    if (DAA_Q[8:4] > 5'd9 || F_In[Flag_C]) begin    // new Ahigh > 9 or C = 1
                        DAA_Q = DAA_Q + 9'd96;
                    end
                end else begin
                    if (DAA_Q[3:0] > 4'd9 || F_In[Flag_H]) begin    // After subtraction
                        if (DAA_Q[3:0] > 4'd5) begin
                            F_Out[Flag_H] = '0;
                        end
                        DAA_Q[7:0] = DAA_Q[7:0] - 8'd6;
                    end
                    if (BusA > 8'd153 || F_In[Flag_C] ) begin
                        DAA_Q = DAA_Q - 9'd352;
                    end
                end
                F_Out[Flag_X] = DAA_Q[3];
                F_Out[Flag_Y] = DAA_Q[5];
                F_Out[Flag_C] = F_In[Flag_C] | DAA_Q[8];
                Q_t = DAA_Q[7:0];
                if (DAA_Q[7:0] == 8'd0) begin
                    F_Out[Flag_Z] = '1;
                end else begin
                    F_Out[Flag_Z] = '0;
                end
                F_Out[Flag_S] = DAA_Q[7];
                F_Out[Flag_P] = ~(^DAA_Q[7:0]);
            end
            4'b1101,
            4'b1110: begin                                          // RLD, RRD
                Q_t[7:4] = BusA[7:4];
                if (ALU_Op[0]) begin
                    Q_t[3:0] = BusB[7:4];
                end else begin
                    Q_t[3:0] = BusB[3:0];
                end
                F_Out[Flag_H] = '0;
                F_Out[Flag_N] = '0;
                F_Out[Flag_X] = Q_t[3];
                F_Out[Flag_Y] = Q_t[5];
                if (Q_t == '0) begin
                    F_Out[Flag_Z] = '1;
                end else begin
                    F_Out[Flag_Z] = '0;
                end
                F_Out[Flag_S] = Q_t[7];
                F_Out[Flag_P] = ~(^Q_t);
            end
            4'b1001: begin                                          // BIT
                Q_t = BusB & BitMask;
                F_Out[Flag_S] = Q_t[7];
                if (Q_t == '0) begin
                    F_Out[Flag_Z] = '1;
                    F_Out[Flag_P] = '1;
                end else begin
                    F_Out[Flag_Z] = '0;
                    F_Out[Flag_P] = '0;
                end
                F_Out[Flag_H] = '1;
                F_Out[Flag_N] = '0;
                if (R800) begin
                    F_Out[Flag_S] = F_In[Flag_S];
                    F_Out[Flag_P] = F_In[Flag_P];
                    F_Out[Flag_X] = F_In[Flag_X];
                    F_Out[Flag_Y] = F_In[Flag_Y];
                end else if (IR[2:0] == 3'b110 || XY_Ind) begin
                    F_Out[Flag_X] = MP_YX[0];
                    F_Out[Flag_Y] = MP_YX[1];
                end else begin
                    F_Out[Flag_X] = BusB[3];
                    F_Out[Flag_Y] = BusB[5];
                end
            end
            4'b1010: begin                                          // SET
                Q_t = BusB | BitMask;
            end
            4'b1011: begin                                          // RES
                Q_t = BusB & ~BitMask;
            end
            4'b1000: begin                                          // ROT
                case (IR[5:3])
                    3'b000: begin                                   // RLC
                        Q_t[7:1]      = BusA[6:0];
                        Q_t[0]        = BusA[7];
                        F_Out[Flag_C] = BusA[7];
                    end
                    3'b010: begin                                   // RL
                        Q_t[7:1]      = BusA[6:0];
                        Q_t[0]        = F_In[Flag_C];
                        F_Out[Flag_C] = BusA[7];
                    end
                    3'b001: begin                                   // RRC
                        Q_t[6:0]      = BusA[7:1];
                        Q_t[7]        = BusA[0];
                        F_Out[Flag_C] = BusA[0];
                    end
                    3'b011: begin                                   // RR
                        Q_t[6:0]      = BusA[7:1];
                        Q_t[7]        = F_In[Flag_C];
                        F_Out[Flag_C] = BusA[0];
                    end
                    3'b100: begin                                   // SLA
                        Q_t[7:1]      = BusA[6:0];
                        Q_t[0]        = '0;
                        F_Out[Flag_C] = BusA[7];
                    end
                    3'b110: begin                                   // SLL (Undocumented) / SWAP
                        if (Mode == 3) begin
                            Q_t[7:4]  = BusA[3:0];
                            Q_t[3:0]  = BusA[7:4];
                            F_Out[Flag_C] = '0;
                        end else begin
                            Q_t[7:1]  = BusA[6:0];
                            Q_t[0]    = '1;
                            F_Out[Flag_C] = BusA[7];
                        end
                    end
                    3'b101: begin                                   // SRA
                        Q_t[6:0]      = BusA[7:1];
                        Q_t[7]        = BusA[7];
                        F_Out[Flag_C] = BusA[0];
                    end
                    3'b111: begin                                   // SRL
                        Q_t[6:0]      = BusA[7:1];
                        Q_t[7]        = '0;
                        F_Out[Flag_C] = BusA[0];
                    end
                endcase
                F_Out[Flag_H] = '0;
                F_Out[Flag_N] = '0;
                F_Out[Flag_X] = Q_t[3];
                F_Out[Flag_Y] = Q_t[5];
                F_Out[Flag_S] = Q_t[7];
                if (Q_t == '0) begin
                    F_Out[Flag_Z] = '1;
                end else begin
                    F_Out[Flag_Z] = '0;
                end
                F_Out[Flag_P] = ~(^Q_t);
                if (ISet == 2'b00) begin
                    F_Out[Flag_P] = F_In[Flag_P];
                    F_Out[Flag_S] = F_In[Flag_S];
                    F_Out[Flag_Z] = F_In[Flag_Z];
                end
            end
            default: ;
        endcase
        Q = Q_t;
    end

endmodule
