// jt8255: a reset sets the control word from control_reset_default (openMSX I8255::reset: all
// ports input, mode 0 = 1Bh) also after the BIOS changed it, and port A to its reset value.
// Run: wsl.exe -- bash rtl/peripheral/tb/run_jt8255.sh   (PREV=<git ref>: jt8255.v from that ref)
module jt8255_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;

logic [1:0] addr = 0;
logic [7:0] din = 0;
wire  [7:0] dout, pa, pb, pc;
logic       rdn = 1, wrn = 1, csn = 1;
logic [6:0] ctrl_default = 7'h1B;

jt8255 dut (
    .rst(rst), .clk(clk), .addr(addr), .din(din), .dout(dout), .rdn(rdn), .wrn(wrn), .csn(csn),
    .porta_din(8'h5A), .portb_din(8'hA5), .portc_din(8'h3C),
    .porta_dout(pa), .portb_dout(pb), .portc_dout(pc),
    .porta_reset_default(8'h00), .control_reset_default(ctrl_default)
);

int errors = 0;
task automatic wr(input logic [1:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; din = d; csn = 0; wrn = 0;
    @(negedge clk); csn = 1; wrn = 1;
endtask
task automatic rd(input logic [1:0] a, output logic [7:0] d);
    @(negedge clk); addr = a; csn = 0; rdn = 0;
    @(negedge clk); csn = 1; rdn = 1; d = dout;
endtask
task automatic expect_ctrl(input string what, input logic [7:0] exp);
    logic [7:0] v;
    rd(2'd3, v);
    if (v !== exp) begin errors++; $display("FAIL %s: control %02h, expected %02h", what, v, exp); end
endtask
task automatic do_reset();
    @(negedge clk); rst = 1;
    repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    logic [7:0] v;
    do_reset();
    expect_ctrl("power-up reset", 8'h9B);
    rd(2'd1, v);
    if (v !== 8'hA5) begin errors++; $display("FAIL port B input after reset: %02h", v); end

    wr(2'd3, 8'h82);                                   // MSX BIOS: A out, B in, C out
    expect_ctrl("after 82h", 8'h82);
    wr(2'd0, 8'hF0);
    @(negedge clk);                                    // porta_dout is registered
    if (pa !== 8'hF0) begin errors++; $display("FAIL port A latch %02h", pa); end

    do_reset();                                        // warm reset
    expect_ctrl("warm reset", 8'h9B);
    if (pa !== 8'h5A) begin errors++; $display("FAIL port A pins after reset %02h (input)", pa); end
    rd(2'd0, v);                                       // port A is an input again
    if (v !== 8'h5A) begin errors++; $display("FAIL port A input after reset: %02h", v); end

    ctrl_default = 7'h0B;                              // other default from ppi.sv
    wr(2'd3, 8'h82);
    do_reset();
    expect_ctrl("warm reset, default 0Bh", 8'h8B);

    if (errors == 0) $display("PASS jt8255_tb");
    else             $display("FAILED jt8255_tb: %0d errors", errors);
    $finish;
end

endmodule
