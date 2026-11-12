// mapper_zemina90 against openMSX RomZemina90in1 (port 77h value, page = 2 x (value & 3Fh)):
// 00h/40h: page, page+1 twice; 80h: (page & ~2)+0/+1 at 4000, (page | 2)+0/+1 at 8000;
// C0h: page, page+1, page+1, page; every block through RomBlocks::setRom (wrap).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_zemina90.sh [alt_zemina90.sv]
module zemina90_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;
logic [7:0]       port77 = '0;

mapper_zemina90 dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out), .data_to_mapper(port77));

logic [15:0] addr = '0;
logic        mreq = 0, rd = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = 8'h00;
assign cpu_bus.mreq = mreq;  assign cpu_bus.rd = rd;  assign cpu_bus.wr = 1'b0;
assign cpu_bus.req  = 1'b0;  assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;

int errors = 0;

task automatic expect_block(input string what, input logic [15:0] a, input int b);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    if (b < 0 ? out.ram_cs !== 1'b0 : (out.ram_cs !== 1'b1 || out.addr !== {6'b0, 8'(b), a[12:0]})) begin
        errors++; $display("FAIL %s: port %02h read %04h -> ram_cs %b addr %07h, expected %s", what, port77, a,
                           out.ram_cs, out.addr, b < 0 ? "FF" : $sformatf("block %0d", b));
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_ZEMINA_90;
    block_info.rom_size = 25'h100000;                    // 1 MB, 128 blocks
    repeat (3) @(negedge clk); rst = 0;

    port77 = 8'h85;                                      // 32 KB mode, value 5: page 10
    expect_block("80h 4000 = (10 & ~2)",     16'h4000, 8);
    expect_block("80h 6000 = (10 & ~2) + 1", 16'h6000, 9);
    expect_block("80h 8000 = (10 | 2)",      16'h8000, 10);
    expect_block("80h A000 = (10 | 2) + 1",  16'hA000, 11);
    port77 = 8'hC3;                                      // Namco mode
    expect_block("C0h 8000 = page + 1", 16'h8000, 7);
    expect_block("C0h A000 = page",     16'hA000, 6);
    expect_block("page 3 unmapped", 16'hC000, -1);

    block_info.rom_size = 25'h80000;                     // 512 KB, 64 blocks: wrap
    port77 = 8'h20;                                      // page 64 -> 0
    expect_block("512 KB page 64 -> 0", 16'h4000, 0);
    expect_block("512 KB page 65 -> 1", 16'h6000, 1);

    if (errors == 0) $display("PASS zemina90_tb");
    else             $display("FAILED zemina90_tb: %0d errors", errors);
    $finish;
end

endmodule
