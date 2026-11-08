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

module msx_cpu (
    clock_bus_if.base_mp clock_bus,
    input                reset,
    input          [1:0] clock_sel,     // 00/11 3.58 MHz, 01 10.7 MHz, 10 5.39 MHz
    input          [2:0] m1_wait,       // wait states inserted after M1
    input          [3:0] mem_wait,      // wait states on each memory access (incl. M1)
    input          [3:0] io_wait,       // extra wait states on each I/O access
    input                ext_wait,      // level wait request from the bus (MegaSD SPI, OPLL busy)
    input                r800,          // R800 instructions MULUB / MULUW (OCM CPU type)
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
        case (clock_sel)
            2'b01:   ce_sel = clock_bus.ce_10m7_n;
            2'b10:   ce_sel = clock_bus.ce_5m39_n;
            default: ce_sel = clock_bus.ce_3m58_n;
        endcase
    end

    logic ce_n = 1'b0;
    wire  ce_p = ce_sel && ~ce_n;           // never on two consecutive clk (speed switch)
    always_ff @(posedge clock_bus.clk) ce_n <= ce_p;

    // M1 wait states (former negedge of the CPU clock)
    logic [2:0] wait_count = '0;
    logic       last_m1    = 1'b0;
    always_ff @(posedge clock_bus.clk) begin
        if (ce_n) begin
            last_m1 <= ~m1_n;
            if (~last_m1 && ~m1_n)
                wait_count <= m1_wait;
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
                acc_wait <= io_wait;
            else if (acc_wait != 4'd0)
                acc_wait <= acc_wait - 4'd1;
        end
    end

    TV80a #(.Mode(0), .R800_MULU(1), .IOWait(1)) Z80 (
        .RESET_n   (~reset),
        .R800_mode (r800),
        .CLK       (clock_bus.clk),
        .CE_p      (ce_p),
        .CE_n      (ce_n),
        .WAIT_n    (wait_count == 3'd0 && acc_wait == 4'd0 && ~ext_wait),
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
        .DO        (dout)
    );

endmodule
