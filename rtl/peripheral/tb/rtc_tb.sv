// RP5C01 (rtc.sv) through its two ports, as the MSX BIOS uses it.
// Reference: openMSX RP5C01.cc.
// - 12 hour mode: hours 0-11, bit 1 of the hour tens = PM. 11:59:59 AM -> 12:00:00 PM ("20")
//   keeps the date, 11:59:59 PM -> 0:00:00 AM advances it. 24 hour mode: 23:59:59 -> next day.
// - Block 1: alarm registers 2-8, 12/24 (10) and leap year (11) read back through the masks
//   F 7 F 3 7 F 3 . 1 3; registers 0, 1, 9, 12 read 0 (low nibble).
//
//   wsl.exe -- bash rtl/peripheral/tb/run_rtc.sh
`timescale 1ns/1ps

module rtc_tb;
    logic clk = 0;
    always #23 clk = ~clk;

    logic       reset = 1, clkena = 0, req = 0, wrt = 0;
    logic [15:0] adr = '0;
    logic [7:0] dbo = '0, dbi;

    rtc dut (
        .clk21m(clk), .reset(reset), .setup(1'b0), .rt('0),
        .clkena(clkena), .req(req), .ack(), .wrt(wrt), .adr(adr),
        .dbi(dbi), .dbo(dbo), .mem_init(1'b0)
    );

    int errors = 0;

    task automatic io_wr(input logic a0, input logic [7:0] d);
        @(negedge clk); adr = {15'h005A, a0}; dbo = d; wrt = 1; req = 1;
        @(negedge clk); req = 0; wrt = 0;
        repeat (2) @(negedge clk);
    endtask

    task automatic reg_wr(input int r, input int v);
        io_wr(1'b0, 8'(r)); io_wr(1'b1, 8'(v));
    endtask

    task automatic reg_rd(input int r, output logic [7:0] v);
        io_wr(1'b0, 8'(r));
        @(negedge clk); adr = 16'h00B5; repeat (2) @(negedge clk); v = dbi;
    endtask

    task automatic block(input int b);              // mode: timer enabled, block b
        reg_wr(13, 8 | b);
    endtask

    task automatic check(input string what, input int r, input logic [7:0] exp);
        logic [7:0] v;
        reg_rd(r, v);
        $display("  %-40s reg %2d = %02h, expected %02h  %s", what, r, v, exp, v == exp ? "OK" : "FAIL");
        if (v != exp) errors++;
    endtask

    // block 0 time: hour tens/units, day tens/units, weekday; 59:59
    task automatic set_time(input int hh, input int hl, input int dh, input int dl, input int wd);
        block(0);
        reg_wr(0, 9); reg_wr(1, 5); reg_wr(2, 9); reg_wr(3, 5);
        reg_wr(4, hl); reg_wr(5, hh); reg_wr(6, wd);
        reg_wr(7, dl); reg_wr(8, dh); reg_wr(9, 5); reg_wr(10, 0);
    endtask

    task automatic one_second();
        repeat (10) begin @(negedge clk); clkena = 1; @(negedge clk); clkena = 0; end
        repeat (2) @(negedge clk);
    endtask

    initial begin
        repeat (4) @(negedge clk); reset = 0;

        $display("12 hour mode");
        block(1); reg_wr(10, 0);
        set_time(1, 1, 1, 5, 3);                    // 11:59:59 AM, 15th, weekday 3
        one_second();
        check("11:59:59 AM -> hour units 0", 4, 8'hF0);
        check("11:59:59 AM -> PM, tens 0", 5, 8'hF2);
        check("noon keeps the day", 7, 8'hF5);
        check("noon keeps the weekday", 6, 8'hF3);
        set_time(3, 1, 1, 5, 3);                    // 11:59:59 PM
        one_second();
        check("11:59:59 PM -> AM 0", 5, 8'hF0);
        check("midnight: day 16", 7, 8'hF6);
        check("midnight: weekday 4", 6, 8'hF4);

        $display("24 hour mode");
        block(1); reg_wr(10, 1);
        set_time(2, 3, 1, 5, 3);                    // 23:59:59
        one_second();
        check("23:59:59 -> 0", 5, 8'hF0);
        check("next day", 7, 8'hF6);
        set_time(1, 1, 1, 5, 3);                    // 11:59:59
        one_second();
        check("11:59:59 -> 12", 5, 8'hF1);
        check("12:00 keeps the day", 7, 8'hF5);

        $display("block 1");
        block(1);
        for (int r = 0; r <= 12; r++) if (r != 10 && r != 11) reg_wr(r, 8'h0A);
        reg_wr(10, 0); reg_wr(11, 2);
        check("unused 0", 0, 8'hF0);
        check("unused 1", 1, 8'hF0);
        check("alarm minute units", 2, 8'hFA);
        check("alarm minute tens", 3, 8'hF2);
        check("alarm hour units", 4, 8'hFA);
        check("alarm hour tens", 5, 8'hF2);
        check("alarm weekday", 6, 8'hF2);
        check("alarm day units", 7, 8'hFA);
        check("alarm day tens", 8, 8'hF2);
        check("unused 9", 9, 8'hF0);
        check("12/24 = 12", 10, 8'hF0);
        reg_wr(10, 1);
        check("12/24 = 24", 10, 8'hF1);
        check("leap year", 11, 8'hF2);
        check("unused 12", 12, 8'hF0);
        block(0);
        check("block 0 unaffected: minutes", 2, 8'hF0);

        $display("%s rtc_tb (%0d errors)", errors ? "FAIL" : "PASS", errors);
        $finish;
    end
endmodule
