// dev_dac: sum of the MSX::N_DAC built DACs at full width (no 16-bit wrap), sign extension of
// negative values. Writes go to all 3 io_device entries, the ones not built stay silent.
// Silence (80h) after reset as openMSX. Own decoding (4000-7FFF, address bit 4 = 0) or, with
// param bit 0, the strobe of the mapper (device_bus.we, KUC).
// Run: wsl.exe -- bash rtl/msx/devices/tb/run_dac.sh [alt_dac.sv]
module dac_tb;

logic clk = 0, rst = 1;
cpu_bus_if   cpu_bus(clk, rst);
clock_bus_if clock_bus(clk, clk);
MSX::block_info_t block_info;
MSX::io_device_t  io_device[3];
MSX::device_bus_t device_bus;
logic signed [31:0] sound;              // wide on purpose: catches a missing sign extension

dev_dac dut (.cpu_bus(cpu_bus), .clock_bus(clock_bus), .block_info(block_info),
             .device_bus(device_bus), .io_device(io_device), .sound(sound));

logic [15:0] addr;
logic  [7:0] data;
logic        wr;
assign cpu_bus.addr = addr;
assign cpu_bus.data = data;
assign cpu_bus.mreq = wr;
assign cpu_bus.wr   = wr;
assign cpu_bus.rd   = 1'b0;
assign cpu_bus.req  = wr;

int errors = 0;

always #5 clk = ~clk;

task automatic dac_write(input int dev, input logic [7:0] v, input logic [15:0] a = 16'h4000,
                         input logic we = 1'b0);
    block_info.device_ref = 3'(dev + 1);
    addr = a; data = v; wr = 1; device_bus.we = we;
    @(posedge clk); #1 wr = 0; device_bus.we = 1'b0;
endtask

task automatic expect_dac(input string what, input int exp);
    if (sound !== exp) begin errors++; $display("FAIL %s: sound=%0d exp %0d", what, sound, exp); end
endtask

function automatic int scale(input logic [7:0] v);
    return (int'(v) - 128) * 128;
endfunction

task automatic check(input logic [7:0] a, b, c);
    int exp;
    dac_write(0, a); dac_write(1, b); dac_write(2, c);
    exp = (MSX::N_DAC > 0 ? scale(a) : 0) + (MSX::N_DAC > 1 ? scale(b) : 0) + (MSX::N_DAC > 2 ? scale(c) : 0);
    if (sound !== exp) begin
        errors++;
        $display("FAIL dac %02h %02h %02h: sound=%0d exp %0d", a, b, c, sound, exp);
    end
endtask

initial begin
    block_info = '0;
    for (int i = 0; i < 3; i++)
        io_device[i] = '{mask: 8'h00, port: 8'h00, param: 8'h00, mem_ref: 3'd0,
                         device_ref: 3'(i + 1), enable: 1'b1};
    addr = '0; data = '0; wr = 0; device_bus = MSX::DEVICE_BUS_IDLE;
    repeat (2) @(posedge clk); #1 rst = 0;

    expect_dac("silence after reset", 0);

    // own decoding: 4000-7FFF with address bit 4 = 0, only the device of the block
    dac_write(0, 8'h90);                  expect_dac("4000", scale(8'h90));
    dac_write(0, 8'hA0, 16'h7FEF);        expect_dac("7FEF", scale(8'hA0));
    dac_write(0, 8'h10, 16'h4010);        expect_dac("4010: bit 4", scale(8'hA0));
    dac_write(0, 8'h10, 16'h8000);        expect_dac("8000", scale(8'hA0));
    dac_write(5, 8'h10, 16'h4000);        expect_dac("other block", scale(8'hA0));
    dac_write(0, 8'h80);

    // param bit 0: the mapper decodes (KUC), the address does not matter
    io_device[0].param = 8'h01;
    dac_write(0, 8'h30);                  expect_dac("mapper DAC without strobe", 0);
    dac_write(0, 8'h30, 16'h4000, 1'b1);  expect_dac("mapper DAC strobe", scale(8'h30));
    dac_write(0, 8'h50, 16'h4010, 1'b1);  expect_dac("mapper DAC strobe, any address", scale(8'h50));
    dac_write(5, 8'h70, 16'h4000, 1'b1);  expect_dac("mapper DAC strobe of another block", scale(8'h50));
    io_device[0].param = 8'h00;

    check(8'h80, 8'h80, 8'h80);       // silence
    check(8'h81, 8'h7F, 8'h80);       // small, both signs
    check(8'h00, 8'h80, 8'h80);       // single negative
    check(8'h00, 8'h00, 8'h00);       // -49152: wraps to +16384 in 16 bit
    check(8'hFF, 8'hFF, 8'hFF);       // +48768: wraps to -16768 in 16 bit
    check(8'hFF, 8'h00, 8'h40);
    for (int i = 0; i < 2000; i++) check(8'($urandom), 8'($urandom), 8'($urandom));

    if (errors == 0) $display("PASS dac_tb");
    else             $display("FAILED dac_tb: %0d errors", errors);
    $finish;
end

endmodule
