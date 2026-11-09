// msx_cpu test: runs a Z80 program (msx_cpu_prog.svh) and hashes the bus transaction trace.
// The hash depends only on transaction order and content, not on timing, so it must be
// identical for any correct implementation; golden values come from the derived-clock
// version (before CE). The memory model can delay read data by LAT clk cycles to find
// the latency margin.
//
// Plusargs: +sel=<0..3> CPU speed (0 3.58, 2 5.39, 1 10.7 MHz), +wait=<0..7> M1 waits,
//           +lat=<n> memory read latency, +n=<transactions>, +golden=<hex> expected hash,
//           +trace=<file> optional transaction dump,
//           +switch=<n> change the speed at random every 1..n clk (run-time turbo switching),
//           +mwait=<n> / +iowait=<n> memory / I/O wait states; LEN prints the strobe length
//           of each access type in CPU clocks (min..max)
//           +mul [+r800]: R800 MULUB / MULUW program instead of the hash test; without +r800
//           the opcodes must act as Z80 NOPs
// Run: wsl.exe -- bash rtl/tb/run_msx_cpu.sh
module msx_cpu_tb;

logic clk = 0;
always #1 clk = ~clk;

clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

int unsigned sel = 0, waits = 0, lat = 0, ntrans = 200000, golden = 0, sw = 0, mwait = 0, iowait = 0;
logic  [1:0] clock_sel = '0;
logic        reset = 1;

logic        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
logic [15:0] addr;
logic  [7:0] dout, di;
logic        int_rq = 0;
logic        r800 = 0;

msx_cpu dut (
    .clock_bus (clock_bus.base_mp),
    .reset     (reset),
    .clock_sel (clock_sel),
    .m1_wait   (3'(waits)),
    .mem_wait  (4'(mwait)),
    .io_wait   (4'(iowait)),
    .ext_wait  (1'b0),
    .r800      (r800),
`ifndef OLD_CPU
    .r800_sel  (1'b0),
    .turbor    (1'b0),
    .cold_reset(reset),
    .r800_active(),
`endif
    .int_rq    (int_rq),
    .di        (di),
    .m1_n, .mreq_n, .iorq_n, .rd_n, .wr_n, .rfsh_n,
    .addr      (addr),
    .dout      (dout)
);

// ---------------- memory / IO model ----------------
logic [7:0] mem [0:65535];
initial begin
    foreach (mem[i]) mem[i] = 8'h00;
    `include "msx_cpu_prog.svh"
    if ($test$plusargs("mul")) begin
        // LD SP,4000h; F = FFh; LD HL,0; LD DE,0; LD A,7; LD B,6; MULUB A,B; LD (3000h),HL; AF -> (3006h)
        // LD HL,1234h; LD BC,0100h; MULUW HL,BC; LD (3002h),HL; LD (3004h),DE; AF -> (3008h)
        // LD A,0; LD C,5; MULUB A,C; LD (300Ch),HL; AF -> (300Ah); JR $
        byte unsigned p[] = '{8'h31, 8'h00, 8'h40, 8'h21, 8'hFF, 8'hFF, 8'hE5, 8'hF1, 8'h21, 8'h00,
                              8'h00, 8'h11, 8'h00, 8'h00, 8'h3E, 8'h07, 8'h06, 8'h06, 8'hED, 8'hC1,
                              8'h22, 8'h00, 8'h30, 8'hF5, 8'hE1, 8'h22, 8'h06, 8'h30, 8'h21, 8'h34,
                              8'h12, 8'h01, 8'h00, 8'h01, 8'hED, 8'hC3, 8'h22, 8'h02, 8'h30, 8'hED,
                              8'h53, 8'h04, 8'h30, 8'hF5, 8'hE1, 8'h22, 8'h08, 8'h30, 8'h3E, 8'h00,
                              8'h0E, 8'h05, 8'hED, 8'hC9, 8'h22, 8'h0C, 8'h30, 8'hF5, 8'hE1, 8'h22,
                              8'h0A, 8'h30, 8'h18, 8'hFE};
        foreach (mem[i]) mem[i] = 8'h00;
        foreach (p[i]) mem[i] = p[i];
    end
end

wire mem_rd = ~mreq_n & ~rd_n;
wire io_rd  = ~iorq_n & ~rd_n;
wire int_ack = ~iorq_n & ~m1_n;
logic [7:0] io_rd_cnt = 0;
int         rd_age = 0;          // clk edges since the current memory read was first seen
logic       mem_rd_q = 0;

always @(posedge clk) begin
    mem_rd_q <= mem_rd;
    rd_age   <= (mem_rd && mem_rd_q) ? rd_age + 1 : 0;
end

wire [7:0] mem_q   = mem[addr];
wire [7:0] io_q    = addr[7:0] ^ io_rd_cnt;
// Read data valid LAT edges after the read was first sampled; garbage (~data) before.
wire       mem_ok  = (lat == 0) || (mem_rd_q && rd_age + 1 >= lat);
assign di = int_ack ? 8'hFF : io_rd ? io_q : mem_rd ? (mem_ok ? mem_q : ~mem_q) : 8'hFF;

// ---------------- transaction trace ----------------
typedef enum logic [2:0] { T_M1, T_MRD, T_MWR, T_IORD, T_IOWR, T_INTA } ttype_t;
logic        act_q = 0, int_pend = 0;
int unsigned count = 0, cycles = 0, ints = 0, iowr_ce10 = 0, iowr_noce10 = 0;
logic [31:0] hash = 32'h811C9DC5;
int          fd = 0;

function automatic logic [31:0] fnv(input logic [31:0] h, input logic [7:0] b);
    return (h ^ 32'(b)) * 32'h01000193;
endfunction

wire act = (~mreq_n & rfsh_n & (~rd_n | ~wr_n)) | (~iorq_n & (~rd_n | ~wr_n)) | int_ack;

always @(posedge clk) begin
    if (!reset) cycles++;
    act_q <= act;
    if (!reset && act && !act_q) begin
        ttype_t t;
        logic [7:0] d;
        t = int_ack ? T_INTA : ~iorq_n ? (~rd_n ? T_IORD : T_IOWR) :
            ~m1_n ? T_M1 : (~rd_n ? T_MRD : T_MWR);
        d = (t == T_MWR || t == T_IOWR) ? dout : (t == T_IORD) ? io_q : (t == T_INTA) ? 8'hFF : mem_q;
        hash = fnv(fnv(fnv(fnv(hash, 8'(t)), addr[15:8]), addr[7:0]), d);
        if (fd) $fdisplay(fd, "%0d %0d %04h %02h", count, t, addr, d);
        count++;
        // Phase of the 1-cycle bus req pulse vs ce_10m7_p (VDP18 samples only on it)
        if (t == T_IOWR) begin if (clock_bus.ce_10m7_p) iowr_ce10++; else iowr_noce10++; end
        if (t == T_MWR && addr >= 16'h2000) mem[addr] <= dout;
        if (t == T_IORD) io_rd_cnt <= io_rd_cnt + 1;
        // INT raised at the start of an instruction fetch, so it is sampled at the end of
        // that instruction regardless of sub-cycle timing (a bus-triggered INT one clk
        // before the sampling point would test timing, not behaviour)
        if (count % 997 == 0) int_pend <= 1;
        if (t == T_INTA) begin int_rq <= 0; ints++; end
        else if (t == T_M1 && (int_pend || count % 997 == 0)) begin int_rq <= 1; int_pend <= 0; end
    end
end

// Strobe length per access type, in CPU clocks (ce_p)
int unsigned len_cur = 0, len_min[6], len_max[6];
ttype_t      len_t;
initial foreach (len_min[i]) begin len_min[i] = '1; len_max[i] = 0; end
always @(posedge clk) begin
    if (act && !act_q)
        len_t <= int_ack ? T_INTA : ~iorq_n ? (~rd_n ? T_IORD : T_IOWR) :
                 ~m1_n ? T_M1 : (~rd_n ? T_MRD : T_MWR);
    if (act) len_cur <= len_cur + (dut.ce_p ? 1 : 0);
    else if (act_q) begin
        if (len_cur < len_min[len_t]) len_min[len_t] <= len_cur;
        if (len_cur > len_max[len_t]) len_max[len_t] <= len_cur;
        len_cur <= 0;
    end
end

// Run-time speed switching at random points (any phase of the CPU cycle)
initial begin
    #1;
    wait (!reset);
    if (sw != 0)
        forever begin
            repeat (1 + $urandom_range(sw - 1)) @(posedge clk);
            clock_sel <= 2'($urandom_range(2));
        end
end

initial begin
    string tf;
    void'($value$plusargs("sel=%d", sel));
    void'($value$plusargs("wait=%d", waits));
    void'($value$plusargs("lat=%d", lat));
    void'($value$plusargs("n=%d", ntrans));
    void'($value$plusargs("golden=%h", golden));
    if ($value$plusargs("trace=%s", tf)) fd = $fopen(tf, "w");
    void'($value$plusargs("switch=%d", sw));
    void'($value$plusargs("mwait=%d", mwait));
    void'($value$plusargs("iowait=%d", iowait));
    clock_sel = 2'(sel);
    r800      = $test$plusargs("r800");
    repeat (20) @(posedge clk);
    reset = 0;
    if ($test$plusargs("mul")) begin
        // R800 (openMSX mulub_a_R / muluw_hl_SS): HL = 002Ah, F = 3Ah (S V Z C = 0, N H X Y kept);
        // DE:HL = 0012 3400h, F = 3Bh (C: result > 16 bits); 0*5: HL = 0, F = 7Ah (Z).
        // Z80: the opcodes are NOPs, HL / DE / F unchanged.
        byte unsigned exp[14];
        bit ok = 1;
        string got = "";
        exp = r800 ? '{8'h2A, 8'h00, 8'h00, 8'h34, 8'h12, 8'h00, 8'h3A, 8'h07, 8'h3B, 8'h07, 8'h7A, 8'h00, 8'h00, 8'h00} :
                     '{8'h00, 8'h00, 8'h34, 8'h12, 8'h00, 8'h00, 8'hFF, 8'h07, 8'hFF, 8'h07, 8'hFF, 8'h00, 8'hFF, 8'h07};
        wait (count >= 400);
        for (int i = 0; i < 14; i++) begin
            if (mem[16'h3000 + i] != exp[i]) ok = 0;
            got = {got, $sformatf(" %02h", mem[16'h3000 + i])};
        end
        $display("%s msx_cpu_tb mul r800=%0d: 3000h =%s", ok ? "PASS" : "FAILED", r800, got);
        $finish;
    end
    wait (count >= ntrans);
    $display("RESULT sel=%0d switch=%0d wait=%0d lat=%0d n=%0d hash=%08h cycles=%0d ints=%0d iowr_req_on_ce10=%0d/%0d",
             sel, sw, waits, lat, count, hash, cycles, ints, iowr_ce10, iowr_ce10 + iowr_noce10);
    $display("LEN M1 %0d..%0d MRD %0d..%0d MWR %0d..%0d IORD %0d..%0d IOWR %0d..%0d INTA %0d..%0d",
             len_min[T_M1], len_max[T_M1], len_min[T_MRD], len_max[T_MRD], len_min[T_MWR], len_max[T_MWR],
             len_min[T_IORD], len_max[T_IORD], len_min[T_IOWR], len_max[T_IOWR], len_min[T_INTA], len_max[T_INTA]);
    if (golden != 0)
        $display("%s msx_cpu_tb (golden %08h)", hash == golden ? "PASS" : "FAILED", golden);
    if (fd) $fclose(fd);
    $finish;
end

endmodule
