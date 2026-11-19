// mapper_zemina80 against openMSX RomZemina80in1: banks 4000-4003 -> regions 2-5, reset 0-3,
// pages 0 / 3 unmapped, every bank through RomBlocks::setRom (also for ROMs of 2 MB and more
// and for the reset banks of a small ROM).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_zemina80.sh [alt_zemina80.sv]
module zemina80_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_zemina80 dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info));

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

task automatic expect_block(input string what, input logic [15:0] a, input int b);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    if (b < 0 ? out.ram_cs !== 1'b0 : (out.ram_cs !== 1'b1 || out.addr !== {6'b0, 8'(b), a[12:0]})) begin
        errors++; $display("FAIL %s: read %04h -> ram_cs %b addr %07h, expected %s", what, a, out.ram_cs, out.addr,
                           b < 0 ? "FF" : $sformatf("block %0d", b));
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

task automatic setup(input int rom_kb);
    block_info = '0;
    block_info.typ      = MAPPER_ZEMINA_80;
    block_info.rom_size = 25'(rom_kb * 1024);
    rst = 1; repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    setup(2048);                                         // 256 blocks
    write(16'h4000, 8'h05);
    expect_block("2 MB bank 5",   16'h4123, 5);
    write(16'h4003, 8'hF0);
    expect_block("2 MB bank F0h", 16'hA123, 240);
    expect_block("page 0 unmapped", 16'h0123, -1);
    expect_block("page 3 unmapped", 16'hC123, -1);
    setup(16);                                           // 2 blocks: reset banks wrap
    expect_block("16 KB reset 8000 = 2 -> 0", 16'h8123, 0);
    expect_block("16 KB reset A000 = 3 -> 1", 16'hA123, 1);

    if (errors == 0) $display("PASS zemina80_tb");
    else             $display("FAILED zemina80_tb: %0d errors", errors);
    $finish;
end

endmodule
