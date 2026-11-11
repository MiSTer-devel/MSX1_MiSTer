// msx_slots: FFFF in an expanded slot is the subslot register only (openMSX MSXCPUInterface,
// "confirmed on turboR GT"): no write to the memory below, no write to the mapper.
// MFRSD with its slot expander off: every access to its slot uses subslot 1 (openMSX
// MegaFlashRomSCCPlusSD::getSubSlot), also the memory of that block (C12).
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_msx_slots.sh [git-ref for the reference DUT]
module msx_slots_tb;

logic clk = 0, rst = 1;
always #1 clk = ~clk;

cpu_bus_if     cpu_bus(clk, rst);
clock_bus_if   clock_bus(clk, clk);
ext_sd_card_if sd();
flash_bus_if   flash();
memory_bus_if  mem();

assign {clock_bus.ce_10m7_p, clock_bus.ce_10m7_n, clock_bus.ce_5m39_p, clock_bus.ce_5m39_n,
        clock_bus.ce_3m58_p, clock_bus.ce_3m58_n, clock_bus.ce_7m16_n, clock_bus.ce_1m79_n,
        clock_bus.ce_1k, clock_bus.ce_10hz} = '0;
assign sd.data_from_SD = 8'hFF;
assign sd.busy         = 1'b0;
assign flash.data_from_flash = 8'hFF;
assign flash.data_valid      = 1'b0;
assign mem.q           = 8'h00;
assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;

logic [15:0] addr = 0;
logic  [7:0] dout = 0;
logic        mreq = 0, rd = 0, wr = 0;
logic  [1:0] slot = 0;
assign cpu_bus.addr   = addr;
assign cpu_bus.data   = dout;
assign cpu_bus.mreq   = mreq;
assign cpu_bus.iorq   = 1'b0;
assign cpu_bus.rd     = rd;
assign cpu_bus.wr     = wr;
assign cpu_bus.m1     = 1'b0;
assign cpu_bus.halt   = 1'b0;
assign cpu_bus.rfsh   = 1'b0;
assign cpu_bus.req    = rd | wr;
assign cpu_bus.int_rq = 1'b0;

// Layout: slot 3 expanded. 3-0 page 3 = RAM 16 KB (lookup 1), 3-1 page 3 = Cross Blaim 64 KB
// (lookup 2). Slot 0 not expanded, page 3 = RAM (lookup 1). Slot 1: MFRSD (expander of the
// cartridge), subslots 0-3 = MFRSD0-3, subslot 1 memory = lookup 3, the others lookup 2.
localparam logic [26:0] BASE_RAM = 27'h0100000, BASE_CB = 27'h0200000, BASE_MFRSD1 = 27'h0400000;

MSX::slot_expander_t expander[4];
MSX::lookup_RAM_t    lookup_RAM[4];
MSX::lookup_SRAM_t   lookup_SRAM[4];
MSX::block_t         active_block;
MSX::main_ram_t      main_ram;
wire           [5:0] layout_id;

initial begin
    expander[0] = '{en: 1'b0, wo: 1'b0, init: 8'h00};
    expander[1] = '{en: 1'b0, wo: 1'b0, init: 8'h00};
    expander[2] = '{en: 1'b0, wo: 1'b0, init: 8'h00};
    expander[3] = '{en: 1'b1, wo: 1'b0, init: 8'h00};
    lookup_RAM[0] = '{addr: '0, size: '0, ro: 1'b1};
    lookup_RAM[1] = '{addr: BASE_RAM, size: 17'd2, ro: 1'b0};
    lookup_RAM[2] = '{addr: BASE_CB,  size: 17'd8, ro: 1'b1};
    lookup_RAM[3] = '{addr: BASE_MFRSD1, size: 17'd512, ro: 1'b1};
    for (int i = 0; i < 4; i++) lookup_SRAM[i] = '{addr: '0, size: '0};
end
assign main_ram = '{en: 1'b0, ref_ram: 4'd0};

always_comb begin
    active_block = '{ref_ram: 4'd0, ref_sram: 2'd0, offset_ram: 2'd0, device_ref: 3'd0,
                     mapper: MAPPER_NONE, mapper_param: 2'd0, cart_num: 1'b0, external: 1'b0};
    case (layout_id)
        {2'd3, 2'd0, 2'd3}, {2'd0, 2'd0, 2'd3}: begin active_block.ref_ram = 4'd1; active_block.mapper = MAPPER_OFFSET; end
        {2'd3, 2'd1, 2'd3}:                     begin active_block.ref_ram = 4'd2; active_block.mapper = MAPPER_CROSS_BLAIM; end
        default: ;
    endcase
    if (layout_id[5:4] == 2'd1) begin
        active_block.ref_ram = layout_id[3:2] == 2'd1 ? 4'd3 : 4'd2;
        case (layout_id[3:2])
            2'd0: active_block.mapper = MAPPER_MFRSD0;
            2'd1: active_block.mapper = MAPPER_MFRSD1;
            2'd2: active_block.mapper = MAPPER_MFRSD2;
            2'd3: active_block.mapper = MAPPER_MFRSD3;
        endcase
    end
    case (layout_id)
        default: ;
    endcase
end

wire  [7:0] data;
wire        data_oe_rq;
MSX::block_info_t block_info;
MSX::device_bus_t device_bus;
wire        mmc_on, mmc_wait;

msx_slots dut (
    .clock_bus(clock_bus), .cpu_bus(cpu_bus), .ext_SD_card_bus(sd), .flash_bus(flash),
    .memory_bus(mem), .block_info(block_info), .slot_expander(expander), .layout_id(layout_id),
    .active_block(active_block), .active_RAM(lookup_RAM[active_block.ref_ram]),
    .main_RAM(lookup_RAM[0]), .lookup_SRAM(lookup_SRAM), .main_ram(main_ram), .dram(1'b0),
    .active_slot(slot), .data(data), .data_oe_rq(data_oe_rq), .device_bus(device_bus),
    .data_to_mapper(8'h00), .ocm_megaSD_enable(1'b0), .ocm_slot1_mode(1'b0),
    .ocm_slot2_mode(2'b00), .ocm_ipl_en(1'b0), .ocm_mmc_on(mmc_on), .ocm_mmc_wait(mmc_wait)
);

// One access; the outputs are sampled while the request is on the bus.
logic       s_cs, s_rnw, s_oe;
logic [26:0] s_addr;
logic  [7:0] s_data;

int errors = 0;
task automatic fail(input string msg);
    errors++;
    $display("FAIL %s (ram_cs=%0b rnw=%0b addr=%07h data=%02h oe=%0b)", msg, s_cs, s_rnw,
             s_addr, s_data, s_oe);
endtask
task automatic access(input logic [1:0] sl, input logic [15:0] a, input logic w, input logic [7:0] v = 8'h00);
    slot = sl; addr = a; dout = v; mreq = 1; rd = ~w; wr = w;
    #0.5;
    s_cs = mem.ram_cs; s_rnw = mem.rnw; s_addr = mem.addr; s_data = data; s_oe = data_oe_rq;
    @(posedge clk); #0.1;
    mreq = 0; rd = 0; wr = 0; addr = 0;
    @(posedge clk); #0.1;
endtask

initial begin
    repeat (3) @(posedge clk);
    #0.1 rst = 0;
    repeat (2) @(posedge clk);
    #0.1;

    // Plain RAM write below FFFF still goes through
    access(3, 16'hFFFE, 1, 8'h11);
    if (!(s_cs && !s_rnw && s_addr == BASE_RAM + 27'h3FFE)) fail("3-0 write FFFE");

    // C1: write to FFFF in an expanded slot must not reach the RAM below
    access(3, 16'hFFFF, 1, 8'h00);
    if (s_cs) fail("3-0 write FFFF reached RAM");

    // Read of FFFF: inverted register, no memory access
    access(3, 16'hFFFF, 0);
    if (s_cs || !s_oe || s_data != 8'hFF) fail("3-0 read FFFF");

    // Slot without an expander: FFFF is ordinary RAM
    access(0, 16'hFFFF, 1, 8'h22);
    if (!(s_cs && !s_rnw && s_addr == BASE_RAM + 27'h3FFF)) fail("slot 0 write FFFF");
    access(0, 16'hFFFF, 0);
    if (!s_cs || s_oe) fail("slot 0 read FFFF");

    // Page 3 -> subslot 1 (Cross Blaim, register on any address; bank 1 in page 3 after reset)
    access(3, 16'hFFFF, 1, 8'h40);
    access(3, 16'hC000, 0);
    if (!(s_cs && s_addr == BASE_CB + 27'h4000)) fail("3-1 read C000 after select");

    // C1: register write must not reach the mapper under FFFF (value 2 would unmap page 3)
    access(3, 16'hFFFF, 1, 8'h42);
    access(3, 16'hC000, 0);
    if (!(s_cs && s_addr == BASE_CB + 27'h4000)) fail("3-1 mapper saw write to FFFF");
    access(3, 16'hFFFF, 0);
    if (s_cs || !s_oe || s_data != ~8'h42) fail("3-1 read FFFF");

    // The mapper itself still gets other writes: value 2 unmaps page 3
    access(3, 16'hC000, 1, 8'h02);
    access(3, 16'hC000, 0);
    if (s_cs) fail("3-1 mapper write C000");

    // C12: MFRSD in slot 1. Page 1 -> subslot 1 (FFFF = 04h), config 7FFC bit 2: expander off.
    // The register still maps page 2 to subslot 0; a read of 8000 must use subslot 1 and its
    // memory (bank 2 of the Konami SCC mode at reset = 4000h in the flash).
    access(1, 16'hFFFF, 1, 8'h04);
    access(1, 16'h8000, 0);
    if (!(s_cs && s_addr == BASE_CB + 27'h0000)) fail("MFRSD expander on: 8000 in subslot 0");
    access(1, 16'h7FFC, 1, 8'h04);
    access(1, 16'h8000, 0);
    if (!(s_cs && s_addr == BASE_MFRSD1 + 27'h4000)) fail("MFRSD expander off: 8000 not in subslot 1 memory");
    access(1, 16'hFFFF, 0);
    if (s_oe) fail("MFRSD expander off: FFFF still the register");

    if (errors == 0) $display("PASS msx_slots_tb");
    else             $display("FAILED msx_slots_tb: %0d errors", errors);
    $finish;
end

endmodule
