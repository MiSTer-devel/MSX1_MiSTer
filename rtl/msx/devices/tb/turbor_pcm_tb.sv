// dev_turbor_pcm against openMSX MSXTurboRPCM: A4h tick count (15.7 kHz, cleared by a write,
// wraps), DAC only when not muted, BUFF delays the DAC to the next tick, BUFF 1 -> 0 writes it at
// once, MUTE (A5h bit 1 = 0) mutes the machine, A5h read COMP and status, reset values.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_turbor_io.sh
module turbor_pcm_tb;

localparam int TICK = 1368;                 // clk_core per 15.7 kHz tick

logic clk = 0, reset = 1;
always #5 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io_pcm[3];
wire  [7:0] data;
MSX::sound_t sound;
wire        mute_all;

dev_turbor_pcm dut (.cpu_bus(cpu_bus), .io_device(io_pcm), .data(data), .sound(sound), .mute_all(mute_all));

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
task automatic expect_dac(input string what, input logic [7:0] exp);
    MSX::sound_t s = MSX::sound_t'(($signed({8'b0, exp}) - 16'sd128) <<< 7);
    if (sound !== s) begin errors++; $display("FAIL %s: sound %0d, expected DAC %02h (%0d)", what, sound, exp, s); end
endtask

task automatic out(input logic [7:0] port, input logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; dbo = v; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; iorq = 0; wr = 0;
endtask
task automatic in(input logic [7:0] port, output logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; #1;
    v = data;
    @(negedge clk); iorq = 0; rd = 0;
endtask
task automatic wait_tick();                 // until just after the next tick
    @(posedge clk);
    while (dut.prescaler != '0) @(posedge clk);
    @(negedge clk);
endtask

initial begin
    logic [7:0] v;
    for (int i = 0; i < 3; i++)
        io_pcm[i] = '{mask: 8'hFE, port: 8'hA4, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: i == 0};
    repeat (3) @(negedge clk); reset = 0;

    // reset: D value 80h, hold 80h -> COMP = 80h >= 80h; DAC 80h (silence), not muted
    in(8'hA5, v); expect8("A5 after reset", v, 8'h80);
    expect_dac("DAC after reset", 8'h80);
    if (mute_all !== 1'b0) begin errors++; $display("FAIL muted after reset"); end

    // tick count: cleared by an A4 write, counts 15.7 kHz ticks, bits 1:0
    wait_tick();
    out(8'hA4, 8'h10);
    in(8'hA4, v); expect8("A4 right after the write", v, 8'h00);
    wait_tick(); in(8'hA4, v); expect8("A4 after 1 tick", v, 8'h01);
    wait_tick(); wait_tick(); in(8'hA4, v); expect8("A4 after 3 ticks", v, 8'h03);
    wait_tick(); in(8'hA4, v); expect8("A4 after 4 ticks (wraps)", v, 8'h00);
    expect_dac("muted status: A4 does not reach the DAC", 8'h80);

    // not muted: the DAC takes the value at once
    out(8'hA5, 8'h02);
    if (mute_all !== 1'b0) begin errors++; $display("FAIL muted with A5 = 02h"); end
    out(8'hA4, 8'hC0); expect_dac("A4 C0h, not muted", 8'hC0);

    // BUFF: at the next tick
    out(8'hA5, 8'h03);
    wait_tick();
    out(8'hA4, 8'h40); expect_dac("BUFF: DAC unchanged before the tick", 8'hC0);
    wait_tick(); expect_dac("BUFF: DAC at the tick", 8'h40);
    out(8'hA4, 8'h20); expect_dac("BUFF: before BUFF 1 -> 0", 8'h40);
    out(8'hA5, 8'h02); expect_dac("BUFF 1 -> 0 writes at once", 8'h20);

    // COMP: input 80h against the D value; status bits 4:0 read back
    in(8'hA5, v); expect8("A5: COMP (80h >= 20h), status 02h", v, 8'h82);
    out(8'hA4, 8'h90);
    in(8'hA5, v); expect8("A5: COMP (80h < 90h)", v, 8'h02);
    out(8'hA5, 8'hFE);
    in(8'hA5, v); expect8("A5 keeps bits 4:0 only", v, 8'h1E);

    // MUTE: A5 bit 1 = 0 mutes the machine
    out(8'hA5, 8'h00);
    if (mute_all !== 1'b1) begin errors++; $display("FAIL not muted with A5 = 00h"); end
    out(8'hA4, 8'h00); expect_dac("muted: A4 does not reach the DAC", 8'h90);

    if (errors == 0) $display("PASS turbor_pcm_tb");
    else             $display("FAILED turbor_pcm_tb: %0d errors", errors);
    $finish;
end

endmodule
