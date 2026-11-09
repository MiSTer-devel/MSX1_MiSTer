//
// Z80 compatible microprocessor core, asynchronous top level
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
//  0211 : Fixed interrupt cycle
//  0235 : Updated for T80 interface change
//  0238 : Updated for T80 interface change
//  0240 : Updated for T80 interface change
//  0242 : Updated for T80 interface change
//  0247 : Fixed bus req/ack cycle
//  0247a: 7th of September, 2003 by Kazuhiro Tsujikawa (tujikawa@hat.hi-ho.ne.jp)
//         Fixed IORQ_n, RD_n, WR_n bus timing
//  0250 : Added R800 Multiplier by TobiFlex 2017.10.15
//
//  +k01 : Added RstKeyLock and swioRESET_n by KdL 2010.10.25
//  +k02 : Added R800_mode signal by KdL 2018.05.14
//  +k03 : RstKeyLock and swioRESET_n were put back outside of T80 by KdL 2019.05.20
//  +k04 : Separation of T800 from T80 by KdL 2021.02.01, then reverted on 2023.05.15
//  +k05 : Version alignment by KdL 2023.05.15
//
//  +m01 : Revrite to systemVerilog by Molekula 2025.01.26, original: https://github.com/gnogni/ocm-pld-dev.git 95aa5e2179f28c0d8028e17203909804ce6ff66b
//  +m02 : Single clock CLK with clock enables CE_p (former posedge) / CE_n (former negedge)
//  +m03 : Savestate REG / DIRSet / DIR (MiSTer T80 layout) and MC / TS / IntCycle_n outputs
//         for the Z80 / R800 context switch in msx_cpu
//  +m04 : Interrupt acknowledge IORQ ends with M1; I/O cycle IORQ, RD and WR go active together
//         (Sord M5 core, doc/sordm5-opravy.md Z4 / Z5)

module TV80a#(
    parameter       Mode      = 0, // 0 => Z80, 1 => Fast Z80, 2 => 8080, 3 => GB
                    R800_MULU = 1, // no MULU, 1=> R800 MULU
                    IOWait    = 1  // Single I/O cycle, 1 => Std I/O cycle
)(
    input           RESET_n,
    input           R800_mode,
    input           CLK,
    input           CE_p,
    input           CE_n,
    input           WAIT_n,
    input           INT_n,
    input           NMI_n,
    input           BUSRQ_n,
    output          M1_n,
    output          MREQ_n,
    output          IORQ_n,
    output          RD_n,
    output          WR_n,
    output          RFSH_n,
    output          HALT_n,
    output          BUSAK_n,
    output   [15:0] A,
    input     [7:0] DI,
    output    [7:0] DO,
    output    [2:0] MC,             // machine cycle (1 = M1)
    output    [2:0] TS,             // T state
    output          IntCycle_n,     // 0 = interrupt acknowledge cycle
    output  [211:0] REG,            // savestate, see TV80
    input           DIRSet,
    input   [211:0] DIR
);

    logic           Reset_s;
    logic           IORQ;
    logic           NoRead;
    logic           Write;
    logic           MREQ;
    logic           MReq_Inhibit;
    logic           IReq_Inhibit;
    logic           Req_Inhibit;
    logic           RD;
    logic           MREQ_n_i;
    logic           IORQ_n_i;
    logic           RD_n_i;
    logic           WR_n_i;
    logic           WR_n_j;
    logic           RFSH_n_i;
    logic           BUSAK_n_i;
    logic    [15:0] A_i;
    logic     [7:0] DI_Reg;
    logic           Wait_s;
    logic     [2:0] MCycle;
    logic     [2:0] TState;

    assign BUSAK_n = BUSAK_n_i;
    assign MREQ_n_i= ~MREQ   || (Req_Inhibit && MReq_Inhibit);
    assign RD_n_i  = ~RD || Req_Inhibit;
    assign WR_n_j  = WR_n_i;

    assign MREQ_n  = MREQ_n_i;
    // Interrupt acknowledge: IORQ ends together with M1, as on the Z80 (IORQ_n_i alone stays
    // low until CE_n in T3, which looks like an I/O write to peripherals without a WR pin).
    assign IORQ_n  = IORQ_n_i || (IReq_Inhibit && IntCycle_n) || (~IntCycle_n && M1_n);
    // I/O cycle: IORQ, RD and WR are latched together on CE_n in T1 and held off by
    // IReq_Inhibit until CE_p, so all go active on the rising edge of T2 as on the Z80.
    wire   io_hold = ~IORQ_n_i && IReq_Inhibit && IntCycle_n;
    assign RD_n    = RD_n_i || io_hold;
    assign WR_n    = WR_n_j || io_hold;
    assign RFSH_n  = RFSH_n_i;
    assign A       = A_i;
    assign MC      = MCycle;
    assign TS      = TState;



    always_ff @(negedge RESET_n or posedge CLK) begin
        if (~RESET_n) begin
            Reset_s <= '0;
        end else if (CE_p) begin
            Reset_s <= '1;
        end
    end

    TV80 #(
        .Mode(Mode),
        .R800_MULU(R800_MULU),
        .IOWait(IOWait)
    ) u0_inst (
        .CEN(CE_p),
        .M1_n(M1_n),
        .IORQ(IORQ),
        .NoRead(NoRead),
        .Write(Write),
        .RFSH_n(RFSH_n_i),
        .HALT_n(HALT_n),
        .WAIT_n(Wait_s),
        .INT_n(INT_n),
        .NMI_n(NMI_n),
        .RESET_n(Reset_s),
        .BUSRQ_n(BUSRQ_n),
        .BUSAK_n(BUSAK_n_i),
        .CLK_n(CLK),
        .A(A_i),
        .DInst(DI),
        .DI(DI_Reg),
        .DO(DO),
        .MC(MCycle),
        .TS(TState),
        .IntCycle_n(IntCycle_n),
        .R800_mode(R800_mode),
        .REG(REG),
        .DIRSet(DIRSet),
        .DIR(DIR)
    );

    always_ff @(posedge CLK) begin
        if (CE_n) begin
            Wait_s <= WAIT_n;
            if (((TState == 3'd3 && IntCycle_n) || (TState == 3'd2 && ~IntCycle_n)) && BUSAK_n_i == '1) begin
                DI_Reg <= DI;
            end
        end
    end

    always_ff @(posedge CLK) begin
        if (CE_p) begin
            IReq_Inhibit <= ~IORQ;
        end
    end

    always_ff @(posedge CLK or negedge Reset_s) begin
        if (~Reset_s) begin
            WR_n_i <= '1;
        end else if (CE_n) begin
            if (~IORQ) begin
                case (TState)
                    3'd2: WR_n_i <= ~Write;
                    3'd3: WR_n_i <= '1;
                    default: ;
                endcase
            end else begin
                case (TState)
                    3'd1: WR_n_i <= ~Write;         // with IORQ_n_i (io_hold)
                    3'd3: WR_n_i <= '1;
                    default: ;
                endcase
            end
        end
    end

    always_ff @(posedge CLK or negedge Reset_s) begin
        if (~Reset_s) begin
            Req_Inhibit <= '0;
        end else if (CE_p) begin
            Req_Inhibit <= MCycle == 3'd1 && TState == 3'd2 && Wait_s;
        end
    end

    always_ff @(posedge CLK or negedge Reset_s) begin
        if (~Reset_s) begin
            MReq_Inhibit <= '0;
        end else if (CE_n) begin
            MReq_Inhibit <= MCycle == 3'd1 && TState == 3'd2;
        end
    end

    always_ff @(posedge CLK or negedge Reset_s) begin
        if (~Reset_s) begin
            RD <= '0;
            IORQ_n_i <= '1;
            MREQ <= '0;
        end else if (CE_n) begin
            if (MCycle == 3'd1) begin
                case (TState)
                    3'd1: begin
                        RD <= IntCycle_n;
                        MREQ <= IntCycle_n;
                        IORQ_n_i <= IntCycle_n;
                    end
                    3'd3: begin
                        RD <= '0;
                        IORQ_n_i <= '1;
                        MREQ <= '1;
                    end
                    3'd4: MREQ <= '0;
                    default: ;
                endcase
            end else begin
                if (TState == 3'd1 && ~NoRead) begin
                    IORQ_n_i <= ~IORQ;
                    MREQ <= ~IORQ;
                    RD <= ~Write;                   // I/O: with IORQ_n_i (io_hold)
                end
                if (TState == 3'd3) begin
                    RD <= '0;
                    IORQ_n_i <= '1;
                    MREQ <= '0;
                end
            end
        end
    end

endmodule
