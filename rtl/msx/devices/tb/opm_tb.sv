// dev_opm: YM2151 (OPM) and YM2164 (OPP) variant, io_device param bit 0 (openMSX YM2151.cc):
// - the test register is 01h on the YM2151 and 09h on the YM2164 (bit 1 resets the LFO);
// - timer B: the YM2164 counts at half the rate of the YM2151 (openMSX createOPP_2 / createOPM_2).
//   The YM2151 period is checked against the datasheet, 1024 x (256 - NB) / phiM, as jt51
//   does; openMSX uses 2048 clocks per count (64 x 2 x 16).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_opm.sh
module opm_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;                       // 1 clk = 10 time units, clk_core 21.48 MHz

cpu_bus_if   cpu_bus(clk, rst);
clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

MSX::io_device_t  io_device[3];
MSX::device_bus_t device_bus = '{device_ref: 3'd0, we: 1'b0, en: 1'b0, mode: 1'b0, param: 1'b0};
MSX::sound_t      sound_L, sound_R;
wire        [7:0] data;
wire              irq;

dev_opm dut (.cpu_bus(cpu_bus), .device_bus(device_bus), .clock_bus(clock_bus.base_mp),
             .io_device(io_device), .sound_L(sound_L), .sound_R(sound_R), .data(data), .irq(irq));

logic [15:0] addr = '0;
logic  [7:0] wdata = '0;
logic        iorq = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = wdata;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = 1'b0;  assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;

task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; wdata = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (8) @(negedge clk);
    iorq = 0; wr = 0;
    repeat (1500) @(negedge clk);           // jt51 busy after a data write
endtask

task automatic opm_reg(input logic [7:0] r, input logic [7:0] v);
    io_write(8'h40, r);
    io_write(8'h41, v);
endtask

task automatic restart(input logic ym2164);
    io_device[0] = '{mask: 8'hFE, port: 8'h40, param: {7'd0, ym2164}, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b1};
    io_device[1] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    io_device[2] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    rst = 1; repeat (200) @(negedge clk); rst = 0;
    repeat (200) @(negedge clk);
endtask

wire [7:0] test_mode = dut.OPM_INSTANCES[0].jt51_i.test_mode;

task automatic test_reg(input logic ym2164);
    string v = ym2164 ? "YM2164" : "YM2151";
    restart(ym2164);
    opm_reg(ym2164 ? 8'h01 : 8'h09, 8'h0A);         // the other variant's test register
    if (test_mode != 8'h00) begin
        $display("FAIL %s: register %02h changed the test register (%02h)", v, ym2164 ? 8'h01 : 8'h09, test_mode);
        errors++;
    end
    opm_reg(ym2164 ? 8'h09 : 8'h01, 8'h02);         // its test register: LFO reset
    if (test_mode != 8'h02) begin
        $display("FAIL %s: register %02h -> test register %02h, expected 02", v, ym2164 ? 8'h09 : 8'h01, test_mode);
        errors++;
    end else
        $display("ok   %s: test register at %02h", v, ym2164 ? 8'h09 : 8'h01);
endtask

// clk between two timer B interrupts, B = 80h (128 counts)
task automatic timer_b(input logic ym2164, output longint period);
    longint t0;
    restart(ym2164);
    opm_reg(8'h12, 8'h80);
    opm_reg(8'h14, 8'h3A);                          // reset flags, IRQ B on, load B
    wait (irq);
    opm_reg(8'h14, 8'h2A);                          // reset flag B, keep running
    wait (!irq);
    t0 = $time;
    wait (irq);
    period = ($time - t0) / 10;
endtask

initial begin
    longint p51, p64;
    real exp51;
    io_device[0] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0}; io_device[1] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0}; io_device[2] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};

    test_reg(1'b0);
    test_reg(1'b1);

    // datasheet: (256 - B) x 1024 clocks of phiM = 3.58 MHz on the YM2151
    exp51 = 128.0 * 1024.0 * 21477270.0 / 3579545.0;
    timer_b(1'b0, p51);
    timer_b(1'b1, p64);
    $display("timer B 80h: YM2151 %0d clk (datasheet %0.0f), YM2164 %0d clk, ratio %0.3f",
             p51, exp51, p64, real'(p64) / real'(p51));
    // the second period starts after the flag reset write, up to one count (1/128) short
    if (real'(p51) < exp51 * 0.98 || real'(p51) > exp51 * 1.01) begin
        $display("FAIL YM2151 timer B period"); errors++;
    end
    if (real'(p64) / real'(p51) < 1.97 || real'(p64) / real'(p51) > 2.03) begin
        $display("FAIL YM2164 timer B is not twice the YM2151 period"); errors++;
    end

    if (errors == 0) $display("PASS opm_tb");
    else             $display("FAIL opm_tb (%0d)", errors);
    $finish;
end

endmodule
