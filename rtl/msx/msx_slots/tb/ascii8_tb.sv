// mapper_ascii8 against openMSX RomAscii8kB / RomAscii8_8 (ASCII8 with SRAM, KOEI, WIZARDRY):
// - a bank past the ROM end wraps (RomBlocks::setRom, blockMask = blocks - 1);
// - the SRAM enable bit maps the SRAM in any region; writable only in sramPages (0x30, KOEI
//   0x34), elsewhere read-only (setBank);
// - an SRAM smaller than 8 KB is mirrored in the 8 KB region (address & (size - 1)).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ascii8.sh [alt_ascii8.sv]
module ascii8_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_ascii8 dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info));

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

task automatic expect_rom(input string what, input logic [15:0] a, input int b);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    if (out.ram_cs !== 1'b1 || out.sram_cs !== 1'b0 || out.addr !== {6'b0, 8'(b), a[12:0]}) begin
        errors++; $display("FAIL %s: read %04h -> ram_cs %b sram_cs %b addr %07h, expected ROM block %0d",
                           what, a, out.ram_cs, out.sram_cs, out.addr, b);
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

// SRAM access at a: offset off in the SRAM, w: write allowed
task automatic expect_sram(input string what, input logic [15:0] a, input logic w, input int off, input logic exp_wr);
    @(negedge clk); addr = a; mreq = 1; rd = !w; wr = w; #1;
    if (exp_wr || !w) begin
        if (out.sram_cs !== 1'b1 || out.ram_cs !== 1'b0 || out.addr !== 27'(off) || out.rnw !== !w) begin
            errors++; $display("FAIL %s: %s %04h -> sram_cs %b ram_cs %b addr %07h rnw %b, expected SRAM %05h",
                               what, w ? "wr" : "rd", a, out.sram_cs, out.ram_cs, out.addr, out.rnw, off);
        end
    end else if (out.sram_cs && !out.rnw) begin
        errors++; $display("FAIL %s: SRAM written at %04h", what, a);
    end
    @(negedge clk); mreq = 0; rd = 0; wr = 0;
endtask

task automatic setup(input mapper_typ_t t, input int rom_kb, input int sram_kb);
    block_info = '0;
    block_info.typ       = t;
    block_info.rom_size  = 25'(rom_kb * 1024);
    block_info.sram_size = 16'(sram_kb);
    rst = 1; repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    // ---- ASCII8 without SRAM: wrap past the ROM end
    setup(MAPPER_ASCII8, 128, 0);
    expect_rom("reset 4000 = 0", 16'h4000, 0);
    write(16'h6000, 8'h10);
    expect_rom("128 KB bank 10h -> 0", 16'h4000, 0);
    write(16'h6800, 8'h13);
    expect_rom("128 KB bank 13h -> 3", 16'h6000, 3);
    setup(MAPPER_ASCII8, 384, 0);                        // 48 blocks, mask 47
    write(16'h7000, 8'h30);
    expect_rom("384 KB bank 30h -> 20h", 16'h8000, 32);
    write(16'h7800, 8'h2F);
    expect_rom("384 KB bank 2Fh", 16'hA000, 47);

    // ---- ASCII8 with 8 KB SRAM (enable bit = ROM blocks = 10h)
    setup(MAPPER_ASCII8, 128, 8);
    write(16'h7000, 8'h10);                              // region 4 (8000): SRAM, writable
    expect_sram("SRAM8 read 8000",  16'h8123, 0, 27'h0123, 1'b0);
    expect_sram("SRAM8 write 8000", 16'h8123, 1, 27'h0123, 1'b1);
    write(16'h6000, 8'h10);                              // region 2 (4000): SRAM read-only
    expect_sram("SRAM8 read 4000 (not in sramPages)",  16'h4123, 0, 27'h0123, 1'b0);
    expect_sram("SRAM8 no write 4000",                  16'h4123, 1, 27'h0123, 1'b0);
    write(16'h6000, 8'h02);
    expect_rom("SRAM8 back to ROM at 4000", 16'h4000, 2);

    // ---- ASCII8 with 2 KB SRAM: mirrored in the 8 KB region
    setup(MAPPER_ASCII8, 128, 2);
    write(16'h7800, 8'h10);                              // region 5 (A000)
    expect_sram("SRAM2 read A123",  16'hA123, 0, 27'h0123, 1'b0);
    expect_sram("SRAM2 mirror A923", 16'hA923, 0, 27'h0123, 1'b0);
    expect_sram("SRAM2 mirror BFFF", 16'hBFFF, 1, 27'h07FF, 1'b1);

    // ---- WIZARDRY: bit 7 enables 8 KB SRAM
    setup(MAPPER_WIZARDY, 128, 8);
    write(16'h7000, 8'h80);
    expect_sram("WIZARDRY SRAM 8000", 16'h8123, 1, 27'h0123, 1'b1);
    write(16'h7000, 8'h05);
    expect_rom("WIZARDRY ROM 8000", 16'h8000, 5);

    if (errors == 0) $display("PASS ascii8_tb");
    else             $display("FAILED ascii8_tb: %0d errors", errors);
    $finish;
end

endmodule
