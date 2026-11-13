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
// R800: the core keeps the Z80 T states and runs them at 10.7 MHz without the M1 wait state,
// which is about 3.5x the Z80 (a real R800 needs fewer cycles and is faster still). What the
// R800 does slower than that is stretched to its real length (openMSX R800.hh): an I/O cycle
// gets 3 wait states (IN / OUT 9 - 10 cycles of 7.16 MHz), MULUB takes 14 and MULUW 36 cycles
// (the CPU clock stops for the rest). An opcode fetch needs its data on the 3rd clk edge after
// the request; the SDRAM has it on the 2nd as long as nothing else uses the chip just then,
// which it avoids with bus_phase_next.
//
// VDP ports (98-9B):
//   - T9769 (vdp_io_wait): one more wait state for the Z80 (openMSX VDP::getDelayCycles);
//   - R800: two accesses start at least 62 R800 cycles apart (openMSX VDPIODelay, 8.7 us);
//   - Matsushita turbo (vdp_wr_wait): two writes start at least 46 cycles of 5.37 MHz apart
//     (openMSX MSXMatsushita::delay, 8.6 us).
// An access that comes too early is held back: io_hold masks the bus strobes (msx.sv) and
// /WAIT stops the CPU in T2, so the device sees the access when the gap is over.

module msx_cpu (
    clock_bus_if.base_mp clock_bus,
    input                reset,
    input          [1:0] clock_sel,     // 00 3.58 MHz, 01 10.7 MHz, 10 5.37 MHz, 11 7.16 MHz
    input          [2:0] m1_wait,       // wait states inserted after M1
    input          [3:0] mem_wait,      // wait states on each memory access (incl. M1)
    input          [3:0] io_wait,       // extra wait states on each I/O access
    input                ext_wait,      // level wait request from the bus (MegaSD SPI, OPLL busy)
    input                r800,          // R800 instructions MULUB / MULUW (OCM CPU type)
    input                r800_sel,      // CPU selected by the S1990 (1 = R800)
    input                cmos_z80,      // CMOS Z80 (Toshiba MSX-Engine): OUT (C),0 = FFh, SCF / CCF keep Y
    input                vdp_io_wait,   // T9769: one more wait state on the VDP ports (Z80)
    input                vdp_wr_hold,   // Matsushita with turbo: VDP writes are timed
    input                vdp_wr_wait,   // Matsushita turbo on: VDP writes keep the gap
    output               io_hold,       // pending VDP access must not start yet
    output logic         r800_active,   // CPU running now (1 = R800)
    output logic         bus_phase,     // clk in which MREQ / IORQ / RD / WR may become active (after CE_n)
    output               bus_phase_next, // bus_phase one clk ahead (SDRAM: no other work then)
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
        if (r800_active) ce_sel = clock_bus.ce_10m7_n;
        else case (clock_sel)
            2'b01:   ce_sel = clock_bus.ce_10m7_n;
            2'b10:   ce_sel = clock_bus.ce_5m39_n;
            2'b11:   ce_sel = clock_bus.ce_7m16_n;
            default: ce_sel = clock_bus.ce_3m58_n;
        endcase
    end

    // R800 multiply: MULUB 14 and MULUW 36 cycles of 7.16 MHz (42 / 108 clk); the core needs
    // 11 / 13 T states (22 / 26 clk), the CPU clock stops for the rest
    localparam logic [6:0] MULUB_STOP = 7'd42 - 7'd22, MULUW_STOP = 7'd108 - 7'd26;
    wire  [1:0] core_mulu;
    logic       mulu_q  = 1'b0;
    logic [6:0] ce_stop = '0;
    always_ff @(posedge clock_bus.clk) begin
        mulu_q <= core_mulu[0];
        if (ce_stop != 7'd0)
            ce_stop <= ce_stop - 7'd1;
        else if (r800_active && core_mulu[0] && ~mulu_q)
            ce_stop <= core_mulu[1] ? MULUW_STOP : MULUB_STOP;
    end

    logic ce_n = 1'b0;
    wire  ce_p = ce_sel && ~ce_n && ce_stop == 7'd0;    // never on two consecutive clk (speed switch)
    always_ff @(posedge clock_bus.clk) ce_n <= ce_p;
    always_ff @(posedge clock_bus.clk) bus_phase <= ce_n;
    assign bus_phase_next = ce_n;

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
                acc_wait <= io_wait + (r800_active ? 4'd3 : {3'b0, vdp_io_wait && vdp_io});
            else if (acc_wait != 4'd0)
                acc_wait <= acc_wait - 4'd1;
        end
    end

    // VDP I/O (98-9B): minimum gap between the starts of two accesses, counted in clk.
    // R800: every access, 62 cycles of 7.16 MHz (186 clk); Matsushita turbo: writes, 46 cycles of
    // 5.37 MHz. The gap is timed in every mode, so it also covers the first access after
    // the switch to the R800 / to the turbo.
    localparam logic [7:0] VDP_GAP_R800  = 8'd62 * 8'd3 - 8'd1;
    localparam logic [7:0] VDP_GAP_TURBO = 8'd46 * 8'd4 - 8'd1;
    wire        vdp_io     = ~iorq_n && m1_n && addr[7:2] == 6'b100110;
    wire        vdp_wr     = vdp_io && rd_n;
    wire        vdp_spaced = r800_active || (vdp_wr_wait && vdp_wr);    // this access keeps the gap
    logic [7:0] vdp_hold = '0;
    logic       vdp_acc  = 1'b0;                // the access has started
    logic [2:0] vdp_post = '0;                  // a held access gets the usual time after its start
    logic       vdp_held_q = 1'b0;
    wire        vdp_held = vdp_spaced && vdp_io && !vdp_acc && vdp_hold != 8'd0;
    always_ff @(posedge clock_bus.clk) begin
        if (reset) begin
            vdp_hold <= '0;
            vdp_acc  <= 1'b0;
            vdp_post <= '0;
            vdp_held_q <= 1'b0;
        end else begin
            vdp_held_q <= vdp_held;
            if (vdp_hold != 8'd0) vdp_hold <= vdp_hold - 8'd1;
            if (vdp_post != 3'd0) vdp_post <= vdp_post - 3'd1;
            if (!vdp_io)
                vdp_acc <= 1'b0;
            else if (!vdp_acc && !vdp_held) begin
                vdp_acc <= 1'b1;
                if (vdp_wr_hold) begin
                    if (vdp_wr) vdp_hold <= VDP_GAP_TURBO;
                end else
                    vdp_hold <= VDP_GAP_R800;
                if (vdp_held_q) vdp_post <= 3'd7;
            end
        end
    end
    assign io_hold = vdp_held;
    wire   vdp_wait = vdp_held || vdp_held_q || vdp_post != 3'd0;

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
        if (reset)          // the R800 starts at 0000h after every reset (the BIOS cold path)
            ctx_r800 <= R800_RESET_CTX;
    end

    TV80a #(.Mode(0), .R800_MULU(1), .IOWait(1)) Z80 (
        .RESET_n   (~reset),
        .R800_mode (r800 || r800_active),
        .CMOS      (cmos_z80),
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
        .MULU      (core_mulu),
        .REG       (core_reg),
        .DIRSet    (swap),
        .DIR       (r800_active ? ctx_z80 : ctx_r800)
    );

endmodule
