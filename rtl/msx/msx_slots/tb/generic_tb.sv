// mapper_generic8k / mapper_generic16k against openMSX RomGeneric8kB / RomGeneric16kB: banks at
// 4000-BFFF, every value and the reset banks through RomBlocks::setRom (block < blocks ? block :
// block & (blocks - 1)), also for ROMs of 2 MB / 4 MB and more and for ROMs smaller than the window.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_generic.sh
module generic_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out8, out16;

mapper_generic8k  g8  (.cpu_bus(cpu_bus), .out(out8),  .block_info(block_info));
mapper_generic16k g16 (.cpu_bus(cpu_bus), .out(out16), .block_info(block_info));

logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;  assign cpu_bus.rd = rd;  assign cpu_bus.wr = wr;
assign cpu_bus.req  = req;   assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;

int errors = 0;

task automatic write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    @(negedge clk); mreq = 0; wr = 0;
endtask

// read of a: expected byte offset in the ROM, or -1 = unmapped (FF)
task automatic expect_off(input string what, input logic [15:0] a, input longint off);
    MSX::mapper_out_t o;
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    o = block_info.typ == MAPPER_GENERIC8KB ? out8 : out16;
    if (off < 0 ? o.ram_cs !== 1'b0 : (o.ram_cs !== 1'b1 || o.addr !== 27'(off))) begin
        errors++; $display("FAIL %s: read %04h -> ram_cs %b addr %07h, expected %s", what, a, o.ram_cs, o.addr,
                           off < 0 ? "FF" : $sformatf("%07h", off));
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

task automatic setup(input mapper_typ_t t, input int rom_kb);
    block_info = '0;
    block_info.typ      = t;
    block_info.rom_size = 25'(rom_kb * 1024);
    rst = 1; repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    // ---- Generic 8 KB
    setup(MAPPER_GENERIC8KB, 2048);                      // 256 blocks
    write(16'h4000, 8'h01);
    expect_off("8K 2 MB bank 1",   16'h4123, 64'h2123);
    write(16'hA000, 8'hFF);
    expect_off("8K 2 MB bank FFh", 16'hA123, 64'h1FE123);
    setup(MAPPER_GENERIC8KB, 16);                        // 2 blocks: reset banks 0-3 wrap
    expect_off("8K 16 KB reset 4000 = 0", 16'h4123, 64'h0123);
    expect_off("8K 16 KB reset 8000 = 2 -> 0", 16'h8123, 64'h0123);
    expect_off("8K 16 KB reset A000 = 3 -> 1", 16'hA123, 64'h2123);
    write(16'h6000, 8'h05);
    expect_off("8K 16 KB bank 5 -> 1", 16'h6123, 64'h2123);

    // ---- Generic 16 KB
    setup(MAPPER_GENERIC16KB, 4096);                     // 256 blocks
    write(16'h4000, 8'h05);
    expect_off("16K 4 MB bank 5", 16'h4123, 64'h14123);
    setup(MAPPER_GENERIC16KB, 16);                       // 1 block: reset bank 1 -> 0
    expect_off("16K 16 KB reset 8000 = 1 -> 0", 16'h8123, 64'h0123);
    setup(MAPPER_GENERIC16KB, 24);                       // 2 blocks (padded), second half beyond
    write(16'h8000, 8'h01);
    expect_off("16K 24 KB bank 1, ROM part", 16'h8123, 64'h4123);
    expect_off("16K 24 KB bank 1, padding",  16'hA123, -1);
    write(16'h8000, 8'h03);
    expect_off("16K 24 KB bank 3 -> 1", 16'h8123, 64'h4123);

    if (errors == 0) $display("PASS generic_tb");
    else             $display("FAILED generic_tb: %0d errors", errors);
    $finish;
end

endmodule
