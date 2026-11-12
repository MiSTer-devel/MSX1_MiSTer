// mapper_konami against openMSX RomKonami: 4000-5FFF fixed block 0, banks at 6000 / 8000 /
// A000 (writes 6000-BFFF), 4000-7FFF mirrored in 0000-3FFF and 8000-BFFF in C000-FFFF, a bank
// past the ROM end masked with 31 (setBlockMask(31)) and FF if still past the end.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_konami.sh [alt_konami.sv]
module konami_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_konami dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info));

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

// read of a: block b, or -1 = unmapped (FF)
task automatic expect_block(input string what, input logic [15:0] a, input int b);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    if (b < 0 ? out.ram_cs !== 1'b0
              : (out.ram_cs !== 1'b1 || out.addr !== {6'b0, 8'(b), a[12:0]})) begin
        errors++;
        $display("FAIL %s: read %04h -> ram_cs %b addr %07h, expected %s", what, a, out.ram_cs, out.addr,
                 b < 0 ? "FF" : $sformatf("block %0d", b));
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_KONAMI;
    block_info.rom_size = 25'h20000;                    // 128 KB, 16 blocks
    repeat (3) @(negedge clk); rst = 0;

    expect_block("reset 4000 fixed 0", 16'h4000, 0);
    expect_block("reset 6000 = 1",     16'h6123, 1);
    expect_block("reset 8000 = 2",     16'h8000, 2);
    expect_block("reset A000 = 3",     16'hA000, 3);
    write(16'h4000, 8'h05);                             // fixed page: no switch
    expect_block("4000 stays 0",       16'h4000, 0);
    write(16'h6000, 8'h05); write(16'h8000, 8'h06); write(16'hA000, 8'h07);
    expect_block("6000 = 5", 16'h6000, 5);
    expect_block("8000 = 6", 16'h8000, 6);
    expect_block("A000 = 7", 16'hA000, 7);

    // mirrors: 0000-3FFF = 4000-7FFF, C000-FFFF = 8000-BFFF
    expect_block("mirror 0000 = 4000", 16'h0123, 0);
    expect_block("mirror 2000 = 6000", 16'h2123, 5);
    expect_block("mirror C000 = 8000", 16'hC123, 6);
    expect_block("mirror E000 = A000", 16'hE123, 7);
    write(16'h2000, 8'h09); write(16'hC000, 8'h09);     // writes only at 6000-BFFF
    expect_block("no switch from mirror writes", 16'h6000, 5);
    expect_block("no switch from mirror writes 8000", 16'h8000, 6);

    // past the end: & 31, FF if still past
    write(16'h6000, 8'h21);
    expect_block("bank 21h -> 1",  16'h6000, 1);
    write(16'h8000, 8'h12);
    expect_block("bank 12h -> FF", 16'h8000, -1);
    write(16'hA000, 8'hEF);
    expect_block("bank EFh -> 15", 16'hA000, 15);

    if (errors == 0) $display("PASS konami_tb");
    else             $display("FAILED konami_tb: %0d errors", errors);
    $finish;
end

endmodule
