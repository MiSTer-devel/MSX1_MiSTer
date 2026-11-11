// memory_upload against a reference revision of itself (module memory_upload_ref, made by
// run_mu_equiv.sh from git): both load the same DDR3 contents through their own ddram and
// DDR3 model with random latency and their own randomly busy SDRAM. After every load all
// results must be equal: slot layout and RAM lookup of all 64 blocks, the 16 RAM entries,
// SRAM, io_device (all 96 entries), io_memory, slot expanders, msx_config, main RAM, error,
// upload / reset / load_sram, and the streams written into the memory and the keyboard map.
//
// One run = one machine pack and a random sequence of OSD actions (+seed): FW pack, mapper
// database, machine pack in a random order, then ROM A / ROM B loads, cartridge type changes,
// eject, database changes, reloads. The reference has the table arrays as ports, the new
// module is read through its layout_id port.
//
// The numbers of the RAM lookup entries (ref_ram) are compared only with +strict: the
// reference starts a load after a stopped one (missing database entry) with the entry counter
// of the stopped run, the module under test from 0. What the entries of the blocks with a
// mapper hold is always compared.
//
// Device limits (MSX::dev_slots, MSX::N_FDC) are applied to the reference result, which has
// the old rules (3 copies, SCC 2; FDC at 0 cartridge A, 1 cartridge B, 2 internal):
// - a load whose reference result needs more copies than built, an FDC cartridge in slot B,
//   or more FDC records than positions must stop with ERR_MISSING_SOURCE / ERR_FDC_PRESENT;
//   only the error is compared and the streams are taken over from the reference. The next
//   load is not compared either: the reference finished the load the new module stopped and
//   carries registers of it (device, last_device_num) into the next one;
// - machine FDC + FDC cartridge A with N_FDC = 1: the new module loads again without
//   cartridge A; the error, the machine FDC at 0 and its drives are compared, the rest is
//   skipped as after a stop;
// - otherwise the FDC of reference position 2 (internal) is at 0, of position 0 (cartridge A)
//   at 1 with N_FDC = 2, else at 0; msx_config.fdd moves with it.
// The FDC records are counted in the reference (tb_fdc_rec, tb_load_start: run_mu_equiv.sh).
//
//   wsl.exe -- bash rtl/tb/run_mu_equiv.sh <packs dir> <CART_FW.msx> <ROM set dir>
`timescale 1ns/1ps

module mu_equiv_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 contents
localparam int unsigned ROM_A_ADDR = MSX::DDR3_ROM_A, ROM_B_ADDR = MSX::DDR3_ROM_B, DB_ADDR = MSX::DDR3_DB, FW_ADDR = MSX::DDR3_FW_PACK;
localparam int NROM = 16, NDB = 8;
byte unsigned pack[$], fw[$], db[$], roma[$], romb[$];
byte unsigned pack_f[$], fw_f[$];
byte unsigned romdata[$], dbdata[$];
int           rom_off[NROM + 1], db_off[NDB + 1], nrom = 0, ndb = 0;

function automatic byte unsigned ddr_byte(input int unsigned a);
    if (a < pack.size())                                  return pack[a];
    if (a >= FW_ADDR && a - FW_ADDR < fw.size())          return fw[a - FW_ADDR];
    if (a >= ROM_A_ADDR && a - ROM_A_ADDR < roma.size())  return roma[a - ROM_A_ADDR];
    if (a >= ROM_B_ADDR && a - ROM_B_ADDR < romb.size())  return romb[a - ROM_B_ADDR];
    if (a >= DB_ADDR && a - DB_ADDR < db.size())          return db[a - DB_ADDR];
    return 8'hFF;
endfunction

// ------------------------------------------------------------------ two ddram + DDR3 models
int          lat_max = 3;
logic        ddr_reset = 1;
wire  [27:0] addr_n, addr_r;
wire   [7:0] dout_n, dout_r;
wire         rd_n, rd_r, ready_n, ready_r, req_n, req_r;
wire  [28:0] DADDR_n, DADDR_r;
wire         DRD_n, DRD_r;
logic [63:0] DOUT_n, DOUT_r;
logic        DRDY_n = 0, DRDY_r = 0;
logic [28:0] ba_n, ba_r;
int          bw_n = -1, bw_r = -1;

ddram ddr_n (
    .reset(ddr_reset), .DDRAM_CLK(clk), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(DADDR_n),
    .DDRAM_DOUT(DOUT_n), .DDRAM_DOUT_READY(DRDY_n), .DDRAM_RD(DRD_n), .DDRAM_DIN(), .DDRAM_BE(), .DDRAM_WE(),
    .addr(addr_n), .dout(dout_n), .din(8'h00), .we(1'b0), .rd(rd_n), .ready(ready_n), .dout64()
);
ddram ddr_r (
    .reset(ddr_reset), .DDRAM_CLK(clk), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(DADDR_r),
    .DDRAM_DOUT(DOUT_r), .DDRAM_DOUT_READY(DRDY_r), .DDRAM_RD(DRD_r), .DDRAM_DIN(), .DDRAM_BE(), .DDRAM_WE(),
    .addr(addr_r), .dout(dout_r), .din(8'h00), .we(1'b0), .rd(rd_r), .ready(ready_r), .dout64()
);

always_ff @(posedge clk) begin
    DRDY_n <= 1'b0;
    if (DRD_n) begin ba_n <= DADDR_n; bw_n <= $urandom_range(0, lat_max); end
    else if (bw_n > 0) bw_n <= bw_n - 1;
    else if (bw_n == 0) begin
        for (int b = 0; b < 8; b++) DOUT_n[8*b +: 8] <= ddr_byte({ba_n[24:0], 3'(b)});
        DRDY_n <= 1'b1; bw_n <= -1;
    end
    DRDY_r <= 1'b0;
    if (DRD_r) begin ba_r <= DADDR_r; bw_r <= $urandom_range(0, lat_max); end
    else if (bw_r > 0) bw_r <= bw_r - 1;
    else if (bw_r == 0) begin
        for (int b = 0; b < 8; b++) DOUT_r[8*b +: 8] <= ddr_byte({ba_r[24:0], 3'(b)});
        DRDY_r <= 1'b1; bw_r <= -1;
    end
end

// ------------------------------------------------------------------ DUT and reference
logic        ioctl_download = 0, rom_eject = 0, reload = 0;
logic [15:0] ioctl_index = '0;
logic [26:0] ioctl_addr = '0;
MSX::config_cart_t cart_conf[2];
logic  [5:0] layout_id = '0;

memory_bus_if            mem_n(), mem_r();
MSX::kb_memory_t         kb_n, kb_r;
MSX::slot_expander_t     exp_n[4], exp_r[4];
MSX::lookup_SRAM_t       sram_n[4], sram_r[4];
MSX::main_ram_t          main_n, main_r;
MSX::io_device_t         dev_n[32][3], dev_r[32][3];
MSX::io_device_mem_ref_t iom_n[8], iom_r[8];
MSX::msx_config_t        cfg_n, cfg_r;
error_t                  err_n, err_r;
wire                     up_n, up_r, ls_n, ls_r, rst_n, rst_r;
MSX::block_t             ab_n;
MSX::lookup_RAM_t        ar_n, mr_n;
MSX::block_t             lay_r[64];
MSX::lookup_RAM_t        ram_r[16];

memory_upload dut (
    .clk(clk), .upload(up_n), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rom_eject(rom_eject), .reload(reload),
    .ddr3_addr(addr_n), .ddr3_rd(rd_n), .ddr3_dout(dout_n), .ddr3_ready(ready_n),
    .ddr3_request(req_n), .memory_bus(mem_n), .kb_upload_memory(kb_n),
    .slot_expander(exp_n), .layout_id(layout_id), .active_block(ab_n), .active_RAM(ar_n), .main_RAM(mr_n),
    .lookup_SRAM(sram_n), .main_ram(main_n), .cart_conf(cart_conf), .io_device(dev_n), .io_memory(iom_n),
    .msx_config(cfg_n), .load_sram(ls_n), .error(err_n), .reset(rst_n)
);

memory_upload_ref ref_i (
    .clk(clk), .upload(up_r), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rom_eject(rom_eject), .reload(reload),
    .ddr3_addr(addr_r), .ddr3_rd(rd_r), .ddr3_dout(dout_r), .ddr3_ready(ready_r),
    .ddr3_request(req_r), .memory_bus(mem_r), .kb_upload_memory(kb_r),
    .slot_expander(exp_r), .slot_layout(lay_r), .lookup_RAM(ram_r),
    .lookup_SRAM(sram_r), .main_ram(main_r), .cart_conf(cart_conf), .io_device(dev_r), .io_memory(iom_r),
    .msx_config(cfg_r), .load_sram(ls_r), .error(err_r), .reset(rst_r)
);

// SDRAM: randomly busy, separately for each
bit   slow = 1;
logic sr_n = 1, sr_r = 1;
always_ff @(posedge clk) begin
    sr_n <= !slow || $urandom_range(0, 3) != 0;
    sr_r <= !slow || $urandom_range(0, 3) != 0;
end
assign mem_n.sdram_ready = sr_n;  assign mem_n.sdram_done = 1'b1;  assign mem_n.q = 8'hFF;
assign mem_r.sdram_ready = sr_r;  assign mem_r.sdram_done = 1'b1;  assign mem_r.q = 8'hFF;

// streams: memory writes, keyboard map writes, pulses
longint unsigned mh_n = 0, mh_r = 0, kh_n = 0, kh_r = 0;
int              mc_n = 0, mc_r = 0, kc_n = 0, kc_r = 0, lsc_n = 0, lsc_r = 0, rsc_n = 0, rsc_r = 0;
int              idle_n = 0, idle_r = 0, bad_bus = 0;
logic            idle_clr = 0;
logic            ls_nq = 0, ls_rq = 0, rst_nq = 0, rst_rq = 0;
always_ff @(posedge clk) begin
    if (mem_n.ram_cs) begin mh_n = (mh_n ^ {29'd0, mem_n.addr, mem_n.data}) * 64'h100000001B3; mc_n++; end
    if (mem_r.ram_cs) begin mh_r = (mh_r ^ {29'd0, mem_r.addr, mem_r.data}) * 64'h100000001B3; mc_r++; end
    if (kb_n.we) begin kh_n = (kh_n ^ {47'd0, kb_n.addr, kb_n.data}) * 64'h100000001B3; kc_n++; end
    if (kb_r.we) begin kh_r = (kh_r ^ {47'd0, kb_r.addr, kb_r.data}) * 64'h100000001B3; kc_r++; end
    if ((mem_n.ram_cs && mem_n.rnw) || mem_n.sram_cs || (mem_r.ram_cs && mem_r.rnw) || mem_r.sram_cs) bad_bus++;
    if (ls_n && !ls_nq) lsc_n++;      ls_nq <= ls_n;
    if (ls_r && !ls_rq) lsc_r++;      ls_rq <= ls_r;
    if (rst_n && !rst_nq) rsc_n++;    rst_nq <= rst_n;
    if (rst_r && !rst_rq) rsc_r++;    rst_rq <= rst_r;
    idle_n <= (idle_clr || rd_n || mem_n.ram_cs || kb_n.we || !ready_n) ? 0 : idle_n + 1;
    idle_r <= (idle_clr || rd_r || mem_r.ram_cs || kb_r.we || !ready_r) ? 0 : idle_r + 1;
end

// FDC block device records of the reference's current load
int   fdc_rec = 0;
always_ff @(posedge clk) begin
    if (ref_i.tb_load_start)   fdc_rec <= 0;
    else if (ref_i.tb_fdc_rec) fdc_rec <= fdc_rec + 1;
end

// ------------------------------------------------------------------ compare
int    errors = 0, compares = 0, limit_stops = 0, after_stop = 0, cart_drops = 0;
bit    stopped = 0;
bit    strict = 0;
MSX::block_t      nlay[64];
MSX::lookup_RAM_t nram[64];
logic [3:0]       shift;
bit               shifted;
int               unowned = 0;
int    maxdiff = 40;
string ctx = "";

`define CMP(what, a, b) begin compares++; if ((a) !== (b)) begin errors++; \
    if (errors <= maxdiff) $display("DIFF [%s] %s: new %0h, ref %0h", ctx, what, a, b); end end

function automatic int ones3(input logic [2:0] m);
    return int'(m[0]) + int'(m[1]) + int'(m[2]);
endfunction

// Machine FDC and FDC cartridge A on the one position: the machine FDC wins
function automatic bit cart_fdc_dropped();
    return MSX::N_FDC == 1 && fdc_rec == 2 &&
           (dev_r[DEV_WD2793][0].enable || dev_r[DEV_TC8566AF][0].enable) &&
           (dev_r[DEV_WD2793][2].enable || dev_r[DEV_TC8566AF][2].enable);
endfunction

// The reference result breaks a limit of this build
function automatic bit over_limit();
    logic [2:0] fdc_at;
    int         npos;
    for (int t = 0; t < 32; t++)
        if (t != DEV_WD2793 && t != DEV_TC8566AF &&
            int'(dev_r[t][0].enable) + int'(dev_r[t][1].enable) + int'(dev_r[t][2].enable) > ones3(MSX::dev_slots(device_t'(t)))) begin
            if ($test$plusargs("v")) $display("| limit: device type %0d, %0d copies", t, int'(dev_r[t][0].enable) + int'(dev_r[t][1].enable) + int'(dev_r[t][2].enable));
            return 1;
        end
    for (int p = 0; p < 3; p++) fdc_at[p] = dev_r[DEV_WD2793][p].enable || dev_r[DEV_TC8566AF][p].enable;
    if (fdc_at[1]) return 1;                                            // cartridge B
    npos = int'(fdc_at[0]) + int'(fdc_at[2]);
    if (cart_fdc_dropped()) return 0;
    if (MSX::N_FDC == 1 ? fdc_rec > 1 : fdc_rec > npos) return 1;       // two FDCs at one position
    if (dev_r[DEV_TC8566AF][2].enable && !MSX::dev_slots(DEV_TC8566AF)[0]) return 1;
    if (dev_r[DEV_TC8566AF][0].enable && !MSX::dev_slots(DEV_TC8566AF)[MSX::N_FDC > 1 ? 1 : 0]) return 1;
    return 0;
endfunction

task automatic compare();
    MSX::io_device_t exp_dev[32][3];
    logic [5:0]      exp_fdd;
    int              cart_pos;
    if (over_limit()) begin
        limit_stops++;
        stopped = 1;
        `CMP("error (limit)", err_n == ERR_MISSING_SOURCE || err_n == ERR_FDC_PRESENT, 1'b1)
        mh_n = mh_r; mc_n = mc_r; kh_n = kh_r; kc_n = kc_r; lsc_n = lsc_r; rsc_n = rsc_r;
        return;
    end
    if (cart_fdc_dropped()) begin
        cart_drops++;
        stopped = 1;
        `CMP("error (machine FDC wins)", err_n, err_r)
        // device_ref follows the record order, which the second load changes
        `CMP("WD2793[0] (machine FDC wins)", {dev_n[DEV_WD2793][0].enable, dev_n[DEV_WD2793][0].param},
                                            {dev_r[DEV_WD2793][2].enable, dev_r[DEV_WD2793][2].param})
        `CMP("TC8566AF[0] (machine FDC wins)", {dev_n[DEV_TC8566AF][0].enable, dev_n[DEV_TC8566AF][0].param},
                                              {dev_r[DEV_TC8566AF][2].enable, dev_r[DEV_TC8566AF][2].param})
        `CMP("msx_config.fdd (machine FDC wins)", cfg_n.fdd, {4'd0, cfg_r.fdd[5:4]})
        mh_n = mh_r; mc_n = mc_r; kh_n = kh_r; kc_n = kc_r; lsc_n = lsc_r; rsc_n = rsc_r;
        return;
    end
    if (stopped) begin                                                  // first load after a stop
        stopped = 0;
        after_stop++;
        mh_n = mh_r; mc_n = mc_r; kh_n = kh_r; kc_n = kc_r; lsc_n = lsc_r; rsc_n = rsc_r;
        return;
    end
    // FDC positions of this build
    cart_pos = MSX::N_FDC > 1 ? 1 : 0;
    exp_dev  = dev_r;
    exp_fdd  = '0;
    for (int j = 0; j < 2; j++) begin
        int t = j ? int'(DEV_TC8566AF) : int'(DEV_WD2793);
        exp_dev[t][0] = dev_r[t][1];                                    // unused entry (the default)
        exp_dev[t][2] = dev_r[t][1];
        if (dev_r[t][2].enable) exp_dev[t][0] = dev_r[t][2];
        if (dev_r[t][0].enable) exp_dev[t][cart_pos] = dev_r[t][0];
    end
    if (dev_r[DEV_WD2793][2].enable || dev_r[DEV_TC8566AF][2].enable) exp_fdd[1:0] = cfg_r.fdd[5:4];
    if (dev_r[DEV_WD2793][0].enable || dev_r[DEV_TC8566AF][0].enable) exp_fdd[2*cart_pos +: 2] = cfg_r.fdd[1:0];
    `CMP("error", err_n, err_r)
    `CMP("upload", up_n, up_r)
    `CMP("reset", rst_n, rst_r)
    `CMP("load_sram", ls_n, ls_r)
    `CMP("reset pulses", rsc_n, rsc_r)
    `CMP("load_sram pulses", lsc_n, lsc_r)
    `CMP("memory writes", mc_n, mc_r)
    `CMP("memory stream", mh_n, mh_r)
    `CMP("keyboard writes", kc_n, kc_r)
    `CMP("keyboard stream", kh_n, kh_r)
    `CMP("bus rnw / sram_cs", bad_bus, 0)
    `CMP("msx_config", {cfg_n.cpu, cfg_n.wait_count, cfg_n.cpu_clock_sel, cfg_n.fdd}, {cfg_r.cpu, cfg_r.wait_count, cfg_r.cpu_clock_sel, exp_fdd})
    `CMP("main_ram.en", main_n.en, main_r.en)
    if (main_r.en) begin
        if (strict) `CMP("main_ram.ref_ram", main_n.ref_ram, main_r.ref_ram)
        `CMP("main_RAM", {mr_n.addr, mr_n.size, mr_n.ro}, {ram_r[main_r.ref_ram].addr, ram_r[main_r.ref_ram].size, ram_r[main_r.ref_ram].ro})
    end
    for (int i = 0; i < 4; i++) begin
        `CMP($sformatf("slot_expander[%0d]", i), {exp_n[i].en, exp_n[i].wo, exp_n[i].init}, {exp_r[i].en, exp_r[i].wo, exp_r[i].init})
        `CMP($sformatf("lookup_SRAM[%0d]", i), {sram_n[i].addr, sram_n[i].size}, {sram_r[i].addr, sram_r[i].size})
    end
    for (int i = 0; i < 8; i++)
        `CMP($sformatf("io_memory[%0d]", i), {iom_n[i].memory, iom_n[i].memory_size}, {iom_r[i].memory, iom_r[i].memory_size})
    for (int t = 0; t < 32; t++)
        for (int k = 0; k < 3; k++)
            `CMP($sformatf("io_device[%0d][%0d] (mask port param mem_ref device_ref enable)", t, k),
                 {dev_n[t][k].mask, dev_n[t][k].port, dev_n[t][k].param, 1'b0, dev_n[t][k].mem_ref, 1'b0, dev_n[t][k].device_ref, 3'b0, dev_n[t][k].enable},
                 {exp_dev[t][k].mask, exp_dev[t][k].port, exp_dev[t][k].param, 1'b0, exp_dev[t][k].mem_ref, 1'b0, exp_dev[t][k].device_ref, 3'b0, exp_dev[t][k].enable})
    if (strict)
        for (int i = 0; i < 16; i++)
            `CMP($sformatf("lookup_RAM[%0d]", i), dut.ram_slots[i], {ram_r[i].addr, ram_r[i].size, ram_r[i].ro})
    // new module: sweep of the read port
    for (int i = 0; i < 64; i++) begin
        layout_id = 6'(i);
        @(negedge clk);
        nlay[i] = ab_n;
        nram[i] = ar_n;
    end
    // Entry numbers of the reference after a stopped load are shifted by its old counter.
    // The shift must be the same for every block that has its own entry.
    shift = '0; shifted = 0;
    if (!strict)
        for (int i = 0; i < 64; i++)
            if (nlay[i].ref_ram != lay_r[i].ref_ram) begin
                if (!shifted) begin shift = lay_r[i].ref_ram - nlay[i].ref_ram; shifted = 1; end
                `CMP($sformatf("ref_ram shift of layout[%0d]", i), 4'(lay_r[i].ref_ram - nlay[i].ref_ram), shift)
            end
    for (int i = 0; i < 64; i++) begin
        MSX::block_t b = lay_r[i];
        `CMP($sformatf("layout[%0d] (ref_ram ref_sram offset device_ref mapper param cart ext)", i),
             {strict ? nlay[i].ref_ram : 4'd0, nlay[i].ref_sram, nlay[i].offset_ram, 1'b0, nlay[i].device_ref, 2'b0, 6'(nlay[i].mapper), 2'b0, nlay[i].mapper_param, 3'b0, nlay[i].cart_num, 3'b0, nlay[i].external},
             {strict ? b.ref_ram : 4'd0, b.ref_sram, b.offset_ram, 1'b0, b.device_ref, 2'b0, 6'(b.mapper), 2'b0, b.mapper_param, 3'b0, b.cart_num, 3'b0, b.external})
        // A block without a mapper has no memory. A block with a mapper but without an entry
        // of its own keeps entry 0 in both; after a shifted start the reference has another
        // block's memory there than after a load from idle (unowned).
        if (strict || (b.mapper != MAPPER_NONE && 4'(b.ref_ram - nlay[i].ref_ram) == shift))
            `CMP($sformatf("active_RAM[%0d]", i), {nram[i].addr, nram[i].size, nram[i].ro}, {ram_r[b.ref_ram].addr, ram_r[b.ref_ram].size, ram_r[b.ref_ram].ro})
        else if (b.mapper != MAPPER_NONE) unowned++;
    end
endtask

// ------------------------------------------------------------------ actions
task automatic load_file(input string name, output byte unsigned d[$]);
    int fd = $fopen(name, "rb"), c;
    d = {};
    if (fd == 0) begin $display("FAILED mu_equiv_tb: cannot open %s", name); $finish; end
    while ((c = $fgetc(fd)) != -1) d.push_back(8'(c));
    $fclose(fd);
endtask

task automatic download(input int idx, input int unsigned size);
    ioctl_index = 16'(idx); ioctl_download = 1;
    @(posedge clk); ioctl_addr = 27'(size);
    @(posedge clk); ioctl_download = 0;
endtask

task automatic do_reload();
    @(posedge clk); reload = 1; @(posedge clk); reload = 0;
endtask

// both loaders finished: not uploading, or stopped on an error (no activity)
task automatic wait_done();
    longint guard = 0;
    idle_clr = 1;                       // a loader stopped on an earlier error starts again
    repeat (20) @(posedge clk);
    idle_clr = 0;
    while (!((!up_n || idle_n > 3000) && (!up_r || idle_r > 3000))) begin
        @(posedge clk);
        guard = guard + 1;
        if (guard > 400_000_000) begin $display("FAILED mu_equiv_tb: timeout [%s]", ctx); $finish; end
    end
    repeat (20) @(posedge clk);
endtask

task automatic set_rom(input int k, output byte unsigned d[$]);
    d = {};
    if (k >= 0) for (int i = rom_off[k]; i < rom_off[k + 1]; i++) d.push_back(romdata[i]);
endtask

task automatic set_db(input int k);
    db = {};
    if (k >= 0) for (int i = db_off[k]; i < db_off[k + 1]; i++) db.push_back(dbdata[i]);
    download(6, db.size());
endtask

function automatic cart_typ_t rnd_cart();
    int r = $urandom_range(0, 99);
    if (r < 40) return CART_TYP_ROM;
    if (r < 55) return CART_TYP_EMPTY;
    return cart_typ_t'($urandom_range(0, 10));
endfunction

int stat_err[16];

task automatic finish_step(input string what);
    ctx = what;
    wait_done();
    compare();
    stat_err[err_r]++;
    if ($test$plusargs("v"))
        $display("| %-34s error %0d/%0d  mem writes %0d  cart %0d %0d  rom %0d %0d  db %0d", what, err_n, err_r, mc_r,
                 cart_conf[0].typ, cart_conf[1].typ, roma.size(), romb.size(), db.size());
endtask

initial begin
    string name, pack_name;
    byte unsigned tmp[$];
    int seed = 1, steps = 12, order, k;

    void'($value$plusargs("seed=%d", seed));
    void'($value$plusargs("steps=%d", steps));
    void'($value$plusargs("lat=%d", lat_max));
    if ($test$plusargs("fast")) slow = 0;
    if ($test$plusargs("strict")) strict = 1;
    void'($value$plusargs("maxdiff=%d", maxdiff));
    if (!$value$plusargs("pack=%s", pack_name)) begin $display("usage: +pack= +fw= +rom0=.. +db0=.. +seed="); $finish; end
    load_file(pack_name, pack_f);
    if ($value$plusargs("fw=%s", name)) load_file(name, fw_f);
    for (int i = 0; i < NROM; i++)
        if ($value$plusargs($sformatf("rom%0d=%%s", i), name)) begin
            load_file(name, tmp);
            rom_off[nrom] = romdata.size();
            foreach (tmp[j]) romdata.push_back(tmp[j]);
            nrom++; rom_off[nrom] = romdata.size();
        end
    for (int i = 0; i < NDB; i++)
        if ($value$plusargs($sformatf("db%0d=%%s", i), name)) begin
            load_file(name, tmp);
            db_off[ndb] = dbdata.size();
            foreach (tmp[j]) dbdata.push_back(tmp[j]);
            ndb++; db_off[ndb] = dbdata.size();
        end
    // the whole scenario is drawn before the clock runs (the models draw from the same generator)
    void'($urandom(seed));
    begin
        int        act[], pk[];
        cart_typ_t pa[], pb[];
        bit        pf[];
        int        db0;
        act = new[steps]; pk = new[steps]; pa = new[steps]; pb = new[steps]; pf = new[steps];
        cart_conf[0].typ = rnd_cart();
        cart_conf[1].typ = rnd_cart();
        order = $urandom_range(0, 7);
        db0   = (ndb > 0 && $urandom_range(0, 3) != 0) ? $urandom_range(0, ndb - 1) : -1;
        for (int i = 0; i < steps; i++) begin
            act[i] = $urandom_range(0, 19);
            pk[i]  = $urandom_range(0, 15);
            pa[i]  = rnd_cart();
            pb[i]  = rnd_cart();
            pf[i]  = $urandom_range(0, 3) != 0;
        end

        repeat (4) @(posedge clk);
        ddr_reset = 0;
        repeat (8) @(posedge clk);

        // HPS start: FW pack, mapper database and machine pack, in a random order
        for (int i = 0; i < 3; i++) begin
            case ((i + order) % 3)
                0: if (fw_f.size() > 0 && order != 7) begin fw = fw_f; download(2, fw.size()); finish_step("FW pack"); end
                1: if (db0 >= 0) set_db(db0);
                2: begin pack = pack_f; download(1, pack.size()); finish_step("machine pack"); end
            endcase
        end

        for (int s = 0; s < steps; s++) begin
            if (act[s] < 6) begin                                // ROM A
                k = nrom > 0 ? pk[s] % (nrom + 1) - 1 : -1;
                set_rom(k, roma);
                download(3, roma.size());
                finish_step($sformatf("step %0d: ROM A %0d", s, k));
            end else if (act[s] < 10) begin                      // ROM B
                k = nrom > 0 ? pk[s] % (nrom + 1) - 1 : -1;
                set_rom(k, romb);
                download(4, romb.size());
                finish_step($sformatf("step %0d: ROM B %0d", s, k));
            end else if (act[s] < 14) begin                      // cartridge types (OSD), core reloads
                cart_conf[0].typ = pa[s];
                cart_conf[1].typ = pb[s];
                do_reload();
                finish_step($sformatf("step %0d: cartridges %0d %0d", s, cart_conf[0].typ, cart_conf[1].typ));
            end else if (act[s] < 15) begin                      // eject
                roma = {}; romb = {};
                @(posedge clk); rom_eject = 1; @(posedge clk); rom_eject = 0;
                finish_step($sformatf("step %0d: eject", s));
            end else if (act[s] < 17) begin                      // other / no database, then reload
                k = ndb > 0 ? pk[s] % (ndb + 1) - 1 : -1;
                set_db(k);
                repeat (4) @(posedge clk);
                do_reload();
                finish_step($sformatf("step %0d: database %0d", s, k));
            end else if (act[s] < 18) begin                      // FW pack again (or removed)
                if (pf[s]) fw = fw_f; else fw = {};
                download(2, fw.size());
                finish_step($sformatf("step %0d: FW pack %0d B", s, fw.size()));
            end else if (act[s] < 19) begin                      // machine pack again
                pack = pack_f;
                download(1, pack.size());
                finish_step($sformatf("step %0d: machine pack", s));
            end else begin
                do_reload();
                finish_step($sformatf("step %0d: reload", s));
            end
        end
    end

    $write("%s mu_equiv seed %0d: %0d compares, %0d differences, %0d limit stops, %0d FDC cartridges left out (%0d next loads skipped); errors seen:", errors ? "FAIL" : "PASS", seed, compares, errors, limit_stops, cart_drops, after_stop);
    for (int i = 0; i < 16; i++) if (stat_err[i] > 0) $write(" %0d x%0d", i, stat_err[i]);
    $display("");
    $finish;
end

endmodule
