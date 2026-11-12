// Z80 instruction timing of msx_cpu against the Zilog T states plus the MSX M1 wait state.
// Every opcode (unprefixed, CB, ED, DD, FD, DD CB, FD CB; taken and not taken branches, block
// repeats), the interrupt acknowledge (IM 0 / 1 / 2) and HALT is measured from its first M1 to
// the M1 of the next instruction. Expected: data sheet T states + m1_wait per M1 cycle (a
// prefix byte is an M1 cycle; openMSX Z80.hh); the interrupt acknowledge gets no extra wait.
// Cases and the program come from z80_timing_prog.py.
// Plusargs: +hex=<file> memory image, +wait=<n> M1 wait states (default 1), +sel=<n> clock_sel,
//           +v list every case.
// Run: wsl.exe -- bash rtl/tb/run_z80_timing.sh
module z80_timing_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

`include "z80_timing_cases.svh"

logic        reset = 1, cold_reset = 1, int_rq = 0, verbose = 0;
logic  [1:0] sel = 0;
logic  [2:0] m1_wait = 3'd1;
logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (sel),
    .m1_wait   (m1_wait),
    .mem_wait  (4'd0),
    .io_wait   (4'd0),
    .ext_wait  (1'b0),
    .r800      (1'b0),
    .r800_sel  (1'b0),
`ifdef CPU_HAS_TURBOR
    .turbor    (1'b0),
`else
    .cmos      (1'b0),
    .vdp_io_wait(1'b0),
    .s1990     (1'b0),
`endif
    .cold_reset(cold_reset),
    .r800_active(),
    .bus_phase (),
    .int_rq    (int_rq),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

logic [7:0] mem [0:65535];
assign di = (~mreq_n && ~rd_n) ? mem[addr] : 8'hFF;
always @(posedge clk) if (~mreq_n && ~wr_n) mem[addr] <= dout;

int unsigned cyc = 0;
always @(posedge clk) cyc++;

int  per = 6;                   // clk per T state
int  idx = 0, errors = 0, t0 = 0, last_done = 0;
bit  armed = 0;
logic m1_q = 1;

task automatic m1_event(input int a);
    bit again = 1;
    int dt, exp;
    while (again && idx < N_CASES) begin
        again = 0;
        if (!armed) begin
            if (a == case_x[idx]) begin
                armed = 1;
                t0 = cyc;
            end
        end else if (a == case_y[idx]) begin
            dt  = cyc - t0;
            exp = case_t[idx] + int'(m1_wait) * case_m1[idx];
            if (dt % per != 0 || dt / per != exp) begin
                $display("FAIL %s: %0d T (%0d clk), expected %0d", case_name[idx], dt / per, dt, exp);
                errors++;
            end else if (verbose)
                $display("ok   %s: %0d T", case_name[idx], dt / per);
            idx++;
            armed = 0;
            again = 1;
            last_done = cyc;
        end
    end
endtask

always @(posedge clk) begin
    m1_q <= m1_n;
    if (!reset && m1_q && !m1_n) begin
        if (idx < N_CASES && !armed && case_trig[idx] != 0 && int'(addr) == case_trig[idx]) int_rq <= 1;
        m1_event(int'(addr));
    end
    if (~iorq_n && ~m1_n) int_rq <= 0;
    if (idx == N_CASES) begin
        if (errors == 0) $display("PASS z80_timing_tb wait=%0d sel=%0d: %0d cases", m1_wait, sel, N_CASES);
        else             $display("FAILED z80_timing_tb wait=%0d sel=%0d: %0d errors of %0d cases", m1_wait, sel, errors, N_CASES);
        $finish;
    end
    if (!reset && cyc - last_done > 40000) begin
        $display("FAILED z80_timing_tb: stuck in case %0d (%s), armed=%0d, addr=%04x", idx, case_name[idx], armed, addr);
        $finish;
    end
end

initial begin
    string hex;
    int t;
    if (!$value$plusargs("hex=%s", hex)) hex = "z80_timing.hex";
    $readmemh(hex, mem);
    if ($value$plusargs("wait=%d", t)) m1_wait = t[2:0];
    if ($value$plusargs("sel=%d", t)) sel = t[1:0];
    per = sel == 2'd1 ? 2 : sel == 2'd2 ? 4 : 6;
    verbose = $test$plusargs("v");
    repeat (4) @(posedge clk); cold_reset = 0;
    repeat (4) @(posedge clk); reset = 0;
end

endmodule
