// mapper_halnote: MSX-JE firmware of the Sony HB-F1XDJ / HB-F1XV (openMSX RomHalnote).
// 8 KB banks in 4000-BFFF (4FFF, 6FFF, 8FFF, AFFF), bit 7 of 4FFF = SRAM in 0000-3FFF, bit 7 of
// 6FFF = sub-mapper in 7000-7FFF (2 KB pages 77FF, 7FFF from the upper 512 KB).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_halnote.sh
module halnote_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_halnote dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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

// write cycle held open, for checking the outputs during it
task automatic write_open(input logic [15:0] a);
    @(negedge clk); rd = 0; addr = a; data = 8'h55; mreq = 1; wr = 1; #0;
endtask

task automatic idle();
    @(negedge clk); rd = 0; wr = 0; mreq = 0;
endtask

function automatic bit rom(input logic [26:0] a);
    return out.ram_cs && !out.sram_cs && out.rnw && out.addr == a;
endfunction

function automatic bit sram(input logic [26:0] a, input bit w);
    return out.sram_cs && !out.ram_cs && out.rnw == !w && out.addr == a;
endfunction

function automatic bit none();
    return !out.ram_cs && !out.sram_cs && !out.main_cs && out.rnw && out.addr == '1 && out.data == 8'hFF;
endfunction

task automatic reset_dut();
    @(negedge clk); rd = 0; wr = 0; mreq = 0; rst = 1;
    repeat (2) @(negedge clk); rst = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ       = MAPPER_HALNOTE;
    block_info.rom_size  = 25'h100000;                  // 1 MB
    block_info.sram_size = 16'd16;                      // 16 KB
    repeat (2) @(negedge clk); rst = 0;

    // reset: ROM block 0 in 4000-BFFF, 0000-3FFF and C000-FFFF unmapped
    read(16'h4123); check("reset: 4000 block 0", rom(27'h0000123));
    read(16'h6123); check("reset: 6000 block 0", rom(27'h0000123));
    read(16'h7FFF); check("reset: 7FFF block 0", rom(27'h0001FFF));
    read(16'h8123); check("reset: 8000 block 0", rom(27'h0000123));
    read(16'hBFFF); check("reset: BFFF block 0", rom(27'h0001FFF));
    read(16'h0123); check("reset: page 0 unmapped", none());
    read(16'hC123); check("reset: page 3 unmapped", none());

    // main banks
    write(16'h4FFF, 8'h05);
    write(16'h6FFF, 8'h7F);
    write(16'h8FFF, 8'h03);
    write(16'hAFFF, 8'h10);
    read(16'h4123); check("4FFF: block 5", rom(27'h000A123));
    read(16'h6123); check("6FFF: block 7Fh", rom(27'h00FE123));
    read(16'h7123); check("6FFF: 7000 without sub-mapper", rom(27'h00FF123));
    read(16'h8123); check("8FFF: block 3", rom(27'h0006123));
    read(16'hA123); check("AFFF: block 10h", rom(27'h0020123));
    write(16'h8FFF, 8'h83);                             // bit 7 of 8FFF / AFFF: block & 7Fh
    read(16'h8000); check("8FFF 83h: block 3", rom(27'h0006000));
    write(16'hAFFF, 8'hFF);
    read(16'hA000); check("AFFF FFh: block 7Fh", rom(27'h00FE000));

    // not registers
    write(16'h4FFE, 8'h01);
    write(16'h5FFF, 8'h01);
    write(16'h4000, 8'h01);
    write(16'h0FFF, 8'h01);
    write(16'hCFFF, 8'h01);
    write(16'hEFFF, 8'h01);
    write(16'h7FFF, 8'h01);                             // sub-bank 1, not the main bank 1
    read(16'h4000); check("bank 0 kept: 4FFE 5FFF 4000 0FFF CFFF EFFF", rom(27'h000A000));
    read(16'h6000); check("bank 1 kept: 7FFF", rom(27'h00FE000));
    write_open(16'h4123); check("ROM write: no access", none());
    write_open(16'h0123); check("page 0 write without SRAM: no access", none());
    idle();

    // SRAM: bit 7 of 4FFF
    write(16'h4FFF, 8'h82);
    read(16'h4123); check("4FFF 82h: block 2", rom(27'h0004123));
    read(16'h0000); check("SRAM read 0000", sram(27'h0000000, 0));
    read(16'h3FFF); check("SRAM read 3FFF", sram(27'h0003FFF, 0));
    write_open(16'h1234); check("SRAM write 1234", sram(27'h0001234, 1));
    idle();
    @(negedge clk); addr = 16'h1234; mreq = 1; #0;
    check("SRAM: MREQ alone selects nothing", none());
    idle();
    read(16'hC000); check("SRAM on: page 3 unmapped", none());
    write(16'h4FFF, 8'h02);
    read(16'h0123); check("4FFF 02h: SRAM off", none());
    read(16'h4123); check("4FFF 02h: block 2", rom(27'h0004123));

    // block without SRAM in the pack: page 0 stays unmapped
    block_info.sram_size = 16'd0;
    write(16'h4FFF, 8'h80);
    read(16'h0123); check("no SRAM in the pack: page 0 unmapped", none());
    block_info.sram_size = 16'd16;
    read(16'h0123); check("SRAM in the pack again", sram(27'h0000123, 0));
    write(16'h4FFF, 8'h00);

    // sub-mapper: 2 KB pages from 80000h, bit 7 of 6FFF
    write(16'h77FF, 8'h03);
    write(16'h7FFF, 8'h81);
    write(16'h6FFF, 8'h05);
    read(16'h7123); check("sub-mapper off: 7000 = bank 1", rom(27'h000B123));
    write(16'h6FFF, 8'h85);
    read(16'h6123); check("6FFF 85h: 6000 block 5", rom(27'h000A123));
    read(16'h6FFF); check("6FFF 85h: 6FFF block 5", rom(27'h000AFFF));
    read(16'h7123); check("sub-bank 0 = 3", rom(27'h0081923));
    read(16'h77FF); check("sub-bank 0 end", rom(27'h0081FFF));
    read(16'h7923); check("sub-bank 1 = 81h", rom(27'h00C0923));
    read(16'h7FFF); check("sub-bank 1 end", rom(27'h00C0FFF));
    write(16'h77FF, 8'hFF);
    read(16'h7000); check("sub-bank 0 = FFh", rom(27'h00FF800));
    read(16'h8123); check("sub-mapper: 8000 unchanged", rom(27'h0006123));
    write(16'h6FFF, 8'h05);
    read(16'h7123); check("sub-mapper off again", rom(27'h000B123));

    // reset clears everything
    write(16'h4FFF, 8'h81);
    write(16'h6FFF, 8'h81);
    reset_dut();
    read(16'h0123); check("reset: SRAM off", none());
    read(16'h7123); check("reset: sub-mapper off, block 0", rom(27'h0001123));
    read(16'hA123); check("reset: A000 block 0", rom(27'h0000123));

    block_info.typ = MAPPER_MSXDOS2;
    read(16'h4000); check("other mapper type: idle", none());
    idle();

    if (errors == 0) $display("PASS halnote_tb");
    else             $display("FAILED halnote_tb: %0d errors", errors);
    $finish;
end

endmodule
