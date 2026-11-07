// reset_status regression test: reset value, write masks, read gating, both polarities.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run.sh
module reset_status_tb;

logic clk = 0, reset = 1, wr = 0, rd = 0, inverted = 0;
logic [7:0] data = 0, status;
always #1 clk = ~clk;

reset_status dut (.*);

int errors = 0;
task automatic chk(input string tag, input logic [7:0] exp);
    rd = 1; #0.1;
    if (status !== exp) begin
        errors++;
        $display("FAIL %s: got=%02h exp=%02h", tag, status, exp);
    end
    rd = 0; #0.1;
    if (status !== 8'hFF) begin
        errors++;
        $display("FAIL %s: not reading, got=%02h", tag, status);
    end
endtask

task automatic write(input logic [7:0] v);
    data = v; wr = 1;
    @(posedge clk); #0.1;
    wr = 0;
endtask

task automatic do_reset();
    reset = 1; repeat (2) @(posedge clk); #0.1; reset = 0;
endtask

initial begin
    // Normal polarity: bits 7 and 5 writable, bit 5 sticky until reset
    inverted = 0;
    do_reset();
    chk("normal reset", 8'h00);
    write(8'hFF);
    chk("normal write FF", 8'hA0);
    write(8'h00);
    chk("normal write 00 keeps bit5", 8'h20);
    write(8'h80);
    chk("normal write 80", 8'hA0);
    do_reset();
    chk("normal re-reset", 8'h00);

    // Inverted polarity: only bit 7 writable, others read 1
    inverted = 1;
    do_reset();
    chk("inverted reset", 8'hFF);
    write(8'h00);
    chk("inverted write 00", 8'h7F);
    write(8'h80);
    chk("inverted write 80", 8'hFF);

    if (errors == 0) $display("PASS reset_status_tb");
    else             $display("FAILED reset_status_tb: %0d errors", errors);
    $finish;
end

endmodule
