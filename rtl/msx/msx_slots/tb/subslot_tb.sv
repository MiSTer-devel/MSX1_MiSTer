// subslot regression test: reset init, FFFF write/read, enable gating, page selection.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run.sh
module subslot_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;

cpu_bus_if cpu_bus(clk, rst);

MSX::slot_expander_t conf[4];
logic [1:0] active_slot = 0;
logic       force_en = 0;
logic [7:0] data;
logic [1:0] active_subslot;
logic       output_rq;

subslot dut (
    .cpu_bus(cpu_bus),
    .slot_expander_conf(conf),
    .active_slot(active_slot),
    .expander_force_en(force_en),
    .data(data),
    .active_subslot(active_subslot),
    .output_rq(output_rq)
);

logic [15:0] addr = 0;
logic  [7:0] dout = 0;
logic        mreq = 0, rd = 0, wr = 0;
assign cpu_bus.addr = addr;
assign cpu_bus.data = dout;
assign cpu_bus.mreq = mreq;
assign cpu_bus.rd   = rd;
assign cpu_bus.wr   = wr;
assign cpu_bus.req  = rd | wr;

int errors = 0;
task automatic chk(input string tag, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin
        errors++;
        $display("FAIL %s: got=%02h exp=%02h", tag, got, exp);
    end
endtask

task automatic cyc(input int n = 1);
    repeat (n) @(posedge clk);
    #0.1;
endtask

task automatic write_ffff(input logic [1:0] slot, input logic [7:0] v);
    active_slot = slot; addr = 16'hFFFF; dout = v; mreq = 1; wr = 1;
    cyc();
    mreq = 0; wr = 0; addr = 0;
    cyc();
endtask

task automatic read_ffff(input logic [1:0] slot, output logic [7:0] v, output logic rq);
    active_slot = slot; addr = 16'hFFFF; mreq = 1; rd = 1;
    #0.1; v = data; rq = output_rq;
    cyc();
    mreq = 0; rd = 0; addr = 0;
    cyc();
endtask

// Expected subslot for page p of register value v
function automatic logic [1:0] page_of(input logic [7:0] v, input int p);
    return v[2*p +: 2];
endfunction

task automatic check_pages(input string tag, input logic [1:0] slot, input logic [7:0] v);
    active_slot = slot;
    for (int p = 0; p < 4; p++) begin
        addr = 16'(p) << 14;
        #0.1;
        chk($sformatf("%s slot%0d page%0d", tag, slot, p), {6'b0, active_subslot}, {6'b0, page_of(v, p)});
    end
    addr = 0;
endtask

initial begin
    logic [7:0] v;
    logic       rq;

    conf[0] = '{en: 1'b1, wo: 1'b0, init: 8'h1B};
    conf[1] = '{en: 1'b0, wo: 1'b0, init: 8'hE4};
    conf[2] = '{en: 1'b1, wo: 1'b0, init: 8'h00};
    conf[3] = '{en: 1'b1, wo: 1'b0, init: 8'hC6};

    cyc(3);
    rst = 0;
    cyc(2);

    // Reset loads init values
    check_pages("init", 0, 8'h1B);
    check_pages("init", 1, 8'hE4);
    check_pages("init", 2, 8'h00);
    check_pages("init", 3, 8'hC6);

    // Write/read on enabled expander; read returns inverted value
    write_ffff(2, 8'h93);
    check_pages("write", 2, 8'h93);
    read_ffff(2, v, rq);
    chk("read slot2", v, ~8'h93);
    chk("read slot2 rq", {7'b0, rq}, 8'd1);

    // Disabled expander ignores write, does not answer read
    write_ffff(1, 8'h00);
    check_pages("disabled write", 1, 8'hE4);
    read_ffff(1, v, rq);
    chk("disabled read", v, 8'hFF);
    chk("disabled read rq", {7'b0, rq}, 8'd0);

    // Forced enable overrides disabled expander
    force_en = 1;
    write_ffff(1, 8'h5A);
    check_pages("forced write", 1, 8'h5A);
    read_ffff(1, v, rq);
    chk("forced read", v, ~8'h5A);
    force_en = 0;

    // Other slots untouched
    check_pages("untouched", 0, 8'h1B);
    check_pages("untouched", 3, 8'hC6);

    // No write without mreq
    active_slot = 0; addr = 16'hFFFF; dout = 8'hFF; wr = 1; mreq = 0;
    cyc(); wr = 0; addr = 0; cyc();
    check_pages("no mreq", 0, 8'h1B);

    // Reset restores init with the current configuration
    conf[2].init = 8'h39;
    rst = 1; cyc(2); rst = 0; cyc();
    check_pages("re-reset", 1, 8'hE4);
    check_pages("re-reset", 2, 8'h39);

    if (errors == 0) $display("PASS subslot_tb");
    else             $display("FAILED subslot_tb: %0d errors", errors);
    $finish;
end

endmodule
