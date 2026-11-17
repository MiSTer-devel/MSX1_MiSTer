// dev_psg with a second PSG of a cartridge (Yamanooto, openMSX Yamanooto.cc): ports 10h-11h,
// write only, not readable; with psg_echo it also takes the writes to A0h-A1h. The system PSG
// (param bit 0) is not touched by the cartridge ports.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_psg_cart.sh
module psg_cart_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
clock u_clock (.clock_bus(clock_bus));
MSX::io_device_t io_device[3];
MSX::sound_t     sound;
wire  [7:0] data;
logic [5:0] joy[2] = '{6'd0, 6'd0};
logic       echo = 0;

dev_psg dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .io_device(io_device), .sound(sound),
             .joy(joy), .ps2_mouse(25'd0), .mouse_port(1'b0),
             .tape_in(1'b0), .psg_echo(echo), .data(data));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

logic [7:0] last_rd;
task automatic io(input logic [7:0] port, input logic [7:0] d, input logic is_wr);
    @(negedge clk); addr = {8'h00, port}; dbo = d; iorq = 1; wr = is_wr; rd = ~is_wr; req = 1;
    @(negedge clk); req = 0;
    repeat (11) @(negedge clk); last_rd = data; iorq = 0; wr = 0; rd = 0;
    repeat (2) @(negedge clk);
endtask

function automatic logic [7:0] sys_reg(input int r);  return dut.PSG_INSTANCES[0].inst.psg_i.u_jt49.regarray[r]; endfunction
function automatic logic [7:0] cart_reg(input int r); return dut.PSG_INSTANCES[1].inst.psg_i.u_jt49.regarray[r]; endfunction

task automatic chk(input string what, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %02h (expected %02h)", what, got, exp); end
endtask

initial begin
    io_device[0] = '{mask: 8'hFC, port: 8'hA0, param: 8'h01, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b1};
    io_device[1] = '{mask: 8'hFE, port: 8'h10, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd1, enable: 1'b1};
    io_device[2] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    repeat (4) @(negedge clk); reset = 0;
    repeat (4) @(negedge clk);

    // cartridge ports
    io(8'h10, 8'd8, 1); io(8'h11, 8'h0F, 1);
    chk("cartridge reg 8 via 10h/11h", cart_reg(8), 8'h0F);
    chk("system reg 8 untouched",      sys_reg(8),  8'h00);

    // system ports without ECHO
    io(8'hA0, 8'd8, 1); io(8'hA1, 8'h05, 1);
    chk("system reg 8 via A0h/A1h",     sys_reg(8),  8'h05);
    chk("cartridge reg 8 without ECHO", cart_reg(8), 8'h0F);

    // ECHO: A0h/A1h reach both
    echo = 1;
    io(8'hA0, 8'd9, 1); io(8'hA1, 8'h07, 1);
    chk("ECHO: system reg 9",    sys_reg(9),  8'h07);
    chk("ECHO: cartridge reg 9", cart_reg(9), 8'h07);
    io(8'hA2, 8'h00, 0);                                // read of the system PSG: no write anywhere
    chk("ECHO: A2h read leaves the cartridge", cart_reg(9), 8'h07);
    echo = 0;

    // reads of 10h-11h: not readable, no latch, no write
    io(8'h10, 8'd10, 1);                                // latch 10
    io(8'h10, 8'd2, 0);                                 // a read with 2 on the bus: must not latch
    io(8'h11, 8'h0C, 0);                                // a read: must not write
    io(8'h11, 8'h0A, 1);
    chk("read did not latch: reg 10", cart_reg(10), 8'h0A);
    chk("read did not write: reg 2",  cart_reg(2),  8'h00);
    io(8'h12, 8'h00, 0);
    chk("cartridge PSG not readable", last_rd, 8'hFF);
    io(8'hA0, 8'd9, 1); io(8'hA2, 8'h00, 0);
    chk("system PSG readable (check of the read itself)", last_rd, 8'h07);

    if (errors == 0) $display("PASS psg_cart_tb");
    else             $display("FAILED psg_cart_tb: %0d errors", errors);
    $finish;
end

endmodule
