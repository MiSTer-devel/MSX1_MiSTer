// mapper_gamemaster2 against openMSX RomGameMaster2:
// - only 4000-BFFF is mapped (ROM and SRAM), pages 0 and 3 read FF;
// - a read of an SRAM bank uses that bank's half (bit 5), a write at B000-BFFF (bank A000 holds
//   the SRAM) uses the half of the last SRAM selection in any bank (sramOffset);
// - each cartridge slot has its own registers.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_gm2.sh [alt_gamemaster2.sv]
module gm2_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_gamemaster2 dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info));

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

// kind: 0 nothing, 1 ROM, 2 SRAM read, 3 SRAM write; off: expected address
task automatic expect_acc(input string what, input logic [15:0] a, input logic w, input int kind, input int off);
    logic ok;
    @(negedge clk); addr = a; data = 8'h5A; mreq = 1; rd = !w; wr = w; #1;
    case (kind)
        0: ok = !out.ram_cs && !(out.sram_cs && !out.rnw) && !(out.sram_cs && !w);
        1: ok = out.ram_cs && !out.sram_cs && out.addr == 27'(off);
        2: ok = out.sram_cs && out.rnw && !out.ram_cs && out.addr == 27'(off);
        3: ok = out.sram_cs && !out.rnw && out.addr == 27'(off);
    endcase
    if (!ok) begin
        errors++; $display("FAIL %s: %s %04h -> ram_cs %b sram_cs %b rnw %b addr %07h", what, w ? "wr" : "rd", a,
                           out.ram_cs, out.sram_cs, out.rnw, out.addr);
    end
    @(negedge clk); mreq = 0; rd = 0; wr = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_GM2;
    block_info.rom_size = 25'h20000;
    repeat (3) @(negedge clk); rst = 0;

    expect_acc("reset 6000 = bank 1", 16'h6123, 0, 1, 32'h2123);
    write(16'hA000, 8'h10);                             // bank A000: SRAM, first half
    expect_acc("SRAM read A123",       16'hA123, 0, 2, 32'h0123);
    expect_acc("page 3 C123 not SRAM", 16'hC123, 0, 0, 0);
    expect_acc("page 0 0123 not SRAM", 16'h0123, 0, 0, 0);
    expect_acc("page 3 write E123",    16'hE123, 1, 0, 0);
    write(16'h6000, 8'h30);                             // bank 6000: SRAM second half -> sramOffset 1000h
    expect_acc("SRAM read 6123 (its half)", 16'h6123, 0, 2, 32'h1123);
    expect_acc("SRAM read A123 (its half)", 16'hA123, 0, 2, 32'h0123);
    expect_acc("SRAM write B123 (sramOffset)", 16'hB123, 1, 3, 32'h1123);

    // second cartridge: own registers
    block_info.id = 1'b1;
    expect_acc("cart B 6000 = bank 1", 16'h6123, 0, 1, 32'h2123);
    expect_acc("cart B A000 = bank 3", 16'hA123, 0, 1, 32'h6123);
    block_info.id = 1'b0;

    if (errors == 0) $display("PASS gm2_tb");
    else             $display("FAILED gm2_tb: %0d errors", errors);
    $finish;
end

endmodule
