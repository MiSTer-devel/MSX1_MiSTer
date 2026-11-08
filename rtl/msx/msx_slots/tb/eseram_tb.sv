// mapper_eseRam against openMSX ESE_RAM.cc: bank registers at 0x6000-0x7FFF (region =
// addr[12:11], bit 7 = writable), RAM in 0x4000-0xBFFF, nothing outside its own slot.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_eseram.sh [alt_eseRam.sv]
module eseram_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if        cpu_bus(clk, rst);
ext_sd_card_if    sd();
MSX::block_info_t block_info;
MSX::mapper_out_t out;

mapper_eseRam dut (.cpu_bus(cpu_bus), .out(out), .block_info(block_info),
                   .ext_SD_card_bus(sd), .megaSD_enable(1'b0));

logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;  assign cpu_bus.rd = rd;  assign cpu_bus.wr = wr;
assign cpu_bus.req  = req;   assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign sd.data_from_SD = 8'hFF;

int errors = 0;

task automatic write(input mapper_typ_t typ, input logic [15:0] a, input logic [7:0] d);
    block_info.typ = typ; addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(posedge clk); #1 req = 0; mreq = 0; wr = 0;
endtask

// One access: expected ram_cs, rnw and (when selected) RAM address
task automatic check(input string what, input mapper_typ_t typ, input logic [15:0] a,
                     input logic is_wr, input logic exp_cs, input logic [26:0] exp_addr);
    block_info.typ = typ; addr = a; data = 8'h5A; mreq = 1; rd = ~is_wr; wr = is_wr;
    #1;
    if (out.ram_cs !== exp_cs ||
        (exp_cs  && (out.addr !== exp_addr || out.rnw !== ~is_wr)) ||
        // another slot: neutral output, it is AND-merged with the active mapper
        (typ != MAPPER_ESE_RAM && (out.addr !== '1 || out.rnw !== 1'b1))) begin
        errors++;
        $display("FAIL %s: typ=%0d %s %04h -> ram_cs=%b rnw=%b addr=%07h (expected cs=%b addr=%07h)",
                 what, typ, is_wr ? "wr" : "rd", a, out.ram_cs, out.rnw, out.addr, exp_cs, exp_addr);
    end
    @(posedge clk); #1 mreq = 0; rd = 0; wr = 0;
endtask

function automatic logic [26:0] ram(input logic [6:0] blk, input logic [15:0] a);
    return {7'b0, blk, a[12:0]};
endfunction

initial begin
    block_info = '0;
    repeat (3) @(posedge clk); #1 rst = 0;

    // Bank registers: region 0 (0x4000) block 5 writable, 1 (0x6000) block 6 read-only,
    // 2 (0x8000) block 7 writable, 3 (0xA000) block 8 read-only
    write(MAPPER_ESE_RAM, 16'h6000, 8'h85);
    write(MAPPER_ESE_RAM, 16'h6800, 8'h06);
    write(MAPPER_ESE_RAM, 16'h7000, 8'h87);
    write(MAPPER_ESE_RAM, 16'h7800, 8'h08);

    // Own slot
    check("read 4000",            MAPPER_ESE_RAM, 16'h4123, 0, 1, ram(5, 16'h4123));
    check("read 6000",            MAPPER_ESE_RAM, 16'h6123, 0, 1, ram(6, 16'h6123));
    check("read 8000",            MAPPER_ESE_RAM, 16'h8123, 0, 1, ram(7, 16'h8123));
    check("read A000",            MAPPER_ESE_RAM, 16'hA123, 0, 1, ram(8, 16'hA123));
    check("write writable 4000",  MAPPER_ESE_RAM, 16'h4123, 1, 1, ram(5, 16'h4123));
    check("write writable 8000",  MAPPER_ESE_RAM, 16'h8123, 1, 1, ram(7, 16'h8123));
    check("write read-only A000", MAPPER_ESE_RAM, 16'hA123, 1, 0, '1);
    check("write register area",  MAPPER_ESE_RAM, 16'h6123, 1, 0, '1);

    // Other slots: no access at all, also with writable banks
    check("other slot write 4000", MAPPER_OFFSET, 16'h4123, 1, 0, '1);
    check("other slot write 8000", MAPPER_MSX2,   16'h8123, 1, 0, '1);
    check("empty slot write 4000", MAPPER_NONE,   16'h4123, 1, 0, '1);
    check("other slot read 4000",  MAPPER_OFFSET, 16'h4123, 0, 0, '1);

    // A write to 0x6000 in another slot must not change the bank registers
    write(MAPPER_MSX2, 16'h6000, 8'h01);
    check("bank after foreign write", MAPPER_ESE_RAM, 16'h4123, 0, 1, ram(5, 16'h4123));

    if (errors == 0) $display("PASS eseram_tb");
    else             $display("FAILED eseram_tb: %0d errors", errors);
    $finish;
end

endmodule
