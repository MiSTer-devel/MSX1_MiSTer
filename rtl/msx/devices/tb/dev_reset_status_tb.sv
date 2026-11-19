// dev_reset_status (port F4): bit 7 survives a warm reset (cpu_bus.reset), only a cold
// reset (hard_reset: power-up, MiSTer menu reset, pack upload) clears it. MSX2+ BIOS
// skips the logo on a warm boot; as OCM (emsx_top portF4_bit7, cleared by pColdReset).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run.sh
module dev_reset_status_tb;

logic clk = 0, reset = 1, hard_reset = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io_device[3];
wire [7:0] data;

dev_reset_status dut (.cpu_bus(cpu_bus), .io_device(io_device), .hard_reset(hard_reset), .data(data));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

task automatic io_write(input logic [7:0] d);
    @(negedge clk); addr = 16'h00F4; dbo = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); iorq = 0; wr = 0;
endtask

task automatic expect_f4(input string what, input logic [7:0] exp);
    @(negedge clk); addr = 16'h00F4; iorq = 1; rd = 1;
    #1;
    if (data !== exp) begin errors++; $display("FAIL %s: F4 = %02h, expected %02h", what, data, exp); end
    @(negedge clk); iorq = 0; rd = 0;
endtask

// cold: hard_reset and reset together (as msx.sv: reset includes core_hard_reset)
task automatic pulse(input logic cold);
    @(negedge clk); reset = 1; hard_reset = cold;
    repeat (3) @(negedge clk); reset = 0; hard_reset = 0;
    repeat (2) @(negedge clk);
endtask

initial begin
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'hFF, port: 8'hF4, param: 8'h01, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    pulse(1);

    // Inverted (MSX2+, OCM): bit 7 = 0 after the BIOS has run once
    expect_f4("cold reset", 8'hFF);
    io_write(8'h00);
    expect_f4("BIOS write", 8'h7F);
    pulse(0);
    expect_f4("warm reset keeps bit 7", 8'h7F);
    pulse(1);
    expect_f4("cold reset clears", 8'hFF);

    // Normal polarity (turbo R): bits 7 and 5
    io_device[0].param = 8'h00;
    pulse(1);
    expect_f4("normal: cold reset", 8'h00);
    io_write(8'hA0);
    pulse(0);
    expect_f4("normal: warm reset keeps", 8'hA0);
    pulse(1);
    expect_f4("normal: cold reset clears", 8'h00);

    if (errors == 0) $display("PASS dev_reset_status_tb");
    else             $display("FAILED dev_reset_status_tb: %0d errors", errors);
    $finish;
end

endmodule
