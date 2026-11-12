// memory_upload: loads an MSX pack (createComp.py output) from a DDR3 model through
// ddram, prints the resulting tables and checks the OCM configuration
// (tools/CreateMSXpack/Computer/OCM/1chipMSX.xml).
// Optional FW pack (createDev.py output, DDR 300000h) and cartridge type of slot 2:
// +fw=<CART_FW_EN.msx> +cartb=<cart_typ_t>.
// OCM has no cartridge slots: slots 1 and 2 hold the internal ESE-SCC / MegaRAM (machine
// blocks, pages 1-2, 1 MB / 2 MB RAM, mapper MEGARAM, own SCC), independent of FW and cartb.
// Run: wsl.exe -- bash rtl/tb/run_memory_upload.sh <pack.msx> <ocm_iplrom.rom> [fw.msx cartb]
module memory_upload_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 model + ddram
localparam int LAT = 5;
byte unsigned pack[$];
byte unsigned ipl[$];
byte unsigned fw[$];

wire  [27:0] ddr3_addr;
wire   [7:0] ddr3_dout;
wire  [63:0] ddr3_dout64;
wire         ddr3_rd, ddr3_ready, ddr3_request;

logic  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
logic [28:0] DDRAM_ADDR;
logic [63:0] DDRAM_DOUT, DDRAM_DIN;
logic        DDRAM_DOUT_READY = 0, DDRAM_RD, DDRAM_WE;
logic        ddr_reset = 1;

ddram ddr (
    .reset(ddr_reset), .DDRAM_CLK(clk), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .addr(ddr3_addr), .dout(ddr3_dout), .din(8'h00), .we(1'b0), .rd(ddr3_rd), .ready(ddr3_ready),
    .dout64(ddr3_dout64)
);

logic [28:0] rd_addr;
int          rd_wait = -1;
always_ff @(posedge clk) begin
    DDRAM_DOUT_READY <= 1'b0;
    if (DDRAM_RD) begin rd_addr <= DDRAM_ADDR; rd_wait <= LAT; end
    else if (rd_wait > 0) rd_wait <= rd_wait - 1;
    else if (rd_wait == 0) begin
        for (int b = 0; b < 8; b++) begin
            int unsigned a = {rd_addr[24:0], 3'(b)};
            DDRAM_DOUT[8*b +: 8] <= (a < pack.size()) ? pack[a] :
                                    (a >= 32'h300000 && a - 32'h300000 < fw.size()) ? fw[a - 32'h300000] : 8'hFF;
        end
        DDRAM_DOUT_READY <= 1'b1;
        rd_wait <= -1;
    end
end

// ------------------------------------------------------------------ DUT
logic        ioctl_download = 0;
logic [15:0] ioctl_index = '0;
logic [26:0] ioctl_addr = '0;
memory_bus_if mem();
MSX::kb_memory_t         kb_upload_memory;
MSX::slot_expander_t     slot_expander[4];
MSX::block_t             slot_layout[64];
MSX::lookup_RAM_t        lookup_RAM[16];
logic              [5:0] layout_id = '0;
MSX::block_t             active_block;
MSX::lookup_RAM_t        active_RAM, main_RAM;

// The tables of the loader into slot_layout / lookup_RAM: a sweep of its read port
task automatic snapshot();
`ifndef OLD_MU
    for (int i = 0; i < 64; i++) begin
        layout_id = 6'(i);
        @(negedge clk);
        slot_layout[i] = active_block;
        lookup_RAM[active_block.ref_ram] = active_RAM;
    end
`endif
endtask
MSX::lookup_SRAM_t       lookup_SRAM[4];
MSX::config_cart_t       cart_conf[2];
MSX::io_device_t         io_device[32][3];
MSX::io_device_mem_ref_t io_memory[8];
MSX::msx_config_t        msx_config;
error_t                  error;
wire                     upload, load_sram, upload_reset;

memory_upload dut (
    .clk(clk), .upload(upload), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rom_eject(1'b0), .reload(1'b0),
    .ddr3_addr(ddr3_addr), .ddr3_rd(ddr3_rd), .ddr3_dout(ddr3_dout), .ddr3_ready(ddr3_ready),
    .ddr3_request(ddr3_request), .memory_bus(mem), .kb_upload_memory(kb_upload_memory),
    .slot_expander(slot_expander),
`ifdef OLD_MU                       // reference revision: the tables as arrays
    .slot_layout(slot_layout), .lookup_RAM(lookup_RAM),
`else
    .layout_id(layout_id), .active_block(active_block), .active_RAM(active_RAM), .main_RAM(main_RAM),
`endif
    .lookup_SRAM(lookup_SRAM), .cart_conf(cart_conf), .io_device(io_device), .io_memory(io_memory),
    .msx_config(msx_config), .load_sram(load_sram), .error(error), .reset(upload_reset)
);

// System memory model: always ready, writes are recorded
assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;
assign mem.q           = 8'hFF;
byte unsigned ram[int unsigned];
int unsigned  ram_lo = 32'hFFFF_FFFF, ram_hi = 0;
always_ff @(posedge clk)
    if (mem.ram_cs && !mem.rnw) begin
        ram[mem.addr] = mem.data;
        if (mem.addr < ram_lo) ram_lo = mem.addr;
        if (mem.addr > ram_hi) ram_hi = mem.addr;
    end

// ------------------------------------------------------------------ checks
int errors = 0;

function automatic int unsigned page_addr(input int s, input int ss, input int p);
    MSX::block_t b = slot_layout[{2'(s), 2'(ss), 2'(p)}];
    return lookup_RAM[b.ref_ram].addr + 32'(b.offset_ram) * 16384;
endfunction

task automatic expect_page(input string what, input int s, input int ss, input int p,
                           input mapper_typ_t m, input int unsigned addr, input logic ro);
    MSX::block_t b = slot_layout[{2'(s), 2'(ss), 2'(p)}];
    if (b.mapper !== m || page_addr(s, ss, p) !== addr || lookup_RAM[b.ref_ram].ro !== ro) begin
        errors++;
        $display("FAIL %-22s %0d-%0d page %0d: mapper=%0d addr=%07h ro=%b (expected mapper=%0d addr=%07h ro=%b)",
                 what, s, ss, p, b.mapper, page_addr(s, ss, p), lookup_RAM[b.ref_ram].ro, m, addr, ro);
    end
endtask

task automatic expect_dev(input string what, input device_t d, input logic [7:0] port,
                          input logic [7:0] mask, input logic [7:0] param);
    MSX::io_device_t io = io_device[d][0];
    if (!io.enable || io.port !== port || io.mask !== mask || io.param !== param) begin
        errors++;
        $display("FAIL device %-12s en=%b port=%02h mask=%02h param=%02h (expected port=%02h mask=%02h param=%02h)",
                 what, io.enable, io.port, io.mask, io.param, port, mask, param);
    end
endtask

initial begin
    string pack_name, ipl_name, fw_name;
    int fd, c, cartb = int'(CART_TYP_ROM);
    int unsigned ese;

    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("ipl=%s", ipl_name)) begin
        $display("usage: +pack=<file.msx> +ipl=<ocm_iplrom.rom>"); $finish;
    end
    fd = $fopen(pack_name, "rb");
    if (fd == 0) begin $display("cannot open %s", pack_name); $finish; end
    while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c));
    $fclose(fd);
    fd = $fopen(ipl_name, "rb");
    if (fd == 0) begin $display("cannot open %s", ipl_name); $finish; end
    while ((c = $fgetc(fd)) != -1) ipl.push_back(8'(c));
    $fclose(fd);
    if ($value$plusargs("fw=%s", fw_name)) begin
        fd = $fopen(fw_name, "rb");
        if (fd == 0) begin $display("cannot open %s", fw_name); $finish; end
        while ((c = $fgetc(fd)) != -1) fw.push_back(8'(c));
        $fclose(fd);
    end
    void'($value$plusargs("cartb=%d", cartb));
    $display("pack %0d bytes, IPL %0d bytes, FW %0d bytes, cartridge B type %0d", pack.size(), ipl.size(), fw.size(), cartb);

    // ROM cartridges without an image: empty slots that do not need the FW pack
    cart_conf[0].typ = CART_TYP_ROM;
    cart_conf[1].typ = cart_typ_t'(cartb);
    repeat (4) @(posedge clk);
    ddr_reset = 0;
    repeat (4) @(posedge clk);

    // HPS download of the FW pack (index 2), as at core start
    if (fw.size() > 0) begin
        ioctl_index = 16'd2; ioctl_download = 1;
        @(posedge clk); ioctl_addr = 27'(fw.size());
        @(posedge clk); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
        wait (upload);
        wait (!upload);
        repeat (10) @(posedge clk);
    end

    // HPS download of the MSX pack (index 1)
    ioctl_index = 16'd1; ioctl_download = 1;
    @(posedge clk); ioctl_addr = 27'(pack.size());
    @(posedge clk); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
    wait (upload);
    wait (!upload);
    repeat (10) @(posedge clk);
    snapshot();
    $display("upload finished at %0t, error=%0d, RAM written %07h..%07h", $time, error, ram_lo, ram_hi);

    // ---- dump
    for (int s = 0; s < 4; s++)
        $display("slot %0d expander en=%b init=%02h", s, slot_expander[s].en, slot_expander[s].init);
    for (int i = 0; i < 64; i++)
        if (slot_layout[i].mapper != MAPPER_NONE || slot_layout[i].cart_num)
            $display("layout %0d-%0d p%0d: mapper=%0d ref_ram=%0d offset=%0d dev_ref=%0d addr=%07h size=%05h ro=%b",
                     i[5:4], i[3:2], i[1:0], slot_layout[i].mapper, slot_layout[i].ref_ram,
                     slot_layout[i].offset_ram, slot_layout[i].device_ref,
                     page_addr(i[5:4], i[3:2], i[1:0]), lookup_RAM[slot_layout[i].ref_ram].size,
                     lookup_RAM[slot_layout[i].ref_ram].ro);
    for (int d = 0; d < 32; d++)
        for (int k = 0; k < 3; k++)
            if (io_device[d][k].enable)
                $display("device %0d[%0d]: port=%02h mask=%02h param=%02h mem_ref=%0d dev_ref=%0d",
                         d, k, io_device[d][k].port, io_device[d][k].mask, io_device[d][k].param,
                         io_device[d][k].mem_ref, io_device[d][k].device_ref);

    // ---- OCM checks
    if (error != ERR_NONE) begin errors++; $display("FAIL error %0d", error); end
    if (msx_config.wait_count != 3'd1) begin errors++; $display("FAIL wait_count %0d", msx_config.wait_count); end
    if (!slot_expander[3].en || slot_expander[3].init != 8'h2B) begin errors++; $display("FAIL slot 3 expander"); end
    if (!slot_expander[0].en) begin errors++; $display("FAIL slot 0 expander"); end

    ese = page_addr(3, 2, 1);
    for (int p = 0; p < 4; p++) expect_page("RAM mapper", 3, 0, p, MAPPER_MSX2, page_addr(3, 0, 0) + p * 16384, 1'b0);
    for (int p = 1; p < 3; p++)
        if (slot_layout[{2'd3, 2'd2, 2'(p)}].mapper !== MAPPER_ESE_RAM) begin errors++; $display("FAIL ESE-RAM 3-2 page %0d", p); end
    for (int p = 0; p < 3; p++) expect_page("EXT + Kanji BASIC", 3, 1, p, MAPPER_OFFSET, ese + 32'h30000 + p * 16384, 1'b1);
    expect_page("XBASIC", 3, 3, 1, MAPPER_OFFSET, ese + 32'h28000, 1'b1);
    for (int p = 0; p < 2; p++) expect_page("MAIN", 0, 0, p, MAPPER_OFFSET, ese + 32'h20000 + p * 16384, 1'b1);
    expect_page("OPLL ROM", 0, 2, 1, MAPPER_OFFSET, ese + 32'h2C000, 1'b1);
    expect_page("FREE ROM", 0, 3, 1, MAPPER_OFFSET, ese + 32'h3C000, 1'b1);
    // ESE-RAM (512 kB) must not overlap the 4 MB mapper RAM
    if (!(ese + 32'h80000 <= page_addr(3, 0, 0) || page_addr(3, 0, 0) + 32'h400000 <= ese)) begin
        errors++; $display("FAIL ESE-RAM %07h overlaps RAM mapper %07h", ese, page_addr(3, 0, 0));
    end
    // Internal ESE-SCC / MegaRAM in slots 1 and 2
    for (int sl = 1; sl <= 2; sl++) begin
        MSX::block_t b = slot_layout[{2'(sl), 2'd0, 2'd1}];
        bit scc = 0;
        for (int p = 0; p < 4; p++)
            if (slot_layout[{2'(sl), 2'd0, 2'(p)}].mapper !== ((p == 1 || p == 2) ? MAPPER_MEGARAM : MAPPER_NONE)) begin
                errors++; $display("FAIL slot %0d page %0d: mapper=%0d", sl, p, slot_layout[{2'(sl), 2'd0, 2'(p)}].mapper);
            end
        if (slot_layout[{2'(sl), 2'd0, 2'd2}].ref_ram !== b.ref_ram || slot_layout[{2'(sl), 2'd0, 2'd2}].device_ref !== b.device_ref) begin
            errors++; $display("FAIL slot %0d: pages 1 and 2 are different blocks", sl);
        end
        if (lookup_RAM[b.ref_ram].size !== (sl == 1 ? 17'd128 : 17'd256) || lookup_RAM[b.ref_ram].ro !== 1'b0) begin
            errors++; $display("FAIL slot %0d RAM size=%0d x 8 kB ro=%b (expected %0d, 0)", sl, lookup_RAM[b.ref_ram].size,
                               lookup_RAM[b.ref_ram].ro, sl == 1 ? 128 : 256);
        end
        for (int k = 0; k < 3; k++)
            if (io_device[DEV_SCC][k].enable && io_device[DEV_SCC][k].device_ref == b.device_ref) scc = 1;
        if (!scc) begin errors++; $display("FAIL slot %0d: no SCC device for the block (dev_ref %0d)", sl, b.device_ref); end
        $display("slot %0d: mapper %0d, RAM %07h, size %0d x 8 kB, SCC dev_ref %0d", sl, b.mapper, page_addr(sl, 0, 1),
                 lookup_RAM[b.ref_ram].size, b.device_ref);
    end
    if (slot_layout[{2'd1, 2'd0, 2'd1}].device_ref == slot_layout[{2'd2, 2'd0, 2'd1}].device_ref) begin
        errors++; $display("FAIL slots 1 and 2 share one SCC (dev_ref %0d)", slot_layout[{2'd1, 2'd0, 2'd1}].device_ref);
    end

    expect_dev("V9958",        DEV_VDP_V99xx,     8'h98, 8'hFC, 8'h02);
    expect_dev("PSG",          DEV_PSG,           8'hA0, 8'hF8, 8'h01);
    expect_dev("PPI",          DEV_PPI,           8'hA8, 8'hF8, 8'h01);
    expect_dev("RTC",          DEV_RTC,           8'hB4, 8'hFE, 8'h00);
    expect_dev("OPLL",         DEV_OPLL,          8'h7C, 8'hFE, 8'h00);
    expect_dev("RESET_STATUS", DEV_RESET_STATUS,  8'hF4, 8'hFF, 8'h01);
    expect_dev("SYSTIMER",     DEV_SYSTIMER,      8'hE6, 8'hFE, 8'h00);
    expect_dev("MEM_MAPPER",   DEV_MSX2_RAM,      8'hFC, 8'hFC, 8'h00);
    if (!io_device[DEV_OCM_BOOT][0].enable) begin errors++; $display("FAIL OCM_BOOT not enabled"); end
    // Kanji font JIS1+JIS2: 256 kB window into ESE-RAM at 40000h
    expect_dev("KANJI", DEV_KANJI, 8'hD8, 8'hFC, 8'h00);
    if (io_memory[io_device[DEV_KANJI][0].mem_ref].memory !== ese + 32'h40000 ||
        io_memory[io_device[DEV_KANJI][0].mem_ref].memory_size !== 8'd16) begin
        errors++;
        $display("FAIL KANJI memory %07h size %0d (expected %07h, 16)", io_memory[io_device[DEV_KANJI][0].mem_ref].memory,
                 io_memory[io_device[DEV_KANJI][0].mem_ref].memory_size, ese + 32'h40000);
    end
    // IPL ROM: slot 3-3 page 0, mapper OCM_IPL, read-only, content in memory
    if (slot_layout[{2'd3, 2'd3, 2'd0}].mapper !== MAPPER_OCM_IPL || lookup_RAM[slot_layout[{2'd3, 2'd3, 2'd0}].ref_ram].ro !== 1'b1) begin
        errors++; $display("FAIL IPL block 3-3 page 0: mapper=%0d", slot_layout[{2'd3, 2'd3, 2'd0}].mapper);
    end else begin
        int unsigned m = page_addr(3, 3, 0);
        int bad = 0;
        foreach (ipl[i]) if (!ram.exists(m + i) || ram[m + i] !== ipl[i]) bad++;
        if (bad) begin errors++; $display("FAIL IPL in memory at %07h: %0d bytes differ", m, bad); end
        else $display("IPL at %07h, %0d bytes OK", m, ipl.size());
    end

    if (errors == 0) $display("PASS memory_upload_tb (OCM)");
    else             $display("FAILED memory_upload_tb: %0d errors", errors);
    $finish;
end

initial begin
    #400_000_000;
    $display("FAILED memory_upload_tb: timeout (upload=%b)", upload);
    $finish;
end

endmodule
