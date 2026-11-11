// msx_cpu
//
// Copyright (c) 2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MSX CPU: TV80a on clk with clock enables, speed selection and M1 wait states.
//
// The CPU used to be clocked by a CE pulse used as a clock (derived clock, not
// analysed by TimeQuest). Now everything runs on clock_bus.clk:
//   ce_p = that pulse          -> former posedge of the CPU clock
//   ce_n = pulse delayed by 1  -> former negedge
// This keeps the original (asymmetric) phase spacing; an evenly spaced 50 % duty
// cost 2 more clk of memory latency margin on M1 fetch (rtl/tb/msx_cpu_tb.sv).
// clock_sel may change at any time (OCM turbo): a ce_p right after the previous
// one is dropped, so no CPU half cycle is ever shorter than at 10.7 MHz.
//
// Turbo R Z80 / R800: one core, the registers of each CPU are kept in a context register
// (savestate REG / DIR of TV80). The switch is made on the CE_n of T1 of the first M1 after
// the S1990 selects the other CPU (instruction boundary, as openMSX): the running context is
// stored and the other one loaded in that clk, so the fetch already uses the new PC. The R800
// context is reset only by a cold reset: the BIOS warm boot expects the R800 still parked
// (doc/turboR.md chapter 6).
// R800 timing: 7.16 MHz, no M1 wait state; two accesses to the VDP (98-9B) at least 62 R800
// cycles apart (openMSX VDPIODelay, 8.7 us). The core keeps the Z80 cycle counts, so a real
// R800 is still about twice as fast per instruction. On a turbo R the Z80 gets one extra wait
// state on the VDP ports (T9769, openMSX VDP::getDelayCycles).

module msx_cpu (
    clock_bus_if.base_mp clock_bus,
    input                reset,
    input          [1:0] clock_sel,     // 00/11 3.58 MHz, 01 10.7 MHz, 10 5.39 MHz
    input          [2:0] m1_wait,       // wait states inserted after M1
    input          [3:0] mem_wait,      // wait states on each memory access (incl. M1)
    input          [3:0] io_wait,       // extra wait states on each I/O access
    input                ext_wait,      // level wait request from the bus (MegaSD SPI, OPLL busy)
    input                r800,          // R800 instructions MULUB / MULUW (OCM CPU type)
    input                r800_sel,      // CPU selected by the S1990 (1 = R800)
    input                turbor,        // turbo R machine: Z80 VDP I/O wait (T9769)
    input                cold_reset,    // power-up / menu reset / pack upload: R800 context to reset
    output logic         r800_active,   // CPU running now (1 = R800)
    output logic         bus_phase,     // clk in which MREQ / IORQ / RD / WR may become active (after CE_n)
    input                int_rq,
    input          [7:0] di,
    output               m1_n,
    output               mreq_n,
    output               iorq_n,
    output               rd_n,
    output               wr_n,
    output               rfsh_n,
    output        [15:0] addr,
    output         [7:0] dout
);

    logic ce_sel;
    always_comb begin
        if (r800_active) ce_sel = clock_bus.ce_7m16_n;
        else case (clock_sel)
            2'b01:   ce_sel = clock_bus.ce_10m7_n;
            2'b10:   ce_sel = clock_bus.ce_5m39_n;
            default: ce_sel = clock_bus.ce_3m58_n;
        endcase
    end

    logic ce_n = 1'b0;
    wire  ce_p = ce_sel && ~ce_n;           // never on two consecutive clk (speed switch)
    always_ff @(posedge clock_bus.clk) ce_n <= ce_p;
    always_ff @(posedge clock_bus.clk) bus_phase <= ce_n;

    // M1 wait states (former negedge of the CPU clock)
    logic [2:0] wait_count = '0;
    logic       last_m1    = 1'b0;
    always_ff @(posedge clock_bus.clk) begin
        if (ce_n) begin
            last_m1 <= ~m1_n;
            if (~last_m1 && ~m1_n)
                wait_count <= r800_active ? 3'd0 : m1_wait;
            else if (wait_count != 3'd0)
                wait_count <= wait_count - 3'd1;
        end
    end

    // Memory / I/O wait states (OCM turbo): loaded on the first rising CPU edge that sees
    // the new MREQ / IORQ (T2), so the CPU samples WAIT_n low at the end of T2.
    logic [3:0] acc_wait  = '0;
    logic       last_mreq = 1'b0, last_iorq = 1'b0;
    always_ff @(posedge clock_bus.clk) begin
        if (reset) begin
            acc_wait  <= '0;
            last_mreq <= 1'b0;
            last_iorq <= 1'b0;
        end else if (ce_p) begin
            last_mreq <= ~mreq_n;
            last_iorq <= ~iorq_n;
            if (~mreq_n && ~last_mreq && rfsh_n)
                acc_wait <= mem_wait;
            else if (~iorq_n && ~last_iorq && m1_n)
                acc_wait <= io_wait + {3'b0, turbor && !r800_active && vdp_io};
            else if (acc_wait != 4'd0)
                acc_wait <= acc_wait - 4'd1;
        end
    end

    // VDP I/O (98-9B): the R800 waits until 62 of its cycles passed since the last access
    // (counted from the accepted T2); the hold also covers an access right after the switch
    wire        vdp_io = ~iorq_n && m1_n && addr[7:2] == 6'b100110;
    logic [5:0] vdp_hold = '0;
    logic       vdp_acc  = 1'b0;
    always_ff @(posedge clock_bus.clk) begin
        if (reset) begin
            vdp_hold <= '0;
            vdp_acc  <= 1'b0;
        end else if (ce_p) begin
            if (vdp_hold != 6'd0) vdp_hold <= vdp_hold - 6'd1;
            if (!vdp_io)
                vdp_acc <= 1'b0;
            else if (!vdp_acc && vdp_hold == 6'd0) begin
                vdp_acc  <= 1'b1;
                vdp_hold <= 6'd61;
            end
        end
    end
    wire vdp_wait = r800_active && vdp_io && !vdp_acc && vdp_hold != 6'd0;

    // Z80 / R800 context switch
    // IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A (openMSX doReset)
    localparam logic [211:0] R800_RESET_CTX = {2'b00, 2'd0, {8{16'hFFFF}}, 16'h0000, 16'hFFFF,
                                               8'h00, 8'h00, 8'hFF, 8'hFF, 8'hFF, 8'hFF};
    logic [211:0] ctx_z80, ctx_r800;
    wire  [211:0] core_reg;
    wire    [2:0] core_mc, core_ts;
    wire          core_intcycle_n;
    // not while an interrupt acknowledge is decided: the old CPU finishes it first
    wire          swap = ~reset && ce_n && (r800_sel != r800_active) &&
                         core_mc == 3'd1 && core_ts == 3'd1 && core_intcycle_n;

    always_ff @(posedge clock_bus.clk) begin
        if (reset)
            r800_active <= 1'b0;
        else if (swap) begin
            r800_active <= r800_sel;
            if (r800_active) ctx_r800 <= core_reg;
            else             ctx_z80  <= core_reg;
        end
        if (cold_reset)
            ctx_r800 <= R800_RESET_CTX;
    end

    TV80a #(.Mode(0), .R800_MULU(1), .IOWait(1)) Z80 (
        .RESET_n   (~reset),
        .R800_mode (r800 || r800_active),
        .CLK       (clock_bus.clk),
        .CE_p      (ce_p),
        .CE_n      (ce_n),
        .WAIT_n    (wait_count == 3'd0 && acc_wait == 4'd0 && ~ext_wait && ~vdp_wait),
        .INT_n     (~int_rq),
        .NMI_n     ('1),
        .BUSRQ_n   ('1),
        .M1_n      (m1_n),
        .MREQ_n    (mreq_n),
        .IORQ_n    (iorq_n),
        .RD_n      (rd_n),
        .WR_n      (wr_n),
        .RFSH_n    (rfsh_n),
        .HALT_n    (),
        .BUSAK_n   (),
        .A         (addr),
        .DI        (di),
        .DO        (dout),
        .MC        (core_mc),
        .TS        (core_ts),
        .IntCycle_n(core_intcycle_n),
        .REG       (core_reg),
        .DIRSet    (swap),
        .DIR       (r800_active ? ctx_z80 : ctx_r800)
    );

endmodule
