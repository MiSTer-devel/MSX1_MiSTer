`timescale 1ns/1ps
// dev_msx_midi (8251 + 8254 at E8h-EFh): 8254 modes 0, 2, 3 (even / odd), 4, LSB-only,
// counter latch, read-back status, counter 1 clocked by OUT2; 8251 transmit decoded from
// TxD (31250 Bd from counter 0 = 8, x16) with random CPU strobe widths (1-16 clk) and
// phases, 7 bits + even parity + 2 stop, break, transmitter off; receive, overrun, error
// reset; RxRDY IRQ (RTS) and timer IRQ (DTR, OUT2 rising, cleared by EAh, DSR).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_msx_midi.sh
module msx_midi_tb;

logic clk = 0, reset = 1;
always #1 clk = ~clk;

cpu_bus_if cpu_bus(clk, reset);
MSX::io_device_t io[3];
logic       rx_strobe = 0;
logic [7:0] rx_data = 0;
wire  [7:0] data;
wire        irq, tx;

dev_msx_midi dut (.cpu_bus(cpu_bus), .io_device(io), .uart_rx(rx_strobe), .uart_rx_data(rx_data),
                  .data(data), .irq(irq), .tx(tx));

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

// CPU access: strobe held w clocks (req only in the first), then 0-3 idle clocks
int w_rand = 0;                                 // 1 = random widths and gaps
function automatic int width();
    return w_rand ? $urandom_range(16, 1) : 2;
endfunction
task automatic out(input logic [7:0] port, input logic [7:0] v);
    int w = width();
    @(negedge clk); addr = {8'h00, port}; dbo = v; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    iorq = 0; wr = 0;
    if (w_rand) repeat ($urandom_range(3)) @(negedge clk);
endtask
task automatic in(input logic [7:0] port, output logic [7:0] v);
    int w = width();
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (w - 1) @(negedge clk);
    v = data;
    iorq = 0; rd = 0;
    if (w_rand) repeat ($urandom_range(3)) @(negedge clk);
endtask

// ------------------------------------------------------------------ 8254 helpers
int ticks = 0;                                  // 4 MHz ticks so far
always @(posedge clk) if (dut.tick4m) ticks <= ticks + 1;

task automatic wait_ticks(input int n);
    int t0 = ticks;
    while (ticks - t0 < n) @(posedge clk);
endtask

// high and low time (4 MHz ticks) of one full cycle of OUTn, after skipping two edges
task automatic measure(input int n, output int hi, output int lo);
    int t;
    logic o;
    for (int k = 0; k < 2; k++) begin o = dut.out[n]; while (dut.out[n] == o) @(posedge clk); end
    while (dut.out[n] != 1'b1) @(posedge clk);
    t = ticks;
    while (dut.out[n] == 1'b1) @(posedge clk);
    hi = ticks - t; t = ticks;
    while (dut.out[n] == 1'b0) @(posedge clk);
    lo = ticks - t;
endtask

// ------------------------------------------------------------------ TxD decoder
real  bit_clk = real'(MSX::CLK_CORE_HZ) / 31250.0;
int   d_bits = 8, d_par = 0, d_even = 0, d_stop = 1;
byte unsigned got[$];
logic dec_on = 1;
initial begin
    forever begin
        logic [7:0] b;
        logic       p;
        @(negedge tx);
        if (!dec_on) continue;
        #(bit_clk);                             // middle of the start bit (2 time units per clk)
        if (tx !== 1'b0) begin errors++; $display("FAIL start bit not low"); continue; end
        b = '0;
        for (int i = 0; i < d_bits; i++) begin #(2.0 * bit_clk); b[i] = tx; end
        if (d_par) begin
            #(2.0 * bit_clk); p = tx;
            if (p !== (^b ^ !d_even)) begin errors++; $display("FAIL parity of %02h", b); end
        end
        for (int i = 0; i < d_stop; i++) begin
            #(2.0 * bit_clk);
            if (tx !== 1'b1) begin errors++; $display("FAIL stop bit %0d of %02h low", i, b); end
        end
        got.push_back(b);
    end
end

// ------------------------------------------------------------------ test
initial begin                                   // a stuck test is a failure
    #40_000_000;
    $display("FAILED msx_midi_tb: timeout (%0d errors before)", errors);
    $finish;
end

initial begin
    logic [7:0] v, lsb, msb;
    int hi, lo, a, b, t0;
    byte unsigned sent[$];
    io[0] = '{mask: 8'hF8, port: 8'hE8, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b1};
    io[1] = '{mask: 8'hF8, port: 8'hE8, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    io[2] = io[1];
    repeat (5) @(negedge clk); reset = 0;

    // ---------------- 8254
    out(8'hEF, 8'h36); out(8'hEC, 8'd8); out(8'hEC, 8'd0);            // counter 0, mode 3, 8
    measure(0, hi, lo); check("mode 3 count 8 high", hi, 4); check("mode 3 count 8 low", lo, 4);
    out(8'hEF, 8'h36); out(8'hEC, 8'd5); out(8'hEC, 8'd0);
    measure(0, hi, lo); check("mode 3 count 5 high", hi, 3); check("mode 3 count 5 low", lo, 2);
    out(8'hEF, 8'h16); out(8'hEC, 8'd10);                             // LSB only
    measure(0, hi, lo); check("LSB-only mode 3 count 10 high", hi, 5); check("low", lo, 5);
    out(8'hEF, 8'hB4); out(8'hEE, 8'd5); out(8'hEE, 8'd0);            // counter 2, mode 2, 5
    measure(2, hi, lo); check("mode 2 count 5 high", hi, 4); check("mode 2 count 5 low", lo, 1);

    out(8'hEF, 8'hB0);                                                // mode 0: OUT low at once
    check("mode 0 OUT after control word", dut.out[2], 0);
    out(8'hEE, 8'd10); out(8'hEE, 8'd0); t0 = ticks;
    while (!dut.out[2]) @(posedge clk);
    check("mode 0 count 10: OUT high after N+1 ticks", ticks - t0, 11);

    out(8'hEF, 8'hB8); out(8'hEE, 8'd6); out(8'hEE, 8'd0); t0 = ticks;  // mode 4
    while (dut.out[2]) @(posedge clk);
    check("mode 4 count 6: strobe after N+1 ticks", ticks - t0, 7);
    t0 = ticks; while (!dut.out[2]) @(posedge clk);
    check("mode 4 strobe length", ticks - t0, 1);

    // read-back status: null count until the count is loaded
    out(8'hEF, 8'hB4); out(8'hEF, 8'hE8); in(8'hEE, v);
    check("status after control word (null count)", v & 8'h7F, 8'h74);
    out(8'hEE, 8'hE8); out(8'hEE, 8'h03); wait_ticks(2);              // 1000
    out(8'hEF, 8'hE8); in(8'hEE, v);
    check("status after load", v & 8'h7F, 8'h34);

    // latch with long read strobes: both bytes from the latch, later live value lower
    w_rand = 1;
    out(8'hEF, 8'h80);
    wait_ticks(50);
    in(8'hEE, lsb); in(8'hEE, msb); a = {msb, lsb};
    out(8'hEF, 8'h80); in(8'hEE, lsb); in(8'hEE, msb); b = {msb, lsb};
    w_rand = 0;
    if (a < 1 || a > 1000 || b < 1 || b > 1000 || ((a - b + 1000) % 1000) < 50 || ((a - b + 1000) % 1000) > 120) begin
        errors++; $display("FAIL latched counts %0d then %0d (expected about 50+ lower)", a, b);
    end

    // counter 1 clocked by OUT2: OUT2 period 4, counter 1 mode 2 count 3 -> period 12
    out(8'hEF, 8'hB6); out(8'hEE, 8'd4); out(8'hEE, 8'd0);
    out(8'hEF, 8'h74); out(8'hED, 8'd3); out(8'hED, 8'd0);
    measure(1, hi, lo); check("counter 1 from OUT2: period", hi + lo, 12); check("low", lo, 4);

    // ---------------- 8251 transmit, 31250 Bd
    out(8'hEF, 8'h36); out(8'hEC, 8'd8); out(8'hEC, 8'd0);            // TxC 500 kHz
    out(8'hE9, 8'h4E);                                                // x16, 8 bits, 1 stop
    out(8'hE9, 8'h05);                                                // TXEN, RXE
    in(8'hE9, v); check("status idle (TXRDY, TXEMPTY)", v & 8'h07, 8'h05);
    out(8'hE8, 8'hA5); in(8'hE9, v); check("status after one byte: TXRDY kept", v & 8'h07, 8'h01);
    out(8'hE8, 8'h3C); in(8'hE9, v); check("status after two bytes", v & 8'h07, 8'h00);
    sent = {8'hA5, 8'h3C};
    w_rand = 1;
    for (int i = 0; i < 150; i++) begin
        logic [7:0] x = 8'($urandom);
        do in(8'hE9, v); while (!v[0]);
        out(8'hE8, x); sent.push_back(x);
    end
    do in(8'hE9, v); while (!v[2]);
    w_rand = 0;
    repeat (int'(bit_clk) * 2) @(posedge clk);
    check("bytes sent", got.size(), sent.size());
    foreach (sent[i]) if (i < got.size() && got[i] !== sent[i]) begin
        errors++; if (errors < 10) $display("FAIL byte %0d: %02h, expected %02h", i, got[i], sent[i]);
    end

    // 7 bits, even parity, 2 stop bits (internal reset back to the mode byte)
    got = {}; sent = {};
    d_bits = 7; d_par = 1; d_even = 1; d_stop = 2;
    out(8'hE9, 8'h40); out(8'hE9, 8'hFA); out(8'hE9, 8'h01);
    for (int i = 0; i < 20; i++) begin
        logic [7:0] x = 8'($urandom);
        do in(8'hE9, v); while (!v[0]);
        out(8'hE8, x); sent.push_back(x & 8'h7F);
    end
    do in(8'hE9, v); while (!v[2]);
    repeat (int'(bit_clk) * 3) @(posedge clk);
    check("7E2 bytes sent", got.size(), sent.size());
    foreach (sent[i]) if (i < got.size() && got[i] !== sent[i]) begin
        errors++; $display("FAIL 7E2 byte %0d: %02h, expected %02h", i, got[i], sent[i]);
    end
    d_bits = 8; d_par = 0; d_stop = 1;

    // break, transmitter off aborts the frame
    dec_on = 0;
    out(8'hE9, 8'h40); out(8'hE9, 8'h4E); out(8'hE9, 8'h09);
    repeat (5) @(posedge clk); check("break holds TxD low", tx, 0);
    out(8'hE9, 8'h01); check("TxD high after break", tx, 1);
    out(8'hE8, 8'h00); repeat (int'(bit_clk) * 3) @(posedge clk);
    check("sending zeros: TxD low", tx, 0);
    out(8'hE9, 8'h00); check("transmitter off: TxD high", tx, 1);
    in(8'hE9, v); check("transmitter off: TXRDY, TXEMPTY", v & 8'h05, 8'h05);
    repeat (int'(bit_clk) * 12) @(posedge clk);
    dec_on = 1;

    // ---------------- 8251 receive, RxRDY IRQ
    out(8'hE9, 8'h24);                                                // RXE, RTS
    @(negedge clk); rx_data = 8'h5A; rx_strobe = 1; @(negedge clk); rx_strobe = 0;
    in(8'hE9, v); check("RXRDY", v[1], 1); check("RxRDY IRQ with RTS", irq, 1);
    w_rand = 1; in(8'hE8, v); w_rand = 0;
    check("received byte", v, 8'h5A);
    in(8'hE9, v); check("RXRDY cleared by the read", v[1], 0); check("IRQ cleared", irq, 0);
    @(negedge clk); rx_data = 8'h11; rx_strobe = 1; @(negedge clk); rx_strobe = 0;
    @(negedge clk); rx_data = 8'h22; rx_strobe = 1; @(negedge clk); rx_strobe = 0;
    in(8'hE9, v); check("overrun", v[4], 1);
    in(8'hE8, v); check("overrun keeps the first byte", v, 8'h11);
    out(8'hE9, 8'h34); in(8'hE9, v); check("error reset", v[4], 0);
    out(8'hE9, 8'h04);                                                // RTS off
    @(negedge clk); rx_data = 8'h33; rx_strobe = 1; @(negedge clk); rx_strobe = 0;
    in(8'hE9, v); check("RXRDY without RTS", v[1], 1); check("no IRQ without RTS", irq, 0);
    in(8'hE8, v);
    out(8'hE9, 8'h00);
    @(negedge clk); rx_data = 8'h44; rx_strobe = 1; @(negedge clk); rx_strobe = 0;
    in(8'hE9, v); check("receiver off: nothing", v[1], 0);

    // ---------------- timer IRQ
    out(8'hEF, 8'hB4); out(8'hEE, 8'd40); out(8'hEE, 8'd0);           // OUT2 rises every 40
    wait_ticks(100); check("timer IRQ off without DTR", irq, 0);
    in(8'hE9, v); check("DSR 0", v[7], 0);
    out(8'hE9, 8'h02);                                                // DTR
    t0 = ticks; while (!irq && ticks - t0 < 50) @(posedge clk);
    check("timer IRQ with DTR", irq, 1);
    in(8'hE9, v); check("DSR = timer IRQ", v[7], 1);
    out(8'hEA, 8'h00); check("EAh clears the timer IRQ", irq, 0);
    t0 = ticks; while (!irq && ticks - t0 < 50) @(posedge clk);
    check("timer IRQ again", irq, 1);
    out(8'hE9, 8'h00); check("DTR off masks it", irq, 0);
    in(8'hE9, v); check("DSR 0 with DTR off", v[7], 0);

    // other ports read FFh
    in(8'hEA, v); check("EAh", v, 8'hFF);
    in(8'hEB, v); check("EBh", v, 8'hFF);
    in(8'hEF, v); check("EFh", v, 8'hFF);
    in(8'hE7, v); check("E7h not decoded", v, 8'hFF);

    if (errors == 0) $display("PASS msx_midi_tb");
    else             $display("FAILED msx_midi_tb: %0d errors", errors);
    $finish;
end

endmodule
