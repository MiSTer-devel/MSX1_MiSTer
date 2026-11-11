// mapper_konami_scc, SCC+ type (128 KB RAM, openMSX MSXSCCPlusCart subtype "expanded"):
// memory readable in every segment (RAM mode controls writes only), bank number masked to 4 bits,
// a write in a RAM segment goes to the RAM only (not to the SCC, not to a bank register),
// mode register at BFFE/BFFF. SCC type: SCC at 9800 after 3Fh to 9000.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_konami_scc.sh   (PREV=<git ref>: mapper from that ref)
module konami_scc_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t dev;

mapper_konami_scc dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out), .device_out(dev));

logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;
assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;
assign cpu_bus.rd   = rd;
assign cpu_bus.wr   = wr;
assign cpu_bus.req  = req;
assign cpu_bus.iorq = 1'b0;
assign cpu_bus.m1   = 1'b0;

int errors = 0;
task automatic fail(input string what);
    errors++;
    $display("FAIL %s: ram_cs %b rnw %b addr %07h scc %b", what, out.ram_cs, out.rnw, out.addr, dev.en);
endtask

// Access held on the bus (outputs checked), then released
task automatic start_write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; data = d; mreq = 1; wr = 1; req = 1; #0;
endtask
task automatic start_read(input logic [15:0] a);
    @(negedge clk); addr = a; mreq = 1; rd = 1; req = 1; #0;
endtask
task automatic idle();
    @(negedge clk); req = 0; mreq = 0; rd = 0; wr = 0;
endtask
task automatic write(input logic [15:0] a, input logic [7:0] d);
    start_write(a, d); idle();
endtask

// Memory read of block b
task automatic expect_mem(input string what, input logic [15:0] a, input int b);
    start_read(a);
    if (!(out.ram_cs && out.rnw && !dev.en && out.addr == {6'b0, 8'(b), a[12:0]})) fail(what);
    idle();
endtask
task automatic expect_scc_read(input string what, input logic [15:0] a);
    start_read(a);
    if (out.ram_cs || !dev.en) fail(what);
    idle();
endtask
task automatic expect_ram_write(input string what, input logic [15:0] a, input int b);
    start_write(a, 8'h55);
    if (!(out.ram_cs && !out.rnw && !dev.en && out.addr == {6'b0, 8'(b), a[12:0]})) fail(what);
    idle();
endtask
task automatic expect_no_ram_write(input string what, input logic [15:0] a, input logic scc);
    start_write(a, 8'h55);
    if ((out.ram_cs && !out.rnw) || dev.en !== scc) fail(what);
    idle();
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_KONAMI_SCC_PLUS;
    block_info.rom_size = 25'h20000;                   // 128 KB
    repeat (2) @(negedge clk); rst = 0;

    // reset: banks 0-3, all segments ROM mode, memory still readable (C3)
    expect_mem("SCC+ reset read 4000", 16'h4000, 0);
    expect_mem("SCC+ reset read 6123", 16'h6123, 1);
    expect_mem("SCC+ reset read 8000", 16'h8000, 2);
    expect_mem("SCC+ reset read A000", 16'hA000, 3);
    expect_no_ram_write("SCC+ ROM mode write 4100", 16'h4100, 1'b0);

    // bank numbers masked to 4 bits (16 blocks of 128 KB, higher values mirror)
    write(16'h5000, 8'h13);
    expect_mem("SCC+ bank 13h -> 3", 16'h4000, 3);
    write(16'h7000, 8'hF5);
    expect_mem("SCC+ bank F5h -> 5", 16'h6000, 5);

    // mode 01h: segment 0 RAM, readable and writable; bank register not written there
    write(16'hBFFE, 8'h01);
    expect_ram_write("SCC+ RAM segment 0 write", 16'h4100, 3);
    expect_ram_write("SCC+ RAM segment 0 write at 5000", 16'h5000, 3);
    expect_mem("SCC+ bank kept after write in RAM mode", 16'h4000, 3);
    expect_mem("SCC+ segment 1 read in ROM mode", 16'h6000, 5);

    // SCC+ sound mode (20h) with bank 4 = 80h: SCC+ registers at B800
    write(16'hBFFE, 8'h20);
    write(16'hB000, 8'h80);
    expect_scc_read("SCC+ register read B800", 16'hB800);
    expect_no_ram_write("SCC+ register write B800", 16'hB800, 1'b1);
    expect_mem("SCC+ memory under B800 area at A000", 16'hA000, 0);

    // all RAM (30h): read B800 is still the SCC, a write goes to the RAM only
    write(16'hBFFF, 8'h30);
    expect_scc_read("SCC+ all RAM read B800", 16'hB800);
    expect_ram_write("SCC+ all RAM write B800 -> RAM", 16'hB800, 0);
    expect_ram_write("SCC+ all RAM write 9000 -> RAM", 16'h9000, 2);
    expect_mem("SCC+ bank 3 kept", 16'h8000, 2);

    // SCC compatible mode in SCC+ (00h) and bank 3 = 3Fh: SCC at 9800
    write(16'hBFFE, 8'h00);
    write(16'h9000, 8'h3F);
    expect_scc_read("SCC+ compatible SCC read 9800", 16'h9800);
    expect_no_ram_write("SCC+ compatible SCC write 9800", 16'h9800, 1'b1);
    expect_mem("SCC+ bank 3Fh -> 15 at 8000", 16'h8000, 15);

    // SCC type (ROM): unchanged behaviour
    block_info.typ = MAPPER_KONAMI_SCC;
    rst = 1; repeat (2) @(negedge clk); rst = 0;
    expect_mem("SCC reset read 4000", 16'h4000, 0);
    expect_no_ram_write("SCC ROM write 4100", 16'h4100, 1'b0);
    write(16'h9000, 8'h3F);
    expect_scc_read("SCC read 9800", 16'h9800);
    expect_no_ram_write("SCC write 9800", 16'h9800, 1'b1);
    write(16'h5000, 8'h07);
    expect_mem("SCC bank 7", 16'h4000, 7);

    if (errors == 0) $display("PASS konami_scc_tb");
    else             $display("FAILED konami_scc_tb: %0d errors", errors);
    $finish;
end

endmodule
