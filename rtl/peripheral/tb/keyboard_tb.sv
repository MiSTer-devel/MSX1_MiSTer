// keyboard: key matrix from the hps_io key events and the Pause key state.
// Pause: hps_io sends the whole Pause sequence as one event 377h (pressed, extended, 77h); each
// event toggles `pause`, other events (077h Num Lock, 177h, a release of 377h) do not, reset
// clears it. The Pause event must not press a matrix key (table entry 177h = FFh).
// ps2_key = {toggle, pressed, extended, code}; the key table is addressed by {extended, code}.
// Run: wsl.exe -- bash rtl/peripheral/tb/run_keyboard.sh
module keyboard_tb;

logic clk = 0, reset = 1;
always #5 clk = ~clk;

logic [10:0]      ps2_key = '0;
logic  [3:0]      kb_row = '0;
wire   [7:0]      kb_data;
wire              pause;
MSX::kb_memory_t  upload = '{addr: '0, data: '0, we: 1'b0, rq: 1'b0};

keyboard dut (.clk(clk), .reset(reset), .ps2_key(ps2_key), .kb_row(kb_row), .kb_data(kb_data),
              .upload_memory(upload), .pause(pause));

int errors = 0;
task automatic expect1(input string what, input logic got, input logic exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %b, expected %b", what, got, exp); end
endtask

task automatic key(input logic [9:0] k);            // one hps_io key event: the toggle bit flips
    @(negedge clk); ps2_key = {~ps2_key[10], k}; repeat (3) @(negedge clk);
endtask

task automatic matrix_free(input string what);      // no key pressed in any row
    for (int r = 0; r < 16; r++) begin
        @(negedge clk); kb_row = 4'(r); @(negedge clk);
        if (kb_data !== 8'hFF) begin errors++; $display("FAIL %s: row %0d = %02h", what, r, kb_data); end
    end
endtask

initial begin
    // key table: all FFh (no key), 01Ch ('A') = row 2 bit 6
    @(negedge clk); upload.rq = 1;
    for (int a = 0; a < 512; a++) begin
        upload.addr = 9'(a); upload.data = a == 'h01C ? 8'h26 : 8'hFF; upload.we = 1; @(negedge clk);
    end
    upload.we = 0; upload.rq = 0;
    repeat (3) @(negedge clk); reset = 0;

    expect1("pause after reset", pause, 0);
    key(10'h277); key(10'h077); key(10'h177);       // Num Lock pressed / released, extended 77h released
    expect1("pause after other keys", pause, 0);

    key(10'h377);
    expect1("pause after the Pause event", pause, 1);
    matrix_free("matrix after the Pause event");
    @(negedge clk); ps2_key[9] = 1'b0; repeat (3) @(negedge clk);   // a release never comes, ignored
    expect1("pause unchanged by a release", pause, 1);

    key(10'h21C);                                   // 'A' pressed while paused
    @(negedge clk); kb_row = 4'd2; @(negedge clk);
    if (kb_data !== 8'hBF) begin errors++; $display("FAIL key A in row 2: %02h", kb_data); end
    key(10'h01C);
    expect1("pause unchanged by other keys", pause, 1);

    key(10'h377); key(10'h377);                     // autorepeat: every event toggles
    expect1("pause after two more Pause events", pause, 1);
    key(10'h377);
    expect1("pause after the next Pause event", pause, 0);

    key(10'h377);
    @(negedge clk); reset = 1; @(negedge clk); @(negedge clk); reset = 0;
    expect1("pause cleared by reset", pause, 0);

    if (errors == 0) $display("PASS keyboard_tb");
    else             $display("FAILED keyboard_tb: %0d errors", errors);
    $finish;
end

endmodule
