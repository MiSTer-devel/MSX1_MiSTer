// mapper_turbor_fdc: 16 KB banks of the turbo R disk ROM in 4000-7FFF, bank written at 7FF0
// exactly and masked by the ROM size, no ROM in 8000-BFFF (openMSX TurboRFDC).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_turbor_fdc.sh
module turbor_fdc_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_turbor_fdc dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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
    if (!c) begin errors++; $display("FAIL %s: ram_cs %b addr %07h", what, out.ram_cs, out.addr); end
endtask

task automatic write(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0; mreq = 0; wr = 0;
endtask

task automatic read(input logic [15:0] a);
    @(negedge clk); addr = a; mreq = 1; rd = 1; #0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_TURBO_R_FDC;
    block_info.rom_size = 25'h10000;                    // 64 KB: 4 banks
    repeat (2) @(negedge clk); rst = 0;

    read(16'h4123); check("bank 0 after reset", out.ram_cs && out.addr == 27'h0000123);
    write(16'h7FF0, 8'h02);
    read(16'h4123); check("bank 2", out.ram_cs && out.addr == 27'h0008123);
    read(16'h7FEF); check("bank 2, end of page 1", out.ram_cs && out.addr == 27'h000BFEF);
    write(16'h7FF0, 8'h07);                             // masked by 4 banks
    read(16'h4000); check("bank 7 & 3", out.ram_cs && out.addr == 27'h000C000);
    write(16'hBFF0, 8'h01);                             // only 7FF0 selects the bank
    write(16'h7FF1, 8'h01);
    read(16'h5000); check("bank kept after BFF0 / 7FF1", out.ram_cs && out.addr == 27'h000D000);
    read(16'h8123); check("no ROM in 8000-BFFF", !out.ram_cs && out.addr == '1);
    @(negedge clk); rd = 0; mreq = 0; wr = 1; mreq = 1; addr = 16'h4000; #0;
    check("write is not a ROM access", !out.ram_cs);
    wr = 0; mreq = 0;
    block_info.rom_size = 25'h4000;                     // 16 KB: one bank, always 0
    write(16'h7FF0, 8'h03);
    read(16'h4000); check("16 KB ROM: bank 0", out.ram_cs && out.addr == 27'h0000000);
    block_info.typ = MAPPER_GENERIC16KB;
    read(16'h4000); check("other mapper type: idle", !out.ram_cs && out.addr == '1);

    if (errors == 0) $display("PASS turbor_fdc_tb");
    else             $display("FAILED turbor_fdc_tb: %0d errors", errors);
    $finish;
end

endmodule
