// mapper_panasonic against openMSX RomPanasonic: reset banks = ROM 0, low bits written at
// 6000-7FEF with regions 5 and 6 swapped, bit 8 at 7FF8, control at 7FF9, read back by control
// bits 2 / 4 / 3, SRAM banks 80h.., SRAM writes from any region, ROM block masking, RAM banks
// (from 180h) in the main RAM through main_cs, ROM without a main RAM.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_panasonic.sh   (PREV=<git ref>: mapper from that ref)
module panasonic_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_panasonic dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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
    $display("FAIL %s: ram_cs %b sram_cs %b main_cs %b rnw %b addr %07h data %02h", what, out.ram_cs, out.sram_cs, out.main_cs, out.rnw, out.addr, out.data);
endtask

task automatic write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; mreq = 0; wr = 0;
endtask
task automatic read(input logic [15:0] a);
    @(negedge clk); wr = 0; addr = a; mreq = 1; rd = 1; #0;
endtask
task automatic idle();
    @(negedge clk); mreq = 0; rd = 0; wr = 0;
endtask

// ROM read of block b at offset o
task automatic expect_rom(input string what, input logic [15:0] a, input int b);
    read(a);
    if (!(out.ram_cs && !out.sram_cs && out.addr == {5'b0, 9'(b), a[12:0]})) fail(what);
    idle();
endtask

initial begin
    block_info = '0;
    block_info.typ       = MAPPER_PANASONIC;
    block_info.rom_size  = 25'h200000;                 // FS-A1ST: 256 blocks of 8 KB
    block_info.sram_size = 16'd16;                     // 16 KB: SRAM banks 80h, 81h
    repeat (2) @(negedge clk); rst = 0;

    // reset: every region ROM block 0
    expect_rom("reset region 0", 16'h0123, 0);
    expect_rom("reset region 7", 16'hE456, 0);

    // low bits: 6000 -> region 0, 6400 -> 1, ..., 7400 -> 6, 7800 -> 5, 7C00 -> 7
    write(16'h6000, 8'h10); write(16'h6400, 8'h11); write(16'h6800, 8'h12); write(16'h6C00, 8'h13);
    write(16'h7000, 8'h14); write(16'h7400, 8'h16); write(16'h7800, 8'h15); write(16'h7C00, 8'h17);
    for (int r = 0; r < 8; r++) expect_rom($sformatf("region %0d", r), 16'(r * 16'h2000 + 16'h0010), 8'h10 + r);
    write(16'h63FF, 8'h28); expect_rom("6000-63FF is region 0", 16'h0000, 8'h28);
    write(16'h7FEF, 8'h27); expect_rom("7C00-7FEF is region 7", 16'hE000, 8'h27);

    // read back: off by default, control bit 2 / 4 / 3
    read(16'h7FF5); if (out.data !== 8'hFF || !out.ram_cs) fail("7FF5 is ROM with control 0"); idle();
    write(16'h7FF9, 8'h1C);
    read(16'h7FF5); if (out.data !== 8'h15 || out.ram_cs) fail("7FF5 reads bank 5 (A000-BFFF)"); idle();
    read(16'h7FF6); if (out.data !== 8'h16 || out.ram_cs) fail("7FF6 reads bank 6"); idle();
    read(16'h7FF9); if (out.data !== 8'h1C) fail("7FF9 reads control"); idle();
    write(16'h7FF8, 8'b1000_0001);                     // bit 8 of banks 0 and 7
    read(16'h7FF8); if (out.data !== 8'h81) fail("7FF8 reads the bit 8"); idle();
    write(16'h7FF9, 8'h00);
    read(16'h7FF8); if (out.data !== 8'hFF || out.sram_cs) fail("7FF8 not read back with control 0"); idle();

    // bank 0 = 128h (bit 8 + 28h) -> ROM block 28h (mirror of 100-17F on 256 blocks)
    expect_rom("bank 128h = ROM 28h", 16'h0000, 8'h28);
    // bank 7 = 127h -> ROM 27h
    expect_rom("bank 127h = ROM 27h", 16'hE000, 8'h27);

    // SRAM: bank 80h / 81h; read and write from the region, 82h is ROM on 16 KB
    write(16'h7FF8, 8'h00);
    write(16'h6800, 8'h80);                            // region 2 (4000-5FFF) = SRAM bank 0
    write(16'h6C00, 8'h81);                            // region 3 (6000-7FFF) = SRAM bank 1
    write(16'h7000, 8'h82);                            // region 4 = ROM 82h
    read(16'h4123); if (!(out.sram_cs && !out.ram_cs && out.addr == 27'h0000123)) fail("SRAM bank 0 read"); idle();
    read(16'h6123); if (!(out.sram_cs && out.addr == 27'h0002123)) fail("SRAM bank 1 read"); idle();
    expect_rom("bank 82h is ROM with 16 KB SRAM", 16'h8000, 8'h82);
    @(negedge clk); addr = 16'h4555; data = 8'hAA; mreq = 1; wr = 1; req = 1; #0;
    if (!(out.sram_cs && !out.rnw && out.addr == 27'h0000555)) fail("SRAM write");
    @(negedge clk); req = 0; idle();
    @(negedge clk); addr = 16'h7FF0; data = 8'hAA; mreq = 1; wr = 1; req = 1; #0;
    if (!(out.sram_cs && !out.rnw && out.addr == 27'h0003FF0)) fail("SRAM write at 7FF0 (region 3)");
    @(negedge clk); req = 0; idle();
    @(negedge clk); addr = 16'h6400; data = 8'h33; mreq = 1; wr = 1; req = 1; #0;
    if (out.sram_cs) fail("register write at 6400 is not an SRAM write");
    @(negedge clk); req = 0; idle();
    @(negedge clk); addr = 16'h8000; data = 8'h55; mreq = 1; wr = 1; req = 1; #0;
    if (out.sram_cs || out.ram_cs) fail("write to a ROM bank ignored");
    @(negedge clk); req = 0; idle();

    // RAM banks (180h..): 8 KB block (bank - 180h) of the main RAM (256 KB = 32 blocks), main_cs
    block_info.main_ram_size = 17'd32;
    write(16'h7FF8, 8'b0000_0100); write(16'h6800, 8'h80);   // region 2 = 180h
    read(16'h4123); if (!(out.main_cs && !out.ram_cs && !out.sram_cs && out.addr == 27'h0000123)) fail("RAM bank 180h read"); idle();
    write(16'h6800, 8'h9F);                                   // 19Fh = RAM block 1Fh
    read(16'h5FFF); if (!(out.main_cs && out.addr == 27'h003FFFF)) fail("RAM bank 19Fh = block 1Fh"); idle();
    write(16'h6800, 8'hA1);                                   // 1A1h = block 21h, masked to 01h
    read(16'h4000); if (!(out.main_cs && out.addr == 27'h0002000)) fail("RAM bank 1A1h masked to block 01h"); idle();
    @(negedge clk); addr = 16'h4777; data = 8'h5A; mreq = 1; wr = 1; req = 1; #0;
    if (!(out.main_cs && !out.rnw && out.addr == 27'h0002777)) fail("RAM bank write");
    @(negedge clk); req = 0; idle();
    write(16'h6C00, 8'h80); write(16'h7FF8, 8'b0000_1100);   // region 3 (6000-7FFF) = 180h
    @(negedge clk); addr = 16'h7FF0; data = 8'h77; mreq = 1; wr = 1; req = 1; #0;
    if (!(out.main_cs && !out.rnw && out.addr == 27'h0001FF0)) fail("RAM write at 7FF0 (region 3)");
    @(negedge clk); req = 0; idle();
    @(negedge clk); addr = 16'h6C00; data = 8'h80; mreq = 1; wr = 1; req = 1; #0;
    if (out.main_cs || out.sram_cs) fail("register write at 6C00 is not a RAM write");
    @(negedge clk); req = 0; idle();
    write(16'h7FF9, 8'h04);                                   // read back banks
    read(16'h7FF2); if (out.main_cs || out.data !== 8'hA1) fail("7FF2 reads bank 2 over a RAM bank"); idle();
    write(16'h7FF9, 8'h00);
    // no main RAM: banks from 180h are ROM (openMSX: getRamSize() == 0)
    block_info.main_ram_size = 17'd0;
    expect_rom("bank 1A1h without main RAM = ROM A1h", 16'h4000, 8'hA1);

    // other mapper type: idle
    block_info.typ = MAPPER_GENERIC8KB;
    read(16'h0000); if (out.ram_cs || out.sram_cs || out.addr !== '1) fail("other mapper type idle"); idle();

    if (errors == 0) $display("PASS panasonic_tb");
    else             $display("FAILED panasonic_tb: %0d errors", errors);
    $finish;
end

endmodule
