// sdram.sv test: ch1 requests from the clk_core domain (memory_upload style and CPU style)
// against a simple SDRAM chip model (ACTIVE / READ / WRITE, CL 2, DQM, burst 1).
// Checks data integrity across refresh collisions and measures read latency in clk_core.
// ch4 (OPL4 sample memory): word reads and byte writes run beside a CPU that starts its
// accesses only in cpu_phase cycles, every 6 / 3 / 2 clk_core (3.58 MHz, R800, 10.7 MHz). The
// data of both must be right and the CPU reads must not get slower than without ch4.
// ch2 / ch3 reads run beside them too; their data goes through the same I/O register (C6).
// Run: wsl.exe -- bash rtl/peripheral/tb/run_sdram.sh [alt_sdram.sv]   (+define+OLD for old port list)
`timescale 1ns/1ps
module sdram_tb;

// clk_sdram = 4 x clk_core, edges aligned (same PLL)
logic clk_sdram = 0, clk_core = 0;
always #5.82  clk_sdram = ~clk_sdram;
always #23.28 clk_core  = ~clk_core;
logic core_tgl = 0;
always @(posedge clk_core) core_tgl <= ~core_tgl;

memory_bus_if bus();
logic [26:0] c4_addr = 0;
logic  [7:0] c4_din = 0;
logic        c4_req = 0, c4_rnw = 1, cpu_phase = 0;
wire  [15:0] c4_dout;
wire         c4_done;
logic        init = 1;
logic [26:0] c2_addr = 0, c3_addr = 0;
logic  [7:0] c2_din = 0, c3_din = 0;
logic        c2_req = 0, c3_req = 0, c2_rnw = 1, c3_rnw = 1;
wire         c2_done, c3_done, c2_ready, c3_ready;
wire   [7:0] c2_dout, c3_dout;
wire  [15:0] dq;            // chip -> controller (reads)
wire  [15:0] ctl_dq;        // controller -> chip (writes), DQ port split by run_sdram.sh
wire  [12:0] sa;
wire   [1:0] ba;
wire         dqml, dqmh, ncs, nwe, nras, ncas, cke, sclk;

sdram dut (
    .init(init), .clk(clk_sdram),
`ifndef OLD
    .core_phase(core_tgl),
`endif
    .doRefresh(1'b0),
    .SDRAM_DQ(dq), .SDRAM_DQ_drv(ctl_dq), .SDRAM_A(sa), .SDRAM_DQML(dqml), .SDRAM_DQMH(dqmh), .SDRAM_BA(ba),
    .SDRAM_nCS(ncs), .SDRAM_nWE(nwe), .SDRAM_nRAS(nras), .SDRAM_nCAS(ncas), .SDRAM_CKE(cke), .SDRAM_CLK(sclk),
    .memory_bus_ch1(bus),
    .ch2_addr(c2_addr), .ch2_dout(c2_dout), .ch2_din(c2_din), .ch2_req(c2_req), .ch2_rnw(c2_rnw), .ch2_ready(c2_ready), .ch2_done(c2_done),
    .ch3_addr(c3_addr), .ch3_dout(c3_dout), .ch3_din(c3_din), .ch3_req(c3_req), .ch3_rnw(c3_rnw), .ch3_ready(c3_ready), .ch3_done(c3_done)
`ifndef NO_CH4
    , .ch4_addr(c4_addr), .ch4_dout(c4_dout), .ch4_din(c4_din), .ch4_req(c4_req), .ch4_rnw(c4_rnw),
    .ch4_done(c4_done), .cpu_phase(cpu_phase)
`endif
);

// ---------------- SDRAM chip model (commands on posedge SDRAM_CLK = negedge clk) ----------------
logic [15:0] chip_mem [int];
logic [12:0] row_open [8];
logic [15:0] dq_drv = '0;
logic  [2:0] rd_pipe_v = 0;
int          rd_pipe_a [3];
assign dq = dq_drv;

always @(negedge clk_sdram) begin
    int a;
    // CL 2: data driven 2 SDRAM_CLK after READ, held for one cycle
    dq_drv <= rd_pipe_v[1] ? (chip_mem.exists(rd_pipe_a[1]) ? chip_mem[rd_pipe_a[1]] : 16'h0000) : 16'h0000;
    rd_pipe_v    <= {rd_pipe_v[1:0], 1'b0};
    rd_pipe_a[1] <= rd_pipe_a[0];
    begin
        case ({nras, ncas, nwe})
            3'b011: row_open[{ncs, ba}] <= sa;                             // ACTIVE
            3'b101: begin                                                  // READ
                rd_pipe_v[0] <= 1'b1;
                rd_pipe_a[0] <= {ncs, ba, row_open[{ncs, ba}], sa[8:0]};
            end
            3'b100: begin                                                  // WRITE
                a = {ncs, ba, row_open[{ncs, ba}], sa[8:0]};
                if (!chip_mem.exists(a)) chip_mem[a] = 16'h0000;
                if (!dqml) chip_mem[a][7:0]  = ctl_dq[7:0];
                if (!dqmh) chip_mem[a][15:8] = ctl_dq[15:8];
            end
            default: ;
        endcase
    end
end

// ---------------- ch1 driver (clk_core domain) ----------------
logic [7:0]  ref_mem [int];
logic        cs = 0, rnw = 1;
logic [26:0] addr = 0;
logic  [7:0] din = 0;
assign bus.ram_cs  = cs;
assign bus.rnw     = rnw;
assign bus.addr    = addr;
assign bus.data    = din;
assign bus.sram_cs = 1'b0;

int errors = 0;
task automatic core(input int n); repeat (n) @(posedge clk_core); #1; endtask

function automatic logic [7:0] pat(input int a);
    return 8'(a * 37 + (a >> 8) * 11 + 5);
endfunction

// memory_upload style: ram_ce 1-cycle pulse whenever ready && ~ram_ce
// (ready sampled at the clk_core edge like the RTL, i.e. the pre-edge value)
task automatic upload(input int base, input int count);
    int i = 0;
    logic rdy;
    while (i < count) begin
        @(posedge clk_core);
        rdy = bus.sdram_ready;
        #1;
        if (cs) cs = 0;
        else if (rdy && ($urandom % 4 == 0)) begin          // irregular cadence (DDR3 source waits)
            addr = 27'(base + i); din = pat(base + i); rnw = 0; cs = 1;
            ref_mem[base + i] = din;
            i++;
        end
    end
    @(posedge clk_core); #1; cs = 0;
    core(2);                            // cs must be seen low before the next access
endtask

// CPU style: ram_cs held for 'hold' clk_core cycles; data sampled 'lat' cycles after cs rose
int lat_hist [8];
task automatic cpu_read(input int a, input int hold);
    int got_at = -1;
    addr = 27'(a); rnw = 1; cs = 1;
    for (int c = 1; c <= hold; c++) begin
        @(posedge clk_core);
        if (got_at < 0 && bus.q === ref_mem[a]) got_at = c;   // value seen at this edge
        #1;
    end
    cs = 0;
    if (got_at < 0) begin
        errors++;
        if (errors < 10) $display("FAIL cpu_read %06h got=%02h exp=%02h", a, bus.q, ref_mem[a]);
    end else lat_hist[got_at > 7 ? 7 : got_at]++;
    core(2);
endtask

task automatic cpu_write(input int a, input logic [7:0] v, input int hold);
    addr = 27'(a); din = v; rnw = 0; cs = 1;
    ref_mem[a] = v;
    core(hold);
    cs = 0; rnw = 1;
    core(3);
endtask

// ch2 / ch3 byte write (clk domain). rnw returns to 1 right after the request edge: the
// controller must use the captured value for DQM too, or both bytes of the word get written.
task automatic ch23_write(input int ch, input int a, input logic [7:0] v);
    @(posedge clk_sdram); #1;
    if (ch == 2) begin c2_addr = 27'(a); c2_din = v; c2_rnw = 0; c2_req = 1; end
    else         begin c3_addr = 27'(a); c3_din = v; c3_rnw = 0; c3_req = 1; end
    @(posedge clk_sdram); #1;
    c2_rnw = 1; c3_rnw = 1;
    for (int t = 0; t < 200 && !(ch == 2 ? c2_done : c3_done); t++) @(posedge clk_sdram);
    #1;
    if (!(ch == 2 ? c2_done : c3_done)) begin errors++; $display("FAIL ch%0d write not done", ch); end
    c2_req = 0; c3_req = 0;
    ref_mem[a] = v;
    core(2);
endtask

`ifndef NO_CH4
// CPU with T states of tlen clk_core: an access starts only in a cpu_phase cycle
int tlen = 6, tcnt = 0;
bit phase_on = 1;
always @(posedge clk_core) begin
    tcnt      <= tcnt >= tlen - 1 ? 0 : tcnt + 1;
    cpu_phase <= phase_on && tcnt >= tlen - 1;
end
task automatic to_phase;
    @(posedge clk_core);
    while (tcnt < tlen - 1) @(posedge clk_core);
    #1;
endtask
task automatic cpu_read_ph(input int a);
    int got_at = -1;
    to_phase();
    addr = 27'(a); rnw = 1; cs = 1;
    for (int c = 1; c <= 8; c++) begin
        @(posedge clk_core);
        if (got_at < 0 && bus.q === ref_mem[a]) got_at = c;
        #1;
    end
    // the value must still be there at the end of the access
    if (bus.q !== ref_mem[a]) begin
        errors++;
        if (errors < 10) $display("FAIL cpu read %06h: %02h at the end of the access, expected %02h", a, bus.q, ref_mem[a]);
    end
    cs = 0;
    if (got_at < 0) begin
        errors++;
        if (errors < 10) $display("FAIL cpu_read_ph %06h got=%02h exp=%02h", a, bus.q, ref_mem[a]);
    end else lat_hist[got_at > 7 ? 7 : got_at]++;
endtask
task automatic cpu_write_ph(input int a, input logic [7:0] v);
    to_phase();
    addr = 27'(a); din = v; rnw = 0; cs = 1;
    ref_mem[a] = v;
    core(4);
    cs = 0; rnw = 1;
endtask

// ch2 / ch3 reads (clk domain, as nvram_backup through system_memory): request, ready falls
// and rises again with the data. Area 0x030000-0x0300FF is filled by upload before.
bit c23_run = 0;
int c23_ops = 0;
initial forever begin
    @(posedge clk_sdram); #1;
    if (c23_run) begin
        int a, ch, t;
        a  = 27'h030000 + ($urandom % 256);
        ch = 2 + $urandom % 2;
        if (ch == 2) begin c2_addr = 27'(a); c2_rnw = 1; c2_req = 1; end
        else         begin c3_addr = 27'(a); c3_rnw = 1; c3_req = 1; end
        t = 0;
        do begin @(posedge clk_sdram); t++; end while ((ch == 2 ? c2_ready : c3_ready) && t < 4);
        if ((ch == 2 ? c2_ready : c3_ready)) begin errors++; if (errors < 10) $display("FAIL ch%0d ready did not fall", ch); end
        while (!(ch == 2 ? c2_ready : c3_ready) && t < 20000) begin @(posedge clk_sdram); t++; end
        #1;
        if ((ch == 2 ? c2_dout : c3_dout) !== ref_mem[a]) begin
            errors++;
            if (errors < 10) $display("FAIL ch%0d read %06h: %02h, expected %02h", ch, a, ch == 2 ? c2_dout : c3_dout, ref_mem[a]);
        end
        c2_req = 0; c3_req = 0; c23_ops++;
        repeat (4 + $urandom % 40) @(posedge clk_sdram);
    end
end

// ch4 traffic: random word reads and byte writes in its own area, checked against a model
bit          ch4_run = 0;
int          ch4_ops = 0, ch4_wait = 0, ch4_wait_max = 0;    // clk_core from the request to done
logic  [7:0] ref4 [int];
function automatic logic [7:0] r4(input int a); return ref4.exists(a) ? ref4[a] : 8'h00; endfunction
initial forever begin
    @(posedge clk_core); #1;
    if (ch4_run) begin
        int a; logic wr;
        a  = 27'h200000 + ($urandom % 4096);
        wr = $urandom % 4 == 0;
        c4_addr = 27'(a); c4_rnw = ~wr; c4_din = 8'($urandom); c4_req = 1;
        if (wr) ref4[a] = c4_din;
        begin
            int t; t = 0;
            while (!c4_done && t < 20000) begin @(posedge clk_core); t++; end
            ch4_wait += t; if (t > ch4_wait_max) ch4_wait_max = t;
            if (!c4_done) begin errors++; if (errors < 10) $display("FAIL ch4 access not served in 20000 clk_core"); end
        end
        if (!wr && c4_done && c4_dout !== {r4(a | 1), r4(a & ~1)}) begin
            errors++;
            if (errors < 10) $display("FAIL ch4 read %06h: %04h, expected %04h", a, c4_dout, {r4(a | 1), r4(a & ~1)});
        end
        #1 c4_req = 0; ch4_ops++;
        repeat (3) @(posedge clk_core);
    end
end
`endif

initial begin
    core(5);
    init = 0;
    wait (bus.sdram_ready === 1'b1);
    core(4);

    upload(27'h010000, 3000);                              // includes many refresh collisions
    for (int i = 0; i < 3000; i++) cpu_read(27'h010000 + i, 8);
    for (int i = 0; i < 500; i++)  cpu_write(27'h020000 + i * 3, pat(i) ^ 8'h5A, 4);
    for (int i = 0; i < 500; i++)  cpu_read(27'h020000 + i * 3, 8);
    // second chip (addr[26]) and odd/even bytes in one word
    upload(27'h4000100, 64);
    upload(27'h030000, 256);
    for (int i = 0; i < 64; i++)   cpu_read(27'h4000100 + i, 8);

    // C7: ch2 / ch3 byte writes keep the other byte of the word
    for (int ch = 2; ch <= 3; ch++)
        for (int i = 0; i < 4; i++) begin
            int a; a = 27'h010200 + ch * 16 + i;
            ch23_write(ch, a, 8'hA0 + 8'(ch * 16 + i));
        end
    for (int i = 0; i < 16; i++) cpu_read(27'h010220 + i, 8);

    $display("read latency (clk_core edges until data valid): 1:%0d 2:%0d 3:%0d 4:%0d 5:%0d 6+:%0d",
             lat_hist[1], lat_hist[2], lat_hist[3], lat_hist[4], lat_hist[5], lat_hist[6] + lat_hist[7]);
`ifndef NO_CH4
    for (int t = 0; t < 3; t++) begin
        int base_max, base_slow, n4;
        tlen = t == 0 ? 6 : t == 1 ? 3 : 2;
        for (int with4 = 0; with4 < 2; with4++) begin
            foreach (lat_hist[i]) lat_hist[i] = 0;
            ch4_run = with4; c23_run = with4; ch4_ops = 0; c23_ops = 0; ch4_wait = 0; ch4_wait_max = 0;
            core(20);
            for (int i = 0; i < 6000; i++) begin
                int a; a = 27'h010000 + ($urandom % 3000);
                if ($urandom % 8 == 0) cpu_write_ph(a, 8'($urandom));
                else                   cpu_read_ph(a);
                if ($urandom % 4 == 0) core($urandom % 40);     // the CPU does something else
            end
            ch4_run = 0; c23_run = 0;
            core(40);
            begin
                int mx, slow; mx = 0; slow = 0;
                for (int i = 1; i < 8; i++) if (lat_hist[i] != 0) mx = i;
                for (int i = 3; i < 8; i++) slow += lat_hist[i];
                $display("T = %0d clk, ch4 %s: latency 1:%0d 2:%0d 3:%0d 4:%0d 5+:%0d, ch4 accesses %0d, ch2/ch3 reads %0d", tlen, with4 ? "on " : "off",
                         lat_hist[1], lat_hist[2], lat_hist[3], lat_hist[4], lat_hist[5] + lat_hist[6] + lat_hist[7], ch4_ops, c23_ops);
                if (with4 && ch4_ops > 0)
                    $display("           ch4 answers after %0d.%0d clk_core on average, %0d at most", ch4_wait / ch4_ops,
                             (ch4_wait * 10 / ch4_ops) % 10, ch4_wait_max);
                if (!with4) begin base_max = mx; base_slow = slow; end
                else begin
                    n4 = ch4_ops;
                    if (mx > base_max) begin errors++; $display("FAIL ch4 slows the CPU down: latency %0d, without ch4 %0d", mx, base_max); end
                    if (slow > 2 * base_slow + 20) begin errors++; $display("FAIL more slow CPU reads with ch4: %0d, without %0d", slow, base_slow); end
                    if (tlen > 2 && n4 < 3000) begin errors++; $display("FAIL ch4 starved: %0d accesses", n4); end
                    if (c23_ops < 100) begin errors++; $display("FAIL ch2/ch3 reads starved: %0d", c23_ops); end
                end
            end
        end
    end
    // CPU stopped (no cpu_phase): ch4 runs alone
    phase_on = 0; ch4_ops = 0; ch4_run = 1; core(4000); ch4_run = 0; core(40);
    if (ch4_ops < 500) begin errors++; $display("FAIL ch4 without a CPU clock: %0d accesses", ch4_ops); end
    $display("ch4 alone: %0d accesses in 4000 clk_core", ch4_ops);
`endif
    if (errors == 0) $display("PASS sdram_tb");
    else             $display("FAILED sdram_tb: %0d errors", errors);
    $finish;
end

endmodule
