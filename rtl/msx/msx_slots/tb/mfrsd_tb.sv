// mapper_mfrsd with the slot expander disabled (config register 0x7FFC bit 2):
// like openMSX MegaFlashRomSCCPlusSD::getSubSlot(), every access to the cartridge
// slot goes to subslot 1, accesses to other slots are not touched.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mfrsd.sh [alt_mfrsd.sv]
module mfrsd_tb;

logic clk = 0, rst = 1;
always #5 clk = ~clk;

cpu_bus_if     cpu_bus(clk, rst);
ext_sd_card_if sd();
flash_bus_if   flash();
MSX::block_info_t block_info;
MSX::mapper_out_t out;
MSX::device_bus_t device_out;
wire              force_en;

mapper_mfrsd dut (.cpu_bus(cpu_bus), .block_info(block_info), .ext_SD_card_bus(sd),
                  .flash_bus(flash), .out(out), .device_out(device_out),
                  .data_to_mapper(8'h00), .slot_expander_force_en(force_en));

logic [15:0] addr = '0;
logic  [7:0] data = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = data;
assign cpu_bus.mreq = mreq;  assign cpu_bus.rd = rd;  assign cpu_bus.wr = wr;
assign cpu_bus.req  = req;   assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign sd.data_from_SD = 8'hFF;
assign flash.data_from_flash = 8'hFF;
assign flash.data_valid = 1'b0;

int errors = 0;

task automatic write(input mapper_typ_t typ, input logic [15:0] a, input logic [7:0] d);
    block_info.typ = typ; addr = a; data = d; mreq = 1; wr = 1; req = 1;
    @(posedge clk); #1 req = 0;
    @(posedge clk); #1 mreq = 0; wr = 0;
endtask

// Read access: is the cartridge (mfrsd1 flash/RAM) selected?
task automatic check_read(input string what, input mapper_typ_t typ, input logic [15:0] a, input logic exp_cs);
    block_info.typ = typ; addr = a; mreq = 1; rd = 1;
    #1;
    if (out.ram_cs !== exp_cs || (!exp_cs && (out.addr !== '1 || flash.ce !== 1'b0))) begin
        errors++;
        $display("FAIL %s: typ=%0d addr=%04h ram_cs=%b addr=%07h flash.ce=%b (expected cs=%b)",
                 what, typ, a, out.ram_cs, out.addr, flash.ce, exp_cs);
    end
    @(posedge clk); #1 mreq = 0; rd = 0;
endtask

task automatic check_write_ignored(input string what, input mapper_typ_t typ, input logic [15:0] a);
    block_info.typ = typ; addr = a; data = 8'hA5; mreq = 1; wr = 1; req = 1;
    #1;
    if (flash.ce !== 1'b0 || flash.we !== 1'b0 || out.ram_cs !== 1'b0) begin
        errors++;
        $display("FAIL %s: typ=%0d write %04h reaches the cartridge (flash ce=%b we=%b, ram_cs=%b)",
                 what, typ, a, flash.ce, flash.we, out.ram_cs);
    end
    @(posedge clk); #1 req = 0; mreq = 0; wr = 0;
endtask

initial begin
    block_info = '0;
    repeat (3) @(posedge clk); #1 rst = 0;

    // Expander enabled: subslot 1 only for MFRSD1
    check_read("expander on, other slot",     MAPPER_OFFSET, 16'h4000, 1'b0);
    check_read("expander on, subslot 1",      MAPPER_MFRSD1, 16'h4000, 1'b1);

    // Disable the expander, flash write enabled (config reg 0x7FFC: bit 2 = 1, bit 0 = 1)
    write(MAPPER_MFRSD1, 16'h7FFC, 8'h05);
    if (force_en !== 1'b0) begin errors++; $display("FAIL expander still forced"); end

    // Cartridge slot: every subslot / page goes to subslot 1 (openMSX getSubSlot() == 1)
    check_read("expander off, cart slot (sub 0)", MAPPER_MFRSD0, 16'h4000, 1'b1);
    check_read("expander off, cart slot (sub 2)", MAPPER_MFRSD2, 16'h6000, 1'b1);
    check_read("expander off, cart slot (sub 3)", MAPPER_MFRSD3, 16'h8000, 1'b1);

    // Other slots must not see the cartridge
    check_read("expander off, other slot ROM",   MAPPER_OFFSET, 16'h4000, 1'b0);
    check_read("expander off, other slot RAM",   MAPPER_MSX2,   16'h8000, 1'b0);
    check_read("expander off, empty slot",       MAPPER_NONE,   16'h6000, 1'b0);
    check_write_ignored("expander off, other slot", MAPPER_MSX2, 16'h6000);

    // A write to 0x7FFC in another slot must not change the cartridge configuration
    write(MAPPER_MSX2, 16'h7FFC, 8'h00);              // would re-enable the expander
    block_info.typ = MAPPER_MFRSD1; mreq = 1; #1;
    if (force_en !== 1'b0) begin errors++; $display("FAIL write to 0x7FFC in another slot changed the config register"); end
    mreq = 0;

    if (errors == 0) $display("PASS mfrsd_tb");
    else             $display("FAILED mfrsd_tb: %0d errors", errors);
    $finish;
end

endmodule
