// sdram.sv test: ch1 requests from the clk_core domain (memory_upload style and CPU style)
// against a simple SDRAM chip model (ACTIVE / READ / WRITE, CL 2, DQM, burst 1).
// Checks data integrity across refresh collisions and measures read latency in clk_core.
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
logic        init = 1;
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
    .ch2_addr('0), .ch2_dout(), .ch2_din('0), .ch2_req(1'b0), .ch2_rnw(1'b1), .ch2_ready(), .ch2_done(),
    .ch3_addr('0), .ch3_dout(), .ch3_din('0), .ch3_req(1'b0), .ch3_rnw(1'b1), .ch3_ready(), .ch3_done()
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
    for (int i = 0; i < 64; i++)   cpu_read(27'h4000100 + i, 8);

    $display("read latency (clk_core edges until data valid): 1:%0d 2:%0d 3:%0d 4:%0d 5:%0d 6+:%0d",
             lat_hist[1], lat_hist[2], lat_hist[3], lat_hist[4], lat_hist[5], lat_hist[6] + lat_hist[7]);
    if (errors == 0) $display("PASS sdram_tb");
    else             $display("FAILED sdram_tb: %0d errors", errors);
    $finish;
end

endmodule
