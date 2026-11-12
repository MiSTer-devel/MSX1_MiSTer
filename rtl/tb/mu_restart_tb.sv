// memory_upload: a load request that arrives while an upload is running.
//
// The OSD can change the configuration at any time (cartridge type, ROM load, eject); each
// change pulses a load. Whatever the loader is doing, the result must be the configuration
// of the last request, the same as if it was loaded from the idle state.
//
// Scenario (Philips VG 8020, FW pack, a 32 kB ROM in slot A known to the database as KONAMI):
//   reference  cartridge B = SCC, loaded from idle
//   trial      cartridge B = empty and a reload; t clocks later cartridge B = SCC and a reload
// The trial runs for every +stride-th clock t of the upload and for every clock of its last
// +dense clocks: there the first upload has already used the old cartridge type and its last
// state transitions follow each other closely. After each trial the tables, io_device, the
// error and the stream written into the memory since the last start must equal the reference.
//
//   wsl.exe -- bash rtl/tb/run_mu_restart.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
`timescale 1ns/1ps

module mu_restart_tb;

logic clk = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DDR3 model + ddram
localparam int LAT = 2;
localparam int unsigned ROM_A_ADDR = MSX::DDR3_ROM_A, DB_ADDR = MSX::DDR3_DB, FW_ADDR = MSX::DDR3_FW_PACK;
byte unsigned pack[$], fw[$], rom[$], db[$];

wire  [27:0] ddr3_addr;
wire   [7:0] ddr3_dout;
wire         ddr3_rd, ddr3_ready, ddr3_request;
wire  [28:0] DDRAM_ADDR;
wire         DDRAM_RD;
logic [63:0] DDRAM_DOUT;
logic        DDRAM_DOUT_READY = 0;
logic        ddr_reset = 1;

ddram ddr (
    .reset(ddr_reset), .DDRAM_CLK(clk), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(),
    .DDRAM_BE(), .DDRAM_WE(), .addr(ddr3_addr), .dout(ddr3_dout), .din(8'h00), .we(1'b0), .rd(ddr3_rd),
    .ready(ddr3_ready), .dout64()
);

function automatic byte unsigned ddr_byte(input int unsigned a);
    if (a < pack.size())                                return pack[a];
    if (a >= FW_ADDR && a - FW_ADDR < fw.size())        return fw[a - FW_ADDR];
    if (a >= ROM_A_ADDR && a - ROM_A_ADDR < rom.size()) return rom[a - ROM_A_ADDR];
    if (a >= DB_ADDR && a - DB_ADDR < db.size())        return db[a - DB_ADDR];
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
logic        ioctl_download = 0, reload = 0;
logic [15:0] ioctl_index = '0;
logic [26:0] ioctl_addr = '0;
logic  [5:0] layout_id = '0;
memory_bus_if            mem();
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
error_t                  error;
wire                     upload, load_sram, upload_reset;

memory_upload dut (
    .clk(clk), .upload(upload), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rom_eject(1'b0), .reload(reload),
    .ddr3_addr(ddr3_addr), .ddr3_rd(ddr3_rd), .ddr3_dout(ddr3_dout), .ddr3_ready(ddr3_ready),
    .ddr3_request(ddr3_request), .memory_bus(mem), .kb_upload_memory(kb_upload_memory),
    .slot_expander(slot_expander), .layout_id(layout_id), .active_block(active_block),
    .active_RAM(active_RAM), .main_RAM(main_RAM), .lookup_SRAM(lookup_SRAM), .main_ram(main_ram),
    .cart_conf(cart_conf), .io_device(io_device), .io_memory(io_memory),
    .msx_config(msx_config), .load_sram(load_sram), .error(error), .reset(upload_reset)
);

assign mem.sdram_ready = 1'b1;
assign mem.sdram_done  = 1'b1;
assign mem.q           = 8'hFF;

// memory image, and the stream written since the loader last started (entered its clean state)
localparam logic [3:0] STATE_CLEAN = 4'd1;      // state_t of memory_upload
byte unsigned    ram[int unsigned];
longint unsigned stream = 0;
int              writes = 0, idle = 0;
logic      [3:0] state_q = '0;
logic            idle_clr = 0;
always_ff @(posedge clk) begin
    if (dut.state == STATE_CLEAN && state_q != STATE_CLEAN) begin stream = 0; writes = 0; end
    state_q <= dut.state;
    if (mem.ram_cs) begin
        ram[mem.addr] = mem.data;
        if (dut.state != STATE_CLEAN) begin         // not the last write of an upload just restarted
            stream = (stream ^ {29'd0, mem.addr, mem.data}) * 64'h100000001B3;
            writes++;
        end
    end
    idle <= (idle_clr || ddr3_rd || mem.ram_cs || kb_upload_memory.we || !ddr3_ready) ? 0 : idle + 1;
end

// ------------------------------------------------------------------ helpers
function automatic logic [31:0] crc32(input byte unsigned d[$]);
    logic [31:0] c = '1;
    foreach (d[i]) begin
        c ^= 32'(d[i]);
        for (int k = 0; k < 8; k++) c = c[0] ? (c >> 1) ^ 32'hEDB88320 : c >> 1;
    end
    return ~c;
endfunction

task automatic download(input int idx, input int unsigned size);
    ioctl_index = 16'(idx); ioctl_download = 1;
    @(posedge clk); ioctl_addr = 27'(size);
    @(posedge clk); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
endtask

task automatic do_reload();
    @(posedge clk); reload = 1; @(posedge clk); reload = 0;
endtask

// finished: not uploading, or stopped on an error
task automatic wait_done();
    idle_clr = 1;
    repeat (20) @(posedge clk);
    idle_clr = 0;
    while (upload && idle <= 3000) @(posedge clk);
    repeat (20) @(posedge clk);
endtask

function automatic longint unsigned mix(input longint unsigned h, input longint unsigned v);
    return (h ^ v) * 64'h100000001B3;
endfunction

// result of the loader: everything the core takes from it
longint unsigned sig_cfg, sig_dev, sig_lay;
longint unsigned blk[64], blk_ram[64], ref_blk[64], ref_blk_ram[64];    // per block, for the report
task automatic signature();
    sig_cfg = 64'hCBF29CE484222325; sig_dev = sig_cfg; sig_lay = sig_cfg;
    sig_cfg = mix(sig_cfg, {error, upload, upload_reset, msx_config.cpu, msx_config.wait_count, msx_config.cpu_clock_sel, msx_config.fdd});
    sig_cfg = mix(sig_cfg, main_ram.en ? {1'b1, main_RAM.addr, main_RAM.size, main_RAM.ro} : 64'd0);
    for (int i = 0; i < 4; i++) begin
        sig_cfg = mix(sig_cfg, {slot_expander[i].en, slot_expander[i].wo, slot_expander[i].init});
        sig_cfg = mix(sig_cfg, lookup_SRAM[i].size != 0 ? {lookup_SRAM[i].addr, lookup_SRAM[i].size} : 64'd0);
    end
    for (int t = 0; t < 32; t++)
        for (int k = 0; k < 3; k++)
            sig_dev = mix(sig_dev, {io_device[t][k].mask, io_device[t][k].port, io_device[t][k].param,
                                    io_device[t][k].mem_ref, io_device[t][k].device_ref, io_device[t][k].enable});
    for (int i = 0; i < 8; i++) sig_dev = mix(sig_dev, {io_memory[i].memory, io_memory[i].memory_size});
    for (int i = 0; i < 64; i++) begin
        layout_id = 6'(i);
        @(negedge clk);
        blk[i]     = {active_block.ref_sram, active_block.offset_ram, 1'b0, active_block.device_ref, 2'b0,
                      6'(active_block.mapper), 2'b0, active_block.mapper_param, 3'b0, active_block.cart_num};
        blk_ram[i] = active_block.mapper != MAPPER_NONE ? {active_RAM.addr, active_RAM.size, active_RAM.ro} : 64'd0;
        sig_lay = mix(mix(sig_lay, blk[i]), blk_ram[i]);
    end
endtask

task automatic make_rom(input int size);
    rom = {};
    for (int i = 0; i < size; i++) rom.push_back(8'(i * 7 + (i >> 9) + 3));
    rom[0] = 8'h41; rom[1] = 8'h42; rom[2] = 8'h10; rom[3] = 8'h40;
endtask

int errors = 0, trials = 0, lost = 0;
longint unsigned ref_cfg, ref_dev, ref_lay, ref_stream;
int              ref_writes;
byte unsigned    ref_img[int unsigned];

// cartridge B empty + reload; t clocks later cartridge B = SCC + reload
task automatic trial(input int t);
    cart_conf[1].typ = CART_TYP_EMPTY;
    do_reload();
    repeat (t) @(posedge clk);
    cart_conf[1].typ = CART_TYP_SCC;
    do_reload();
    wait_done();
    signature();
    trials++;
    if (sig_cfg !== ref_cfg || sig_dev !== ref_dev || sig_lay !== ref_lay || stream !== ref_stream || writes !== ref_writes) begin
        errors++;
        if (sig_lay !== ref_lay && sig_dev !== ref_dev) lost++;
        if (errors <= 12)
            $display("FAIL load %0d clocks into the upload: error %0d upload %b; differs:%s%s%s%s", t, error, upload,
                     sig_cfg !== ref_cfg ? " config" : "", sig_dev !== ref_dev ? " io_device" : "",
                     sig_lay !== ref_lay ? " layout" : "", (stream !== ref_stream || writes !== ref_writes) ? " memory" : "");
        if (errors <= 12)
            for (int i = 0; i < 64; i++)
                if (blk[i] !== ref_blk[i] || blk_ram[i] !== ref_blk_ram[i])
                    $display("     block %0d-%0d page %0d: sram/offset/device/mapper/param/cart %0h (expected %0h), memory %0h (expected %0h)",
                             i[5:4], i[3:2], i[1:0], blk[i], ref_blk[i], blk_ram[i], ref_blk_ram[i]);
        if (upload) begin do_reload(); wait_done(); end          // a stopped loader: start it again
    end
endtask

initial begin
    string name;
    int fd, c, len, dense = 800, stride = 3001, t0, bad_img = 0;
    logic [31:0] crc;

    if (!$value$plusargs("pack=%s", name)) begin $display("usage: +pack=<VG 8020 pack> +fw=<CART_FW_EN.msx>"); $finish; end
    fd = $fopen(name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
    void'($value$plusargs("fw=%s", name));
    fd = $fopen(name, "rb"); while ((c = $fgetc(fd)) != -1) fw.push_back(8'(c)); $fclose(fd);
    void'($value$plusargs("dense=%d", dense));
    void'($value$plusargs("stride=%d", stride));
    make_rom(32768);
    crc = crc32(rom);
    db = {};                                            // one entry: CRC32, FW configuration 52 = KONAMI
    db.push_back(crc[7:0]); db.push_back(crc[15:8]); db.push_back(crc[23:16]); db.push_back(crc[31:24]);
    db.push_back(8'd52); db.push_back(8'd0); db.push_back(8'd0); db.push_back(8'd0);

    cart_conf[0].typ = CART_TYP_ROM;
    cart_conf[1].typ = CART_TYP_SCC;
    repeat (4) @(posedge clk);
    ddr_reset = 0;
    repeat (8) @(posedge clk);

    // HPS start, then the reference: cartridge B = SCC, loaded from the idle state
    download(2, fw.size());   wait_done();
    download(6, db.size());   repeat (4) @(posedge clk);
    download(1, pack.size()); wait_done();
    download(3, rom.size());  wait_done();
    do_reload();
    t0 = $time / 2;
    wait_done();
    len = $time / 2 - t0;
    signature();
    ref_cfg = sig_cfg; ref_dev = sig_dev; ref_lay = sig_lay; ref_stream = stream; ref_writes = writes;
    ref_img = ram;
    ref_blk = blk; ref_blk_ram = blk_ram;
    $display("reference: error %0d, %0d memory writes, upload about %0d clocks", error, writes, len);
    layout_id = {2'd1, 2'd0, 2'd1}; @(negedge clk);
    if (error !== ERR_NONE || active_block.mapper !== MAPPER_KONAMI) begin
        errors++; $display("FAIL reference: error %0d, slot 1 page 1 mapper %0d (expected KONAMI)", error, active_block.mapper);
    end
    layout_id = {2'd2, 2'd0, 2'd2}; @(negedge clk);
    if (active_block.mapper === MAPPER_NONE) begin errors++; $display("FAIL reference: no SCC cartridge in slot 2"); end

    for (int t = 1; t < len - dense; t += stride) trial(t);
    for (int t = len - dense; t <= len + 20; t++) trial(t);

    foreach (ref_img[a]) if (ram[a] !== ref_img[a]) bad_img++;
    if (bad_img) begin errors++; $display("FAIL memory image: %0d bytes differ from the reference", bad_img); end
    $display("%s mu_restart_tb: %0d loads during an upload, %0d wrong (%0d of them kept the old configuration)",
             errors ? "FAIL" : "PASS", trials, errors, lost);
    $finish;
end

endmodule
