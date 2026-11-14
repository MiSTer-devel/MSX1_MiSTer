// mapper_msxdos2: 16 KB bank of the MSX-DOS2 ROM in 4000-7FFF, nothing in the other pages
// (openMSX RomMSXDOS2). Bank register by mapper_param: 0 6000-6FFF, 1 7FF0, 2 7FFE.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_msxdos2.sh
module msxdos2_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_msxdos2 dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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
task automatic check(input string what, input bit c);
    if (!c) begin errors++; $display("FAIL %s: ram_cs %b sram_cs %b rnw %b addr %07h", what, out.ram_cs, out.sram_cs, out.rnw, out.addr); end
endtask

task automatic write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); rd = 0; addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; mreq = 0; wr = 0;
endtask

task automatic read(input logic [15:0] a);
    @(negedge clk); wr = 0; addr = a; mreq = 1; rd = 1; #0;
endtask

function automatic bit at(input logic [26:0] a);
    return out.ram_cs && !out.sram_cs && out.addr == a;
endfunction

task automatic reset_dut();
    @(negedge clk); rd = 0; mreq = 0; rst = 1;
    repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_MSXDOS2;
    block_info.rom_size = 25'h10000;                    // 64 KB: 4 banks
    repeat (2) @(negedge clk); rst = 0;

    // param 0: cartridge, register 6000-6FFF
    read(16'h4123); check("bank 0 after reset", at(27'h0000123));
    read(16'h7FFF); check("bank 0, end of page 1", at(27'h0003FFF));
    read(16'h0123); check("page 0 unmapped", !out.ram_cs && out.addr == '1);
    read(16'h8123); check("page 2 unmapped", !out.ram_cs && out.addr == '1);
    read(16'hC123); check("page 3 unmapped", !out.ram_cs && out.addr == '1);
    write(16'h6000, 8'h02);
    read(16'h4123); check("6000: bank 2", at(27'h0008123));
    write(16'h6FFF, 8'h03);
    read(16'h4000); check("6FFF: bank 3", at(27'h000C000));
    write(16'h7000, 8'h01);
    write(16'h5FFF, 8'h01);
    write(16'h7FF0, 8'h01);
    write(16'h7FFE, 8'h01);
    write(16'hA000, 8'h01);
    read(16'h4000); check("bank kept: 7000 5FFF 7FF0 7FFE A000", at(27'h000C000));
    write(16'h6000, 8'h05);                             // 5 >= 4 banks: 5 & 3
    read(16'h4001); check("bank 5 wraps to 1", at(27'h0004001));
    @(negedge clk); rd = 0; wr = 1; mreq = 1; addr = 16'h4000; #0;
    check("write is not a ROM access", !out.ram_cs && !out.sram_cs);
    wr = 0; mreq = 0;
    reset_dut();
    read(16'h4000); check("reset: bank 0", at(27'h0000000));

    // param 1: register 7FF0 only
    block_info.mapper_param = 2'd1;
    write(16'h6000, 8'h02);
    read(16'h4000); check("param 1: 6000 ignored", at(27'h0000000));
    write(16'h7FF0, 8'h02);
    read(16'h4000); check("param 1: 7FF0 bank 2", at(27'h0008000));
    write(16'h7FF1, 8'h03);
    write(16'h7FFE, 8'h03);
    read(16'h4000); check("param 1: 7FF1 / 7FFE ignored", at(27'h0008000));

    // param 2: register 7FFE only
    reset_dut();
    block_info.mapper_param = 2'd2;
    write(16'h6000, 8'h01);
    write(16'h7FF0, 8'h01);
    write(16'h7FFF, 8'h01);
    read(16'h4000); check("param 2: 6000 / 7FF0 / 7FFF ignored", at(27'h0000000));
    write(16'h7FFE, 8'h03);
    read(16'h4000); check("param 2: 7FFE bank 3", at(27'h000C000));

    // 48 KB, 3 banks: past the end -> block & (blocks - 1) (openMSX setRom, blockMask = 2)
    reset_dut();
    block_info.mapper_param = 2'd0;
    block_info.rom_size = 25'hC000;
    write(16'h6000, 8'h01);
    read(16'h4000); check("48 KB: bank 1", at(27'h0004000));
    write(16'h6000, 8'h03);
    read(16'h4000); check("48 KB: bank 3 -> 3 & 2 = 2", at(27'h0008000));
    write(16'h6000, 8'h05);
    read(16'h4000); check("48 KB: bank 5 -> 5 & 2 = 0", at(27'h0000000));

    block_info.typ = MAPPER_GENERIC16KB;
    read(16'h4000); check("other mapper type: idle", !out.ram_cs && out.addr == '1);

    if (errors == 0) $display("PASS msxdos2_tb");
    else             $display("FAILED msxdos2_tb: %0d errors", errors);
    $finish;
end

endmodule
