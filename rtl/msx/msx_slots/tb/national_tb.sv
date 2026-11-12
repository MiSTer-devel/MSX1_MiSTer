// mapper_national against openMSX RomNational:
// - control bit 2: bank select read back at (address & 7FF9h) == 7FF0h (7FF0/2/4/6, FFF0/...),
//   the register alone (no ROM byte), and only in its own slot;
// - banks (6400 / 6000 / 7000 / 7400 -> pages 0-3) through RomBlocks::setRom (wrap).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_national.sh [alt_national.sv]
module national_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_national dut (.cpu_bus(cpu_bus), .block_info(block_info), .out(out));

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

// kind 0: FF from this mapper, 1: ROM block b, 2: register value b alone
task automatic expect_rd(input string what, input logic [15:0] a, input int kind, input int b);
    logic ok;
    @(negedge clk); addr = a; mreq = 1; rd = 1; req = 1; #1;
    case (kind)
        0: ok = !out.ram_cs && out.data == 8'hFF;
        1: ok = out.ram_cs && out.data == 8'hFF && out.addr == {5'b0, 8'(b), a[13:0]};
        2: ok = !out.ram_cs && out.data == 8'(b);
    endcase
    if (!ok) begin
        errors++; $display("FAIL %s: typ %0d read %04h -> ram_cs %b addr %07h data %02h", what, block_info.typ, a,
                           out.ram_cs, out.addr, out.data);
    end
    @(negedge clk); mreq = 0; rd = 0; req = 0;
endtask

initial begin
    block_info = '0;
    block_info.typ      = MAPPER_NATIONAL;
    block_info.rom_size = 25'h20000;                     // 128 KB, 8 blocks
    repeat (3) @(negedge clk); rst = 0;

    write(16'h6000, 8'h05);                              // page 1
    write(16'h7000, 8'h06);                              // page 2
    write(16'h7FF9, 8'h04);                              // bank read back on
    expect_rd("read back 7FF2 = page 1", 16'h7FF2, 2, 5);
    expect_rd("read back 7FF4 = page 2", 16'h7FF4, 2, 6);
    expect_rd("read back mirror FFF2",   16'hFFF2, 2, 5);
    expect_rd("7FF8 is ROM",             16'h7FF8, 1, 5);
    block_info.typ = MAPPER_OFFSET;                      // another slot
    expect_rd("no read back in another slot", 16'hFFF2, 0, 0);
    block_info.typ = MAPPER_NATIONAL;

    write(16'h7FF9, 8'h00);
    write(16'h7000, 8'h0B);                              // 11 -> 3
    expect_rd("bank 0Bh -> 3", 16'h8123, 1, 3);
    write(16'h7400, 8'h09);                              // page 3: 9 -> 1
    expect_rd("bank 09h -> 1", 16'hC123, 1, 1);

    if (errors == 0) $display("PASS national_tb");
    else             $display("FAILED national_tb: %0d errors", errors);
    $finish;
end

endmodule
