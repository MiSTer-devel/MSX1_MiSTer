// dev_systimer (S1990 E6h-E7h): tick every 84 clk_core (3.911 us), low / high byte,
// write clears the counter but keeps the prescaler phase, reset, disabled device silent.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_systimer.sh
module systimer_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io_device[3];
wire [7:0] data;

dev_systimer dut (.cpu_bus(cpu_bus), .io_device(io_device), .data(data));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;
int unsigned clks = 0;               // clk since reset release
always @(posedge clk) clks <= reset ? 0 : clks + 1;

task automatic io_write(input logic [7:0] port);
    @(negedge clk); addr = {8'h00, port}; dbo = 8'h55; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; iorq = 0; wr = 0;
endtask

// 16-bit read: low byte, then high byte in the same clk (no carry between them)
task automatic read16(output logic [15:0] v);
    @(negedge clk); iorq = 1; rd = 1;
    addr = 16'h00E6; #1; v[7:0]  = data;
    addr = 16'h00E7; #1; v[15:8] = data;
    iorq = 0; rd = 0;
endtask

task automatic expect_eq(input string what, input logic [15:0] got, input logic [15:0] exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %04h, expected %04h", what, got, exp); end
endtask

initial begin
    logic [15:0] v;
    int unsigned t0;
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'hFE, port: 8'hE6, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    repeat (3) @(negedge clk); reset = 0;

    // Count rate: ticks every 84 clk (first one in the clk after reset)
    read16(v); expect_eq("after reset", v, 16'h0001);
    repeat (84 * 100) @(negedge clk);
    read16(v); expect_eq("100 periods later", v, 16'd101);
    repeat (84 * 300) @(negedge clk);
    read16(v); expect_eq("carry into high byte", v, 16'd401);

    // Write clears, phase kept: next tick still on the 84-clk grid
    while (clks % 84 != 40) @(negedge clk);
    io_write(8'hE7);
    read16(v); expect_eq("write clears", v, 16'h0000);
    while (clks % 84 != 0) @(negedge clk);
    @(negedge clk);
    read16(v); expect_eq("phase kept", v, 16'h0001);

    // Other ports, disabled device
    addr = 16'h00E5; iorq = 1; rd = 1; #1;
    if (data !== 8'hFF) begin errors++; $display("FAIL port E5 = %02h", data); end
    iorq = 0; rd = 0;
    io_device[0].enable = 0;
    read16(v); expect_eq("disabled", v, 16'hFFFF);

    if (errors == 0) $display("PASS systimer_tb");
    else             $display("FAILED systimer_tb: %0d errors", errors);
    $finish;
end

endmodule
