`timescale 1ns/1ps
// dev_YM2148 MIDI out (openMSX YM2148): 31250 Bd 8N1 decoded from tx, TXRDY kept for the
// first byte and cleared for a second one written while sending, TxRDY IRQ when the
// waiting byte starts, random CPU strobe widths, transmitter off aborts the frame.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_ym2148.sh
module ym2148_tb;

logic clk = 0, reset = 1;
always #1 clk = ~clk;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
MSX::io_device_t io[3];
MSX::device_bus_t device_bus;
wire  [7:0] data;
wire        irq, tx;

dev_YM2148 dut (.cpu_bus(cpu_bus), .device_bus(device_bus), .clock_bus(clock_bus), .io_device(io),
                .uart_rx_data(8'h00), .uart_rx(1'b0), .data(data), .irq(irq), .tx(tx));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0, sel = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = 1'b0;  assign cpu_bus.mreq = mreq;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;
assign device_bus   = '{device_ref: 3'd0, we: sel, en: sel, mode: 1'b1, param: 1'b1};

int errors = 0;
task automatic check(input string what, input int got, input int exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %0h, expected %0h", what, got, exp); end
endtask

int w_rand = 0;
function automatic int width();
    return w_rand ? $urandom_range(16, 1) : 2;
endfunction
task automatic wr_reg(input logic [2:0] r, input logic [7:0] v);
    int w = width();
    @(negedge clk); addr = 16'h3FF0 | r; dbo = v; mreq = 1; wr = 1; req = 1; sel = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    mreq = 0; wr = 0; sel = 0;
    if (w_rand) repeat ($urandom_range(3)) @(negedge clk);
endtask
task automatic rd_reg(input logic [2:0] r, output logic [7:0] v);
    int w = width();
    @(negedge clk); addr = 16'h3FF0 | r; mreq = 1; rd = 1; req = 1; sel = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    v = data;
    mreq = 0; rd = 0; sel = 0;
    if (w_rand) repeat ($urandom_range(3)) @(negedge clk);
endtask

// decoder, 31250 Bd 8N1
real bit_clk = real'(MSX::CLK_CORE_HZ) / 31250.0;
byte unsigned got[$];
logic dec_on = 1;
initial forever begin
    logic [7:0] b;
    @(negedge tx);
    if (!dec_on) continue;
    #(bit_clk);
    if (tx !== 1'b0) begin errors++; $display("FAIL start bit"); continue; end
    for (int i = 0; i < 8; i++) begin #(2.0 * bit_clk); b[i] = tx; end
    #(2.0 * bit_clk);
    if (tx !== 1'b1) begin errors++; $display("FAIL stop bit of %02h", b); end
    got.push_back(b);
end

initial begin
    #20_000_000;
    $display("FAILED ym2148_tb: timeout (%0d errors before)", errors);
    $finish;
end

initial begin
    logic [7:0] v;
    byte unsigned sent[$];
    int t0;
    io[0] = '{mask: 8'h00, port: 8'h00, param: 8'h01, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b1};
    io[1] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    io[2] = io[1];
    repeat (5) @(negedge clk); reset = 0;
    check("idle line", tx, 1);

    wr_reg(6, 8'h01);                                   // TXEN
    rd_reg(6, v); check("TXRDY after TXEN", v[0], 1);
    wr_reg(5, 8'h96); rd_reg(6, v); check("TXRDY kept for the first byte", v[0], 1);
    wr_reg(5, 8'h0F); rd_reg(6, v); check("TXRDY clear with a byte waiting", v[0], 0);
    sent = {8'h96, 8'h0F};
    // bit time: line low for the start bit
    @(negedge tx); t0 = $time; @(posedge tx);         // second byte: start + bits 0-3 low? 0F -> start only
    check("start bit about 687 clk", ($time - t0 + 1) / 2 >= 680 && ($time - t0 + 1) / 2 <= 695, 1);
    do rd_reg(6, v); while (!v[0]);

    wr_reg(6, 8'h03);                                   // TXEN, TXIE (already enabled: no IRQ yet)
    w_rand = 1;
    for (int i = 0; i < 40; i++) begin
        logic [7:0] x = 8'($urandom);
        do rd_reg(6, v); while (!v[0]);
        wr_reg(5, x); sent.push_back(x);
    end
    w_rand = 0;
    repeat (int'(bit_clk) * 25) @(posedge clk);
    check("bytes sent", got.size(), sent.size());
    foreach (sent[i]) if (i < got.size() && got[i] !== sent[i]) begin
        errors++; if (errors < 10) $display("FAIL byte %0d: %02h, expected %02h", i, got[i], sent[i]);
    end

    // TxRDY IRQ when the waiting byte starts
    wr_reg(5, 8'h55); wr_reg(5, 8'hAA);
    check("IRQ off while a byte waits", irq, 0);
    t0 = 0; while (!irq && t0 < int'(bit_clk) * 12) begin @(posedge clk); t0++; end
    check("TxRDY IRQ when it starts", irq, 1);
    repeat (int'(bit_clk) * 12) @(posedge clk);

    // transmitter off aborts
    dec_on = 0;
    wr_reg(5, 8'h00); repeat (int'(bit_clk) * 3) @(posedge clk);
    check("sending zeros", tx, 0);
    wr_reg(6, 8'h00); check("transmitter off: line high", tx, 1);
    rd_reg(6, v); check("TXRDY off", v[0], 0);

    if (errors == 0) $display("PASS ym2148_tb");
    else             $display("FAILED ym2148_tb: %0d errors", errors);
    $finish;
end

endmodule
