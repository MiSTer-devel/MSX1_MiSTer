// ps2mouse: MSX mouse nibbles (X high, X low, Y high, Y low) from MiSTer PS/2 mouse events.
// MSX X = -dx / 2, Y = dy / 2, saturated to -128..127; buttons on bits 5:4 (active low).
// Run: wsl.exe -- bash rtl/peripheral/tb/run_ps2mouse.sh [alt_ps2mouse.v]
module ps2mouse_tb;

logic clk = 0, reset = 1, strobe = 1;
logic [24:0] ps2_mouse = '0;
wire  [5:0] data;
always #5 clk = ~clk;

ps2mouse dut (.clk(clk), .reset(reset), .strobe(strobe), .data(data), .ps2_mouse(ps2_mouse));

int errors = 0;

// PS/2 event: signed 9-bit dx / dy, buttons {right, left}
task automatic move(input int dx, input int dy, input logic [1:0] btn = 2'b00);
    @(negedge clk);
    ps2_mouse = {~ps2_mouse[24], 8'(dy), 8'(dx), 2'b00, 1'(dy < 0), 1'(dx < 0), 2'b00, btn};
    repeat (2) @(negedge clk);
endtask

task automatic wait_ms15();                  // latch allowed again
    repeat (33000) @(negedge clk);
endtask

task automatic edge_read(input logic level, output logic [5:0] v);
    strobe = level;
    repeat (3) @(negedge clk);
    v = data;
endtask

// Full read: (fall), rise X hi, fall X lo, rise Y hi, fall Y lo, rise (end of sequence)
task automatic read_mouse(input string what, input logic [7:0] ex, input logic [7:0] ey,
                          input logic [1:0] exp_btn_n = 2'b11);
    logic [5:0] xh, xl, yh, yl, d;
    edge_read(0, d);
    edge_read(1, xh); edge_read(0, xl); edge_read(1, yh); edge_read(0, yl);
    edge_read(1, d);
    if ({xh[3:0], xl[3:0]} !== ex || {yh[3:0], yl[3:0]} !== ey || xh[5:4] !== exp_btn_n) begin
        errors++;
        $display("FAIL %s: X=%02h Y=%02h btn=%b, expected X=%02h Y=%02h btn=%b",
                 what, {xh[3:0], xl[3:0]}, {yh[3:0], yl[3:0]}, xh[5:4], ex, ey, exp_btn_n);
    end
endtask

initial begin
    logic [5:0] d;
    repeat (3) @(negedge clk); reset = 0;
    wait_ms15();

    move(6, 4);
    read_mouse("small move", 8'hFD, 8'h02);                // X = -3, Y = +2
    wait_ms15();
    read_mouse("no move", 8'h00, 8'h00);

    wait_ms15();
    move(20, -30);
    read_mouse("X 20 (ps2mouse.v gave E6)", 8'hF6, 8'hF1);  // X = -10, Y = -15

    wait_ms15();
    move(-100, 100); move(-100, 100); move(-100, 100);
    read_mouse("saturation", 8'h7F, 8'h7F);                // +150 -> 127

    wait_ms15();
    move(0, 0, 2'b01);
    read_mouse("left button", 8'h00, 8'h00, 2'b10);
    move(0, 0, 2'b10);
    wait_ms15();
    read_mouse("right button", 8'h00, 8'h00, 2'b01);
    move(0, 0, 2'b00);

    // Abandoned sequence (only X high read), then a full read after 1.5 ms
    wait_ms15();
    move(2, 0);
    edge_read(0, d); edge_read(1, d);
    wait_ms15();
    move(0, 8);
    read_mouse("after abandoned sequence", 8'h00, 8'h04);

    if (errors == 0) $display("PASS ps2mouse_tb");
    else             $display("FAILED ps2mouse_tb: %0d errors", errors);
    $finish;
end

endmodule
