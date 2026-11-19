// Equivalence of mappers (current) and mappers_old (reference from git) under random stimulus.
// Run: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mappers_eq.sh [git-ref]
module mappers_eq_tb;

localparam int CYCLES = 2_000_000;

logic clk = 0, reset = 1;
cpu_bus_if   cpu_bus(clk, reset);
clock_bus_if clock_bus(clk, clk);

logic [15:0] addr;
logic  [7:0] cpu_data, data_to_mapper, flash_q, sd_q;
logic        mreq, iorq, rd, wr, m1, req, flash_valid;
logic        megaSD_en, slot1_mode, ipl_en;
logic  [1:0] slot2_mode;
MSX::block_info_t block_info;

assign cpu_bus.addr   = addr;
assign cpu_bus.data   = cpu_data;
assign cpu_bus.mreq   = mreq;
assign cpu_bus.iorq   = iorq;
assign cpu_bus.rd     = rd;
assign cpu_bus.wr     = wr;
assign cpu_bus.m1     = m1;
assign cpu_bus.req    = req;
assign cpu_bus.halt   = 1'b0;
assign cpu_bus.rfsh   = 1'b0;
assign cpu_bus.int_rq = 1'b0;
assign {clock_bus.ce_10m7_p, clock_bus.ce_10m7_n, clock_bus.ce_5m39_p, clock_bus.ce_5m39_n,
        clock_bus.ce_3m58_p, clock_bus.ce_3m58_n, clock_bus.ce_1m79_n, clock_bus.ce_1k,
        clock_bus.ce_10hz} = '0;

// Per-DUT buses, same responses
flash_bus_if   flash_new(), flash_old();
ext_sd_card_if sd_new(),    sd_old();
memory_bus_if  mem_new(),   mem_old();
assign flash_new.data_from_flash = flash_q;     assign flash_old.data_from_flash = flash_q;
assign flash_new.data_valid      = flash_valid; assign flash_old.data_valid      = flash_valid;
assign sd_new.data_from_SD       = sd_q;        assign sd_old.data_from_SD       = sd_q;

MSX::device_bus_t dev_new, dev_old;
logic [7:0] data_new, data_old;
logic       force_new, force_old;
logic       main_new, main_old;

mappers dut_new (
    .clock_bus(clock_bus), .cpu_bus(cpu_bus), .ext_SD_card_bus(sd_new), .flash_bus(flash_new),
    .block_info(block_info), .device_bus(dev_new), .memory_bus(mem_new), .main_cs(main_new), .data(data_new),
    .data_to_mapper(data_to_mapper), .slot_expander_force_en(force_new),
    .ocm_megaSD_enable(megaSD_en), .ocm_slot1_mode(slot1_mode), .ocm_slot2_mode(slot2_mode),
    .ocm_ipl_en(ipl_en)
);

mappers_old dut_old (
    .clock_bus(clock_bus), .cpu_bus(cpu_bus), .ext_SD_card_bus(sd_old), .flash_bus(flash_old),
    .block_info(block_info), .device_bus(dev_old), .memory_bus(mem_old), .main_cs(main_old), .data(data_old),
    .data_to_mapper(data_to_mapper), .slot_expander_force_en(force_old),
    .ocm_megaSD_enable(megaSD_en), .ocm_slot1_mode(slot1_mode), .ocm_slot2_mode(slot2_mode),
    .ocm_ipl_en(ipl_en)
);

wire [191:0] obs_new = {main_new, mem_new.addr, mem_new.rnw, mem_new.ram_cs, mem_new.sram_cs, mem_new.data,
                        data_new, dev_new, force_new,
                        flash_new.base_addr, flash_new.addr, flash_new.data_to_flash, flash_new.we, flash_new.ce,
                        sd_new.rx, sd_new.tx, sd_new.data_to_SD};
wire [191:0] obs_old = {main_old, mem_old.addr, mem_old.rnw, mem_old.ram_cs, mem_old.sram_cs, mem_old.data,
                        data_old, dev_old, force_old,
                        flash_old.base_addr, flash_old.addr, flash_old.data_to_flash, flash_old.we, flash_old.ce,
                        sd_old.rx, sd_old.tx, sd_old.data_to_SD};

int errors = 0, compared = 0, hold = 0;
logic [191:0] obs_mask;
mapper_typ_t  typ_q = MAPPER_NONE;     // block type of the previous clock (registered SD outputs)
always @(posedge clk) typ_q <= block_info.typ;
int active[64];          // cycles with ram_cs/sram_cs/device en, per mapper type

int err_typ[int];                   // mismatches per mapper type (summary at the end)
task automatic check(string phase);
    compared++;
    // MFRSD SD requests wait for the SPI and set rx on writes too (mfrsd_sd_tb, C10): the
    // SD signals are not compared while an MFRSD block is or was just active
    if (block_info.typ == MAPPER_MFRSD3 || typ_q == MAPPER_MFRSD3) begin
        obs_mask = {192{1'b1}};
        obs_mask[9:0] = '0;                         // sd rx, tx, data_to_SD
    end else
        obs_mask = {192{1'b1}};
    if ((obs_new & obs_mask) !== (obs_old & obs_mask)) begin
        errors++;
        err_typ[int'(block_info.typ)]++;
        if (errors <= 10 || err_typ[int'(block_info.typ)] == 1)
            $display("FAIL %s cyc=%0d typ=%0d addr=%04h rd=%b wr=%b\n  new=%040h\n  old=%040h",
                     phase, compared, block_info.typ, addr, rd, wr, obs_new, obs_old);
    end
endtask

// Mapper types with an implementation get most of the time; any 6-bit value is possible.
function automatic logic [5:0] pick_typ();
    if ($urandom_range(9) == 0) return 6'($urandom_range(63));
    return 6'($urandom_range(int'(MAPPER_UNUSED)));
endfunction

initial begin
    block_info = '0;
    {addr, cpu_data, data_to_mapper, flash_q, sd_q} = '0;
    {mreq, iorq, rd, wr, m1, req, flash_valid, megaSD_en, slot1_mode, slot2_mode, ipl_en} = '0;

    for (int c = 0; c < CYCLES; c++) begin
        // inputs change after the rising edge
        reset = (c < 4) || ($urandom_range(19999) == 0);
        if (hold == 0) begin    // new block for a while: lets bank registers take effect
            hold                  = $urandom_range(256, 1);
            block_info.typ        = mapper_typ_t'(pick_typ());
            block_info.rom_size   = 25'($urandom);
            block_info.sram_size  = 16'($urandom);
            block_info.offset_ram = 2'($urandom);
            block_info.base_ram   = 27'($urandom);
            block_info.device_ref = 3'($urandom);
            block_info.id         = 1'($urandom);
            block_info.mapper_param  = 2'($urandom);    // turbo R fields: other mappers ignore them
            // OFFSET: bit 0 = memory in the upper 8 kB of the page (offset_tb), not in the reference
            if (block_info.typ == MAPPER_OFFSET) block_info.mapper_param[0] = 1'b0;
            // KONAMI_SCC: a bank past the ROM end wraps (konami_scc_tb); from 2 MB none does
            if (block_info.typ == MAPPER_KONAMI_SCC) block_info.rom_size[24] = 1'b1;
            if (block_info.typ == MAPPER_KONAMI)     block_info.rom_size[24] = 1'b1;   // konami_tb
            // ASCII16 family (ascii16_tb): below 4 MB in whole 16 KB blocks the block count is the
            // same as in the reference; R-Type differs by design and is not compared
            if (block_info.typ == MAPPER_RTYPE) block_info.typ = MAPPER_ASCII16;
            // GM2 (gm2_tb): registers per slot, pages 0/3 unmapped, SRAM write half: compare one
            // slot, pages 1-2, SRAM selected through A000 only
            if (block_info.typ == MAPPER_GM2) block_info.id = 1'b0;
            // Generic 8 / 16 KB (generic_tb): one fixed size where the reference block count is right
            // and the reset banks are inside the ROM. The bank wraps when read, the reference when
            // written, so the size must not change between the two.
            if (block_info.typ == MAPPER_GENERIC8KB)  block_info.rom_size = 25'h0180000;   // 1.5 MB
            if (block_info.typ == MAPPER_GENERIC16KB) block_info.rom_size = 25'h0300000;   // 3 MB
            if (block_info.typ == MAPPER_ZEMINA_80)   block_info.rom_size = 25'h0100000;   // 1 MB, zemina80_tb
            if (block_info.typ == MAPPER_ZEMINA_90)   block_info.rom_size = 25'h0100000;   // 1 MB, zemina90_tb
            // Mirror (mirror_tb): the reference used (page + 2 x offset) % blocks, equal only for
            // offset 0 and 8 / 16 / 32 KB
            if (block_info.typ == MAPPER_MIRROR) begin
                block_info.offset_ram     = 2'd0;
                block_info.rom_size[15:0] = 16'h2000 << $urandom_range(2);
            end
            if (block_info.typ == MAPPER_ASCII16 || block_info.typ == MAPPER_MSXWRITE || block_info.typ == MAPPER_SUPERSWANGI) begin
                block_info.rom_size[24:22] = '0;
                block_info.rom_size[13:0]  = '0;
            end
            // ASCII8 / KOEI / WIZARDRY (ascii8_tb): no wrap, no SRAM enable bit from the ROM size,
            // SRAM of 8 KB or more (no mirror)
            if (block_info.typ == MAPPER_ASCII8 || block_info.typ == MAPPER_KOEI || block_info.typ == MAPPER_WIZARDY) begin
                block_info.rom_size[24]    = 1'b1;
                block_info.rom_size[20:13] = '0;
                block_info.sram_size[3]    = 1'b1;
            end
            block_info.main_ram_size = 17'($urandom);
            block_info.dram          = 1'($urandom);
            megaSD_en             = 1'($urandom);
            slot1_mode            = 1'($urandom);
            slot2_mode            = 2'($urandom);
            ipl_en                = 1'($urandom);
        end
        hold--;
        addr           = 16'($urandom);
        // ESE_RAM maps 0x4000-0xBFFF only (eseram_tb); the reference mirrored pages 0 and 3
        if (block_info.typ == MAPPER_ESE_RAM) addr[15] = ~addr[14];
        // KONAMI_SCC mirrors pages 1-2 in pages 3 and 0 (konami_scc_tb); the reference did not
        if (block_info.typ == MAPPER_KONAMI_SCC) addr[15] = ~addr[14];
        if (block_info.typ == MAPPER_KONAMI)     addr[15] = ~addr[14];      // mirrors: konami_tb
        if (block_info.typ == MAPPER_GM2)        addr[15] = ~addr[14];
        // FM-PAC (fm_pac_tb): window 4000-7FFF only, register reads alone, FF beside the SRAM:
        // compare in the window, without 7FF6 / 7FF7
        if (block_info.typ == MAPPER_FMPAC) begin
            addr[15:14] = 2'b01;
            if (addr[13:1] == 13'h1FFB) addr[13] = 1'b0;
        end
        cpu_data       = 8'($urandom);
        // WIZARDRY: SRAM bit only for the writable regions (shown read-only elsewhere: ascii8_tb)
        if (block_info.typ == MAPPER_WIZARDY && addr[15:12] == 4'h6) cpu_data[7] = 1'b0;
        if (block_info.typ == MAPPER_GM2 && (addr[15:12] == 4'h6 || addr[15:12] == 4'h8)) cpu_data[4] = 1'b0;
        if (block_info.typ == MAPPER_FMPAC && addr[13:0] == 14'h1FFE && cpu_data == 8'h4D) cpu_data = 8'h4C;   // no SRAM
        data_to_mapper = 8'($urandom);
        // Zemina 90 mode 80h is fixed (zemina90_tb), the reference had it wrong
        if (block_info.typ == MAPPER_ZEMINA_90 && data_to_mapper[7:6] == 2'b10) data_to_mapper[6] = 1'b1;
        flash_q        = 8'($urandom);
        sd_q           = 8'($urandom);
        flash_valid    = ($urandom_range(3) == 0);
        mreq           = ($urandom_range(7) != 0);
        iorq           = ~mreq & 1'($urandom);
        rd             = 1'($urandom);
        wr             = ~rd & 1'($urandom);
        m1             = ($urandom_range(7) == 0);
        req            = 1'($urandom);
        #1 check("comb");
        if (mem_new.ram_cs || mem_new.sram_cs || dev_new.en) active[int'(block_info.typ)]++;
        #4 clk = 1;
        #1 check("reg");
        #4 clk = 0;
    end

    $write("active cycles per type:");
    for (int t = 0; t <= int'(MAPPER_UNUSED); t++) $write(" %0d:%0d", t, active[t]);
    $display("");
    if (errors == 0) $display("PASS mappers_eq_tb (%0d comparisons)", compared);
    else begin
        $display("FAILED mappers_eq_tb: %0d mismatches of %0d", errors, compared);
        foreach (err_typ[t]) $display("  mapper type %0d: %0d mismatches", t, err_typ[t]);
    end
    $finish;
end

endmodule
