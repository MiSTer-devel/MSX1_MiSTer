// memory_upload: cartridge ROM in slot A (Philips VG 8020: slot 1) with and without a mapper
// database entry. A ROM whose CRC32 is not in the database (or with no database loaded) is a
// plain ROM, read linearly and placed by its MSX header (FW pack configurations 0x0000 /
// 0x4000 / 0x8000); a ROM above 64 kB still needs the database. A database entry still wins.
// Two ROMs with SRAM in slots A and B each get their own SRAM; blocks without SRAM see none (C9).
// DDR3 as the HPS fills it: every file whole at its OSD address (CONF_STR of MSX1.sv, given by
// run_cart_rom.sh), the later download wins where two overlap. A ROM A over 5 MB must not
// destroy ROM B, a ROM over the area of its slot is refused (C8).
// Run: wsl.exe -- bash rtl/tb/run_cart_rom.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
//   OLD=<git rev>: memory_upload.sv of that revision
module cart_rom_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 model + ddram
localparam int LAT = 5;
int unsigned ROM_A_ADDR, ROM_B_ADDR, DB_ADDR, FW_ADDR;        // from the OSD strings
byte unsigned pack[$], fw[$], rom[$], rom_b[$], db[$];
int          stamp_fw = 0, stamp_a = 0, stamp_b = 0, stamp_db = 0, stamp_n = 0;   // download order

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

function automatic byte unsigned ddr_byte(input int unsigned a);
    int best = 0;
    byte unsigned v = 8'hFF;
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
    if (DDRAM_RD) begin rd_addr <= DDRAM_ADDR; rd_wait <= LAT; end
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

assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;
assign mem.q           = 8'hFF;
byte unsigned ram[int unsigned];
// pad_mode: FF writes are not stored (a missing byte reads FF), only their runs are kept
bit          pad_mode = 0;
int unsigned ff_lo[$], ff_hi[$];
always_ff @(posedge clk) if (mem.ram_cs && !mem.rnw) begin
    if (pad_mode && mem.data == 8'hFF) begin
        if (ff_hi.size() > 0 && ff_hi[$] + 1 == mem.addr) ff_hi[$] = mem.addr;
        else begin ff_lo.push_back(mem.addr); ff_hi.push_back(mem.addr); end
    end else ram[mem.addr] = mem.data;
end

// ------------------------------------------------------------------ helpers
int errors = 0;

function automatic logic [31:0] crc32(input byte unsigned d[$]);
    logic [31:0] c = '1;
    foreach (d[i]) begin
        c ^= 32'(d[i]);
        for (int k = 0; k < 8; k++) c = c[0] ? (c >> 1) ^ 32'hEDB88320 : c >> 1;
    end
    return ~c;
endfunction

task automatic download(input int idx, input int unsigned size, input bit wait_upload);
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
    @(posedge clk); ioctl_download = 0;
    if (wait_upload) begin wait (upload); wait (!upload); end
    repeat (10) @(posedge clk);
endtask

// ROM of size bytes: 'AB' + INIT at offset hdr (-1: none), a pattern elsewhere
task automatic make_rom(input int size, input int hdr, input logic [15:0] init);
    rom = {};
    for (int i = 0; i < size; i++) rom.push_back(8'(i * 7 + (i >> 9) + 3));
    for (int i = 0; i < size; i += 16384) begin rom[i] = 8'h00; rom[i + 1] = 8'h00; end   // no stray 'AB'
    if (hdr >= 0) begin rom[hdr] = 8'h41; rom[hdr + 1] = 8'h42; rom[hdr + 2] = init[7:0]; rom[hdr + 3] = init[15:8]; end
endtask

// Load ROM A; expect the pages of slot 1-0 (-1: no ROM there, else ROM offset in kB / 16)
task automatic check(input string what, input int p0, input int p1, input int p2, input int p3,
                     input mapper_typ_t m = MAPPER_OFFSET, input error_t err = ERR_NONE);
    int exp[4] = '{p0, p1, p2, p3};
    download(3, rom.size(), 0);
    wait (upload);
    wait (!upload || error != ERR_NONE);                // an error leaves the loader stopped
    repeat (10) @(posedge clk);
    snapshot();
    if (error !== err) begin
        errors++; $display("FAIL %s: error %0d (expected %0d)", what, error, err);
        return;
    end
    if (err != ERR_NONE) begin $display("ok   %s: error %0d", what, error); return; end
    for (int p = 0; p < 4; p++) begin
        MSX::block_t b = slot_layout[{2'd1, 2'd0, 2'(p)}];
        if (exp[p] < 0) begin                           // empty, or past the ROM end (OFFSET reads FFh there)
            if (b.mapper == MAPPER_OFFSET && 32'(b.offset_ram) * 16384 < rom.size())
                begin errors++; $display("FAIL %s: page %0d maps ROM offset %0d", what, p, b.offset_ram); end
        end else if (b.mapper !== m) begin
            errors++; $display("FAIL %s: page %0d mapper %0d (expected %0d)", what, p, b.mapper, m);
        end else if (m == MAPPER_OFFSET) begin
            int unsigned a = lookup_RAM[b.ref_ram].addr + 32'(b.offset_ram) * 16384;
            int bad = 0;
            for (int i = 0; i < 16384 && exp[p] * 16384 + i < rom.size(); i += 61)
                if (!ram.exists(a + i) || ram[a + i] !== rom[exp[p] * 16384 + i]) bad++;
            if (bad || lookup_RAM[b.ref_ram].ro !== 1'b1)
                begin errors++; $display("FAIL %s: page %0d content (%0d bytes differ, ro %b)", what, p, bad, lookup_RAM[b.ref_ram].ro); end
        end
    end
    $display("ok   %s", what);
endtask

// ROM in the database as ASCII16-X (cart_device.json 57): the mapper in all four pages, the ROM
// image at the start of an 8 MB flash, the rest erased, nothing else in those 8 MB
task automatic check_ascii16x(input string what);
    localparam int unsigned FLASH = 32'h800000;
    logic [31:0] crc = crc32(rom);
    MSX::block_t b;
    int unsigned base;
    int bad = 0, pad = 0;
    db = {crc[7:0], crc[15:8], crc[23:16], crc[31:24], 8'd57, 8'h00, 8'h00, 8'h00};
    download(6, db.size(), 0);
    ram.delete(); ff_lo = {}; ff_hi = {}; pad_mode = 1;
    download(3, rom.size(), 0);
    wait (upload);
    wait (!upload || error != ERR_NONE);
    repeat (10) @(posedge clk);
    snapshot();
    pad_mode = 0;
    if (error !== ERR_NONE) begin errors++; $display("FAIL %s: error %0d", what, error); return; end
    b = slot_layout[{2'd1, 2'd0, 2'd0}];
    base = lookup_RAM[b.ref_ram].addr;
    for (int p = 0; p < 4; p++) begin
        MSX::block_t q = slot_layout[{2'd1, 2'd0, 2'(p)}];
        if (q.mapper !== MAPPER_ASCII16X || q.ref_ram !== b.ref_ram) begin
            errors++; $display("FAIL %s: page %0d mapper %0d ref %0d", what, p, q.mapper, q.ref_ram);
        end
    end
    if (lookup_RAM[b.ref_ram].size !== 17'(FLASH / 8192) || lookup_RAM[b.ref_ram].ro !== 1'b1) begin
        errors++; $display("FAIL %s: memory size %0d x 8 kB, ro %b", what, lookup_RAM[b.ref_ram].size, lookup_RAM[b.ref_ram].ro);
    end
    for (int i = 0; i < rom.size(); i += 53)
        if ((ram.exists(base + i) ? ram[base + i] : 8'hFF) !== rom[i]) bad++;
    if (bad) begin errors++; $display("FAIL %s: %0d bytes of the image differ", what, bad); end
    foreach (ff_lo[i])                                  // the run of FF up to the end of the flash
        if (ff_lo[i] <= base + rom.size() && ff_hi[i] == base + FLASH - 1) pad = 1;
    if (!pad) begin
        errors++; $display("FAIL %s: no FF fill from %07h to %07h", what, base + rom.size(), base + FLASH - 1);
    end
    for (int i = 0; i < 64; i++) begin                  // other blocks lie outside the flash
        MSX::block_t q = slot_layout[i];
        int unsigned a = lookup_RAM[q.ref_ram].addr;
        if (q.ref_ram !== b.ref_ram && q.mapper !== MAPPER_NONE && lookup_RAM[q.ref_ram].size != 0 && a >= base && a < base + FLASH) begin
            errors++; $display("FAIL %s: block %0d memory %07h inside the flash", what, i, a);
        end
    end
    $display("ok   %s", what);
endtask

// ROM A and ROM B in the database as ASCII8 with 8 kB SRAM (cart_device.json 36): slot 1 and
// slot 2 blocks of the mapper point to two different SRAM entries of 8 kB, the other blocks to an
// entry without SRAM
task automatic check_sram_ab(input string what);
    logic [31:0] ca, cb;
    int ra = -1, rb = -1, bad = 0, err0 = errors;
    make_rom(32768, 0, 16'h4010);
    rom_b = rom;
    foreach (rom_b[i]) rom_b[i] = rom_b[i] ^ 8'hA5;
    ca = crc32(rom); cb = crc32(rom_b);
    db = {ca[7:0], ca[15:8], ca[23:16], ca[31:24], 8'd36, 8'h00, 8'h00, 8'h00,
          cb[7:0], cb[15:8], cb[23:16], cb[31:24], 8'd36, 8'h00, 8'h00, 8'h00};
    download(6, db.size(), 0);
    download(3, rom.size(), 1);
    download(4, rom_b.size(), 1);
    snapshot();
    if (error !== ERR_NONE) begin errors++; $display("FAIL %s: error %0d", what, error); return; end
    for (int i = 0; i < 64; i++) begin
        MSX::block_t q = slot_layout[i];
        if (q.mapper == MAPPER_ASCII8 && i[5:4] == 2'd1) begin
            if (ra < 0) ra = q.ref_sram; else if (q.ref_sram != ra) bad++;
        end else if (q.mapper == MAPPER_ASCII8 && i[5:4] == 2'd2) begin
            if (rb < 0) rb = q.ref_sram; else if (q.ref_sram != rb) bad++;
        end else if (q.mapper != MAPPER_NONE && lookup_SRAM[q.ref_sram].size != 0) begin
            errors++; $display("FAIL %s: block %0d (mapper %0d) sees SRAM entry %0d", what, i, q.mapper, q.ref_sram);
        end
    end
    if (ra < 0 || rb < 0 || bad) begin
        errors++; $display("FAIL %s: ASCII8 blocks slot 1 ref %0d, slot 2 ref %0d, %0d inconsistent", what, ra, rb, bad);
        return;
    end
    if (ra == rb) begin errors++; $display("FAIL %s: slots A and B share SRAM entry %0d", what, ra); end
    if (lookup_SRAM[ra].size != 16'd8 || lookup_SRAM[rb].size != 16'd8) begin
        errors++; $display("FAIL %s: SRAM sizes %0d / %0d kB", what, lookup_SRAM[ra].size, lookup_SRAM[rb].size);
    end
    if (lookup_SRAM[ra].addr == lookup_SRAM[rb].addr) begin
        errors++; $display("FAIL %s: SRAM of A and B at the same address %07h", what, lookup_SRAM[ra].addr);
    end
    if (errors == err0) $display("ok   %s (SRAM entries %0d and %0d)", what, ra, rb);
    rom_b = {};
    download(4, 0, 1);
endtask

// C8: ROM B (32 kB plain, pages 1-2 of slot 2) loaded first, then a ROM A of 5.25 MB
// (ASCII16-X in the database): ROM B must stay intact. Then a ROM A of 17 MB is refused.
task automatic check_rom_areas(input string what);
    localparam int BIG = 5 * 1048576 + 262144;
    logic [31:0] crc;
    int bad = 0, err0 = errors;
    make_rom(32768, 0, 16'h4010);
    rom_b = rom;
    foreach (rom_b[i]) rom_b[i] = rom_b[i] ^ 8'h3C;
    rom_b[0] = 8'h41; rom_b[1] = 8'h42;                 // header kept after the XOR
    rom_b[16384] = 8'h00; rom_b[16385] = 8'h00;
    make_rom(BIG, 0, 16'h4010);
    crc = crc32(rom);
    db = {crc[7:0], crc[15:8], crc[23:16], crc[31:24], 8'd57, 8'h00, 8'h00, 8'h00};
    download(6, db.size(), 0);
    download(4, rom_b.size(), 1);
    download(3, rom.size(), 1);
    snapshot();
    if (error !== ERR_NONE) begin errors++; $display("FAIL %s: error %0d", what, error); return; end
    for (int p = 1; p <= 2; p++) begin
        MSX::block_t b = slot_layout[{2'd2, 2'd0, 2'(p)}];
        int unsigned a = lookup_RAM[b.ref_ram].addr + 32'(b.offset_ram) * 16384;
        for (int i = 0; i < 16384; i += 31)
            if (!ram.exists(a + i) || ram[a + i] !== rom_b[(p - 1) * 16384 + i]) bad++;
    end
    if (bad) begin errors++; $display("FAIL %s: ROM B differs in %0d bytes (overwritten by ROM A)", what, bad); end
    // a ROM over 16 MB is refused (the HPS has already written past the area of slot A)
    rom = {}; for (int i = 0; i < 4096; i++) rom.push_back(8'(i));
    download(3, 17 * 1048576, 0);
    wait (upload);
    wait (!upload || error != ERR_NONE);
    repeat (10) @(posedge clk);
    if (error !== ERR_ROM_TOO_BIG) begin errors++; $display("FAIL %s: 17 MB ROM A: error %0d (expected %0d)", what, error, ERR_ROM_TOO_BIG); end
    if (errors == err0) $display("ok   %s", what);
    rom = {}; rom_b = {};
    download(3, 0, 0); download(4, 0, 1);
endtask

initial begin
    string pack_name, fw_name;
    int fd, c;
    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("fw=%s", fw_name) ||
        !$value$plusargs("rom_a=%h", ROM_A_ADDR) || !$value$plusargs("rom_b=%h", ROM_B_ADDR) ||
        !$value$plusargs("db=%h", DB_ADDR) || !$value$plusargs("fwaddr=%h", FW_ADDR)) begin
        $display("usage: +pack=<machine.msx> +fw=<CART_FW_EN.msx> +rom_a= +rom_b= +db= +fwaddr=<hex>"); $finish;
    end
    $display("DDR3 areas: FW %07h, ROM A %07h, ROM B %07h, DB %07h", FW_ADDR, ROM_A_ADDR, ROM_B_ADDR, DB_ADDR);
    fd = $fopen(pack_name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
    fd = $fopen(fw_name, "rb");   while ((c = $fgetc(fd)) != -1) fw.push_back(8'(c));   $fclose(fd);
    cart_conf[0].typ = CART_TYP_ROM;
    cart_conf[1].typ = CART_TYP_ROM;
    repeat (4) @(posedge clk);
    ddr_reset = 0;
    repeat (4) @(posedge clk);
    download(2, fw.size(), 1);
    download(1, pack.size(), 1);
    if (error != ERR_NONE) begin $display("FAILED cart_rom_tb: pack error %0d", error); $finish; end

    // --- optional: a real ROM file with a real database file (+realrom= +realdb=), report only
    begin
        string rr, rd;
        if ($value$plusargs("realrom=%s", rr) && $value$plusargs("realdb=%s", rd)) begin
            fd = $fopen(rd, "rb"); while ((c = $fgetc(fd)) != -1) db.push_back(8'(c));  $fclose(fd);
            download(6, db.size(), 0);
            fd = $fopen(rr, "rb"); while ((c = $fgetc(fd)) != -1) rom.push_back(8'(c)); $fclose(fd);
            $display("real ROM %0d B CRC32 %08h, DB %0d B", rom.size(), crc32(rom), db.size());
            download(3, rom.size(), 0);
            wait (upload);
            wait (!upload || error != ERR_NONE);
            repeat (10) @(posedge clk);
            snapshot();
            for (int p = 0; p < 4; p++)
                $display("REAL page %0d: mapper %0d sram %0d", p, slot_layout[{2'd1, 2'd0, 2'(p)}].mapper,
                         lookup_SRAM[0].size);
            $display("REAL error %0d", error);
            $finish;
        end
    end

    // --- no database loaded
    make_rom(16384, 0, 16'h4010);  check("16 kB, INIT 4010h, no DB", -1, 0, -1, -1);
    make_rom(16384, 0, 16'h8010);  check("16 kB, INIT 8010h, no DB", -1, -1, 0, -1);
    make_rom(32768, -1, 16'h0);    check("32 kB, no header, no DB", -1, 0, 1, -1);
    make_rom(49152, 16384, 16'h4010); check("48 kB, header at 4000h, no DB", 0, 1, 2, -1);
    make_rom(65536, 0, 16'h0010);  check("64 kB, INIT 0010h, no DB", 0, 1, 2, 3);
    make_rom(131072, 0, 16'h4010); check("128 kB, no DB", -1, -1, -1, -1, MAPPER_OFFSET, ERR_NO_CRC_DB);

    // --- database without the ROM (one unrelated entry)
    db = {8'h78, 8'h56, 8'h34, 8'h12, 8'd52, 8'h00, 8'h00, 8'h00};
    download(6, db.size(), 0);
    make_rom(32768, 0, 16'h4010);  check("32 kB, INIT 4010h, not in DB", -1, 0, 1, -1);
    make_rom(131072, 0, 16'h4010); check("128 kB, not in DB", -1, -1, -1, -1, MAPPER_OFFSET, ERR_NO_CRC_FOUND);

    // --- database entry wins: the same 32 kB ROM as KONAMI (cart_device.json 52)
    make_rom(32768, 0, 16'h4010);
    begin
        logic [31:0] crc = crc32(rom);
        db = {crc[7:0], crc[15:8], crc[23:16], crc[31:24], 8'd52, 8'h00, 8'h00, 8'h00};
    end
    download(6, db.size(), 0);
    check("32 kB in DB as KONAMI", 0, 0, 0, 0, MAPPER_KONAMI);

    // --- ASCII16-X: flash of 8 MB with the ROM image at its start
    make_rom(131072, 0, 16'h4010);  check_ascii16x("128 kB in DB as ASCII16-X");
    make_rom(100000, 0, 16'h4010);  check_ascii16x("100000 B in DB as ASCII16-X");

    // --- C9: SRAM of ROM A and ROM B
    check_sram_ab("ROM A and ROM B with SRAM");

    // --- C8: areas of ROM A and ROM B in the DDR3
    check_rom_areas("ROM A of 5.25 MB beside ROM B, ROM A of 17 MB");

    if (errors == 0) $display("PASS cart_rom_tb");
    else             $display("FAILED cart_rom_tb: %0d errors", errors);
    $finish;
end

initial begin
    #900_000_000;
    $display("FAILED cart_rom_tb: timeout (upload=%b error=%0d)", upload, error);
    $finish;
end

endmodule
