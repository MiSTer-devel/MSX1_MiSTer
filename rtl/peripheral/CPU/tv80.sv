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
//  0210 : Fixed wait and halt
//  0211 : Fixed Refresh addition and IM 1
//  0214 : Fixed mostly flags, only the block instructions now fail the zex regression test
//  0232 : Removed refresh address output for Mode > 1 and added DJNZ M1_n fix by Mike Johnson
//  0235 : Added clock enable and IM 2 fix by Mike Johnson
//  0237 : Changed 8080 I/O address output, added IntE output
//  0238 : Fixed (IX/IY+d) timing and 16 bit ADC and SBC zero flag
//  0240 : Added interrupt ack fix by Mike Johnson, changed (IX/IY+d) timing and changed flags in GB mode
//  0242 : Added I/O wait, fixed refresh address, moved some registers to RAM
//  0247 : Fixed bus req/ack cycle
//  0248 : Added undocumented DDCB and FDCB opcodes by TobiFlex 2010.04.20
//  0249 : Added undocumented XY-Flags for CPI/CPD by TobiFlex 2012.07.22
//  0250 : Added R800 Multiplier by TobiFlex 2017.10.15
//
//  +k01 : Version alignment by KdL 2010.10.25
//  +k02 : Added R800_mode signal by KdL 2018.05.14
//  +k03 : Version alignment by KdL 2019.05.20
//  +k04 : Separation of T800 from T80 by KdL 2021.02.01, then reverted on 2023.05.15
//  +k05 : Fixed a bug in which the flag register was not changing in "LD A,I" and "LD A,R" by t.hara 2022.11.05
//
//  +m01 : Revrite to systemVerilog by Molekula 2025.01.26, original: https://github.com/gnogni/ocm-pld-dev.git 95aa5e2179f28c0d8028e17203909804ce6ff66b
//  +m02 : Savestate ports REG / DIRSet / DIR as T80.vhd of the MiSTer T80 (T80(c) version 350,
//         Sorgelig); DIRSet also clears Alternate, the pending write-back and the INT/NMI/HALT
//         state, so the core can resume fetching at the loaded PC (Z80 / R800 switch, turbo R)

module TV80#( parameter Mode      = 0,
                        R800_MULU = 1,
                        IOWait    = 0,
                        Flag_C    = 0,
                        Flag_N    = 1,
                        Flag_P    = 2,
                        Flag_X    = 3,
                        Flag_H    = 4,
                        Flag_Y    = 5,
                        Flag_Z    = 6,
                        Flag_S    = 7
)
(
    input               RESET_n,
    input               CLK_n,
    input               CEN,
    input               WAIT_n,
    input               INT_n,
    input               NMI_n,
    input               BUSRQ_n,
    output logic        M1_n,
    output              IORQ,
    output              NoRead,
    output              Write,
    output logic        RFSH_n,
    output              HALT_n,
    output              BUSAK_n,
    output logic [15:0] A,
    input         [7:0] DInst,
    input         [7:0] DI,
    output        [7:0] DO,
    output        [2:0] MC,
    output        [2:0] TS,
    output              IntCycle_n,
    input               R800_mode,
    output              IntE,
    output              Stop,
    // Savestate (MiSTer T80 layout): IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    output      [211:0] REG,
    input               DIRSet,         // load DIR (has priority over CEN, works with CEN = 0)
    input       [211:0] DIR
);

    localparam          aNone = 3'b111;
    localparam          aBC   = 3'b000;
    localparam          aDE   = 3'b001;
    localparam          aXY   = 3'b010;
    localparam          aIOA  = 3'b100;
    localparam          aSP   = 3'b101;
    localparam          aZI   = 3'b110;


    // Registers
    logic         [7:0] ACC, F;
    logic         [7:0] Ap, Fp;
    logic         [7:0] I;
    logic         [7:0] R;
    logic        [15:0] SP, PC;
    logic         [7:0] RegDIH;
    logic         [7:0] RegDIL;
    logic        [15:0] RegBusA;
    logic        [15:0] RegBusB;
    logic        [15:0] RegBusC;
    logic         [2:0] RegAddrA_r;
    logic         [2:0] RegAddrA;
    logic         [2:0] RegAddrB_r;
    logic         [2:0] RegAddrB;
    logic         [2:0] RegAddrC;
    logic               RegWEH;
    logic               RegWEL;
    logic               Alternate;

    // Help Registers
    logic        [15:0] TmpAddr;                                                                   // Temporary address register
    logic         [7:0] IR;                                                                        // Instruction register
    logic         [1:0] ISet;                                                                      // Instruction set selector
    logic        [15:0] RegBusA_r;
    logic        [31:0] MULU_Prod32;
    logic        [31:0] MULU_tmp;
    logic        [15:0] MULU_Fakt1;
    logic               MULU_W;                                                                    // 1: MULUW, 0: MULUB

    logic signed [15:0] ID16;
    logic         [7:0] Save_Mux;

    logic         [2:0] TState;
    logic         [2:0] MCycle;
    logic               IntE_FF1;
    logic               IntE_FF2;
    logic               Halt_FF;
    logic               BusReq_s;
    logic               BusAck;
    logic               ClkEn;
    logic               NMI_s;
    logic               INT_s;
    logic         [1:0] IStatus;

    logic         [7:0] DI_Reg;
    logic               T_Res;
    logic         [1:0] XY_State;
    logic         [2:0] Pre_XY_F_M;
    logic               NextIs_XY_Fetch;
    logic               XY_Ind;
    logic               No_BTR;
    logic               BTR_r;
    logic               Auto_Wait;
    logic               Auto_Wait_t1;
    logic         [1:0] IntWait;    // wait states left in the interrupt acknowledge
    logic               Wait_i;     // /WAIT only counts in cycles that use the bus
    logic               IncDecZ;

    // ALU signals
    logic         [7:0] BusB;
    logic         [7:0] BusA;
    logic         [7:0] ALU_Q;
    logic         [7:0] F_Out;

    // Registered micro code outputs
    logic         [4:0] Read_To_Reg_r;
    logic               Arith16_r;
    logic               Z16_r;
    logic         [3:0] ALU_Op_r;
    logic               ALU_cpi_r;
    logic               Save_ALU_r;
    logic               PreserveC_r;
    logic         [2:0] MCycles;

    // Micro code outputs
    wire         [2:0] MCycles_d;
    wire         [2:0] TStates;
    logic               IntCycle;
    logic               NMICycle;
    wire               Inc_PC;
    wire               Inc_WZ;
    wire         [3:0] IncDec_16;
    wire         [1:0] Prefix;
    wire               Read_To_Acc;
    wire               Read_To_Reg;
    wire         [3:0] Set_BusB_To;
    wire         [3:0] Set_BusA_To;
    wire         [3:0] ALU_Op;
    wire               ALU_cpi;
    wire               Save_ALU;
    wire               PreserveC;
    wire               Arith16;
    wire         [2:0] Set_Addr_To;
    wire               Jump;
    wire               JumpE;
    wire               JumpXY;
    wire               Call;
    wire               RstP;
    wire               LDZ;
    wire               LDW;
    wire               LDSPHL;
    wire               IORQ_i;
    wire         [2:0] Special_LD;
    wire               ExchangeDH;
    wire               ExchangeRp;
    wire               ExchangeAF;
    wire               ExchangeRS;
    wire               I_DJNZ;
    wire               I_CPL;
    wire               I_CCF;
    wire               I_SCF;
    wire               I_RETN;
    wire               I_BT;
    wire               I_BC;
    wire               I_BTR;
    wire               I_RLD;
    wire               I_RRD;
    wire               I_INRC;
    wire               I_MULUB;
    wire               I_MULU;
    wire               SetDI;
    wire               SetEI;
    wire         [1:0] IMode;
    wire               Halt;
    wire               XYbit_undoc;

    TV80_MCode #(
        .Mode(Mode),
        .R800_MULU(R800_MULU),
        .Flag_C(Flag_C),
        .Flag_N(Flag_N),
        .Flag_P(Flag_P),
        .Flag_X(Flag_X),
        .Flag_H(Flag_H),
        .Flag_Y(Flag_Y),
        .Flag_Z(Flag_Z),
        .Flag_S(Flag_S)
    ) mcode (
        .IR(IR),
        .ISet(ISet),
        .MCycle(MCycle),
        .F(F),
        .NMICycle(NMICycle),
        .IntCycle(IntCycle),
        .XY_State(XY_State),
        .MCycles(MCycles_d),
        .TStates(TStates),
        .Prefix(Prefix),
        .Inc_PC(Inc_PC),
        .Inc_WZ(Inc_WZ),
        .IncDec_16(IncDec_16),
        .Read_To_Acc(Read_To_Acc),
        .Read_To_Reg(Read_To_Reg),
        .Set_BusB_To(Set_BusB_To),
        .Set_BusA_To(Set_BusA_To),
        .ALU_Op(ALU_Op),
        .ALU_cpi(ALU_cpi),
        .Save_ALU(Save_ALU),
        .PreserveC(PreserveC),
        .Arith16(Arith16),
        .Set_Addr_To(Set_Addr_To),
        .IORQ(IORQ_i),
        .Jump(Jump),
        .JumpE(JumpE),
        .JumpXY(JumpXY),
        .Call(Call),
        .RstP(RstP),
        .LDZ(LDZ),
        .LDW(LDW),
        .LDSPHL(LDSPHL),
        .Special_LD(Special_LD),
        .ExchangeDH(ExchangeDH),
        .ExchangeRp(ExchangeRp),
        .ExchangeAF(ExchangeAF),
        .ExchangeRS(ExchangeRS),
        .I_DJNZ(I_DJNZ),
        .I_CPL(I_CPL),
        .I_CCF(I_CCF),
        .I_SCF(I_SCF),
        .I_RETN(I_RETN),
        .I_BT(I_BT),
        .I_BC(I_BC),
        .I_BTR(I_BTR),
        .I_RLD(I_RLD),
        .I_RRD(I_RRD),
        .I_INRC(I_INRC),
        .I_MULUB(I_MULUB),
        .I_MULU(I_MULU),
        .SetDI(SetDI),
        .SetEI(SetEI),
        .IMode(IMode),
        .Halt(Halt),
        .NoRead(NoRead),
        .Write(Write),
        .XYbit_undoc(XYbit_undoc),
        .R800_mode(R800_mode)
    );

    TV80_ALU #(
        .Mode(Mode),
        .Flag_C(Flag_C),
        .Flag_N(Flag_N),
        .Flag_P(Flag_P),
        .Flag_X(Flag_X),
        .Flag_H(Flag_H),
        .Flag_Y(Flag_Y),
        .Flag_Z(Flag_Z),
        .Flag_S(Flag_S)
    ) alu (
        .Arith16(Arith16_r),
        .Z16(Z16_r),
        .ALU_cpi(ALU_cpi_r),
        .ALU_Op(ALU_Op_r),
        .IR(IR[5:0]),
        .ISet(ISet),
        .BusA(BusA),
        .BusB(BusB),
        .F_In(F),
        .Q(ALU_Q),
        .F_Out(F_Out)
    );

    assign ClkEn           = CEN & ~BusAck;
    assign T_Res           = TState == TStates;
    assign NextIs_XY_Fetch = XY_State != 2'b00 && ~XY_Ind && (   (Set_Addr_To == aXY )
                                                              || (MCycle == 3'd1 && IR == 8'b11001011)
                                                              || (MCycle == 3'd1 && IR == 8'b00110110)
                                                             );
    assign Save_Mux        = ExchangeRp ? BusB   :
                             Save_ALU_r ? ALU_Q  :
                                          DI_Reg ;

    // Register file in logical order regardless of EXX (Alternate swaps pairs 0-2 with 4-6)
    wire [127:0] DOR;
    wire [127:0] DOR_logical = Alternate ? {DOR[127:112], DOR[47:0], DOR[63:48], DOR[111:64]} : DOR;
    assign REG = {IntE_FF2, IntE_FF1, IStatus, DOR_logical, PC, SP, R, I, Fp, Ap, F, ACC};

    always_ff @(negedge RESET_n or posedge CLK_n) begin
        if (~RESET_n) begin
            PC            <= '0;
            A             <= '0;
            TmpAddr       <= '0;
            IR            <= '0;
            ISet          <= '0;
            XY_State      <= '0;
            IStatus       <= '0;
            MCycles       <= '0;
            DO            <= '0;

            ACC           <= '0;
            F             <= '0;
            Ap            <= '0;
            Fp            <= '0;
            I             <= '0;
            R             <= '0;
            SP            <= '0;
            Alternate     <= '0;

            Read_To_Reg_r <= '0;
            Arith16_r     <= '0;
            BTR_r         <= '0;
            Z16_r         <= '0;
            ALU_Op_r      <= '0;
            ALU_cpi_r     <= '0;
            Save_ALU_r    <= '0;
            PreserveC_r   <= '0;
            XY_Ind        <= '0;
        end else if (DIRSet) begin
            ACC           <= DIR[7:0];
            F             <= DIR[15:8];
            Ap            <= DIR[23:16];
            Fp            <= DIR[31:24];
            I             <= DIR[39:32];
            R             <= DIR[47:40];
            SP            <= DIR[63:48];
            PC            <= DIR[79:64];
            A             <= DIR[79:64];
            IStatus       <= DIR[209:208];
            Alternate     <= '0;                // DIR is in logical order
            // drop a write-back still pending from the previous instruction (none after OUT)
            Read_To_Reg_r <= '0;
            Save_ALU_r    <= '0;
            ALU_Op_r      <= '0;
        end else begin
            if (ClkEn) begin
                ALU_Op_r      <= '0;
                ALU_cpi_r     <= '0;
                Save_ALU_r    <= '0;
                Read_To_Reg_r <= '0;
                MCycles       <= MCycles_d;
                Arith16_r     <= Arith16;
                PreserveC_r   <= PreserveC;

                if (IMode != 2'b11)
                    IStatus <= IMode;

                Z16_r <= ISet == 2'b10 && ~ALU_Op[2] && ALU_Op[0] && MCycle == 3'd3;

                if (MCycle == 3'd1 && ~TState[2]) begin
                    if (TState == 3'd2 && Wait_i) begin
                        if (Mode < 2) begin
                            A      <= {I, R};
                            R[6:0] <= R[6:0] + 7'b1;
                        end

                        if (~Jump && ~Call && ~NMICycle && ~IntCycle && ~(Halt_FF || Halt) )
                            PC <= PC + 16'b1;

                        IR <= (IntCycle && IStatus == 2'b01)                          ? '1    :
                              (Halt_FF || (IntCycle && IStatus == 2'b10) || NMICycle) ? '0    :
                                                                                        DInst ;

                        ISet <= '0;
                        case(Prefix)
                            2'b00: begin
                                XY_State <= '0;
                                XY_Ind   <= '0;
                            end
                            2'b01: ISet     <= Prefix;
                            2'b10: begin
                                XY_State <= '0;
                                XY_Ind   <= '0;
                                ISet     <= Prefix;
                            end
                            2'b11: XY_State <= IR[5] ? 2'b10 : 2'b01;
                        endcase
                    end
                end else begin

                    if (MCycle == 3'd6) begin
                        XY_Ind <= '1;
                        if (Prefix == 2'b01) begin
                            ISet <= 2'b01;
                        end
                    end

                    if (T_Res) begin
                        BTR_r <= (I_BT || I_BC || I_BTR) && ~No_BTR;

                        if (Jump) begin
                            A  <= {DI_Reg, TmpAddr[7:0]};
                            PC <= {DI_Reg, TmpAddr[7:0]};
                        end else if (JumpXY) begin
                            A  <= RegBusC;
                            PC <= RegBusC;
                        end else if (Call || RstP) begin
                            A  <= TmpAddr;
                            PC <= TmpAddr;
                        end else if (MCycle == MCycles && NMICycle) begin
                            A  <= 16'b0000000001100110;
                            PC <= 16'b0000000001100110;
                        end else if (MCycle == 3'd3 && IntCycle && IStatus == 2'b10) begin
                            A  <= {I, TmpAddr[7:0]};
                            PC <= {I, TmpAddr[7:0]};
                        end else begin
                            case (Set_Addr_To)
                                aXY:
                                    A <= (XY_State == 2'b00) ? RegBusC :
                                        (NextIs_XY_Fetch)  ? PC : TmpAddr;
                                aIOA:
                                    A <= { (Mode == 3) ? 8'b11111111 :                          // Memory map I/O on GBZ80
                                           (Mode == 2) ? DI_Reg      :                          // Duplicate I/O address on 8080
                                                         ACC, DI_Reg };
                                aSP:
                                    A <= SP;
                                aBC:
                                    A <= (Mode == 3 && IORQ_i) ? {8'b11111111, RegBusC[7:0]} : // Memory map I/O on GBZ80
                                                                 RegBusC;
                                aDE:
                                    A <= RegBusC;
                                aZI:
                                    A <= Inc_WZ ? (TmpAddr + 16'b1) : {DI_Reg, TmpAddr[7:0]};
                                default:
                                    A <= PC;
                            endcase
                        end

                        Save_ALU_r <= Save_ALU;
                        ALU_cpi_r  <= ALU_cpi;
                        ALU_Op_r   <= ALU_Op;

                        if (I_CPL) begin
                            ACC <= ~ACC;
                            F[Flag_Y] <= ~ACC[5];
                            F[Flag_H] <= '1;
                            F[Flag_X] <= ~ACC[3];
                            F[Flag_N] <= '1;
                        end
                        if (I_CCF) begin
                            F[Flag_C] <= ~F[Flag_C];
                            F[Flag_Y] <= ACC[5];
                            F[Flag_H] <= F[Flag_C];
                            F[Flag_X] <= ACC[3];
                            F[Flag_N] <= '0;
                        end
                        if (I_SCF) begin
                            F[Flag_C] <= '1;
                            F[Flag_Y] <= ACC[5];
                            F[Flag_H] <= '0;
                            F[Flag_X] <= ACC[3];
                            F[Flag_N] <= '0;
                        end
                    end

                    if (TState == 3'd2 && Wait_i) begin
                        if (ISet == 2'b01 && MCycle == 3'd7)
                            IR <= DInst;
                        if (JumpE)
                            PC <= $unsigned($signed(PC) + $signed({{8{DI_Reg[7]}}, DI_Reg}));
                        else if (Inc_PC)
                            PC <= PC + 16'b1;
                        if (BTR_r)
                            PC <= PC - 16'd2;
                        if (RstP) begin
                            TmpAddr <= '0;
                            TmpAddr[5:3] <= IR[5:3];
                        end
                    end

                    if (TState == 3'd3 && MCycle == 3'd6)
                        TmpAddr <= $unsigned($signed(RegBusC) + $signed({{8{DI_Reg[7]}}, DI_Reg}));

                    if ((TState == 3'd2 && Wait_i) || (TState == 3'd4 && MCycle == 3'd1))
                        if (IncDec_16[2:0] == 3'b111)
                            SP <= IncDec_16[3] ? SP - 16'b1 : SP + 16'b1;

                    if (LDSPHL)
                        SP <= RegBusC;

                    if (ExchangeAF) begin
                        Ap  <= ACC;
                        ACC <= Ap;
                        Fp  <= F;
                        F   <= Fp;
                    end

                    if (ExchangeRS)
                        Alternate <= ~Alternate;
                end

                if (TState == 3'd3) begin
                    if (LDZ)
                        TmpAddr[7:0] <= DI_Reg;
                    if (LDW)
                        TmpAddr[15:8] <= DI_Reg;
                    if (Special_LD[2])
                        case(Special_LD[1:0])
                            2'b00: begin
                                ACC <= I;
                                F[Flag_P] <= IntE_FF2;
                                F[Flag_N] <= '0;                        // Added by t.hara, 2022/Nov/05th
                                F[Flag_H] <= '0;                        // Added by t.hara, 2022/Nov/05th
                                F[Flag_S] <= I[7];                      // Added by t.hara, 2022/Nov/05th
                                F[Flag_Z] <= I == 8'd0;                 // Added by t.hara, 2022/Nov/05th
                            end
                            2'b01: begin
                                ACC <= R;
                                F[Flag_P] <= IntE_FF2;
                                F[Flag_N] <= '0;                        // Added by t.hara, 2022/Nov/05th
                                F[Flag_H] <= '0;                        // Added by t.hara, 2022/Nov/05th
                                F[Flag_S] <= R[7];                      // Added by t.hara, 2022/Nov/05th
                                F[Flag_Z] <= R == 8'd0;                 // Added by t.hara, 2022/Nov/05th
                            end
                            2'b10: I <= ACC;
                            default: R <= ACC;
                        endcase
                end

                if ((~I_DJNZ && Save_ALU_r) || ALU_Op_r == 4'b1001) begin
                    if (Mode == 3) begin
                        F[6] <= F_Out[6];
                        F[5] <= F_Out[5];
                        F[7] <= F_Out[7];
                        if (~PreserveC_r)
                            F[4] <= F_Out[4] ;
                    end else begin
                        F[7:1] <= F_Out[7:1];
                        if (~PreserveC_r)
                            F[Flag_C] <= F_Out[0] ;
                    end
                end

                if (T_Res && I_INRC) begin
                    F[Flag_H] <= '0;
                    F[Flag_N] <= '0;
                    F[Flag_Z] <= DI_Reg == 8'd0;
                    F[Flag_S] <= DI_Reg[7];
                    F[Flag_P] <= ~(^DI_Reg);
                end

                if (T_Res && I_MULU) begin                                      // R800 MULUB / MULUW flags (openMSX)
                    F[Flag_S] <= '0;
                    F[Flag_P] <= '0;
                    F[Flag_Z] <= MULU_W ? MULU_Prod32 == '0 : MULU_Prod32[31:16] == '0;
                    F[Flag_C] <= MULU_W ? MULU_Prod32[31:16] != '0 : MULU_Prod32[31:24] != '0;
                end

                if (TState == 3'd1 && ~Auto_Wait_t1) begin
                    DO <= BusB;
                    if (I_RLD)
                        DO <= {BusB[3:0], BusA[3:0]};
                    if (I_RRD)
                        DO <= {BusA[3:0], BusB[7:4]};
                end

                if (T_Res) begin
                    Read_To_Reg_r[3:0] <= Set_BusA_To;
                    Read_To_Reg_r[4] <= Read_To_Reg;
                    if (Read_To_Acc) begin
                        Read_To_Reg_r[3:0] <= 4'b0111;
                        Read_To_Reg_r[4] <= '1;
                    end
                end

                if (TState == 3'd1 && I_BT) begin
                    F[Flag_X] <= ALU_Q[3];
                    F[Flag_Y] <= ALU_Q[1];
                    F[Flag_H] <= '0;
                    F[Flag_N] <= '0;
                end

                if (I_BC || I_BT)
                    F[Flag_P] <= IncDecZ;

                if ((TState == 3'd1 && ~Save_ALU_r && ~Auto_Wait_t1) || (Save_ALU_r     && ALU_Op_r != 4'b0111)) begin
                    case (Read_To_Reg_r)
                        5'b10111: ACC      <= Save_Mux;
                        5'b10110: DO       <= Save_Mux;
                        5'b11000: SP[7:0]  <= Save_Mux;
                        5'b11001: SP[15:8] <= Save_Mux;
                        5'b11011: F        <= Save_Mux;
                        default: ;
                    endcase
                    if (XYbit_undoc)
                        DO <= ALU_Q;
                end
            end
        end
    end

// Multiply
    assign MULU_tmp[31:12] = (MULU_Fakt1 * MULU_Prod32[3:0]) + {4'b0000, MULU_Prod32[31:16]};
    assign MULU_tmp[11:0]  = MULU_Prod32[15:4];

    always_ff @(posedge CLK_n) begin
        if (ClkEn) begin
            if (T_Res) begin
                MULU_W <= ~I_MULUB;
                if (I_MULUB) begin
                    MULU_Prod32[7:0]  <= ACC;
                    MULU_Prod32[15:8] <= 8'b0;
                    MULU_Prod32[31:16] <= 16'b0;
                    MULU_Fakt1[7:0]   <= 8'b0;
                    if (Set_BusB_To[0])
                        MULU_Fakt1[15:8] <= RegBusB[7:0];
                    else
                        MULU_Fakt1[15:8] <= RegBusB[15:8];
                end else begin
                    MULU_Prod32[15:0] <= RegBusA;
                    MULU_Prod32[31:16] <= 16'b0;
                    MULU_Fakt1 <= RegBusB;
                end
            end else begin
                MULU_Prod32 <= MULU_tmp;
            end
        end
    end

// BC('), DE('), HL('), IX and IY
    always_ff @(posedge CLK_n) begin
        if (ClkEn) begin
            // Bus A / Write
            RegAddrA_r <= {Alternate, Set_BusA_To[2:1]};
            if (~XY_Ind && XY_State != 2'b00 && Set_BusA_To[2:1] == 2'b10)
                RegAddrA_r <= {XY_State[1], 2'b11};

            // Bus B
            RegAddrB_r <= {Alternate, Set_BusB_To[2:1]};
            if (~XY_Ind && XY_State != 2'b00 && Set_BusB_To[2:1] == 2'b10)
                RegAddrB_r <= {XY_State[1], 2'b11};

            // Address from register
            RegAddrC <= {Alternate, Set_Addr_To[1:0]};

            // Jump (HL), LD SP,HL
            if (JumpXY || LDSPHL)
                RegAddrC <= {Alternate, 2'b10};

            if (((JumpXY || LDSPHL) && XY_State != 2'b00) || (MCycle == 3'd6))
                RegAddrC <= {XY_State[1], 2'b11};

            if (I_DJNZ && Save_ALU_r && Mode < 2)
                IncDecZ <= F_Out[Flag_Z];

            if (TState == 3'd2 || (TState == 3'd3 && MCycle == 3'd1))
                if (IncDec_16[2:0] == 3'b100)
                    IncDecZ <= ID16 != 0;

            // RegBusA to RegBusA_r
            RegBusA_r <= RegBusA;
        end
    end

    always_comb begin
        if ((TState == 3'd2) || (TState == 3'd3 && MCycle == 3'd1 && IncDec_16[2])) begin      // 16 bit increment/decrement
            if (XY_State == 2'b00)
                RegAddrA = {Alternate, IncDec_16[1:0]};
            else if (IncDec_16[1:0] == 2'b10)
                RegAddrA = {XY_State[1], 2'b11};
            else
                RegAddrA = RegAddrA_r;
        end                                                                                                 // EX HL,DL
        else if (ExchangeDH && TState == 3'd3) begin
            RegAddrA = {Alternate, 2'b10};
        end
        else if ((ExchangeDH || I_MULU) && TState == 3'd4) begin
            RegAddrA = {Alternate, 2'b01};
        end
        else begin                                                                                          // Bus A / Write
            RegAddrA = RegAddrA_r;
        end

        RegAddrB = ExchangeDH && TState == 3'd3 ? {Alternate, 2'b01} : RegAddrB_r;

        ID16 = IncDec_16[3] ? $signed(RegBusA) - 16'sd1 : $signed(RegBusA) + 16'sd1;
    end

    always_comb begin
        RegWEH = '0;
        RegWEL = '0;

        if ((TState == 3'd1 && ~Save_ALU_r && ~Auto_Wait_t1) ||
            (Save_ALU_r && ALU_Op_r != 4'b0111)) begin
            case (Read_To_Reg_r)
                5'b10000, 5'b10001, 5'b10010, 5'b10011, 5'b10100, 5'b10101: begin
                    RegWEH = ~Read_To_Reg_r[0];
                    RegWEL = Read_To_Reg_r[0];
                end
                default: ;
            endcase
        end

        if (I_MULU && (T_Res || TState == 3'd4)) begin                                         // TState = 4 DE write
            RegWEH = '1;
            RegWEL = '1;
        end

        if (ExchangeDH && (TState == 3'd3 || TState == 3'd4)) begin
            RegWEH = '1;
            RegWEL = '1;
        end

        if (IncDec_16[2] && ((TState == 3'd2 && Wait_i && MCycle != 3'd1) || (TState == 3'd3 && MCycle == 3'd1))) begin
            case (IncDec_16[1:0])
                2'b00, 2'b01, 2'b10: begin
                    RegWEH = '1;
                    RegWEL = '1;
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        RegDIH = Save_Mux;
        RegDIL = Save_Mux;

        // MULUB: HL = product; MULUW: DE = high word (TState 4), HL = low word (as openMSX;
        // the T80 of MSX_MiSTer / OCM-PLD writes them swapped)
        if (I_MULU) begin
            if (T_Res)
                {RegDIH, RegDIL} = MULU_W ? MULU_Prod32[15:0] : MULU_Prod32[31:16];
            else
                {RegDIH, RegDIL} = MULU_tmp[31:16];
        end

        if (ExchangeDH) begin
            if (TState == 3'd3) begin
                RegDIH = RegBusB[15:8];
                RegDIL = RegBusB[7:0];
            end
            if (TState == 3'd4) begin
                RegDIH = RegBusA_r[15:8];
                RegDIL = RegBusA_r[7:0];
            end
        end

        if (IncDec_16[2] && ((TState == 3'd2 && MCycle != 3'd1) || (TState == 3'd3 && MCycle == 3'd1))) begin
            RegDIH = ID16[15:8];
            RegDIL = ID16[7:0];
        end
    end

    TV80_Reg Regs (
        .Clk(CLK_n),
        .CEN(ClkEn),
        .WEH(RegWEH),
        .WEL(RegWEL),
        .AddrA(RegAddrA),
        .AddrB(RegAddrB),
        .AddrC(RegAddrC),
        .DIH(RegDIH),
        .DIL(RegDIL),
        .DOAH(RegBusA[15:8]),
        .DOAL(RegBusA[7:0]),
        .DOBH(RegBusB[15:8]),
        .DOBL(RegBusB[7:0]),
        .DOCH(RegBusC[15:8]),
        .DOCL(RegBusC[7:0]),
        .DOR(DOR),
        .DIRSet(DIRSet),
        .DIR(DIR[207:80])                   // logical = physical order with Alternate = 0
    );

// Buses
    always @(posedge CLK_n) begin
        if (ClkEn) begin
            case (Set_BusB_To)
                4'b0111: BusB <= ACC;
                4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101:
                    BusB <= Set_BusB_To[0] ? RegBusB[7:0] : RegBusB[15:8];
                4'b0110: BusB <= DI_Reg;
                4'b1000: BusB <= SP[7:0];
                4'b1001: BusB <= SP[15:8];
                4'b1010: BusB <= 8'b00000001;
                4'b1011: BusB <= F;
                4'b1100: BusB <= PC[7:0];
                4'b1101: BusB <= PC[15:8];
                4'b1110: BusB <= 8'b00000000;
                default: BusB <= 8'b00000000;
            endcase

            case (Set_BusA_To)
                4'b0111: BusA <= ACC;
                4'b0000, 4'b0001, 4'b0010, 4'b0011, 4'b0100, 4'b0101:
                    BusA <= Set_BusA_To[0] ? RegBusA[7:0] : RegBusA[15:8];
                4'b0110: BusA <= DI_Reg;
                4'b1000: BusA <= SP[7:0];
                4'b1001: BusA <= SP[15:8];
                4'b1010: BusA <= 8'b00000000;
                default: BusA <= 8'b00000000;
            endcase

            if (XYbit_undoc) begin
                BusA <= DI_Reg;
                BusB <= DI_Reg;
            end
        end
    end

// Generate external control signals
    always @(negedge RESET_n or posedge CLK_n) begin
        if (~RESET_n)
            RFSH_n <= '1;
        else if (CEN) begin  // was CLK_n && CEN: clock must not be used as data
            if (MCycle == 3'b001 && ((TState == 3'd2 && Wait_i) || TState == 3'd3))
                RFSH_n <= '0;
            else
                RFSH_n <= '1;
        end
    end

    assign MC = MCycle;
    assign TS = TState;
    assign DI_Reg = DI;
    assign HALT_n = ~Halt_FF;
    assign BUSAK_n = ~BusAck;
    assign IntCycle_n = ~IntCycle;
    assign IntE = IntE_FF1;
    assign IORQ = IORQ_i;
    assign Stop = I_DJNZ;

// Syncronise inputs
    logic OldNMI_n;
    always @(negedge RESET_n or posedge CLK_n) begin
        if (~RESET_n) begin
            BusReq_s <= '0;
            INT_s <= '0;
            NMI_s <= '0;
            OldNMI_n <= '0;
        end else if (CEN) begin
            BusReq_s <= ~BUSRQ_n;
            INT_s <= ~INT_n;

            if (NMICycle)
                NMI_s <= '0;
            else if (~NMI_n && OldNMI_n)
                NMI_s <= '1;

            OldNMI_n <= NMI_n;
        end
    end

// Main state machine

    always @(negedge RESET_n or posedge CLK_n) begin
        if (~RESET_n) begin
            MCycle <= 3'd1;
            TState <= 3'd0;
            Pre_XY_F_M <= 3'b000;
            Halt_FF <= '0;
            BusAck <= '0;
            NMICycle <= '0;
            IntCycle <= '0;
            IntE_FF1 <= '0;
            IntE_FF2 <= '0;
            No_BTR <= '0;
            Auto_Wait_t1 <= '0;
            M1_n <= '1;
        end else if (DIRSet) begin
            IntE_FF2 <= DIR[211];
            IntE_FF1 <= DIR[210];
            // the loaded context decides on INT / NMI at the end of its first instruction
            IntCycle <= '0;
            NMICycle <= '0;
            Halt_FF  <= '0;
        end else if (CEN) begin
            if (T_Res)
                Auto_Wait_t1 <= '0;
            else
                Auto_Wait_t1 <= Auto_Wait | IORQ_i;

            No_BTR <= (I_BT  & (~IR[4] | ~F[Flag_P])) |
                      (I_BC  & (~IR[4] | F[Flag_Z] | ~F[Flag_P])) |
                      (I_BTR & (~IR[4] | F[Flag_Z]));

            if (TState == 3'd2) begin
                if (SetEI) begin
                    IntE_FF1 <= '1;
                    IntE_FF2 <= '1;
                end
                if (I_RETN)
                    IntE_FF1 <= IntE_FF2;
            end

            if (TState == 3'd3) begin
                if (SetDI) begin
                    IntE_FF1 <= '0;
                    IntE_FF2 <= '0;
                end
            end

            if (IntCycle | NMICycle)
                Halt_FF <= '0;

            // Interrupt acknowledge: TV80a latches the vector on every CE_n of T2, so M1 stays
            // low until the automatic wait states are over (else the last latch takes FF)
            if (MCycle == 3'd1 && TState == 3'd2 && Wait_i && ~Auto_Wait)
                M1_n <= '1;

            if (BusReq_s & BusAck) begin
            end else begin
                BusAck <= '0;
                if (TState == 3'd2 && ~Wait_i) begin
                end else if (T_Res) begin
                    if (Halt)
                        Halt_FF <= '1;
                    if (BusReq_s)
                        BusAck <= '1;
                    else begin
                        TState <= 3'd1;
                        if (NextIs_XY_Fetch) begin
                            MCycle <= 3'd6;
                            Pre_XY_F_M <= MCycle;
                            if (IR == 8'b00110110 && Mode == 0)
                                Pre_XY_F_M <= 3'b010;
                        end else if ((MCycle == 3'd7) || (MCycle == 3'd6 && Mode == 1 && ISet != 2'b01))
                            MCycle <= Pre_XY_F_M + 3'd1;
                        else if (MCycle == MCycles || No_BTR || (MCycle == 3'd2 && I_DJNZ && IncDecZ)) begin
                            M1_n <= '0;
                            MCycle <= 3'd1;
                            IntCycle <= '0;
                            NMICycle <= '0;
                            if (NMI_s && Prefix == 2'b00) begin
                                NMICycle <= '1;
                                IntE_FF1 <= '0;
                            end else if (IntE_FF1 && INT_s && Prefix == 2'b00 && ~SetEI) begin
                                IntCycle <= '1;
                                IntE_FF1 <= '0;
                                IntE_FF2 <= '0;
                            end
                        end else
                            MCycle <= MCycle + 3'd1;
                    end
                end else if (~(Auto_Wait || (IOWait == 1 & IORQ_i & ~Auto_Wait_t1)))
                    TState <= TState + 3'd1;
            end

            if (TState == 3'd0)
                M1_n <= '0;
        end
    end

    // Z80 samples /WAIT only in bus cycles; internal ones (JR M3, DJNZ, ADD HL, ...) run on
    assign Wait_i = WAIT_n | (NoRead & (MCycle != 3'd1));

    // Interrupt acknowledge: two wait states in M1, 13 T for IM0/IM1, 19 T for IM2; none for
    // NMI (11 T). Counted here: Auto_Wait_t1/t2 carried state from the previous cycle (also set
    // by IORQ_i), so after IN/OUT there was one wait state instead of two.
    always_ff @(negedge RESET_n or posedge CLK_n) begin
        if (~RESET_n)
            IntWait <= 2'd2;
        else if (DIRSet)
            IntWait <= 2'd2;
        else if (CEN) begin
            if (~(IntCycle && MCycle == 3'd1))
                IntWait <= 2'd2;
            else if (TState == 3'd2 && Wait_i && IntWait != 2'd0)
                IntWait <= IntWait - 2'd1;
        end
    end

    always_comb
        Auto_Wait = IntCycle && MCycle == 3'd1 && TState == 3'd2 && IntWait != 2'd0;


endmodule
