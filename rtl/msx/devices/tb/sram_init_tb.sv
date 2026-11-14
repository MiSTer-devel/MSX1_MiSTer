`timescale 1ns/1ps
// SRAMs of the machine devices (not saved): RTC backup memory (banks 2 and 3) and the 2 kB SRAM
// of the Matsushita switched I/O. After power-on they read FFh (openMSX: new SRAM = FFh), the
// CPU writes read back, a reset keeps them, sram_init (pack load) fills them with FFh again.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_sram_init.sh   (OLD=1: modules without sram_init)
module sram_init_tb;

logic clk = 0, reset = 1, hard_reset = 1, sram_init = 0;
always #1 clk = ~clk;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
assign clock_bus.ce_10hz = 1'b0;

MSX::io_device_t io_rtc[3], io_mat[3];
wire [7:0] data_rtc, data_mat;
wire [7:0] data = data_rtc & data_mat;
MSX::cpu_speed_t speed;

dev_rtc rtc (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .io_device(io_rtc), .rtc_time(65'd0),
`ifndef OLD
             .sram_init(sram_init),
`endif
             .data(data_rtc));
dev_matsushita mat (.cpu_bus(cpu_bus), .io_device(io_mat), .hard_reset(hard_reset),
`ifndef OLD
                    .sram_init(sram_init),
`endif
                    .firmware_sw(1'b0), .data(data_mat), .cpu_speed(speed));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

int errors = 0;
task automatic check(input string what, input int got, input int exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %0h, expected %0h", what, got, exp); end
endtask

task automatic out(input logic [7:0] port, input logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; dbo = v; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat ($urandom_range(4)) @(negedge clk);
    iorq = 0; wr = 0;
    @(negedge clk);
endtask
task automatic in(input logic [7:0] port, output logic [7:0] v);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat ($urandom_range(4, 1)) @(negedge clk);
    v = data;
    iorq = 0; rd = 0;
    @(negedge clk);
endtask

// RTC: register r of bank b (mode register 13: timer enable + bank)
task automatic rtc_wr(input int b, input int r, input logic [3:0] v);
    out(8'hB4, 8'd13); out(8'hB5, 8'(8 + b));
    out(8'hB4, 8'(r)); out(8'hB5, {4'h0, v});
endtask
task automatic rtc_rd(input int b, input int r, output logic [7:0] v);
    out(8'hB4, 8'd13); out(8'hB5, 8'(8 + b));
    out(8'hB4, 8'(r)); in(8'hB5, v);
endtask
// Matsushita SRAM: select ID 08h, address 47h / 48h, data 49h (auto increment)
task automatic mat_addr(input int a);
    out(8'h40, 8'h08); out(8'h47, 8'(a)); out(8'h48, 8'(a >> 8));
endtask

function automatic logic [3:0] pat(input int b, input int r);
    return 4'((b * 5 + r * 3 + 1) & 15);
endfunction

task automatic check_all_ff(input string when);
    logic [7:0] v;
    int e0 = errors;
    for (int b = 2; b < 4; b++)
        for (int r = 0; r < 13; r++) begin
            rtc_rd(b, r, v);
            check($sformatf("%s: RTC bank %0d reg %0d", when, b, r), v, 8'hFF);
        end
    mat_addr(0);
    for (int a = 0; a < 2048; a += 1) begin
        in(8'h49, v);
        if (v !== 8'hFF) begin check($sformatf("%s: Matsushita SRAM %03h", when, a), v, 8'hFF); break; end
    end
    if (errors == e0) $display("ok   %s: RTC banks 2-3 and Matsushita SRAM read FFh", when);
endtask

task automatic write_and_check(input string when);
    logic [7:0] v;
    int e0 = errors;
    for (int b = 2; b < 4; b++)
        for (int r = 0; r < 13; r++) rtc_wr(b, r, pat(b, r));
    for (int b = 2; b < 4; b++)
        for (int r = 0; r < 13; r++) begin
            rtc_rd(b, r, v);
            check($sformatf("%s: RTC bank %0d reg %0d", when, b, r), v, {4'hF, pat(b, r)});
        end
    // the last 16 bytes; 800h is past the 2 kB and stays FFh
    mat_addr(16'h7F0);
    for (int i = 0; i < 17; i++) out(8'h49, 8'((i * 7 + 3) & 255));
    mat_addr(16'h7F0);
    for (int i = 0; i < 17; i++) begin
        in(8'h49, v);
        check($sformatf("%s: Matsushita SRAM %03h", when, 16'h7F0 + i), v, i < 16 ? (i * 7 + 3) & 255 : 255);
    end
    if (errors == e0) $display("ok   %s: written values read back", when);
endtask

initial begin
    #20_000_000;
    $display("FAILED sram_init_tb: timeout (%0d errors before)", errors);
    $finish;
end

initial begin
    foreach (io_rtc[i]) begin io_rtc[i] = '{default: '0}; io_mat[i] = '{default: '0}; end
    io_rtc[0].enable = 1; io_rtc[0].port = 8'hB4; io_rtc[0].mask = 8'hFE;
    io_mat[0].enable = 1; io_mat[0].port = 8'h40; io_mat[0].mask = 8'hF0; io_mat[0].param = 8'h03;
    repeat (3) @(negedge clk); reset = 0; hard_reset = 0;

    check_all_ff("power-on");
    write_and_check("CPU writes");

    // a reset (cold or warm) keeps the battery-backed memory
    @(negedge clk); reset = 1; hard_reset = 1; repeat (3) @(negedge clk); reset = 0; hard_reset = 0;
    begin
        logic [7:0] v;
        rtc_rd(3, 12, v); check("after reset: RTC bank 3 reg 12", v, {4'hF, pat(3, 12)});
        mat_addr(16'h7F1); in(8'h49, v); check("after reset: Matsushita SRAM 7F1", v, 8'd10);
    end

    // pack load: reset and sram_init for a few thousand clocks
    @(negedge clk); reset = 1; hard_reset = 1; sram_init = 1;
    repeat (5000) @(negedge clk);
    reset = 0; hard_reset = 0; sram_init = 0;
    check_all_ff("after sram_init");

    if (errors == 0) $display("PASS sram_init_tb");
    else             $display("FAILED sram_init_tb: %0d errors", errors);
    $finish;
end

endmodule
