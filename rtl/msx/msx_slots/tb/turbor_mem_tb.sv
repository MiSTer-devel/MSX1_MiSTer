// Turbo R main RAM users against openMSX (RomDRAM, PanasonicMemory, PanasonicRam):
//   mapper_dram: ROM page in ROM mode, top 64 KB of the main RAM in DRAM mode
//                (size - 64K + (mapper_param + offset_ram) x 16K), writes ignored;
//   mapper_msx2_ram with PANASONIC_RAM: DRAM mode protects the top 64 KB against writes.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_turbor_mem.sh   (PREV=<git ref>: mappers from that ref)
module turbor_mem_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;
cpu_bus_if cpu_bus(clk, rst);
MSX::block_info_t block_info;
MSX::mapper_out_t out_d, out_m;
logic [7:0] segment = '0;                       // data_to_mapper: segment of the page (dev_msx2_ram)

mapper_dram     dut_dram (.cpu_bus(cpu_bus), .block_info(block_info), .out(out_d));
mapper_msx2_ram dut_ram  (.cpu_bus(cpu_bus), .block_info(block_info), .out(out_m), .data_to_mapper(segment));

logic [15:0] addr = '0;
logic        mreq = 0, rd = 0, wr = 0;
assign cpu_bus.addr = addr;
assign cpu_bus.data = 8'h00;
assign cpu_bus.mreq = mreq;
assign cpu_bus.rd   = rd;
assign cpu_bus.wr   = wr;
assign cpu_bus.req  = mreq;
assign cpu_bus.iorq = 1'b0;
assign cpu_bus.m1   = 1'b0;

int errors = 0;
task automatic fail(input string what, input MSX::mapper_out_t o);
    errors++;
    $display("FAIL %s: ram_cs %b main_cs %b sram_cs %b rnw %b addr %07h", what, o.ram_cs, o.main_cs, o.sram_cs, o.rnw, o.addr);
endtask

task automatic access(input logic [15:0] a, input logic write);
    @(negedge clk); addr = a; mreq = 1; rd = !write; wr = write; #0;
endtask
task automatic idle();
    @(negedge clk); mreq = 0; rd = 0; wr = 0;
endtask

// mapper_dram read of page address a: from ROM (main = 0) or the main RAM (main = 1) at offset off
task automatic dram_read(input string what, input logic [15:0] a, input logic main, input logic [26:0] off);
    access(a, 1'b0);
    if (main  && !(out_d.main_cs && !out_d.ram_cs && out_d.rnw && out_d.addr == off)) fail(what, out_d);
    if (!main && !(out_d.ram_cs && !out_d.main_cs && out_d.rnw && out_d.addr == off)) fail(what, out_d);
    idle();
endtask

// mapper_msx2_ram write to segment s: allowed or ignored (rnw stays 1)
task automatic ram_write(input string what, input logic [7:0] s, input logic allowed);
    segment = s;
    access(16'h8123, 1'b1);
    if (!(out_m.ram_cs && out_m.rnw == !allowed && out_m.addr == {5'b0, s, 14'h0123})) fail(what, out_m);
    idle();
endtask

initial begin
    block_info = '0;
    repeat (2) @(negedge clk); rst = 0;

    // --- mapper_dram, FS-A1ST: main RAM 256 KB (32 blocks of 8 KB), BIOS ROM 32 KB
    block_info.typ           = MAPPER_DRAM;
    block_info.rom_size      = 25'h8000;
    block_info.main_ram_size = 17'd32;
    block_info.mapper_param  = 2'd0;
    block_info.offset_ram    = 2'd0;
    dram_read("ROM mode page 0", 16'h0123, 1'b0, 27'h0000123);
    block_info.offset_ram    = 2'd1;
    dram_read("ROM mode page 1", 16'h7FFF, 1'b0, 27'h0007FFF);
    access(16'h4000, 1'b1);
    if (out_d.ram_cs || out_d.main_cs || !out_d.rnw) fail("ROM mode write ignored", out_d);
    idle();
    block_info.offset_ram    = 2'd2;                    // beyond the 32 KB ROM
    access(16'h8000, 1'b0);
    if (out_d.ram_cs || out_d.main_cs) fail("ROM mode outside the ROM", out_d);
    idle();

    block_info.dram          = 1'b1;
    block_info.offset_ram    = 2'd0;
    dram_read("DRAM BIOS page 0 = 30000h", 16'h0123, 1'b1, 27'h0030123);
    block_info.offset_ram    = 2'd1;
    dram_read("DRAM BIOS page 1 = 34000h", 16'h7FFF, 1'b1, 27'h0037FFF);
    block_info.offset_ram    = 2'd0;
    block_info.mapper_param  = 2'd2;
    dram_read("DRAM Sub ROM = 38000h", 16'h0001, 1'b1, 27'h0038001);
    block_info.mapper_param  = 2'd3;
    dram_read("DRAM Kanji driver = 3C000h", 16'h4002, 1'b1, 27'h003C002);
    access(16'h4002, 1'b1);
    if (out_d.ram_cs || out_d.main_cs || !out_d.rnw) fail("DRAM mode write ignored", out_d);
    idle();
    block_info.main_ram_size = 17'd64;                  // FS-A1GT: 512 KB
    block_info.mapper_param  = 2'd0;
    dram_read("DRAM BIOS on 512 KB = 70000h", 16'h0000, 1'b1, 27'h0070000);
    block_info.main_ram_size = 17'd0;                   // no main RAM: stays ROM
    dram_read("DRAM mode without main RAM reads ROM", 16'h0100, 1'b0, 27'h0000100);

    // --- mapper_msx2_ram, PANASONIC_RAM 256 KB = 16 segments: 12-15 protected in DRAM mode
    block_info               = '0;
    block_info.typ           = MAPPER_PANASONIC_RAM;
    block_info.rom_size      = 25'h40000;
    ram_write("ROM mode: segment 15 writable", 8'd15, 1'b1);
    block_info.dram          = 1'b1;
    ram_write("DRAM: segment 11 writable", 8'd11, 1'b1);
    ram_write("DRAM: segment 12 protected", 8'd12, 1'b0);
    ram_write("DRAM: segment 15 protected", 8'd15, 1'b0);
    segment = 8'd15;
    access(16'h8000, 1'b0);
    if (!(out_m.ram_cs && out_m.rnw && out_m.addr == 27'h003C000)) fail("DRAM: segment 15 readable", out_m);
    idle();
    block_info.rom_size      = 25'h80000;               // 512 KB: 28-31 protected
    ram_write("DRAM 512 KB: segment 27 writable", 8'd27, 1'b1);
    ram_write("DRAM 512 KB: segment 28 protected", 8'd28, 1'b0);
    block_info.typ           = MAPPER_MSX2;             // plain RAM mapper: no protection
    ram_write("MSX2 RAM ignores DRAM mode", 8'd31, 1'b1);

    // other mapper type: dram mapper idle
    block_info.typ = MAPPER_OFFSET;
    access(16'h0000, 1'b0);
    if (out_d.ram_cs || out_d.main_cs || out_d.addr !== '1) fail("dram mapper idle for another type", out_d);
    idle();

    if (errors == 0) $display("PASS turbor_mem_tb");
    else             $display("FAILED turbor_mem_tb: %0d errors", errors);
    $finish;
end

endmodule
