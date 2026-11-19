// Configuration report in the DDR3 (cfg_report + memory_upload + ddram, Verilator --timing).
// After each configuration run the report at MSX::DDR3_INFO must say how each cartridge slot
// was configured: source, FW ID, CRC32 of the ROM, the error. The report is written valid = 0
// first and valid = 1 last; a load during the report ends it, the next report follows.
// DDR3 port shared as in msx_system: report > memory_upload (no cassette here).
// Build and run: wsl.exe -- bash rtl/tb/run_cfg_report.sh <VG_8020 pack> <CART_FW_EN.msx>
//   EXTRA="+busy": DDR3 randomly busy; "+fdcpack=<NMS_8245 pack>": FDC cartridge left out

`timescale 1ns/1ps

module cfg_report_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 model + ddram
localparam int LAT = 5;
int unsigned ROM_A_ADDR, ROM_B_ADDR, DB_ADDR, FW_ADDR;
byte unsigned pack[$], fw[$], rom[$], rom_b[$], db[$];
int          stamp_fw = 0, stamp_a = 0, stamp_b = 0, stamp_db = 0, stamp_n = 0;
byte unsigned wmem[int unsigned];               // bytes written by the core
int          wlog_off[$], wlog_val[$];          // writes into the report area, in order

logic  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
logic [28:0] DDRAM_ADDR;
logic [63:0] DDRAM_DOUT, DDRAM_DIN;
logic        DDRAM_DOUT_READY = 0, DDRAM_RD, DDRAM_WE;
logic        ddr_reset = 1;
logic        busy_en = 0, DDRAM_BUSY = 0;

wire  [27:0] mu_addr, rp_addr;
wire         mu_rd, mu_request, rp_request, rp_we;
wire   [7:0] rp_din, ddr3_dout;
wire         ddr3_ready;
wire  [27:0] ddr3_addr = rp_request ? rp_addr : mu_addr;
wire         ddr3_rd   = rp_request ? 1'b0    : mu_rd;
wire         ddr3_we   = rp_request && rp_we;

ddram ddr (
    .reset(ddr_reset), .DDRAM_CLK(clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .addr(ddr3_addr), .dout(ddr3_dout), .din(rp_din), .we(ddr3_we), .rd(ddr3_rd), .ready(ddr3_ready),
    .dout64()
);

function automatic byte unsigned ddr_byte(input int unsigned a);
    int best = 0;
    byte unsigned v = 8'hFF;
    if (wmem.exists(a)) return wmem[a];
    if (a < pack.size()) return pack[a];
    if (a >= FW_ADDR    && a - FW_ADDR    < fw.size()    && stamp_fw > best) begin best = stamp_fw; v = fw[a - FW_ADDR];       end
    if (a >= ROM_A_ADDR && a - ROM_A_ADDR < rom.size()   && stamp_a  > best) begin best = stamp_a;  v = rom[a - ROM_A_ADDR];   end
    if (a >= ROM_B_ADDR && a - ROM_B_ADDR < rom_b.size() && stamp_b  > best) begin best = stamp_b;  v = rom_b[a - ROM_B_ADDR]; end
    if (a >= DB_ADDR    && a - DB_ADDR    < db.size()    && stamp_db > best) begin best = stamp_db; v = db[a - DB_ADDR];       end
    return v;
endfunction

logic [28:0] rd_addr;
int          rd_wait = -1;
always_ff @(posedge clk) begin
    DDRAM_DOUT_READY <= 1'b0;
    DDRAM_BUSY <= busy_en && $urandom_range(3) == 0;
    if (DDRAM_WE && !DDRAM_BUSY)
        for (int b = 0; b < 8; b++) if (DDRAM_BE[b]) begin
            int unsigned a = {DDRAM_ADDR[24:0], 3'(b)};
            wmem[a] = DDRAM_DIN[8*b +: 8];
            if (a >= MSX::DDR3_INFO && a < MSX::DDR3_INFO + 4096) begin
                wlog_off.push_back(int'(a - MSX::DDR3_INFO));
                wlog_val.push_back(int'(DDRAM_DIN[8*b +: 8]));
            end
        end
    if (DDRAM_RD && !DDRAM_BUSY) begin rd_addr <= DDRAM_ADDR; rd_wait <= LAT; end
    else if (rd_wait > 0) rd_wait <= rd_wait - 1;
    else if (rd_wait == 0) begin
        for (int b = 0; b < 8; b++) DDRAM_DOUT[8*b +: 8] <= ddr_byte({rd_addr[24:0], 3'(b)});
        DDRAM_DOUT_READY <= 1'b1;
        rd_wait <= -1;
    end
end

// ------------------------------------------------------------------ DUT
logic        ioctl_download = 0;
logic [15:0] ioctl_index = '0;
logic [26:0] ioctl_addr = '0;
logic        rom_eject = 0, reload = 0;
memory_bus_if mem();
MSX::kb_memory_t         kb_upload_memory;
MSX::slot_expander_t     slot_expander[4];
MSX::block_t             active_block;
MSX::lookup_RAM_t        active_RAM, main_RAM;
MSX::lookup_SRAM_t       lookup_SRAM[4];
MSX::main_ram_t          main_ram;
MSX::config_cart_t       cart_conf[2];
MSX::io_device_t         io_device[32][3];
MSX::io_device_mem_ref_t io_memory[8];
MSX::msx_config_t        msx_config;
MSX::cart_report_t       cart_report[2];
error_t                  error;
wire                     upload, load_sram, upload_reset, mu_done;

memory_upload mu (
    .clk(clk), .upload(upload), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rom_eject(rom_eject), .reload(reload),
    .ddr3_addr(mu_addr), .ddr3_rd(mu_rd), .ddr3_dout(ddr3_dout), .ddr3_ready(ddr3_ready),
    .ddr3_request(mu_request), .memory_bus(mem), .kb_upload_memory(kb_upload_memory),
    .slot_expander(slot_expander), .layout_id(6'd0), .active_block(active_block),
    .active_RAM(active_RAM), .main_RAM(main_RAM), .lookup_SRAM(lookup_SRAM), .main_ram(main_ram),
    .cart_conf(cart_conf), .sdram_sz(16'h0000), .io_device(io_device), .io_memory(io_memory),
    .msx_config(msx_config), .load_sram(load_sram), .error(error), .reset(upload_reset),
    .done(mu_done), .cart_report(cart_report)
);

cfg_report rpt (
    .clk(clk), .done(mu_done), .mu_rd(mu_rd), .error(error), .cart(cart_report),
    .ddr3_ready(ddr3_ready), .ddr3_request(rp_request), .ddr3_addr(rp_addr), .ddr3_din(rp_din),
    .ddr3_we(rp_we)
);

assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;
assign mem.q           = 8'hFF;

// ------------------------------------------------------------------ helpers
int errors = 0;
int last_gen = -1;

function automatic logic [31:0] crc32(input byte unsigned d[$]);
    logic [31:0] c = '1;
    foreach (d[i]) begin
        c ^= 32'(d[i]);
        for (int k = 0; k < 8; k++) c = c[0] ? (c >> 1) ^ 32'hEDB88320 : c >> 1;
    end
    return ~c;
endfunction

function automatic logic [31:0] crc_or_0(input byte unsigned d[$]);
    return d.size() ? crc32(d) : 32'd0;
endfunction

task automatic download(input int idx, input int unsigned size);
    stamp_n++;
    case (idx)
        2: stamp_fw = stamp_n;
        3: stamp_a  = stamp_n;
        4: stamp_b  = stamp_n;
        6: stamp_db = stamp_n;
        default: ;
    endcase
    ioctl_index = 16'(idx); ioctl_download = 1;
    @(posedge clk); ioctl_addr = 27'(size);
    @(posedge clk); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;
    repeat (10) @(posedge clk);
endtask

task automatic pulse(ref logic s);
    @(posedge clk); s = 1; @(posedge clk); s = 0;
    repeat (10) @(posedge clk);
endtask

// ROM of size bytes: 'AB' + INIT at offset hdr (-1: none), a pattern from seed elsewhere
function automatic void make_rom(ref byte unsigned r[$], input int size, input int hdr, input logic [15:0] init, input int seed);
    r = {};
    for (int i = 0; i < size; i++) r.push_back(8'(i * 7 + (i >> 9) + seed));
    for (int i = 0; i < size; i += 16384) begin r[i] = 8'h00; r[i + 1] = 8'h00; end
    if (hdr >= 0) begin r[hdr] = 8'h41; r[hdr + 1] = 8'h42; r[hdr + 2] = init[7:0]; r[hdr + 3] = init[15:8]; end
endfunction

function automatic void db_entry(input logic [31:0] crc, input int fw_id);
    db = {crc[7:0], crc[15:8], crc[23:16], crc[31:24], 8'(fw_id), 8'h00, 8'h00, 8'h00};
endfunction

// memory_upload done again and the report written
task automatic wait_report();
    repeat (3) @(posedge clk);
    wait (mu_done);
    repeat (3) @(posedge clk);
    wait (mu_done && !rp_request && !rpt.pending);
    // ddram is ready again while the DDR3 still holds off its last write (BUSY)
    do @(posedge clk); while (DDRAM_WE || !ddr3_ready);
    repeat (3) @(posedge clk);
endtask

function automatic int rb(input int off);
    int unsigned a = MSX::DDR3_INFO + off;
    return wmem.exists(a) ? int'(wmem[a]) : -1;
endfunction

function automatic logic [31:0] rcrc(input int off);
    return {8'(rb(off + 3)), 8'(rb(off + 2)), 8'(rb(off + 1)), 8'(rb(off))};
endfunction

// The last report: header, order of its writes, its content
task automatic check(input string what, input error_t err,
                     input MSX::cart_src_t src_a, input int fw_a, input logic [31:0] crc_a,
                     input MSX::cart_src_t src_b, input int fw_b, input logic [31:0] crc_b);
    int bad = errors;
    int n = wlog_off.size();
    if (rb(0) != 8'h4D || rb(1) != 8'h53 || rb(2) != 8'h58 || rb(3) != 8'h52 || rb(5) != 1)
        begin errors++; $display("FAIL %s: header %0h %0h %0h %0h version %0d", what, rb(0), rb(1), rb(2), rb(3), rb(5)); end
    if (rb(4) != 1) begin errors++; $display("FAIL %s: valid %0d", what, rb(4)); end
    if (last_gen >= 0 && rb(6) != ((last_gen + 1) & 255))
        begin errors++; $display("FAIL %s: generation %0d after %0d", what, rb(6), last_gen); end
    // the report of this check: from the last valid = 0 to valid = 1 at the end
    if (n < 22 || wlog_off[n - 1] != 4 || wlog_val[n - 1] != 1 || wlog_off[n - 22] != 4 || wlog_val[n - 22] != 0) begin
        string s = "";
        foreach (wlog_off[i]) s = {s, $sformatf(" %0d=%0h", wlog_off[i], wlog_val[i])};
        errors++; $display("FAIL %s: report writes not 'valid 0, 20 bytes, valid 1' (%0d writes):%s", what, n, s);
    end
    else for (int i = 0; i < 20; i++)
        if (wlog_off[n - 21 + i] != i) begin errors++; $display("FAIL %s: write %0d to offset %0d", what, i, wlog_off[n - 21 + i]); break; end
    if (rb(7) != int'(err)) begin errors++; $display("FAIL %s: error %0d (expected %0d)", what, rb(7), err); end
    if (rb(8) != int'(src_a) || (fw_a >= 0 && rb(9) != fw_a) || rcrc(12) !== crc_a)
        begin errors++; $display("FAIL %s: slot A source %0d FW %0d CRC %08h (expected %0d %0d %08h)", what, rb(8), rb(9), rcrc(12), src_a, fw_a, crc_a); end
    if (rb(10) != int'(src_b) || (fw_b >= 0 && rb(11) != fw_b) || rcrc(16) !== crc_b)
        begin errors++; $display("FAIL %s: slot B source %0d FW %0d CRC %08h (expected %0d %0d %08h)", what, rb(10), rb(11), rcrc(16), src_b, fw_b, crc_b); end
    last_gen = rb(6);
    wlog_off = {}; wlog_val = {};
    if (errors == bad) $display("ok   %s (gen %0d, A %0d/%0d, B %0d/%0d, error %0d)", what, rb(6), rb(8), rb(9), rb(10), rb(11), rb(7));
endtask

initial begin
    string pack_name, fw_name, fdc_name;
    int fd, c;
    logic [31:0] crc_a, crc_b;
    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("fw=%s", fw_name) ||
        !$value$plusargs("rom_a=%h", ROM_A_ADDR) || !$value$plusargs("rom_b=%h", ROM_B_ADDR) ||
        !$value$plusargs("db=%h", DB_ADDR) || !$value$plusargs("fwaddr=%h", FW_ADDR)) begin
        $display("usage: +pack=<machine.msx> +fw=<CART_FW_EN.msx> +rom_a= +rom_b= +db= +fwaddr=<hex>"); $finish;
    end
    busy_en = $test$plusargs("busy");
    fd = $fopen(pack_name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
    fd = $fopen(fw_name, "rb");   while ((c = $fgetc(fd)) != -1) fw.push_back(8'(c));   $fclose(fd);
    cart_conf[0].typ = CART_TYP_ROM;
    cart_conf[1].typ = CART_TYP_ROM;
    repeat (4) @(posedge clk);
    ddr_reset = 0;
    repeat (4) @(posedge clk);

    // no report before the first load
    repeat (200) @(posedge clk);
    if (wlog_off.size() != 0) begin errors++; $display("FAIL report written without a load"); end

    download(2, fw.size());     wait_report();
    wlog_off = {}; wlog_val = {};
    download(1, pack.size());   wait_report();
    check("machine, no ROMs", ERR_NONE, MSX::CART_SRC_NO_ROM, -1, 0, MSX::CART_SRC_NO_ROM, -1, 0);

    // --- no database: plain ROM, or refused
    make_rom(rom, 16384, 0, 16'h4010, 3);  crc_a = crc32(rom);
    download(3, rom.size());    wait_report();
    check("16 kB ROM A, no DB: plain 4000h", ERR_NONE, MSX::CART_SRC_PLAIN, 21, crc_a, MSX::CART_SRC_NO_ROM, -1, 0);
    make_rom(rom, 131072, 0, 16'h4010, 5); crc_a = crc32(rom);
    download(3, rom.size());    wait_report();
    check("128 kB ROM A, no DB: refused", ERR_NO_CRC_DB, MSX::CART_SRC_FAIL, -1, crc_a, MSX::CART_SRC_NONE, -1, 0);

    // --- database without the ROM
    db_entry(32'h12345678, 52);
    download(6, db.size());
    make_rom(rom, 32768, 0, 16'h8010, 7);  crc_a = crc32(rom);
    download(3, rom.size());    wait_report();
    check("32 kB ROM A not in DB: plain 8000h", ERR_NONE, MSX::CART_SRC_PLAIN, 22, crc_a, MSX::CART_SRC_NO_ROM, -1, 0);
    make_rom(rom, 131072, 0, 16'h4010, 9); crc_a = crc32(rom);
    download(3, rom.size());    wait_report();
    check("128 kB ROM A not in DB: refused", ERR_NO_CRC_FOUND, MSX::CART_SRC_FAIL, -1, crc_a, MSX::CART_SRC_NONE, -1, 0);

    // --- database entry: ROM A as KONAMI (52), then ROM B plain
    make_rom(rom, 32768, 0, 16'h4010, 11); crc_a = crc32(rom);
    db_entry(crc_a, 52);
    download(6, db.size());
    download(3, rom.size());    wait_report();
    check("32 kB ROM A in DB as KONAMI", ERR_NONE, MSX::CART_SRC_DB, 52, crc_a, MSX::CART_SRC_NO_ROM, -1, 0);
    make_rom(rom_b, 16384, 0, 16'h4010, 13); crc_b = crc32(rom_b);
    download(4, rom_b.size());  wait_report();
    check("ROM B plain beside ROM A in DB", ERR_NONE, MSX::CART_SRC_DB, 52, crc_a, MSX::CART_SRC_PLAIN, 21, crc_b);

    // --- cartridge chosen in the OSD, then ROM eject
    cart_conf[0].typ = CART_TYP_SCC;
    pulse(reload);              wait_report();
    check("slot A: SCC from the OSD", ERR_NONE, MSX::CART_SRC_OSD, int'(CART_TYP_SCC), 0, MSX::CART_SRC_PLAIN, 21, crc_b);
    cart_conf[0].typ = CART_TYP_ROM;
    pulse(rom_eject);           wait_report();
    check("ROMs ejected", ERR_NONE, MSX::CART_SRC_NO_ROM, -1, 0, MSX::CART_SRC_NO_ROM, -1, 0);

    // --- a load while a report is being written: that report ends without valid = 1
    download(3, rom.size());
    wait (rp_request && rpt.step == 5'd10);
    begin
        int n0 = wlog_off.size();
        make_rom(rom, 16384, 0, 16'h8010, 15); crc_a = crc32(rom);
        download(3, rom.size());
        wait (!mu_done);
        for (int i = n0; i < wlog_off.size(); i++)
            if (wlog_off[i] == 4 && wlog_val[i] == 1) begin errors++; $display("FAIL interrupted report set valid"); end
        wait_report();
        last_gen = (last_gen + 1) & 255;    // the interrupted report counted
        check("load during a report: the next report", ERR_NONE, MSX::CART_SRC_PLAIN, 22, crc_a, MSX::CART_SRC_NO_ROM, -1, 0);
    end

    // --- FDC cartridge in a machine with its own FDC: slot A left out
    if ($value$plusargs("fdcpack=%s", fdc_name)) begin
        pack = {};
        fd = $fopen(fdc_name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
        cart_conf[0].typ = CART_TYP_FDC;
        download(1, pack.size());   wait_report();
        check("FDC cartridge left out (machine FDC)", ERR_NONE, MSX::CART_SRC_LEFT_OUT, -1, 0, MSX::CART_SRC_NO_ROM, -1, 0);
    end

    if (errors == 0) $display("PASS cfg_report_tb");
    else             $display("FAILED cfg_report_tb: %0d errors", errors);
    $finish;
end

initial begin
    #900_000_000;
    $display("FAILED cfg_report_tb: timeout (upload=%b done=%b error=%0d)", upload, mu_done, error);
    $finish;
end

endmodule
