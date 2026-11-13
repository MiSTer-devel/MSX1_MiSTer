// CPU speed and VDP port timing of msx_cpu (doc/cpu.md, doc/turboR.md chapter 3 and 6):
//   - Z80 3.58 MHz with one M1 wait: NOP 5 T = 30 clk; T9769 (vdp_io_wait): one more wait
//     state on the VDP ports (98-9B);
//   - R800: Z80 T states at 10.7 MHz, no M1 wait state (NOP 4 T = 8 clk); I/O cycles with
//     3 wait states (OUT (n),A 14 T = 28 clk = 9.3 cycles of 7.16 MHz); MULUB 14 and MULUW 36
//     cycles of 7.16 MHz (42 / 108 clk); two accesses to the VDP ports start exactly 62 R800
//     cycles (186 clk) apart when they come sooner (openMSX VDPIODelay), reads and writes;
//     other ports not delayed;
//   - the Z80 timing is back after the switch to the Z80;
//   - Matsushita turbo (5.37 MHz, vdp_wr_wait): two VDP writes start 46 cycles of 5.37 MHz
//     apart, reads are not delayed (openMSX MSXMatsushita);
//   - clock_sel 3: Z80 at 7.16 MHz (CIEL turbo).
// "Start" is what the devices see: the bus strobes masked by io_hold, as in msx.sv.
// Zero-latency memory, r800_sel driven directly (the S1990 is not part of the test). Program
// (both CPUs start at 0000h): LD A,0; OUT (98h),A x2; OUT (A0h),A x2; IN A,(98h) x2;
// MULUB A,B; MULUW HL,BC (NOPs on the Z80); 16 x NOP; JP 0000h.
// Plusargs: +turbor=0 (no T9769 wait), +v verbose. OLD_CPU (run_r800_timing.sh ALT=<dir>): the
// msx_cpu before io_hold (port turbor), must fail.
// Run: wsl.exe -- bash rtl/tb/run_r800_timing.sh
module r800_timing_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

logic        reset = 1, cold_reset = 1, r800_sel = 0, turbor = 1, verbose = 0;
logic        wr_hold = 0, wr_wait = 0;
logic  [1:0] clock_sel = 2'd0;
logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;
logic        active;                        // CPU running now (1 = R800)
logic        io_hold;

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (clock_sel),
    .m1_wait   (3'd1),
    .mem_wait  (4'd0),
    .io_wait   (4'd0),
    .ext_wait  (1'b0),
    .r800      (1'b0),
    .r800_sel  (r800_sel),
`ifndef OLD_CPU
    .cmos_z80  (1'b0),
    .vdp_io_wait(turbor),
    .vdp_wr_hold(wr_hold),
    .vdp_wr_wait(wr_wait),
    .io_hold   (io_hold),
`else
    .turbor    (turbor),
`endif
    .cold_reset(cold_reset),
    .r800_active(active),
    .bus_phase (),
    .bus_phase_next(),
    .int_rq    (1'b0),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);
`ifdef OLD_CPU
assign io_hold = 1'b0;
`endif

// ---------------- memory ----------------
logic [7:0] mem [0:255];
localparam logic [15:0] NOP_FIRST = 16'h0012, NOP_LAST = 16'h0021;
initial begin
    foreach (mem[i]) mem[i] = 8'h00;
    {mem[0], mem[1]} = {8'h3E, 8'h00};                      // LD A,0
    {mem[2], mem[3], mem[4], mem[5]} = {8'hD3, 8'h98, 8'hD3, 8'h98};    // OUT (98h),A x2
    {mem[6], mem[7], mem[8], mem[9]} = {8'hD3, 8'hA0, 8'hD3, 8'hA0};    // OUT (A0h),A x2
    {mem[10], mem[11], mem[12], mem[13]} = {8'hDB, 8'h98, 8'hDB, 8'h98}; // IN A,(98h) x2
    {mem[14], mem[15], mem[16], mem[17]} = {8'hED, 8'hC1, 8'hED, 8'hC3}; // MULUB A,B; MULUW HL,BC
    {mem[34], mem[35], mem[36]} = {8'hC3, 8'h00, 8'h00};    // JP 0000h (0012h-0021h: NOP)
end
assign di = (~mreq_n && ~rd_n) ? mem[addr[7:0]] : 8'h00;    // IN reads 00h (A stays 0)

// ---------------- monitors (clk counts) ----------------
int unsigned cyc = 0;
always @(posedge clk) cyc++;

// per phase: NOP M1 interval (min / max), I/O cycle lengths (IORQ low, waits included), the
// gap between the ends of the two OUT cycles of a pair (98h, A0h) and the starts of the four
// VDP accesses as the devices see them (OUT, OUT, IN, IN)
typedef struct { int nop_min, nop_max, len98_1, len98_2, lenA0, gap98, gapA0, loops, mulub, muluw; int s98[4]; } meas_t;
meas_t m;
task automatic clear_meas();
    m = '{nop_min: 1 << 30, nop_max: 0, len98_1: -1, len98_2: -1, lenA0: -1, gap98: -1, gapA0: -1, loops: 0,
          mulub: -1, muluw: -1, s98: '{-1, -1, -1, -1}};
endtask

logic        m1_q = 0, io_q = 0, dev_q = 0, measure = 0;
int          t_m1 = 0, t_io_start = 0, t_98 = -1, t_A0 = -1, t_mul = 0;
int          n98 = 0, nA0 = 0, d98 = 0;
wire         m1_act  = ~m1_n && ~mreq_n;
wire         io_act  = ~iorq_n && m1_n;
wire         dev_act = io_act && !io_hold;                  // I/O cycle as the devices see it
always @(posedge clk) begin
    m1_q  <= m1_act;
    io_q  <= io_act;
    dev_q <= dev_act;
    if (m1_act && !m1_q) begin                              // M1 starts
        if (measure && addr > NOP_FIRST && addr <= NOP_LAST) begin
            if (cyc - t_m1 < m.nop_min) m.nop_min = cyc - t_m1;
            if (cyc - t_m1 > m.nop_max) m.nop_max = cyc - t_m1;
        end
        if (measure && addr == 16'h0010) m.mulub = cyc - t_mul;     // MULUB: 000Eh to 0010h
        if (measure && addr == 16'h0012) m.muluw = cyc - t_mul;     // MULUW: 0010h to 0012h
        if (addr == 16'h000E || addr == 16'h0010) t_mul = cyc;
        if (addr == 16'h0000) begin
            if (measure) m.loops++;
            n98 = 0; nA0 = 0; d98 = 0;
        end
        t_m1 = cyc;
    end
    if (dev_act && !dev_q && addr[7:0] == 8'h98) begin      // VDP access starts
        if (measure && d98 < 4) m.s98[d98] = cyc;
        d98++;
    end
    if (io_act && !io_q) t_io_start = cyc;                  // I/O cycle starts
    if (!io_act && io_q && measure) begin                   // I/O cycle ends
        if (addr[7:0] == 8'h98) begin
            n98++;
            if (n98 == 1) begin m.len98_1 = cyc - t_io_start; t_98 = cyc; end
            if (n98 == 2) begin m.len98_2 = cyc - t_io_start; m.gap98 = cyc - t_98; end
        end else if (addr[7:0] == 8'hA0) begin
            nA0++;
            m.lenA0 = cyc - t_io_start;
            if (nA0 == 1) t_A0 = cyc;
            if (nA0 == 2) m.gapA0 = cyc - t_A0;
        end
    end
end

// ---------------- checks ----------------
int errors = 0;
task automatic fail(input string s);
    $display("FAIL %s", s);
    errors++;
endtask
task automatic expect_eq(input string what, input int got, input int exp);
    if (got != exp) fail($sformatf("%s: %0d (expected %0d)", what, got, exp));
endtask

// the device sees a held access at least as long as a plain I/O cycle
task automatic check_window(input string phase);
    int win = m.gap98 - (m.s98[1] - m.s98[0]) + m.len98_1;
    if (win < m.len98_1) fail($sformatf("%s held VDP access seen for %0d clk, one not held %0d", phase, win, m.len98_1));
endtask

// run complete loops of the program and report
task automatic run_loops(input string phase, input int n);
    @(posedge clk); wait (m1_act && addr == 16'h0000);     // align to the loop start
    @(posedge clk); clear_meas(); measure = 1;
    wait (m.loops == n); @(posedge clk); measure = 0;
    if (verbose || errors)
        $display("%s: NOP M1 interval %0d..%0d clk, OUT(98) %0d / %0d clk, OUT(A0) %0d clk, gap 98 %0d, gap A0 %0d, VDP starts +%0d +%0d +%0d, MULUB %0d, MULUW %0d",
                 phase, m.nop_min, m.nop_max, m.len98_1, m.len98_2, m.lenA0, m.gap98, m.gapA0,
                 m.s98[1] - m.s98[0], m.s98[2] - m.s98[1], m.s98[3] - m.s98[2], m.mulub, m.muluw);
endtask

initial begin
    int t, w;
    if ($value$plusargs("turbor=%d", t)) turbor = t[0];
    verbose = $test$plusargs("v");
    w = turbor ? 1 : 0;                                     // T9769 wait state

    repeat (4) @(posedge clk); cold_reset = 0;
    repeat (4) @(posedge clk); reset = 0;

    // --- Z80 (3.58 MHz, M1 wait 1): NOP 5 T = 30 clk, VDP port one T (6 clk) longer with the T9769
    run_loops("Z80", 3);
    expect_eq("Z80 NOP interval min", m.nop_min, 30);
    expect_eq("Z80 NOP interval max", m.nop_max, 30);
    expect_eq("Z80 OUT (98) I/O cycle (T9769)", m.len98_1, m.lenA0 + 6 * w);
    expect_eq("Z80 second OUT (98) the same", m.len98_2, m.len98_1);
    expect_eq("Z80 gap of the OUT (98) pair", m.gap98, m.gapA0 + 6 * w);
    expect_eq("Z80 gap of the OUT (A0) pair", m.gapA0, 12 * 6);                 // OUT (n),A = 11 T + M1 wait
    expect_eq("Z80 VDP writes not held", m.s98[1] - m.s98[0], (12 + w) * 6);
    expect_eq("Z80 VDP reads not held", m.s98[3] - m.s98[2], (12 + w) * 6);
    expect_eq("Z80 ED C1 is a NOP", m.mulub, 10 * 6);
    expect_eq("Z80 ED C3 is a NOP", m.muluw, 10 * 6);
    if (active) fail("R800 active without a request");

    // --- R800 (10.7 MHz, no M1 wait): NOP 4 T = 8 clk, I/O with 3 wait states, MULUB / MULUW
    // 14 / 36 cycles of 7.16 MHz, VDP accesses start 62 such cycles = 186 clk apart
    r800_sel = 1;
    @(posedge clk); wait (active); if (verbose) $display("%0t R800 active", $time);
    run_loops("R800", 4);
    expect_eq("R800 NOP interval min", m.nop_min, 8);
    expect_eq("R800 NOP interval max", m.nop_max, 8);
    expect_eq("R800 gap of the OUT (A0) pair", m.gapA0, (11 + 3) * 2);          // OUT (n),A = 11 T + 3 waits
    expect_eq("R800 MULUB", m.mulub, 14 * 3);
    expect_eq("R800 MULUW", m.muluw, 36 * 3);
    expect_eq("R800 first OUT (98) not delayed", m.len98_1, m.lenA0);
    expect_eq("R800 VDP write after write", m.s98[1] - m.s98[0], 62 * 3);
    expect_eq("R800 VDP read after write", m.s98[2] - m.s98[1], 62 * 3);
    expect_eq("R800 VDP read after read", m.s98[3] - m.s98[2], 62 * 3);
    if (m.len98_2 <= m.lenA0) fail("R800 second OUT (98) not stretched by wait states");
    check_window("R800");

    // --- back to the Z80
    r800_sel = 0;
    @(posedge clk); wait (!active);
    run_loops("Z80 again", 3);
    expect_eq("Z80 again NOP interval", m.nop_max, 30);
    expect_eq("Z80 again OUT (98)", m.len98_1, m.lenA0 + 6 * w);

    // --- Matsushita turbo: 5.37 MHz (4 clk per T), VDP writes 46 T apart, reads not delayed
    clock_sel = 2'd2; wr_hold = 1; wr_wait = 1;
    run_loops("Matsushita turbo", 3);
    expect_eq("turbo NOP interval min", m.nop_min, 5 * 4);
    expect_eq("turbo NOP interval max", m.nop_max, 5 * 4);
    expect_eq("turbo VDP write after write", m.s98[1] - m.s98[0], 46 * 4);
    expect_eq("turbo VDP read after read", m.s98[3] - m.s98[2], (12 + w) * 4);
    expect_eq("turbo gap of the OUT (A0) pair", m.gapA0, 12 * 4);
    if (m.s98[2] - m.s98[1] >= 46 * 4) fail("turbo VDP read held after a write");
    check_window("turbo");

    // --- Matsushita, turbo off: nothing held
    clock_sel = 2'd0; wr_wait = 0;
    run_loops("Matsushita 3.58", 3);
    expect_eq("3.58 NOP interval", m.nop_max, 30);
    expect_eq("3.58 VDP write after write", m.s98[1] - m.s98[0], (12 + w) * 6);
    wr_hold = 0;

    // --- Z80 at 7.16 MHz (CIEL turbo): 3 clk per T
    clock_sel = 2'd3;
    run_loops("Z80 7.16", 3);
    expect_eq("7.16 NOP interval min", m.nop_min, 5 * 3);
    expect_eq("7.16 NOP interval max", m.nop_max, 5 * 3);
    expect_eq("7.16 VDP write after write", m.s98[1] - m.s98[0], (12 + w) * 3);

    if (errors == 0) $display("PASS r800_timing_tb turbor=%0d", turbor);
    else             $display("FAILED r800_timing_tb turbor=%0d: %0d errors", turbor, errors);
    $finish;
end

initial begin
    #40_000_000;
    $display("FAILED r800_timing_tb: timeout (active=%b loops=%0d)", active, m.loops);
    $finish;
end

endmodule
