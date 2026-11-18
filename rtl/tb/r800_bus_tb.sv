// R800 on the single phase bus of msx_cpu (R800_FAST = 1 and 2) against the two phase one
// (R800_FAST = 0): both run the image of z80_timing_prog.py (every instruction, interrupts) and
// every bus transaction must be the same in both, in the same order: opcode fetch, memory
// read / write, port read / write, interrupt acknowledge, with address and written data.
// The memory of the single phase CPU answers like the SDRAM: the data is there for the 3rd clk
// edge after the start of the access (+lat=2) and garbage before; the start is the first clk
// of the strobe or acc_start.
// Plusargs: +hex=<image>, +lat=<clk> (default 2; 3 must fail), +v
// Run: wsl.exe -- bash rtl/tb/run_r800_bus.sh
module r800_bus_tb #(parameter FAST_LEVEL = 2);

logic clk = 0;
always #1 clk = ~clk;
clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

`include "z80_timing_cases.svh"

logic reset = 1, verbose = 0;
int   lat = 2;

typedef struct packed { logic [2:0] kind; logic [15:0] a; logic [7:0] d; } tr_t;
localparam logic [2:0] K_F = 3'd0, K_R = 3'd1, K_W = 3'd2, K_I = 3'd3, K_O = 3'd4, K_A = 3'd5;

// one CPU with its memory, interrupt source and transaction log
`define CPU(NAME, FASTP, LATENCY)                                                                           \
    logic NAME``_m1_n, NAME``_mreq_n, NAME``_iorq_n, NAME``_rd_n, NAME``_wr_n, NAME``_rfsh_n, NAME``_acc;  \
    logic NAME``_active, NAME``_int = 0;                                                                    \
    logic [15:0] NAME``_a; logic [7:0] NAME``_do, NAME``_di;                                               \
    msx_cpu #(.R800_FAST(FASTP), .R800_REFRESH(0)) NAME (.clock_bus(clock_bus.base_mp), .reset(reset), .clock_sel(2'd0),     \
        .m1_wait(3'd1), .mem_wait(4'd0), .io_wait(4'd0), .ext_wait(1'b0), .r800(1'b0), .r800_sel(1'b1),    \
        .r800_memdelay(2'd0), .cmos_z80(1'b0), .vdp_io_wait(1'b0), .vdp_wr_hold(1'b0), .vdp_wr_wait(1'b0), \
        .io_hold(), .r800_active(NAME``_active), .bus_phase(), .bus_phase_next(), .acc_start(NAME``_acc),  \
        .int_rq(NAME``_int), .di(NAME``_di), .m1_n(NAME``_m1_n), .mreq_n(NAME``_mreq_n),                   \
        .iorq_n(NAME``_iorq_n), .rd_n(NAME``_rd_n), .wr_n(NAME``_wr_n), .rfsh_n(NAME``_rfsh_n),            \
        .addr(NAME``_a), .dout(NAME``_do));                                                                 \
    logic [7:0] NAME``_mem [0:65535];                                                                       \
    tr_t  NAME``_q [$];                                                                                     \
    logic NAME``_act_q = 0; int NAME``_age = 0, NAME``_idx = 0; bit NAME``_arm = 0;                        \
    wire  NAME``_inta = ~NAME``_iorq_n & ~NAME``_m1_n;                                                     \
    wire  NAME``_act  = (~NAME``_mreq_n & NAME``_rfsh_n & (~NAME``_rd_n | ~NAME``_wr_n)) |                 \
                        (~NAME``_iorq_n & (~NAME``_rd_n | ~NAME``_wr_n)) | NAME``_inta;                     \
    wire  NAME``_new  = NAME``_act && (!NAME``_act_q || NAME``_acc);                                        \
    wire  NAME``_ok   = NAME``_mreq_n || (NAME``_new ? 0 : NAME``_age) >= LATENCY;                                           \
    assign NAME``_di  = !NAME``_ok ? 8'hA5 ^ NAME``_a[7:0] : ~NAME``_mreq_n ? NAME``_mem[NAME``_a] :       \
                        NAME``_inta ? 8'hFF : NAME``_a[7:0] ^ 8'h5A;                                        \
    always @(posedge clk) begin                                                                             \
        NAME``_act_q <= NAME``_act;                                                                         \
        NAME``_age   <= NAME``_new ? 1 : NAME``_age + 1;                                                    \
        if (!reset && NAME``_active && NAME``_new) begin                                                    \
            automatic tr_t t;                                                                               \
            t.a = NAME``_a; t.d = (~NAME``_wr_n) ? NAME``_do : 8'h00;                                       \
            t.kind = NAME``_inta ? K_A : ~NAME``_iorq_n ? (~NAME``_wr_n ? K_O : K_I) :                     \
                     ~NAME``_wr_n ? K_W : ~NAME``_m1_n ? K_F : K_R;                                         \
            NAME``_q.push_back(t);                                                                          \
            if (t.kind == K_W) NAME``_mem[NAME``_a] <= NAME``_do;                                           \
            if (t.kind == K_A) NAME``_int <= 0;                                                             \
            if ((t.kind == K_F || t.kind == K_A) && NAME``_idx < N_CASES) begin                                                \
                automatic bit again = 1;                                                                    \
                if (case_trig[NAME``_idx] != 0 && !NAME``_arm && int'(NAME``_a) == case_trig[NAME``_idx])  \
                    NAME``_int <= 1;                                                                        \
                while (again && NAME``_idx < N_CASES) begin                                                 \
                    again = 0;                                                                              \
                    if (!NAME``_arm) begin                                                                  \
                        if (int'(NAME``_a) == case_x[NAME``_idx]) NAME``_arm = 1;                           \
                    end else if (int'(NAME``_a) == case_y[NAME``_idx]) begin                                \
                        NAME``_idx++; NAME``_arm = 0; again = 1;                                            \
                    end                                                                                     \
                end                                                                                         \
            end                                                                                             \
        end                                                                                                 \
    end

`CPU(slow, 0, 0)
`CPU(fast, FAST_LEVEL, lat)

int n = 0, errors = 0, stopc = 0;
always @(negedge clk) begin
    while (slow_q.size() != 0 && fast_q.size() != 0) begin
        automatic tr_t s = slow_q.pop_front();
        automatic tr_t f = fast_q.pop_front();
        if (s !== f) begin
            errors++;
            if (errors <= 10)
                $display("FAIL transaction %0d (case %0d %s): two phase kind %0d %04x %02x, single phase kind %0d %04x %02x",
                         n, slow_idx, slow_idx < N_CASES ? case_name[slow_idx] : "-", s.kind, s.a, s.d, f.kind, f.a, f.d);
        end
        n++;
    end
    stopc++;
    if ((slow_idx >= N_CASES - 2 && fast_idx >= N_CASES - 2) || errors > 10 || stopc > 4000000) begin
        if (errors == 0 && slow_idx >= N_CASES - 2 && fast_idx >= N_CASES - 2)
            $display("PASS r800_bus_tb R800_FAST=%0d lat=%0d: %0d transactions, %0d cases", FAST_LEVEL, lat, n, N_CASES - 2);
        else
            $display("FAILED r800_bus_tb R800_FAST=%0d lat=%0d: %0d errors, %0d transactions, cases %0d / %0d of %0d", FAST_LEVEL, lat, errors, n, slow_idx, fast_idx, N_CASES);
        $finish;
    end
end

initial begin
    string hex;
    if (!$value$plusargs("hex=%s", hex)) hex = "z80_timing.hex";
    $readmemh(hex, slow_mem); $readmemh(hex, fast_mem);
    void'($value$plusargs("lat=%d", lat));
    verbose = $test$plusargs("v");
    repeat (8) @(posedge clk); reset = 0;
end

endmodule
