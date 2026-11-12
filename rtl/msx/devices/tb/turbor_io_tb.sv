// Turbo R I/O devices against openMSX: dev_s1990 (E4h / E5h: select read back, register 5
// firmware switch, register 6 CPU status, 13-15 fixed, others FFh, reset 60h) and
// dev_turbor_pause (A7h: pause toggle, LEDs, hardware pause).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_turbor_io.sh
module turbor_io_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io_s1990[3], io_pause[3];
wire  [7:0] s1990_data, pause_data;
wire        r800, dram, hw_pause, pause_led, turbo_led;
logic       firmware_sw = 0;
logic       pause_key = 0;                       // Pause key state from keyboard.sv (keyboard_tb)
task automatic key;                              // the Pause key toggles the state
    @(negedge clk); pause_key = ~pause_key; @(negedge clk);
endtask

dev_s1990 s1990 (.cpu_bus(cpu_bus), .io_device(io_s1990), .firmware_sw(firmware_sw),
                 .data(s1990_data), .r800(r800), .dram(dram));
dev_turbor_pause pause (.cpu_bus(cpu_bus), .io_device(io_pause), .pause_key(pause_key),
                        .data(pause_data), .hw_pause(hw_pause), .pause_led(pause_led), .turbo_led(turbo_led));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;
task automatic expect8(input string what, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %02h, expected %02h", what, got, exp); end
endtask
task automatic expect1(input string what, input logic got, input logic exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %b, expected %b", what, got, exp); end
endtask

task automatic out(input logic [7:0] port, input logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; dbo = v; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; iorq = 0; wr = 0;
endtask
task automatic in(input logic [7:0] port, output logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; #1;
    v = s1990_data & pause_data;
    @(negedge clk); iorq = 0; rd = 0;
endtask

initial begin
    logic [7:0] v;
    for (int i = 0; i < 3; i++) begin
        io_s1990[i] = '{mask: 8'hFE, port: 8'hE4, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
        io_pause[i] = '{mask: 8'hFF, port: 8'hA7, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    end
    repeat (3) @(negedge clk); reset = 0;

    // --- S1990
    in(8'hE4, v); expect8("E4 after reset", v, 8'h00);
    out(8'hE4, 8'h06); in(8'hE4, v); expect8("E4 read back", v, 8'h06);
    in(8'hE5, v); expect8("reg 6 after reset (Z80, ROM)", v, 8'h60);
    expect1("r800 after reset", r800, 0); expect1("dram after reset", dram, 0);
    out(8'hE5, 8'hFF); in(8'hE5, v); expect8("reg 6 keeps bits 6:5", v, 8'h60);
    out(8'hE5, 8'h40); in(8'hE5, v); expect8("reg 6 = 40h (R800, ROM)", v, 8'h40);
    expect1("r800 with 40h", r800, 1); expect1("dram with 40h", dram, 0);
    out(8'hE5, 8'h00);
    expect1("r800 with 00h", r800, 1); expect1("dram with 00h", dram, 1);
    out(8'hE4, 8'h05); in(8'hE5, v); expect8("reg 5, firmware switch off", v, 8'h00);
    firmware_sw = 1;   in(8'hE5, v); expect8("reg 5, firmware switch on", v, 8'h40);
    out(8'hE5, 8'h12); in(8'hE5, v); expect8("reg 5 not writable", v, 8'h40);
    out(8'hE4, 8'd13); in(8'hE5, v); expect8("reg 13", v, 8'h03);
    out(8'hE4, 8'd14); in(8'hE5, v); expect8("reg 14", v, 8'h2F);
    out(8'hE4, 8'd15); in(8'hE5, v); expect8("reg 15", v, 8'h8B);
    out(8'hE4, 8'd0);  in(8'hE5, v); expect8("reg 0", v, 8'hFF);
    out(8'hE4, 8'd6);  in(8'hE5, v); expect8("reg 6 unchanged by other writes", v, 8'h00);
    in(8'hE6, v); expect8("E6 is not the S1990", v, 8'hFF);

    // --- Pause
    in(8'hA7, v); expect8("A7 after reset", v, 8'h00);
    key;
    in(8'hA7, v); expect8("A7 after the pause key", v, 8'h01);
    expect1("no hardware pause without bit 1", hw_pause, 0); expect1("pause LED off", pause_led, 0);
    out(8'hA7, 8'h02);
    expect1("hardware pause", hw_pause, 1); expect1("pause LED with hardware pause", pause_led, 1);
    key;
    expect1("pause released", hw_pause, 0);
    out(8'hA7, 8'h81);
    expect1("pause LED bit 0", pause_led, 1); expect1("turbo LED bit 7", turbo_led, 1);
    in(8'hA7, v); expect8("A7 reads the pause only", v, 8'h00);

    // --- reset
    @(negedge clk); reset = 1; @(negedge clk); reset = 0;
    expect1("r800 after reset", r800, 0); expect1("turbo LED after reset", turbo_led, 0);

    if (errors == 0) $display("PASS turbor_io_tb");
    else             $display("FAILED turbor_io_tb: %0d errors", errors);
    $finish;
end

endmodule
