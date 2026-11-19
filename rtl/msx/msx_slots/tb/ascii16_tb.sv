// mapper_ascii16 (ASCII16, R-Type) against openMSX RomAscii16kB / RomRType:
// - a bank past the ROM end wraps (RomBlocks::setRom), also for ROMs of 4 MB and more;
// - R-Type: page 1 fixed at block 17h, page 2 switched by a write anywhere in 4000-7FFF
//   (value & (bit 4 ? 17h : 1Fh)), both through setRom.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ascii16.sh [alt_ascii16.sv]
module ascii16_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_ascii16 dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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

// 16 KB block b at a
task automatic expect_rom(input string what, input logic [15:0] a, input int b);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    if (out.ram_cs !== 1'b1 || out.addr !== {5'b0, 8'(b), a[13:0]}) begin
        errors++; $display("FAIL %s: read %04h -> ram_cs %b addr %07h, expected block %0d", what, a, out.ram_cs, out.addr, b);
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
    // ---- ASCII16
    setup(MAPPER_ASCII16, 128);                          // 8 blocks
    write(16'h6000, 8'h0A);
    expect_rom("128 KB bank 0Ah -> 2", 16'h4000, 2);
    setup(MAPPER_ASCII16, 4096);                         // 256 blocks
    write(16'h6000, 8'h05);
    expect_rom("4 MB bank 5", 16'h4000, 5);
    write(16'h7000, 8'hFE);
    expect_rom("4 MB bank FEh", 16'h8000, 254);

    // ---- R-Type 384 KB (24 blocks)
    setup(MAPPER_RTYPE, 384);
    expect_rom("R-Type page 1 = 17h", 16'h4000, 23);
    expect_rom("R-Type page 2 reset 0", 16'h8000, 0);
    write(16'h4000, 8'h03);
    expect_rom("R-Type write 4000 switches page 2", 16'h8000, 3);
    write(16'h6123, 8'h15);
    expect_rom("R-Type 15h & 17h", 16'h8000, 21);
    write(16'h7FFF, 8'h0E);
    expect_rom("R-Type 0Eh & 1Fh", 16'hA000, 14);
    expect_rom("R-Type page 1 still 17h", 16'h7FFF, 23);
    // ---- R-Type 128 KB: fixed block and banks wrap
    setup(MAPPER_RTYPE, 128);
    expect_rom("R-Type 128 KB page 1 17h -> 7", 16'h4000, 7);
    write(16'h5000, 8'h0C);
    expect_rom("R-Type 128 KB 0Ch -> 4", 16'h8000, 4);

    if (errors == 0) $display("PASS ascii16_tb");
    else             $display("FAILED ascii16_tb: %0d errors", errors);
    $finish;
end

endmodule
