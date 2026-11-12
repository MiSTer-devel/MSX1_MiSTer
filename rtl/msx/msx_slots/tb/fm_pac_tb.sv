// mapper_fm_pac against openMSX MSXFmPac (window 4000-7FFF, fmpac.xml):
// - ROM, SRAM and registers only in 4000-7FFF, nothing in the other pages;
// - with the SRAM on (5FFE = 4Dh, 5FFF = 69h): SRAM below 5FFE, 5FFE / 5FFF the magic, the rest
//   of 6000-7FFF reads FF;
// - 7FF6 / 7FF7 (and 5FFE / 5FFF with the SRAM on) read the register alone, no ROM byte with it
//   (the CPU data is an AND of all sources).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_fm_pac.sh [alt_fm_pac.sv]
module fm_pac_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t dev;

mapper_fm_pac dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out), .device_out(dev));

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

// kind: 0 nothing (FF), 1 ROM at off, 2 SRAM at off, 3 register value v alone
task automatic expect_rd(input string what, input logic [15:0] a, input int kind, input int off, input logic [7:0] v = 8'hFF);
    logic ok;
    @(negedge clk); addr = a; mreq = 1; rd = 1; #1;
    case (kind)
        0: ok = !out.ram_cs && !out.sram_cs && out.data == 8'hFF;
        1: ok = out.ram_cs && !out.sram_cs && out.addr == 27'(off) && out.data == 8'hFF;
        2: ok = out.sram_cs && !out.ram_cs && out.addr == 27'(off);
        3: ok = !out.ram_cs && !out.sram_cs && out.data == v;
    endcase
    if (!ok) begin
        errors++; $display("FAIL %s: read %04h -> ram_cs %b sram_cs %b addr %07h data %02h", what, a,
                           out.ram_cs, out.sram_cs, out.addr, out.data);
    end
    @(negedge clk); mreq = 0; rd = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_FMPAC;
    block_info.rom_size = 25'h10000;
    repeat (3) @(negedge clk); rst = 0;

    expect_rd("ROM 4123",            16'h4123, 1, 32'h0123);
    expect_rd("page 2 8123 nothing", 16'h8123, 0, 0);
    write(16'hBFF7, 8'h01);                             // outside the window: no bank switch
    expect_rd("bank kept after BFF7", 16'h4123, 1, 32'h0123);
    write(16'h7FF7, 8'h02);
    expect_rd("bank 2",               16'h4123, 1, 32'h8123);
    expect_rd("7FF7 register alone",  16'h7FF7, 3, 0, 8'h02);
    write(16'h7FF6, 8'h01);
    expect_rd("7FF6 register alone",  16'h7FF6, 3, 0, 8'h01);
    expect_rd("BFF6 not a register",  16'hBFF6, 0, 0);

    write(16'h5FFE, 8'h4D); write(16'h5FFF, 8'h69);     // SRAM on
    expect_rd("SRAM 4123",            16'h4123, 2, 32'h0123);
    expect_rd("5FFE magic alone",     16'h5FFE, 3, 0, 8'h4D);
    expect_rd("6123 FF with SRAM",    16'h6123, 0, 0);
    expect_rd("8123 no SRAM",         16'h8123, 0, 0);
    expect_rd("C123 no SRAM",         16'hC123, 0, 0);

    if (errors == 0) $display("PASS fm_pac_tb");
    else             $display("FAILED fm_pac_tb: %0d errors", errors);
    $finish;
end

endmodule
