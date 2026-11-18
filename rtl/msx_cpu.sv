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
// Z80: everything runs on clock_bus.clk with two enables per T state:
//   ce_p = pulse of the selected speed -> rising edge of the CPU clock
//   ce_n = pulse delayed by 1          -> falling edge
// This keeps the (asymmetric) phase spacing of the former derived clock; an evenly spaced
// 50 % duty cost 2 more clk of memory latency margin on M1 fetch (rtl/tb/msx_cpu_tb.sv).
// clock_sel may change at any time (OCM turbo): a ce_p right after the previous one is
// dropped, so no CPU half cycle is ever shorter than at 10.7 MHz.
//
// Turbo R Z80 / R800: one core, the registers of each CPU are kept in a context register
// (savestate REG / DIR of TV80). The switch is made in T1 of the first M1 after the S1990
// selects the other CPU (instruction boundary, as openMSX): the running context is stored and
// the other one loaded in that clk, so the fetch already uses the new PC. Every reset starts
// the R800 context from 0000h (the BIOS cold path, doc/turboR.md chapter 6).
//
// R800 (R800_FAST = 1 or 2): the core runs one T state per clk (TV80a FAST, 21.48 M T states
// per second). The SDRAM has the data on the 3rd clk edge after the address, so an opcode fetch
// gets one wait state and a data read is used in its T3 (3 clk = one cycle of the 7.16 MHz
// R800). 1: the T states of the Z80 (M1 = 5 clk). 2: without the idle ones (TV80 TRIM: M1 =
// 4 clk, any other cycle 3).
// r800_pace then keeps the long run speed of a real R800 (openMSX R800.hh): it adds up what
// every bus access and instruction costs there (1 cycle per access, page breaks, slower
// memory, I/O, MULUB / MULUW, DRAM refresh) and holds T1 of the next opcode fetch while the
// core is ahead of that. Where the core needs more clk than the R800 (an instruction in the
// registers: 4 clk against 3), it runs behind and catches up in instructions that leave it
// slack. R800_REFRESH = 0 leaves the DRAM refresh out (test benches).
// R800_FAST = 0 is the former R800: T states at 10.7 MHz, I/O with 3 wait states, MULUB /
// MULUW stretched to 14 / 36 cycles.
//
// VDP ports (98-9B):
//   - T9769 (vdp_io_wait): one more wait state for the Z80 (openMSX VDP::getDelayCycles);
//   - R800: two accesses start at least 62 R800 cycles apart (openMSX VDPIODelay, 8.7 us);
//   - Matsushita turbo (vdp_wr_wait): two writes start at least 46 cycles of 5.37 MHz apart
//     (openMSX MSXMatsushita::delay, 8.6 us).
// An access that comes too early is held back: io_hold masks the bus strobes (msx.sv) and
// /WAIT stops the CPU in T2, so the device sees the access when the gap is over.

module msx_cpu #(parameter R800_FAST = 2, R800_REFRESH = 1) (
    clock_bus_if.base_mp clock_bus,
    input                reset,
    input          [1:0] clock_sel,     // 00 3.58 MHz, 01 10.7 MHz, 10 5.37 MHz, 11 7.16 MHz
    input          [2:0] m1_wait,       // wait states inserted after M1
    input          [3:0] mem_wait,      // wait states on each memory access (incl. M1)
    input          [3:0] io_wait,       // extra wait states on each I/O access
    input                ext_wait,      // level wait request from the bus (MegaSD SPI, OPLL busy)
    input                r800,          // R800 instructions MULUB / MULUW (OCM CPU type)
    input                r800_sel,      // CPU selected by the S1990 (1 = R800)
    input          [1:0] r800_memdelay, // R800: memory at the address on the bus (0 RAM, 1 internal ROM, 2 external slot)
    input                cmos_z80,      // CMOS Z80 (Toshiba MSX-Engine): OUT (C),0 = FFh, SCF / CCF keep Y
    input                vdp_io_wait,   // T9769: one more wait state on the VDP ports (Z80)
    input                vdp_wr_hold,   // Matsushita with turbo: VDP writes are timed
    input                vdp_wr_wait,   // Matsushita turbo on: VDP writes keep the gap
    output               io_hold,       // pending VDP access must not start yet
    output logic         r800_active,   // CPU running now (1 = R800)
    output logic         bus_phase,     // clk in which a bus access may start
    output               bus_phase_next, // bus_phase one clk ahead (SDRAM: no other work then)
    output               acc_start,     // R800: first clk of a read (MREQ / RD may stay low from the access before)
    output               mem_free,      // R800: the read data is taken, the memory may change it (SDRAM)
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

    wire fast = R800_FAST != 0 && r800_active;   // single phase bus

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

    // R800 at 10.7 MHz (R800_FAST = 0) multiply: MULUB 14 and MULUW 36 cycles of 7.16 MHz
    // (42 / 108 clk); the core needs 11 / 13 T states (22 / 26 clk), the CPU clock stops for the rest
    localparam logic [6:0] MULUB_STOP = 7'd42 - 7'd22, MULUW_STOP = 7'd108 - 7'd26;
    wire  [1:0] core_mulu;
    logic       mulu_q  = 1'b0;
    logic [6:0] ce_stop = '0;
    always_ff @(posedge clock_bus.clk) begin
        mulu_q <= core_mulu[0];
        if (ce_stop != 7'd0)
            ce_stop <= ce_stop - 7'd1;
        else if (r800_active && ~fast && core_mulu[0] && ~mulu_q)
            ce_stop <= core_mulu[1] ? MULUW_STOP : MULUB_STOP;
    end

    wire  [14:0] hint;                  // {taken, IX / IY, ISet, IR, operand fetch, last T, last T of the instruction}
    wire   [2:0] core_mc, core_ts;
    wire         core_intcycle_n;
    wire         pace_stall, pace_stall_last;
    wire         swap;

    logic ce_n = 1'b0;
    // Z80: never on two consecutive clk (speed switch). R800: every clk unless paced.
    wire  ce_p = fast ? ~pace_stall : ce_sel && ~ce_n && ce_stop == 7'd0;
    always_ff @(posedge clock_bus.clk) ce_n <= ~fast && ce_p;
    always_ff @(posedge clock_bus.clk) bus_phase <= bus_phase_next;
    // R800: a read starts in T1 (the edge after the last T state of a cycle, after the context
    // switch or after the clk the pacing held T1 for), a write or an I/O access on an edge of its T1
    assign bus_phase_next = fast ? (ce_p && (hint[1] || (core_ts == 3'd1 && core_mc != 3'd1))) || pace_stall_last || swap : ce_n;

    // M1 wait states of the Z80 (falling edge of the CPU clock)
    logic [2:0] wait_count = '0;
    logic       last_m1    = 1'b0;
    always_ff @(posedge clock_bus.clk) begin
        if (swap) begin                 // T1 of the first M1 of the other CPU
            last_m1    <= 1'b1;
            wait_count <= r800_sel ? 3'd0 : m1_wait;
        end else if (ce_n) begin
            last_m1 <= ~m1_n;
            if (~last_m1 && ~m1_n)
                wait_count <= r800_active ? 3'd0 : m1_wait;
            else if (wait_count != 3'd0)
                wait_count <= wait_count - 3'd1;
        end
    end

    // R800 single phase: the SDRAM answers on the 3rd edge, an opcode is taken at the end of T2
    wire  need_tw = fast && core_ts == 3'd2 &&
                    ((core_mc == 3'd1 && core_intcycle_n) || (core_mc == 3'd7 && hint[12:11] == 2'b01));
    logic tw_done = 1'b0;
    always_ff @(posedge clock_bus.clk) if (ce_p) tw_done <= need_tw;
    wire  fetch_wait = need_tw && ~tw_done;

    // Memory / I/O wait states (OCM turbo, R800 I/O): loaded on the first rising CPU edge that
    // sees the new MREQ / IORQ (T2), so the CPU samples WAIT_n low at the end of T2.
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
            if (~mreq_n && ~last_mreq && rfsh_n && ~fast)
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
    // T1 of an M1 (Z80: its falling edge), not while an interrupt acknowledge is decided: the
    // old CPU finishes it first
    assign swap = ~reset && (fast || ce_n) && (r800_sel != r800_active) &&
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

    // R800 pacing: starts of the bus accesses of the single phase bus
    logic wr_q = 1'b0, io_q = 1'b0, inta_q = 1'b0;
    wire  mwr  = ~mreq_n && ~wr_n;
    wire  iorw = ~iorq_n && m1_n;
    wire  inta = ~iorq_n && ~m1_n;
    always_ff @(posedge clock_bus.clk) begin
        wr_q   <= mwr;
        io_q   <= iorw;
        inta_q <= inta;
    end
    wire  acc_fetch = acc_start && (core_mc == 3'd1 || core_mc == 3'd7 || hint[2]);

    r800_pace #(.REFRESH(R800_REFRESH)) pace (
        .clk      (clock_bus.clk),
        .en       (fast),
        .fetch    (acc_fetch),
        .read     (acc_start && ~acc_fetch),
        .write    (mwr && ~wr_q),
        .io       (iorw && ~io_q),
        .inta     (inta && ~inta_q),
        .page     (addr[15:8]),
        .memdelay (r800_memdelay),
        .end_instr(hint[0]),
        .m1_t1    (core_mc == 3'd1 && core_ts == 3'd1),
        .ir       (hint[10:3]),
        .iset     (hint[12:11]),
        .xy       (hint[13]),
        .taken    (hint[14]),
        .hold     (vdp_wait || ext_wait),
        .stall    (pace_stall),
        .stall_last(pace_stall_last)
    );

    TV80a #(.Mode(0), .R800_MULU(1), .IOWait(1)) Z80 (
        .RESET_n   (~reset),
        .R800_mode (r800 || r800_active),
        .CMOS      (cmos_z80),
        .CLK       (clock_bus.clk),
        .CE_p      (ce_p),
        .CE_n      (ce_n),
        .WAIT_n    (wait_count == 3'd0 && acc_wait == 4'd0 && ~ext_wait && ~vdp_wait && ~fetch_wait),
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
        .FAST      (fast),
        .TRIM      (R800_FAST >= 2),
        .HOLD      (pace_stall),
        .ACC_START (acc_start),
        .DATA_FREE (mem_free),
        .HINT      (hint),
        .REG       (core_reg),
        .DIRSet    (swap),
        .DIR       (r800_active ? ctx_z80 : ctx_r800)
    );

endmodule

// Speed of a real R800 for the R800 of msx_cpu on the single phase bus.
// credit = clk the R800 would have needed for what the core has done minus the clk it took.
// Every bus access and every instruction adds its R800 cost (cycles of 7.16 MHz = 3 clk), every
// clk takes one off. With credit left at the end of an instruction the core is ahead: T1 of the
// next opcode fetch waits (bus idle) until it is used up. Without, the core is behind (to DEBT clk at most) and catches up.
// Costs as openMSX R800.hh / doc/internal/r800test.txt:
//   - opcode or operand fetch, data read, data write: 1 cycle;
//   - page break, 1 cycle: the access is of another kind than the one before it (fetch / read /
//     write) or in another 256 byte page; EX (SP),HL writes without it;
//   - memory other than the internal RAM: the page break always and 1 (internal ROM) or
//     2 (external slot) cycles more;
//   - I/O: 1 cycle, to an even cycle, 6 cycles; interrupt acknowledge 1 cycle;
//   - inside the instruction (xcyc): PUSH, RST, DI, IM, taken JR / DJNZ / JP, JP (HL) 1 (and a
//     page break at the target of a JP);
//     read-modify-write of (HL) and (IX+d), RRD / RLD, CPI / CPD 1; (IX+d) address 1;
//     MULUB 12, MULUW 34;
//   - DRAM refresh: after 210 cycles the next instruction end takes 25 more (not after EI).
module r800_pace #(parameter DEBT = 255, REFRESH = 1) (
    input        clk,
    input        en,            // R800 on the single phase bus
    input        fetch,         // 1 clk at the start of an access: opcode / operand fetch
    input        read,          // data read
    input        write,         // data write
    input        io,            // port access
    input        inta,          // interrupt acknowledge
    input  [7:0] page,          // high byte of the address of the access
    input  [1:0] memdelay,
    input        end_instr,     // last T state of the instruction
    input        m1_t1,         // T1 of an M1: the place where the core can wait
    input  [7:0] ir,
    input  [1:0] iset,          // 00 plain, 01 CB, 10 ED
    input        xy,            // IX / IY instruction
    input        taken,         // jump taken
    input        hold,          // the CPU waits for a device (VDP gap, /WAIT): that time is not the core's
    output       stall,         // hold T1
    output       stall_last     // last clk of it
);

    function automatic logic [5:0] xcyc(input logic [1:0] iset, input logic [7:0] ir, input logic xy, input logic taken);
        xcyc = 6'd0;
        case (iset)
            2'b00: begin
                if (ir == 8'hF3) xcyc = 6'd1;                                               // DI
                if (ir[7:6] == 2'b11 && (ir[3:0] == 4'h5 || ir[2:0] == 3'b111)) xcyc = 6'd1; // PUSH, RST
                if (ir == 8'h34 || ir == 8'h35) xcyc = xy ? 6'd2 : 6'd1;                    // INC / DEC (HL), (IX+d)
                if (xy && ir != 8'h76 && ((ir[7:6] == 2'b01 && (ir[2:0] == 3'b110 || ir[5:3] == 3'b110)) ||
                                          (ir[7:6] == 2'b10 && ir[2:0] == 3'b110))) xcyc = 6'd1;   // (IX+d) operand
                if (taken && (ir == 8'h18 || ir == 8'h10 || (ir[7:5] == 3'b001 && ir[2:0] == 3'b000))) xcyc = 6'd1; // JR, DJNZ
                if (taken && (ir == 8'hC3 || (ir[7:6] == 2'b11 && ir[2:0] == 3'b010))) xcyc = 6'd1; // JP
                if (ir == 8'hE9) xcyc = 6'd1;                                               // JP (HL)
            end
            2'b01: if (ir[7:6] != 2'b01 && (xy || ir[2:0] == 3'b110)) xcyc = 6'd1;          // rotate / RES / SET in memory
            2'b10: begin
                if (ir[7:6] == 2'b01 && ir[2:0] == 3'b110) xcyc = 6'd1;                     // IM
                if (ir == 8'h67 || ir == 8'h6F) xcyc = 6'd1;                                // RRD, RLD
                if (ir[7:5] == 3'b101 && ir[2:0] == 3'b001) xcyc = 6'd1;                    // CPI, CPD, CPIR, CPDR
                if (ir[7:5] == 3'b110 && ir[2:0] == 3'b001) xcyc = 6'd12;                   // MULUB
                if (ir == 8'hC3 || ir == 8'hF3) xcyc = 6'd34;                               // MULUW
            end
            default: ;
        endcase
    endfunction

    localparam logic [1:0] K_NONE = 2'd0, K_FETCH = 2'd1, K_READ = 2'd2, K_WRITE = 2'd3;
    localparam logic [8:0] RFSH_PERIOD = 9'd210;
    localparam logic [5:0] RFSH_CYCLES = 6'd25;

    logic signed [11:0] credit = '0;
    logic         [1:0] last_kind = K_NONE;
    logic         [7:0] last_page = '0;
    logic               par = 1'b0;                 // R800 cycle count is odd
    logic         [8:0] since_rfsh = '0;            // R800 cycles since the last refresh
    logic               end_seen = 1'b0;
    logic        [15:0] total = '0;                 // R800 cycles (test benches)

    wire        mem  = fetch || read || write;
    wire  [1:0] kind = fetch ? K_FETCH : read ? K_READ : K_WRITE;
    wire        ex_sp = write && iset == 2'b00 && ir == 8'hE3;
    wire        brk  = memdelay != 2'd0 || page != last_page || (kind != last_kind && ~ex_sp);
    wire        end_first = end_instr && ~end_seen;
    wire        ei   = iset == 2'b00 && ir == 8'hFB && ~xy;
    wire        jp   = iset == 2'b00 && taken && (ir == 8'hC3 || (ir[7:6] == 2'b11 && ir[2:0] == 3'b010));
    wire        rfsh = REFRESH != 0 && end_first && since_rfsh >= RFSH_PERIOD && ~ei;

    logic [5:0] add;
    always_comb begin
        add = 6'd0;
        if (mem)        add = 6'd1 + {5'd0, brk} + {4'd0, memdelay};
        else if (io)    add = 6'd7 + {5'd0, ~par};                      // 1, to an even cycle, 6
        else if (inta)  add = 6'd1;
        if (end_first)  add = add + xcyc(iset, ir, xy, taken) + (rfsh ? RFSH_CYCLES + {5'd0, par} : 6'd0);
    end
    localparam logic signed [11:0] CREDIT_MIN = -DEBT, CREDIT_MAX = 12'sd1500;
    wire        [11:0] add12 = {6'd0, add};
    wire signed [11:0] gain  = $signed(add12 + add12 + add12);         // 3 clk per cycle
    wire signed [11:0] next  = credit + gain - (hold ? 12'sd0 : 12'sd1);

    // more than 1 left = still ahead at the next edge. T1 of the next M1 waits, with the bus
    // idle: the strobes of the access before it keep their length.
    assign stall      = en && m1_t1 && credit > 12'sd1;
    assign stall_last = stall && credit == 12'sd2;

    always_ff @(posedge clk) begin
        if (~en) begin
            credit     <= '0;
            last_kind  <= K_NONE;
            par        <= 1'b0;
            since_rfsh <= '0;
            end_seen   <= 1'b0;
        end else begin
            credit <= next < CREDIT_MIN ? CREDIT_MIN : next > CREDIT_MAX ? CREDIT_MAX : next;
            if (mem) begin
                last_kind <= kind;
                last_page <= page;
            end else if (end_first && jp)
                last_kind <= K_NONE;                // the fetch at the target of a JP has a page break
            par        <= par ^ add[0];
            since_rfsh <= rfsh ? since_rfsh - RFSH_PERIOD + {3'd0, add} : since_rfsh >= 9'd448 ? since_rfsh : since_rfsh + {3'd0, add};
            end_seen   <= end_instr;
            total      <= total + {10'd0, add};
        end
    end

endmodule
