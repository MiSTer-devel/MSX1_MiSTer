// memory_upload: cartridge ROM in slot A (Philips VG 8020: slot 1) with and without a mapper
// database entry. A ROM whose CRC32 is not in the database (or with no database loaded) is a
// plain ROM, read linearly and placed by its MSX header (FW pack configurations 0x0000 /
// 0x4000 / 0x8000); a ROM above 64 kB still needs the database. A database entry still wins.
// Run: wsl.exe -- bash rtl/tb/run_cart_rom.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
//   OLD=<git rev>: memory_upload.sv of that revision
module cart_rom_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 model + ddram
localparam int LAT = 5;
localparam int unsigned ROM_A_ADDR = 32'hC00000, DB_ADDR = 32'h1600000, FW_ADDR = 32'h300000;
byte unsigned pack[$], fw[$], rom[$], db[$];

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
    if (a < pack.size())                              return pack[a];
    if (a >= FW_ADDR && a - FW_ADDR < fw.size())      return fw[a - FW_ADDR];
    if (a >= ROM_A_ADDR && a - ROM_A_ADDR < rom.size()) return rom[a - ROM_A_ADDR];
    if (a >= DB_ADDR && a - DB_ADDR < db.size())      return db[a - DB_ADDR];
    return 8'hFF;
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
    .slot_expander(slot_expander), .slot_layout(slot_layout), .lookup_RAM(lookup_RAM),
    .lookup_SRAM(lookup_SRAM), .cart_conf(cart_conf), .io_device(io_device), .io_memory(io_memory),
    .msx_config(msx_config), .load_sram(load_sram), .error(error), .reset(upload_reset)
);

assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;
assign mem.q           = 8'hFF;
byte unsigned ram[int unsigned];
always_ff @(posedge clk) if (mem.ram_cs && !mem.rnw) ram[mem.addr] = mem.data;

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

initial begin
    string pack_name, fw_name;
    int fd, c;
    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("fw=%s", fw_name)) begin
        $display("usage: +pack=<machine.msx> +fw=<CART_FW_EN.msx>"); $finish;
    end
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

    if (errors == 0) $display("PASS cart_rom_tb");
    else             $display("FAILED cart_rom_tb: %0d errors", errors);
    $finish;
end

initial begin
    #400_000_000;
    $display("FAILED cart_rom_tb: timeout (upload=%b error=%0d)", upload, error);
    $finish;
end

endmodule
