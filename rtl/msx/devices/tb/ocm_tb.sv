// dev_ocm against OCM-PLD swioports.vhd: ports 40h-4Fh (ID 212 / 008), virtual DIP-SW,
// lock mask, smart commands, warm / cold reset, IPL phase (until the first write to A8h).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_ocm.sh [alt_ocm.sv]
module ocm_tb;

logic clk = 0;
always #5 clk = ~clk;

// Core reset as in msx.sv: registered, from the hard reset and the swio request
logic hard = 1, reset = 1;
wire  swio_reset;
always_ff @(posedge clk) reset <= hard || swio_reset;

cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);
MSX::io_device_t io_device[3];
logic [7:0] dip;
wire  [7:0] data;
wire        ipl_en, mapper_limit, megaSD_enable, Slot1Mode, rst_key_lock;
wire  [1:0] Slot2Mode;

dev_ocm dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .io_device(io_device), .ff_dip_req(dip),
             .data(data), .ipl_en(ipl_en), .mapper_limit(mapper_limit), .megaSD_enable(megaSD_enable),
             .Slot1Mode(Slot1Mode), .Slot2Mode(Slot2Mode), .rst_key_lock(rst_key_lock),
             .swio_reset(swio_reset));

logic [15:0] addr = '0;
logic  [7:0] dbo = '0;
logic        iorq = 0, rd = 0, wr = 0, req = 0, ce_10hz = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.iorq = iorq;  assign cpu_bus.mreq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;
assign clock_bus.ce_10hz = ce_10hz;

int errors = 0;

task automatic io_write(input logic [7:0] port, input logic [7:0] d);
    @(negedge clk); addr = {8'h00, port}; dbo = d; iorq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); iorq = 0; wr = 0;
endtask

task automatic expect_read(input string what, input logic [7:0] port, input logic [7:0] exp);
    @(negedge clk); addr = {8'h00, port}; iorq = 1; rd = 1;
    #1;
    if (data !== exp) begin errors++; $display("FAIL %s: port %02h = %02h, expected %02h", what, port, data, exp); end
    @(negedge clk); iorq = 0; rd = 0;
endtask

task automatic check_bit(input string what, input logic got, input logic exp);
    if (got !== exp) begin errors++; $display("FAIL %s: %b, expected %b", what, got, exp); end
endtask

task automatic tick_10hz();
    @(negedge clk); ce_10hz = 1;
    @(negedge clk); ce_10hz = 0;
endtask

task automatic wait_reset_done();
    int n = 0;
    while (!reset && n < 10000) begin @(negedge clk); n++; end
    if (!reset) begin errors++; $display("FAIL no reset (swio_reset)"); return; end
    wait (!reset);
    repeat (2) @(negedge clk);
endtask

initial begin
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0, device_ref: 3'd0, enable: 1'b0};
    io_device[0].enable = 1'b1;
    // MegaSD on, mapper 4096 kB, slot 2 MegaSCC+ (Slot2Mode 10 -> bits 5:4 = 01), slot 1 SCC-I, display 11, turbo off
    dip = 8'b1_1_01_1_11_0;
    repeat (4) @(negedge clk); hard = 0;
    repeat (4) @(negedge clk);

    // ---- cold reset state
    check_bit("ipl_en after reset", ipl_en, 1'b1);
    check_bit("MegaSD from DIP", megaSD_enable, 1'b1);
    check_bit("mapper 4096 kB from DIP", mapper_limit, 1'b0);
    check_bit("reset key unlocked", rst_key_lock, 1'b0);
    tick_10hz();
    check_bit("Slot1Mode", Slot1Mode, 1'b1);
    if (Slot2Mode !== 2'b10) begin errors++; $display("FAIL Slot2Mode %b, expected 10", Slot2Mode); end

    // ---- ports, ID 212
    expect_read("port 40 before ID",  8'h40, 8'hFF);
    expect_read("ID 212 not selected", 8'h42, 8'hFF);
    io_write(8'h40, 8'hD4);
    expect_read("port 40 ID 212",     8'h40, 8'h2B);
    expect_read("virtual DIP-SW",     8'h42, dip);
    expect_read("lock mask",          8'h43, 8'h00);
    expect_read("lights mask",        8'h44, 8'h00);
    expect_read("physical DIP-SW",    8'h4C, dip);
    expect_read("PLD version",        8'h4E, 8'd38);
    expect_read("keyb/rev",           8'h4F, 8'h89);
    io_write(8'h43, 8'hFE);                       // write_n: lock turbo
    expect_read("lock mask written",  8'h43, 8'h01);
    io_write(8'h44, 8'hFD);
    expect_read("lights mask written", 8'h44, 8'h02);
    expect_read("lock mask kept",     8'h43, 8'h01);

    // ---- smart commands
    io_write(8'h41, 8'd16);                       // SCC-I slot 1 + SCC-I slot 2
    expect_read("slot modes by cmd 16", 8'h42, {dip[7:6], 3'b011, dip[2:0]});
    io_write(8'h41, 8'd57);                       // MegaSD locked
    expect_read("MegaSD lock",        8'h43, 8'h81);
    dip[7] = 1'b0;                                // OSD: MegaSD off -> ignored while locked
    repeat (4) @(negedge clk);
    expect_read("locked DIP ignored", 8'h47, 8'hCF);   // MegaSD_req, Mapper_req, tMegaSD, speed level 7
    io_write(8'h41, 8'd29);                       // MegaSD off request
    check_bit("MegaSD stays until warm reset", megaSD_enable, 1'b1);
    expect_read("RstReq_sta",         8'h48, 8'hC2);
    io_write(8'h41, 8'd253);                      // warm reset
    wait_reset_done();
    check_bit("warm: MegaSD off", megaSD_enable, 1'b0);
    check_bit("warm: ipl_en again", ipl_en, 1'b1);
    io_write(8'h40, 8'hD4);
    expect_read("warm: lock mask kept", 8'h43, 8'h81);
    expect_read("warm: slot modes kept", 8'h42, {1'b0, dip[6], 3'b011, dip[2:0]});

    // ---- IPL phase ends only with port A8h
    io_write(8'hA9, 8'h00);
    check_bit("A9 does not end IPL", ipl_en, 1'b1);
    io_write(8'hA8, 8'hF0);
    check_bit("A8 ends IPL", ipl_en, 1'b0);

    // ---- cold reset: lock mask cleared, MegaSD from DIP (now off)
    hard = 1; repeat (2) @(negedge clk); hard = 0;
    wait_reset_done();
    io_write(8'h40, 8'hD4);
    expect_read("cold: lock mask cleared", 8'h43, 8'h00);
    check_bit("cold: MegaSD from DIP", megaSD_enable, 1'b0);

    // ---- ID 008
    io_write(8'h40, 8'h08);
    expect_read("ID 008", 8'h40, 8'hF7);
    expect_read("ID 008 port 43", 8'h43, 8'h00);

    // ---- not present: ports silent, no IPL
    io_device[0].enable = 1'b0;
    hard = 1; repeat (2) @(negedge clk); hard = 0;
    wait_reset_done();
    io_write(8'h40, 8'hD4);
    expect_read("absent device", 8'h40, 8'hFF);
    check_bit("absent: no IPL", ipl_en, 1'b0);

    if (errors == 0) $display("PASS ocm_tb");
    else             $display("FAILED ocm_tb: %0d errors", errors);
    $finish;
end

endmodule
