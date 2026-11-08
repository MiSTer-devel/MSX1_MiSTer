// dev_opll: an OPLL of the machine (1chipMSX.xml, device_ref 0) must take I/O writes on 7Ch/7Dh
// while the device bus is idle; an OPLL of an FM-PAC block (device_ref != 0) only after the
// block enabled it (device_bus.en, FM-PAC 7FF6h bit 0). In turbo (enawait) back-to-back writes
// must wait while the OPLL is busy (as OCM eseopll, with YM2413 timing) and all reach the OPLL.
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_opll.sh [alt_opll.sv]
//      (NO_WAIT=1 for an opll.sv without enawait / wait_rq: the turbo test then fails)
module opll_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if   cpu_bus(clk, rst);
clock_bus_if clock_bus(clk, clk);
clock #(.sysCLK(21477270)) u_clock (.clock_bus(clock_bus));

MSX::io_device_t   io_device[3];
MSX::device_bus_t  device_bus;
MSX::sound_t       sound;

logic enawait = 0, wait_rq;
`ifdef NO_WAIT
dev_opll dut (.cpu_bus(cpu_bus), .device_bus(device_bus), .clock_bus(clock_bus.base_mp),
              .io_device(io_device), .sound(sound));
assign wait_rq = 1'b0;
`else
dev_opll dut (.cpu_bus(cpu_bus), .device_bus(device_bus), .clock_bus(clock_bus.base_mp),
              .io_device(io_device), .enawait(enawait), .wait_rq(wait_rq), .sound(sound));
`endif

logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        iorq = 0, mreq = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = data;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = mreq;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = 1'b0;  assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

localparam MSX::device_bus_t IDLE = '{device_ref: 3'd0, we: 1'b0, en: 1'b0, mode: 1'b1, param: 1'b1};

int errors = 0;

// CPU I/O write: strobe of 10 clk (10.7 MHz with the OCM I/O waits), stretched while wait_rq,
// then gap clk (600: OPLL write recovery at 3.58 MHz; small: turbo code)
int gap = 600, waited = 0;
task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; data = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    while (wait_rq) begin waited++; @(negedge clk); end
    repeat (8) @(negedge clk);
    iorq = 0; wr = 0;
    repeat (gap) @(negedge clk);
endtask

task automatic opll_reg(input logic [7:0] r, input logic [7:0] v);
    io_write(8'h7C, r);
    io_write(8'h7D, v);
endtask

// A tone on channel 0: instrument 1 (violin), volume 0 (loudest), F-num 0AB, block 4, key on
task automatic play;
    opll_reg(8'h20, 8'h08);                     // key off first: a held key gives no new attack
    repeat (20000) @(negedge clk);
    opll_reg(8'h30, 8'h10);
    opll_reg(8'h10, 8'hAB);
    opll_reg(8'h20, 8'h18);
endtask

// Peak-to-peak of the output over n clocks (an idle OPLL gives a constant value)
task automatic peak(input int n, output int p);
    int lo = 1 << 30, hi = -(1 << 30);
    repeat (n) begin
        @(posedge clk);
        if (sound < lo) lo = sound;
        if (sound > hi) hi = sound;
    end
    p = hi - lo;
endtask

task automatic restart(input logic [2:0] ref0);
    io_device[0] = '{mask: 8'hFE, port: 8'h7C, param: 8'h00, mem_ref: 3'd0, device_ref: ref0, enable: 1'b1};
    rst = 1; repeat (2000) @(negedge clk); rst = 0;
    repeat (2000) @(negedge clk);               // idle device bus after reset
endtask

initial begin
    int p, idle;
    device_bus = IDLE;
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};

    // ---- OPLL of the machine (OCM): device_ref 0
    // (a tone must swing well above the ripple of the idle output in the same window)
    restart(3'd0);
    peak(200000, idle);
    play();
    peak(200000, p);
    $display("machine OPLL: idle %0d, after key on %0d", idle, p);
    if (p < idle + 200) begin errors++; $display("FAIL machine OPLL (device_ref 0): no tone after key on"); end

    // ---- OPLL of an FM-PAC block (device_ref 2): I/O only once the block enabled it
    restart(3'd2);
    peak(200000, idle);
    device_bus = '{device_ref: 3'd2, we: 1'b0, en: 1'b0, mode: 1'b1, param: 1'b1};   // block access, 7FF6 bit 0 = 0
    @(negedge clk); device_bus = IDLE;
    play();
    peak(200000, p);
    $display("FM-PAC OPLL: idle %0d, I/O disabled %0d", idle, p);
    if (p >= idle + 200) begin errors++; $display("FAIL FM-PAC OPLL: tone while I/O is disabled"); end
    device_bus = '{device_ref: 3'd2, we: 1'b0, en: 1'b1, mode: 1'b1, param: 1'b1};   // 7FF6 bit 0 = 1
    @(negedge clk); device_bus = IDLE;
    play();
    peak(200000, p);
    $display("FM-PAC OPLL: I/O enabled %0d", p);
    if (p < idle + 200) begin errors++; $display("FAIL FM-PAC OPLL: no tone with I/O enabled"); end

    // ---- turbo: back-to-back writes (gap 4 clk) with enawait; the CPU must wait for the OPLL
    restart(3'd0);
    enawait = 1; gap = 4;
    peak(200000, idle);
    waited = 0;
    play();
    peak(200000, p);
    $display("turbo OPLL: idle %0d, after key on %0d, CPU waited %0d clk", idle, p, waited);
    if (p < idle + 200) begin errors++; $display("FAIL turbo OPLL: writes lost (no tone)"); end
    // play(): twice an address write right after a data write (516 clk busy), four times a data
    // write after an address write (84 clk), minus ~13 clk of strobe and gap each: ~1290 clk
    if (waited < 1200) begin errors++; $display("FAIL turbo OPLL: CPU waited only %0d clk", waited); end

    if (errors == 0) $display("PASS opll_tb");
    else             $display("FAILED opll_tb: %0d errors", errors);
    $finish;
end

endmodule
