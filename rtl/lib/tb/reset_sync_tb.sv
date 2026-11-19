// reset_sync test: async assert (also with stopped clock), release after STAGES edges.
// Run: wsl.exe -- bash rtl/lib/tb/run.sh
`timescale 1ns/1ps
module reset_sync_tb;

logic clk = 0, run = 1, arst = 1;
always #5 if (run) clk = ~clk;

wire rst;
reset_sync #(.STAGES(2)) dut (.clk, .arst, .rst);

int errors = 0;
task automatic chk(input string tag, input logic exp);
    if (rst !== exp) begin errors++; $display("FAIL %s: rst=%b exp=%b at %0t", tag, rst, exp, $time); end
endtask

int edges_until_release;
task automatic release_and_count();
    edges_until_release = 0;
    @(negedge clk) arst = 0;
    while (rst) begin @(posedge clk); #0.1; edges_until_release++; end
endtask

initial begin
    // power-up value: reset active
    #0.1 chk("power-up", 1);
    release_and_count();
    if (edges_until_release != 2) begin errors++; $display("FAIL first release after %0d edges", edges_until_release); end

    // async assert in the middle of a clock period: immediate
    repeat (3) @(posedge clk);
    #2 arst = 1; #0.1 chk("async assert mid-cycle", 1);
    #1 arst = 0;                                   // short pulse, shorter than a period
    #0.1 chk("held after short pulse", 1);
    @(posedge clk); #0.1 chk("1st edge after pulse", 1);
    @(posedge clk); #0.1 chk("2nd edge after pulse", 0);

    // clock stopped (PLL in reset): reset still asserts, releases after clock returns
    @(negedge clk) run = 0;
    #20 arst = 1; #0.1 chk("assert with stopped clock", 1);
    #50 run = 1;
    release_and_count();
    if (edges_until_release != 2) begin errors++; $display("FAIL release after restart took %0d edges", edges_until_release); end

    if (errors == 0) $display("PASS reset_sync_tb");
    else             $display("FAILED reset_sync_tb: %0d errors", errors);
    $finish;
end

endmodule
