// R800 timing of msx_cpu (turbo R, doc/turboR.md chapter 3 and 6):
//   - R800: 7.16 MHz, no M1 wait state (NOP every 4 T = 12 clk; Z80 at 3.58 MHz with one M1
//     wait: 5 T = 30 clk);
//   - R800: two accesses to the VDP ports (98-9B) at least 62 R800 cycles apart (openMSX
//     VDPIODelay), other ports not delayed;
//   - Z80 on a turbo R (turbor = 1): one extra wait state on the VDP ports (T9769);
//   - the Z80 timing is back after the switch to the Z80.
// Zero-latency memory, r800_sel driven directly (the S1990 is not part of the test). Program
// (both CPUs start at 0000h): LD A,0; OUT (98h),A x2; OUT (A0h),A x2; 16 x NOP; JP 0000h.
// Plusargs: +turbor=0 (no T9769 wait), +v verbose. OLD_CPU (run_r800_timing.sh ALT=<dir>): the
// core before the R800 timing, must fail.
// Run: wsl.exe -- bash rtl/tb/run_r800_timing.sh
module r800_timing_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

logic        reset = 1, cold_reset = 1, r800_sel = 0, turbor = 1, verbose = 0;
logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;
logic        active;                        // CPU running now (1 = R800)

`ifndef OLD_CPU
logic        r800_active;
assign active = r800_active;
`else
assign active = r800_sel;
`endif

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (2'd0),                      // Z80: 3.58 MHz
    .m1_wait   (3'd1),
    .mem_wait  (4'd0),
    .io_wait   (4'd0),
    .ext_wait  (1'b0),
    .r800      (1'b0),
`ifndef OLD_CPU
    .r800_sel  (r800_sel),
    .turbor    (turbor),
    .cold_reset(cold_reset),
    .r800_active(r800_active),
`endif
    .int_rq    (1'b0),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

// ---------------- memory ----------------
logic [7:0] mem [0:255];
localparam logic [15:0] NOP_FIRST = 16'h000A, NOP_LAST = 16'h0019;
initial begin
    foreach (mem[i]) mem[i] = 8'h00;
    {mem[0], mem[1]} = {8'h3E, 8'h00};                      // LD A,0
    {mem[2], mem[3], mem[4], mem[5]} = {8'hD3, 8'h98, 8'hD3, 8'h98};    // OUT (98h),A x2
    {mem[6], mem[7], mem[8], mem[9]} = {8'hD3, 8'hA0, 8'hD3, 8'hA0};    // OUT (A0h),A x2
    {mem[26], mem[27], mem[28]} = {8'hC3, 8'h00, 8'h00};    // JP 0000h (000Ah-0019h: NOP)
end
assign di = (~mreq_n && ~rd_n) ? mem[addr[7:0]] : 8'hFF;

// ---------------- monitors (clk counts) ----------------
int unsigned cyc = 0;
always @(posedge clk) cyc++;

// per phase: NOP M1 interval (min / max), I/O cycle lengths (IORQ low, waits included) and the
// gap between the ends of the two I/O cycles of a pair for ports 98h and A0h (the delay is made
// of wait states inside the second cycle, so the end is the moment of the access)
typedef struct { int nop_min, nop_max, len98_1, len98_2, lenA0, gap98, gapA0, loops; } meas_t;
meas_t m;
task automatic clear_meas();
    m = '{nop_min: 1 << 30, nop_max: 0, len98_1: -1, len98_2: -1, lenA0: -1, gap98: -1, gapA0: -1, loops: 0};
endtask

logic        m1_q = 0, io_q = 0, measure = 0;
int          t_m1 = 0, t_io_start = 0, t_98 = -1, t_A0 = -1;
int          n98 = 0, nA0 = 0;
wire         m1_act = ~m1_n && ~mreq_n;
wire         io_act = ~iorq_n && m1_n;
always @(posedge clk) begin
    m1_q <= m1_act;
    io_q <= io_act;
    if (m1_act && !m1_q) begin                              // M1 starts
        if (measure && addr > NOP_FIRST && addr <= NOP_LAST) begin
            if (cyc - t_m1 < m.nop_min) m.nop_min = cyc - t_m1;
            if (cyc - t_m1 > m.nop_max) m.nop_max = cyc - t_m1;
        end
        if (addr == 16'h0000) begin
            if (measure) m.loops++;
            n98 = 0; nA0 = 0;
        end
        t_m1 = cyc;
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

// run complete loops of the program and report
task automatic run_loops(input string phase, input int n);
    @(posedge clk); wait (m1_act && addr == 16'h0000);     // align to the loop start
    @(posedge clk); clear_meas(); measure = 1;
    wait (m.loops == n); @(posedge clk); measure = 0;
    if (verbose || errors)
        $display("%s: NOP M1 interval %0d..%0d clk, OUT(98) %0d / %0d clk, OUT(A0) %0d clk, gap 98 %0d, gap A0 %0d",
                 phase, m.nop_min, m.nop_max, m.len98_1, m.len98_2, m.lenA0, m.gap98, m.gapA0);
endtask

initial begin
    int t;
    if ($value$plusargs("turbor=%d", t)) turbor = t[0];
    verbose = $test$plusargs("v");

    repeat (4) @(posedge clk); cold_reset = 0;
    repeat (4) @(posedge clk); reset = 0;

    // --- Z80 (3.58 MHz, M1 wait 1): NOP 5 T = 30 clk, VDP port one T (6 clk) longer with the T9769
    run_loops("Z80", 3);
    expect_eq("Z80 NOP interval min", m.nop_min, 30);
    expect_eq("Z80 NOP interval max", m.nop_max, 30);
    expect_eq("Z80 OUT (98) I/O cycle (T9769)", m.len98_1, m.lenA0 + (turbor ? 6 : 0));
    expect_eq("Z80 second OUT (98) the same", m.len98_2, m.len98_1);
    expect_eq("Z80 gap of the OUT (98) pair", m.gap98, m.gapA0 + (turbor ? 6 : 0));
    expect_eq("Z80 gap of the OUT (A0) pair", m.gapA0, 12 * 6);                 // OUT (n),A = 11 T + M1 wait
    if (active) fail("R800 active without a request");

    // --- R800 (7.16 MHz, no M1 wait): NOP 4 T = 12 clk, VDP pair 62 T = 186 clk apart
    r800_sel = 1;
    @(posedge clk); wait (active); if (verbose) $display("%0t R800 active", $time);
    run_loops("R800", 4);
    expect_eq("R800 NOP interval min", m.nop_min, 12);
    expect_eq("R800 NOP interval max", m.nop_max, 12);
    expect_eq("R800 gap of the OUT (A0) pair", m.gapA0, 11 * 3);                // OUT (n),A = 11 T
    expect_eq("R800 first OUT (98) not delayed", m.len98_1, m.lenA0);
    if (m.gap98 < 61 * 3) fail($sformatf("R800 gap of the OUT (98) pair %0d clk, expected >= %0d", m.gap98, 61 * 3));
    if (m.gap98 > 63 * 3) fail($sformatf("R800 gap of the OUT (98) pair %0d clk, expected <= %0d", m.gap98, 63 * 3));
    expect_eq("R800 second OUT (98) delayed by waits", m.len98_2, m.lenA0 + m.gap98 - m.gapA0);

    // --- back to the Z80
    r800_sel = 0;
    @(posedge clk); wait (!active);
    run_loops("Z80 again", 3);
    expect_eq("Z80 again NOP interval", m.nop_max, 30);
    expect_eq("Z80 again OUT (98)", m.len98_1, m.lenA0 + (turbor ? 6 : 0));

    if (errors == 0) $display("PASS r800_timing_tb turbor=%0d", turbor);
    else             $display("FAILED r800_timing_tb turbor=%0d: %0d errors", turbor, errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("FAILED r800_timing_tb: timeout (active=%b loops=%0d)", active, m.loops);
    $finish;
end

endmodule
