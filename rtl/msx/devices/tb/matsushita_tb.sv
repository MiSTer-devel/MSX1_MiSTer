`timescale 1ns/1ps
// dev_matsushita (switched I/O 40h-4Fh, ID 08h) and dev_ciel_turbo against openMSX
// MSXMatsushita.cc / MSXCielTurbo.cc: device select, turbo switch and its read-back
// (with and without the turbo), firmware switch, colour / pattern register, SRAM address
// and data with auto increment, resets; CIEL port: speed bit 7 and read-back.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_matsushita.sh
module matsushita_tb;

logic clk = 0, reset = 1, hard_reset = 1, firmware_sw = 0;
always #1 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io[3], io_ciel[3];
wire  [7:0] data_m, data_c;
wire  [7:0] data = data_m & data_c;
MSX::cpu_speed_t speed, speed_c;

dev_matsushita dut (.cpu_bus(cpu_bus), .io_device(io), .hard_reset(hard_reset),
                    .firmware_sw(firmware_sw), .data(data_m), .cpu_speed(speed));
dev_ciel_turbo ciel (.cpu_bus(cpu_bus), .io_device(io_ciel), .data(data_c), .cpu_speed(speed_c));

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

// CPU access: strobe held 1-12 clocks (req only in the first), then 0-3 idle clocks
task automatic out(input logic [7:0] port, input logic [7:0] v);
    int w = $urandom_range(12, 1);
    @(negedge clk); addr = {8'h00, port}; dbo = v; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    iorq = 0; wr = 0;
    repeat ($urandom_range(3)) @(negedge clk);
endtask
task automatic in(input logic [7:0] port, output logic [7:0] v);
    int w = $urandom_range(12, 2);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    v = data;
    iorq = 0; rd = 0;
    repeat ($urandom_range(3)) @(negedge clk);
endtask
task automatic rd_check(input string what, input logic [7:0] port, input int exp);
    logic [7:0] v;
    in(port, v);
    check(what, v, exp);
endtask
task automatic do_reset(input logic hard);
    @(negedge clk); reset = 1; hard_reset = hard;
    repeat (3) @(negedge clk); reset = 0; hard_reset = 0;
    @(negedge clk);
endtask

logic [7:0] ref_sram [0:2047];

initial begin
    #2_000_000;
    $display("FAILED matsushita_tb: timeout (%0d errors before)", errors);
    $finish;
end

initial begin
    logic [7:0] v;
    foreach (io[i]) begin io[i] = '{default: '0}; io_ciel[i] = '{default: '0}; end
    io[0].enable = 1; io[0].port = 8'h40; io[0].mask = 8'hF0; io[0].param = 8'h03;   // turbo + SRAM
    io_ciel[0].enable = 1; io_ciel[0].port = 8'hB6; io_ciel[0].mask = 8'hFF;
    do_reset(1);

    // --- not selected: everything reads FF, writes to the registers are ignored
    rd_check("40h, nothing selected", 8'h40, 8'hFF);
    rd_check("41h, nothing selected", 8'h41, 8'hFF);
    out(8'h41, 8'h00);
    check("turbo not switched without select", speed.clock_sel, 0);
    out(8'h40, 8'hD4);                          // another device
    rd_check("40h, other device", 8'h40, 8'hFF);
    out(8'h41, 8'h00);
    check("turbo not switched for another ID", speed.clock_sel, 0);

    // --- selected: ID complement, turbo available (bit 2 = 0), turbo off (bit 0 = 1)
    out(8'h40, 8'h08);
    rd_check("40h", 8'h40, 8'hF7);
    rd_check("41h after cold reset", 8'h41, 8'hFB);
    check("speed override present", speed.en, 1);
    check("3.58 MHz after cold reset", speed.clock_sel, 0);
    check("VDP writes timed", speed.vdp_wr_hold, 1);
    check("VDP writes not held", speed.vdp_wr_wait, 0);
    out(8'h41, 8'hFE);                          // bit 0 = 0: turbo on
    check("5.37 MHz", speed.clock_sel, 2);
    check("VDP writes held in turbo", speed.vdp_wr_wait, 1);
    rd_check("41h, turbo on", 8'h41, 8'hFA);
    firmware_sw = 1;
    rd_check("41h, firmware switch on", 8'h41, 8'h7A);
    firmware_sw = 0;
    do_reset(0);                                // warm reset keeps the turbo, drops the select
    check("turbo kept over a warm reset", speed.clock_sel, 2);
    rd_check("select cleared by reset", 8'h40, 8'hFF);
    out(8'h40, 8'h08);
    out(8'h41, 8'h01);
    check("3.58 MHz again", speed.clock_sel, 0);
    rd_check("41h, turbo off", 8'h41, 8'hFB);
    out(8'h41, 8'h00);
    do_reset(1);
    check("turbo off after a cold reset", speed.clock_sel, 0);
    out(8'h40, 8'h08);

    // --- colours and pattern: two pixels per read, the pattern rotates by 2 bits
    out(8'h43, 8'hA5);                          // colour 2 = A, colour 1 = 5
    out(8'h44, 8'b10_01_11_00);
    rd_check("pattern 10", 8'h43, 8'hA5);
    rd_check("pattern 01", 8'h43, 8'h5A);
    rd_check("pattern 11", 8'h43, 8'hAA);
    rd_check("pattern 00", 8'h43, 8'h55);
    rd_check("pattern again 10", 8'h43, 8'hA5);
    rd_check("42h unused", 8'h42, 8'hFF);

    // --- SRAM: address 13 bits, 2 kB below 800h, auto increment on read and write
    out(8'h47, 8'h00); out(8'h48, 8'h00);
    rd_check("SRAM empty", 8'h49, 8'hFF);       // address 1 now
    out(8'h47, 8'h00);
    for (int i = 0; i < 2048; i++) begin
        ref_sram[i] = 8'($urandom);
        out(8'h49, ref_sram[i]);
    end
    out(8'h49, 8'h12);                          // address 800h: no SRAM
    out(8'h47, 8'h00); out(8'h48, 8'hE0);       // high: 5 bits only -> 0000h
    for (int i = 0; i < 2048; i++) begin
        in(8'h49, v);
        if (v !== ref_sram[i]) begin
            errors++;
            if (errors < 10) $display("FAIL SRAM %0h: %0h, expected %0h", i, v, ref_sram[i]);
        end
    end
    rd_check("SRAM above 800h", 8'h49, 8'hFF);
    out(8'h47, 8'hFF); out(8'h48, 8'h1F);       // 1FFFh, wraps to 0000h
    rd_check("SRAM 1FFFh", 8'h49, 8'hFF);
    rd_check("SRAM wrapped to 0", 8'h49, ref_sram[0]);
    do_reset(0);
    out(8'h40, 8'h08);
    rd_check("address 0 after reset, SRAM kept", 8'h49, ref_sram[0]);
    rd_check("colours cleared by reset", 8'h43, 8'h00);

    // --- no turbo, no SRAM (Sanyo PHC-35J): flag works, no speed change
    io[0].param = 8'h00;
    do_reset(1);
    out(8'h40, 8'h08);
    rd_check("41h without turbo", 8'h41, 8'hFF);
    out(8'h41, 8'h00);
    rd_check("41h, flag set without turbo", 8'h41, 8'hFE);
    check("no speed override", speed.en, 0);
    check("no speed change", speed.clock_sel, 0);
    check("no VDP hold", speed.vdp_wr_wait, 0);
    out(8'h47, 8'h00); out(8'h48, 8'h00); out(8'h49, 8'h55);
    out(8'h47, 8'h00);
    rd_check("no SRAM", 8'h49, 8'hFF);

    // --- device disabled
    io[0].enable = 0;
    rd_check("disabled", 8'h40, 8'hFF);

    // --- CIEL turbo
    check("CIEL: 3.58 MHz after reset", speed_c.clock_sel, 0);
    rd_check("CIEL: reads 00", 8'hB6, 8'h00);
    out(8'hB6, 8'h85);
    check("CIEL: 7.16 MHz", speed_c.clock_sel, 3);
    rd_check("CIEL: reads back", 8'hB6, 8'h85);
    out(8'hB7, 8'h00);
    check("CIEL: other port ignored", speed_c.clock_sel, 3);
    out(8'hB6, 8'h7F);
    check("CIEL: 3.58 MHz", speed_c.clock_sel, 0);
    out(8'hB6, 8'h80);
    do_reset(0);
    check("CIEL: reset clears the turbo", speed_c.clock_sel, 0);

    if (errors == 0) $display("PASS matsushita_tb");
    else             $display("FAILED matsushita_tb: %0d errors", errors);
    $finish;
end

endmodule
