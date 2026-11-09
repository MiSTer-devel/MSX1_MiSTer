// Z80 / R800 context switch of msx_cpu (turbo R, doc/turboR.md chapter 6).
//
// Runs cpu_switch_prog.svh (CHGCPU as in the FS-A1ST BIOS) with a model of the S1990 (E4 / E5,
// register 6 bit 5 = Z80) and of the F4 reset status. Checks:
//   - after each switch the new CPU fetches where it was parked: the R800 from 0000h after a cold
//     reset, the Z80 inside its OTIR, the R800 after its OTIR (resume);
//   - every byte of the OTIR reaches E5 exactly once, written by the expected CPU;
//   - the CPU at each marker, registers handed over through the stack;
//   - separate IM (Z80 IM 2, R800 IM 1) and no interrupt acknowledge inside CHGCPU (DI);
//   - a warm reset keeps the parked R800, a cold reset starts it again from 0000h.
// Plusargs: +sel=<0..2> CPU speed as msx_cpu_tb, +v verbose log.
// OLD_CPU: msx_cpu without the switch ports (run_cpu_switch.sh ALT=<dir>), must fail.
// Run: wsl.exe -- bash rtl/tb/run_cpu_switch.sh
module cpu_switch_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

int unsigned sel = 0;
logic        reset = 1, cold_reset = 1;
logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;
logic        int_rq = 0;
logic        verbose = 0;

// S1990 and F4 models
logic  [7:0] s1990_sel = 0, cpu_status = 8'h60, f4 = 0;
wire         r800_sel = ~cpu_status[5];
logic        active;                        // CPU running now (1 = R800)

`ifndef OLD_CPU
logic        r800_active;
assign active = r800_active;
`else
assign active = r800_sel;                   // no switch in the old core: what the S1990 selects
`endif

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (2'(sel)),
    .m1_wait   (3'd1),
    .mem_wait  (4'd0),
    .io_wait   (4'd0),
    .ext_wait  (1'b0),
    .r800      (1'b0),
`ifndef OLD_CPU
    .r800_sel  (r800_sel),
    .turbor    (1'b0),
    .cold_reset(cold_reset),
    .r800_active(r800_active),
`endif
    .int_rq    (int_rq),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

// ---------------- memory / IO ----------------
logic [7:0] mem [0:65535];
`include "cpu_switch_prog.svh"
initial begin
    foreach (mem[i]) mem[i] = 8'h00;
    load_prog();
end

wire mem_rd  = ~mreq_n & ~rd_n;
wire io_rd   = ~iorq_n & ~rd_n;
wire int_ack = ~iorq_n & ~m1_n;
logic [7:0] io_q;
always_comb
    case (addr[7:0])
        8'hF4:   io_q = f4;
        8'hE4:   io_q = s1990_sel;
        8'hE5:   io_q = s1990_sel == 8'd6 ? cpu_status : 8'hFF;
        default: io_q = 8'hFF;
    endcase
assign di = int_ack ? 8'h00 : io_rd ? io_q : mem_rd ? mem[addr] : 8'hFF;   // IM 2 vector 00h

// ---------------- checks ----------------
typedef enum logic [2:0] { T_M1, T_MRD, T_MWR, T_IORD, T_IOWR, T_INTA } ttype_t;
int errors = 0;
task automatic fail(input string s);
    $display("FAIL %0t: %s", $time, s);
    errors++;
endtask

// expected first fetch after each change of the running CPU: {r800, address}
localparam int NSW = 12;
logic [16:0] exp_sw[NSW] = '{{1'b1, 16'h0000}, {1'b0, L_OTIR_COLD}, {1'b1, L_RESUME}, {1'b0, L_OTIR_CHG},
                             {1'b1, L_RESUME}, {1'b0, L_OTIR_CHG}, {1'b1, L_RESUME},           // warm reset
                             {1'b1, L_RESUME}, {1'b0, L_OTIR_CHG},                              // cold reset
                             {1'b1, 16'h0000}, {1'b0, L_OTIR_COLD}, {1'b1, L_RESUME}};
// expected writes to E5: {r800, data}
localparam int NE5 = 19;
logic [8:0] exp_e5[NE5] = '{{1'b0, 8'h40}, {1'b1, 8'h60}, {1'b0, 8'h60},     // cold boot handshake
                            {1'b0, 8'h40}, {1'b1, 8'h60}, {1'b0, 8'h60},     // marker 1, 2
                            {1'b0, 8'h00}, {1'b1, 8'h60}, {1'b0, 8'h60},     // marker 3, 4
                            {1'b0, 8'h40},                                   // marker 5, warm reset
                            {1'b0, 8'h40}, {1'b1, 8'h60}, {1'b0, 8'h60},     // marker 6, 7, cold reset
                            {1'b0, 8'h40}, {1'b1, 8'h60}, {1'b0, 8'h60},     // cold boot handshake
                            {1'b0, 8'h40},                                   // marker 1
                            9'h1FF, 9'h1FF};
int n_sw = 0, n_e5 = 0, im1_r800 = 0, im2_z80 = 0, marker = 0, phase = 0;
logic act_q = 0, active_q = 0, sw_seen = 0, in_chg = 0, arm = 0;

wire act = (~mreq_n & rfsh_n & (~rd_n | ~wr_n)) | (~iorq_n & (~rd_n | ~wr_n)) | int_ack;

always @(posedge clk) begin
    ttype_t t;
    logic   sw_now;
    act_q    <= act;
    active_q <= active;
    sw_now   = !reset && active != active_q;
    if (sw_now) sw_seen <= 1;
    if (!reset && act && !act_q) begin
        t = int_ack ? T_INTA : ~iorq_n ? (~rd_n ? T_IORD : T_IOWR) :
            ~m1_n ? T_M1 : (~rd_n ? T_MRD : T_MWR);
        case (t)
            T_M1: begin
                if (sw_seen || sw_now) begin
                    sw_seen <= 0;
                    if (verbose) $display("%0t switch -> %s, fetch %04h", $time, active ? "R800" : "Z80", addr);
                    if (n_sw >= NSW) fail($sformatf("switch #%0d not expected", n_sw + 1));
                    else if (exp_sw[n_sw] != {active, addr})
                        fail($sformatf("switch #%0d: %s fetches %04h, expected %s %04h", n_sw + 1,
                             active ? "R800" : "Z80", addr, exp_sw[n_sw][16] ? "R800" : "Z80", exp_sw[n_sw][15:0]));
                    n_sw++;
                end
                if (addr == L_CHG || addr == L_CHG2) in_chg <= 1;
                if (addr == L_CHG_RET)               in_chg <= 0;
                if (addr == L_IM1) begin
                    if (active) im1_r800++; else fail("IM 1 handler on the Z80 (Z80 uses IM 2)");
                end
                if (addr == L_IM2) begin
                    if (!active) im2_z80++; else fail("IM 2 handler on the R800 (R800 uses IM 1)");
                end
            end
            T_INTA: if (in_chg) fail($sformatf("interrupt acknowledged inside CHGCPU (%s)", active ? "R800" : "Z80"));
            T_MWR:  if (addr >= 16'hC000) mem[addr] <= dout;
            T_IOWR: begin
                case (addr[7:0])
                    8'hF4: f4 <= (f4 & 8'h20) | (dout & 8'hA0);
                    8'hE4: s1990_sel <= dout;
                    8'hE5: begin
                        if (verbose) $display("%0t E5 <- %02h by %s", $time, dout, active ? "R800" : "Z80");
                        if (n_e5 >= NE5 || exp_e5[n_e5] != {active, dout})
                            fail($sformatf("E5 write #%0d: %02h by %s, expected %02h by %s", n_e5 + 1, dout,
                                 active ? "R800" : "Z80", exp_e5[n_e5][7:0], exp_e5[n_e5][8] ? "R800" : "Z80"));
                        n_e5++;
                        if (s1990_sel == 8'd6) cpu_status <= dout & 8'h60;
                        if (arm) begin int_rq <= 1; arm <= 0; end
                    end
                    8'h10: int_rq <= 0;
                    8'h11: arm <= 1;
                    default: if (addr[7:4] == 4'h2) marker <= 32'(addr[3:0]) + 1;
                endcase
            end
            default: ;
        endcase
    end
end

function automatic logic [15:0] w(input logic [15:0] a);
    return {mem[a + 16'd1], mem[a]};
endfunction

task automatic expect_cpu(input int m, input logic r800);
    wait (marker == m);
    if (verbose) $display("%0t marker %0d on %s", $time, m, active ? "R800" : "Z80");
    if (active != r800) fail($sformatf("marker %0d on %s, expected %s", m, active ? "R800" : "Z80", r800 ? "R800" : "Z80"));
endtask

task automatic do_reset(input logic cold);
    @(posedge clk);
    reset <= 1; cold_reset <= cold;
    s1990_sel <= 0; cpu_status <= 8'h60;    // S1990 resets with the machine
    if (cold) f4 <= 0;
    marker <= 0; int_rq <= 0; arm <= 0; in_chg <= 0;
    repeat (20) @(posedge clk);
    reset <= 0; cold_reset <= 0;
endtask

task automatic report();
    $display("%s cpu_switch_tb sel=%0d (switches %0d, E5 writes %0d, IM1 R800 %0d, IM2 Z80 %0d, errors %0d)",
             errors == 0 ? "PASS" : "FAILED", sel, n_sw, n_e5, im1_r800, im2_z80, errors);
    $finish;
endtask

initial begin
    repeat (8_000_000) @(posedge clk);
    fail($sformatf("timeout at marker %0d (switches %0d, E5 writes %0d)", marker, n_sw, n_e5));
    report();
end

initial begin
    void'($value$plusargs("sel=%d", sel));
    verbose = $test$plusargs("v");
    repeat (20) @(posedge clk);
    reset = 0; cold_reset = 0;
    expect_cpu(1, 1);
    if (im1_r800 != 1 || im2_z80 != 0) fail($sformatf("marker 1: IM 1 / IM 2 handlers %0d / %0d, expected 1 / 0", im1_r800, im2_z80));
    expect_cpu(2, 0);
    if (im1_r800 != 1 || im2_z80 != 1) fail($sformatf("marker 2: IM 1 / IM 2 handlers %0d / %0d, expected 1 / 1", im1_r800, im2_z80));
    if ({w(16'hE020), w(16'hE022), w(16'hE024), w(16'hE026), w(16'hE028), w(16'hE02A), w(16'hE02C), w(16'hE02E)}
        != {16'h1111, 16'h2222, 16'h3333, 16'h4444, 16'h5555, 16'h6666, 16'h7777, 16'h8888})
        fail("R800 did not get the Z80 registers (E020h)");
    expect_cpu(3, 1);
    if ({w(16'hE030), w(16'hE032), w(16'hE034)} != {16'hA1A1, 16'hA2A2, 16'hA3A3})
        fail("Z80 did not get the R800 registers (E030h)");
    expect_cpu(4, 0);
    expect_cpu(5, 1);
    repeat (200) @(posedge clk);
    do_reset(0);                        // warm: F4 bit 7 set, R800 stays parked
    expect_cpu(6, 1);
    expect_cpu(7, 0);
    if ({w(16'hE040), w(16'hE042), w(16'hE044)} != {16'hB1B1, 16'hB2B2, 16'hB3B3})
        fail("R800 after the warm reset did not get the Z80 registers (E040h)");
    wait (marker == 16);                // 2Fh: end
    repeat (200) @(posedge clk);
    do_reset(1);                        // cold: R800 from 0000h again
    expect_cpu(1, 1);
    if (n_sw != NSW) fail($sformatf("%0d switches, expected %0d", n_sw, NSW));
    if (n_e5 != NE5 - 2) fail($sformatf("%0d writes to E5, expected %0d", n_e5, NE5 - 2));
    report();
end

endmodule
