// uart_rx regression test (lookup-table version, speeds 115200 and MIDI 31250).
// Run: wsl.exe -- bash rtl/peripheral/UART/tb/run.sh
module uart_rx_tb;

localparam int SYSCLK = 21477270;
localparam int SETTLE = 8;             // cycles for baudrate_q to follow uart_speed in idle

logic        clk = 0, reset = 1, rx = 1;
logic [31:0] uart_speed = 32'd115200;
logic        data_rx, framing_err;
logic  [7:0] data;

always #1 clk = ~clk;

uart_rx #(.sysCLK(SYSCLK)) dut (.*);

int          errors   = 0;
int          rx_count = 0;
logic  [7:0] rx_last;
logic        fe_last;

always @(posedge clk) if (data_rx) begin
    rx_count++;
    rx_last = data;
    fe_last = framing_err;
end

// Bit sampling period = spacing of clk_rx pulses inside one frame
int t = 0, t_last = 0, per_n = 0, per_sum = 0;
always @(posedge clk) begin
    t++;
    if (dut.clk_rx) begin
        if (t_last != 0) begin per_sum += t - t_last; per_n++; end
        t_last = t;
    end
end

task automatic wait_cycles(input int n);
    repeat (n) @(posedge clk);
endtask

task automatic send_frame(input logic [7:0] b, input int bit_cycles, input logic stop);
    rx = 0; wait_cycles(bit_cycles);
    for (int i = 0; i < 8; i++) begin
        rx = b[i]; wait_cycles(bit_cycles);
    end
    rx = stop; wait_cycles(bit_cycles);
    rx = 1;
endtask

function automatic int bit_len(input int spd);
    return SYSCLK / spd;               // same rounding as original sysCLK / uart_speed
endfunction

task automatic expect_rx(input string tag, input int cnt0, input logic [7:0] b, input logic fe);
    if (rx_count != cnt0 + 1 || rx_last !== b || fe_last !== fe) begin
        errors++;
        $display("FAIL %s: sent=%02h got=%02h fe=%b count=%0d", tag, b, rx_last, fe_last, rx_count - cnt0);
    end
endtask

task automatic check_rx(input int spd, input logic [7:0] b);
    int cnt0;
    uart_speed = spd;
    wait_cycles(SETTLE);
    cnt0 = rx_count;
    send_frame(b, bit_len(spd), 1'b1);
    wait_cycles(bit_len(spd));
    expect_rx($sformatf("rx speed=%0d", spd), cnt0, b, 1'b0);
endtask

task automatic check_period(input int spd);
    uart_speed = spd;
    wait_cycles(SETTLE);
    t_last = 0; per_n = 0; per_sum = 0;
    send_frame(8'h00, bit_len(spd), 1'b1);
    wait_cycles(bit_len(spd));
    if (per_n == 0 || per_sum != per_n * bit_len(spd)) begin
        errors++;
        $display("FAIL period speed=%0d got=%0d/%0d exp=%0d", spd, per_sum, per_n, bit_len(spd));
    end
endtask

task automatic check_baud(input logic [31:0] spd, input int exp_spd);
    uart_speed = spd;
    wait_cycles(SETTLE);
    if (dut.baudrate_q !== 14'(bit_len(exp_spd))) begin
        errors++;
        $display("FAIL baudrate speed=%0d got=%0d exp=%0d", spd, dut.baudrate_q, bit_len(exp_spd));
    end
endtask

logic [7:0] patterns[6] = '{8'h55, 8'hA3, 8'h00, 8'hFF, 8'h01, 8'h80};

initial begin
    int cnt0;

    wait_cycles(10);
    reset = 0;
    wait_cycles(10);

    // Exact bit period (equal to original sysCLK / uart_speed)
    check_period(115200);
    check_period(31250);

    // Lookup values; unsupported speeds fall back to 115200
    check_baud(32'd115200, 115200);
    check_baud(32'd31250,  31250);
    check_baud(32'd9600,   115200);
    check_baud(32'd0,      115200);

    // Byte reception
    foreach (patterns[i]) begin
        check_rx(115200, patterns[i]);
        check_rx(31250,  patterns[i]);
    end

    // Back-to-back frames without idle gap
    uart_speed = 115200;
    wait_cycles(SETTLE);
    cnt0 = rx_count;
    send_frame(8'h12, bit_len(115200), 1'b1);
    send_frame(8'h34, bit_len(115200), 1'b1);
    send_frame(8'h56, bit_len(115200), 1'b1);
    wait_cycles(bit_len(115200));
    if (rx_count != cnt0 + 3 || rx_last !== 8'h56) begin
        errors++;
        $display("FAIL back-to-back: count=%0d last=%02h", rx_count - cnt0, rx_last);
    end

    // Framing error: stop bit low
    uart_speed = 31250;
    wait_cycles(SETTLE);
    cnt0 = rx_count;
    send_frame(8'hC3, bit_len(31250), 1'b0);
    wait_cycles(2 * bit_len(31250));
    expect_rx("framing", cnt0, 8'hC3, 1'b1);

    // Speed change in the middle of a frame applies only after the frame
    uart_speed = 115200;
    wait_cycles(SETTLE);
    cnt0 = rx_count;
    fork
        send_frame(8'h69, bit_len(115200), 1'b1);
        // inline wait: Verilator mishandles the same task running in both fork branches
        begin repeat (3 * bit_len(115200)) @(posedge clk); uart_speed = 31250; end
    join
    wait_cycles(bit_len(115200));
    expect_rx("speed change mid-frame", cnt0, 8'h69, 1'b0);
    check_rx(31250, 8'h96);

    if (errors == 0) $display("PASS uart_rx_tb");
    else             $display("FAILED uart_rx_tb: %0d errors", errors);
    $finish;
end

endmodule
