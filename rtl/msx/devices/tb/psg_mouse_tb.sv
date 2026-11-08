// dev_psg joystick ports with the PS/2 mouse (OCM): PSG register 14 shows the joystick until
// the mouse moves, then the mouse nibbles strobed by register 15 bit 4 / 5 (pin 8); a joystick
// action on that port gives it back; without mouse_en the mouse is ignored.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_psg_mouse.sh
module psg_mouse_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
clock u_clock (.clock_bus(clock_bus));
MSX::io_device_t io_device[3];
MSX::sound_t     sound;
wire  [7:0] data;
logic [5:0] joy[2];
logic [24:0] ps2_mouse = '0;
logic       mouse_en = 1, mouse_port = 0;

dev_psg dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .io_device(io_device), .sound(sound),
             .joy(joy), .ps2_mouse(ps2_mouse), .mouse_en(mouse_en), .mouse_port(mouse_port),
             .tape_in(1'b0), .data(data));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

// I/O cycle held for 12 clk (> one 3.58 MHz clock enable period)
task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; dbo = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (11) @(negedge clk); iorq = 0; wr = 0;
    repeat (2) @(negedge clk);
endtask

task automatic psg_read(input logic [7:0] r, output logic [7:0] v);
    io_write(8'hA0, r);
    @(negedge clk); addr = 16'h00A2; iorq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (11) @(negedge clk);
    v = data;
    iorq = 0; rd = 0;
    repeat (2) @(negedge clk);
endtask

task automatic set_b(input logic [7:0] v);  // register 15: port B (pins 6/7/8, port select)
    io_write(8'hA0, 8'd15); io_write(8'hA1, v);
endtask

task automatic move(input int dx, input int dy);
    @(negedge clk);
    ps2_mouse = {~ps2_mouse[24], 8'(dy), 8'(dx), 2'b00, 1'(dy < 0), 1'(dx < 0), 4'b0000};
    repeat (2) @(negedge clk);
endtask

task automatic expect_a(input string what, input logic [5:0] exp);
    logic [7:0] v;
    psg_read(8'd14, v);
    if (v[5:0] !== exp) begin errors++; $display("FAIL %s: reg 14 = %02h (bits 5:0 %02h), expected %02h", what, v, v[5:0], exp); end
endtask

// Mouse nibbles on port 1: strobe = reg 15 bit 4 (pins 6/7 high, port 1 selected)
task automatic read_mouse(input string what, input logic [7:0] ex, input logic [7:0] ey);
    logic [7:0] xh, xl, yh, yl;
    set_b(8'h0F); repeat (40000) @(negedge clk);       // > 1.5 ms since the last latch
    set_b(8'h1F); psg_read(8'd14, xh);
    set_b(8'h0F); psg_read(8'd14, xl);
    set_b(8'h1F); psg_read(8'd14, yh);
    set_b(8'h0F); psg_read(8'd14, yl);
    set_b(8'h1F);
    if ({xh[3:0], xl[3:0]} !== ex || {yh[3:0], yl[3:0]} !== ey) begin
        errors++;
        $display("FAIL %s: X=%02h Y=%02h, expected X=%02h Y=%02h", what, {xh[3:0], xl[3:0]}, {yh[3:0], yl[3:0]}, ex, ey);
    end
endtask

initial begin
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'hFC, port: 8'hA0, param: 8'h01, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    joy[0] = '0; joy[1] = '0;
    repeat (4) @(negedge clk); reset = 0;
    io_write(8'hA0, 8'd7); io_write(8'hA1, 8'h80);      // port A input, port B output
    set_b(8'h0F);

    // Joystick: up + fire 1 (MiSTer bits 3, 4) -> active low bits 0, 4
    joy[0] = 6'b010000 | 6'b001000;
    expect_a("joystick", 6'b101110);
    joy[0] = '0;
    expect_a("joystick idle", 6'b111111);

    // Mouse moves -> port 1 is the mouse
    move(-8, 6);
    read_mouse("mouse port 1", 8'h04, 8'h03);

    // Joystick on port 1 gives the port back
    set_b(8'h0F);                                         // pin 8 low: joystick common
    joy[0] = 6'b000001;                                   // right
    expect_a("joystick back", 6'b110111);
    joy[0] = '0;

    // Mouse on port 2: port 1 stays joystick
    mouse_port = 1;
    move(4, 0);
    expect_a("port 1 joystick (mouse on 2)", 6'b111111);

    // Without mouse_en (not OCM) the mouse is ignored
    mouse_port = 0; mouse_en = 0;
    move(10, 10);
    set_b(8'h0F);
    expect_a("mouse disabled", 6'b111111);

    if (errors == 0) $display("PASS psg_mouse_tb");
    else             $display("FAILED psg_mouse_tb: %0d errors", errors);
    $finish;
end

endmodule
