// OCM boot: msx_system with the OCM pack, the SD path of emu (spi_divmmc + sd_card) and an
// HPS model serving a FAT16 image with OCM-BIOS.DAT. Checks that the IPL loads the BIOS
// from the SD card into ESE-RAM, leaves the IPL phase (write to A8h) and the BIOS runs
// (M1 fetches from MAIN ROM, VDP writes).
// +dos: then runs on (+run_ms MSX time) and logs the switched I/O ports, the internal
// ESE-SCC / MegaRAM accesses in slots 1/2 and the text screen (shadow VRAM from ports 98h/99h).
// +fw=<CART_FW_EN.msx>: FW pack (needed for cartridge types other than ROM), +status=<hex>: OSD.
// Run: wsl.exe -- bash rtl/tb/run_ocm_boot.sh <1chipMSX.msx> <OCM-BIOS.rom>
module ocm_boot_tb;

// clk_sdram = 4x clk_core, phase aligned (as the PLL)
logic clk_sdram = 0, clk_core = 0;
always #1 clk_sdram = ~clk_sdram;
always #4 clk_core  = ~clk_core;

clock_bus_if clock_bus(clk_core, clk_sdram);
clock #(.sysCLK(MSX::CLK_CORE_HZ)) clock_i (.clock_bus(clock_bus));

// ------------------------------------------------------------------ files
byte unsigned pack[$];
byte unsigned fw[$];
byte unsigned bios[$];
byte unsigned img[];
int unsigned  img_bytes;

// ------------------------------------------------------------------ msx_system
logic         rst_core_async = 1;
wire          reset;
logic [127:0] status = '0;
logic         ioctl_download = 0;
logic  [15:0] ioctl_index = '0;
logic  [26:0] ioctl_addr = '0;
logic   [5:0] joy[2] = '{6'd0, 6'd0};
wire   [15:0] status_menumask;
wire          info_req;
wire    [7:0] info;
MSX::msx_config_t msx_config;
MSX::video_t  video_bus;
wire   [15:0] audio_L, audio_R;
wire   [27:0] ddr3_addr;
wire          ddr3_rd, ddr3_ready;
wire    [7:0] ddr3_dout;
wire   [63:0] ddr3_dout64;

block_device_if block_device_FDD[2*MSX::N_FDC]();
ext_sd_card_if  ext_SD_card_bus();
memory_bus_if   sd_ch1(), sd_ch2(), sd_ch3();
wave_bus_if     sd_ch4();
wire            cpu_phase;

genvar gi;
generate for (gi = 0; gi < 2*MSX::N_FDC; gi++) begin : fdd_idle
    assign block_device_FDD[gi].ack          = 1'b0;
    assign block_device_FDD[gi].buff_addr    = '0;
    assign block_device_FDD[gi].buff_dout    = '0;
    assign block_device_FDD[gi].buff_wr      = 1'b0;
    assign block_device_FDD[gi].img_mounted  = 1'b0;
    assign block_device_FDD[gi].img_size     = '0;
    assign block_device_FDD[gi].img_readonly = 1'b0;
end endgenerate

logic [10:0] ps2_key = '0;                              // +dos: Space presses (+keys)

msx_system sys (
    .clock_bus(clock_bus), .rst_core_async(rst_core_async), .reset(reset),
    .status(status), .status_menumask(status_menumask), .info_req(info_req), .info(info),
    .ps2_key(ps2_key), .ps2_mouse(25'd0), .joy(joy), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rtc(65'd0), .sdram_sz(16'h8002), .uart_speed(32'd115200),
    .img_readonly(1'b0), .img_size(64'd0), .sd_img_mounted(1'b0),
    .block_device_FDD(block_device_FDD), .msx_config(msx_config),
    .video_bus(video_bus), .audio_L(audio_L), .audio_R(audio_R), .uart_rxd(1'b1), .tape_adc(1'b0),
    .ext_SD_card_bus(ext_SD_card_bus),
    .memory_bus_sdram_ch1(sd_ch1), .memory_bus_sdram_ch2(sd_ch2), .memory_bus_sdram_ch3(sd_ch3),
    .wave_bus_sdram_ch4(sd_ch4), .cpu_phase(cpu_phase),
    .ddr3_addr(ddr3_addr), .ddr3_rd(ddr3_rd), .ddr3_dout(ddr3_dout), .ddr3_dout64(ddr3_dout64),
    .ddr3_ready(ddr3_ready)
);

// ------------------------------------------------------------------ DDR3 (pack) via ddram
logic  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
logic [28:0] DDRAM_ADDR;
logic [63:0] DDRAM_DOUT, DDRAM_DIN;
logic        DDRAM_DOUT_READY = 0, DDRAM_RD, DDRAM_WE;

ddram ddr (
    .reset(reset), .DDRAM_CLK(clk_core), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .addr(ddr3_addr), .dout(ddr3_dout), .din(8'h00), .we(1'b0), .rd(ddr3_rd), .ready(ddr3_ready),
    .dout64(ddr3_dout64)
);

logic [28:0] ddr_rd_addr;
int          ddr_wait = -1;
always_ff @(posedge clk_core) begin
    DDRAM_DOUT_READY <= 1'b0;
    if (DDRAM_RD) begin ddr_rd_addr <= DDRAM_ADDR; ddr_wait <= 5; end
    else if (ddr_wait > 0) ddr_wait <= ddr_wait - 1;
    else if (ddr_wait == 0) begin
        for (int b = 0; b < 8; b++) begin
            int unsigned a = {ddr_rd_addr[24:0], 3'(b)};
            DDRAM_DOUT[8*b +: 8] <= (a < pack.size()) ? pack[a] :
                                    (a >= 32'h300000 && a - 32'h300000 < fw.size()) ? fw[a - 32'h300000] : 8'hFF;
        end
        DDRAM_DOUT_READY <= 1'b1;
        ddr_wait <= -1;
    end
end

// ------------------------------------------------------------------ SDRAM channels
logic [7:0] sdram [0:(1<<25)-1];
logic ch1_q = 0; logic [7:0] ch1_data = 0;
always @(posedge clk_core) begin
    ch1_q <= sd_ch1.ram_cs;
    if (sd_ch1.ram_cs && !ch1_q && !sd_ch1.rnw) sdram[sd_ch1.addr[24:0]] = sd_ch1.data;
    ch1_data <= sdram[sd_ch1.addr[24:0]];
end
assign sd_ch1.q = ch1_data; assign sd_ch1.sdram_ready = 1'b1; assign sd_ch1.sdram_done = 1'b0;

typedef struct { logic q; int busy; logic done; logic ready; logic [7:0] data; } chan_t;
chan_t c2 = '{0, 0, 0, 1, 0}, c3 = '{0, 0, 0, 1, 0};
always @(posedge clk_core) begin
    c2.q <= sd_ch2.ram_cs;
    if (!sd_ch2.ram_cs) c2.done <= 0;
    if (sd_ch2.ram_cs && !c2.q) begin c2.busy <= 3; c2.ready <= 0; end
    else if (c2.busy == 1) begin
        if (!sd_ch2.rnw) begin sdram[sd_ch2.addr[24:0]] = sd_ch2.data; c2.done <= 1; end
        c2.data <= sdram[sd_ch2.addr[24:0]]; c2.ready <= 1; c2.busy <= 0;
    end else if (c2.busy > 1) c2.busy <= c2.busy - 1;
    c3.q <= sd_ch3.ram_cs;
    if (sd_ch3.ram_cs && !c3.q) begin c3.busy <= 3; c3.ready <= 0; end
    else if (c3.busy == 1) begin
        if (!sd_ch3.rnw) sdram[sd_ch3.addr[24:0]] = sd_ch3.data;
        c3.data <= sdram[sd_ch3.addr[24:0]]; c3.ready <= 1; c3.busy <= 0;
    end else if (c3.busy > 1) c3.busy <= c3.busy - 1;
end
assign sd_ch2.q = c2.data; assign sd_ch2.sdram_ready = c2.ready; assign sd_ch2.sdram_done = c2.done;
assign sd_ch3.q = c3.data; assign sd_ch3.sdram_ready = c3.ready; assign sd_ch3.sdram_done = 1'b0;

// OPL4 sample memory (ch4): word read / byte write, done held until the request falls
int         ch4_delay = 2, ch4_cnt = 0, ch4_reads = 0, ch4_writes = 0;
logic       ch4_done = 0;
logic [15:0] ch4_data = 0;
always @(posedge clk_core) begin
    if (!sd_ch4.req) begin ch4_done <= 0; ch4_cnt <= 0; end
    else if (!ch4_done) begin
        if (ch4_cnt == ch4_delay) begin
            if (sd_ch4.we) begin sdram[sd_ch4.addr[24:0]] = sd_ch4.wdata; ch4_writes++; end
            else ch4_reads++;
            ch4_data <= {sdram[sd_ch4.addr[24:0] | 25'd1], sdram[sd_ch4.addr[24:0] & ~25'd1]};
            ch4_done <= 1;
        end else ch4_cnt <= ch4_cnt + 1;
    end
end
assign sd_ch4.ack = ch4_done; assign sd_ch4.rdata = ch4_data;

// every ch1 request of the running machine must begin in a cpu_phase cycle (the SDRAM
// controller starts ch4 accesses between those points)
// Not held to it: the first access after a reset (the OPL4 is still clearing its memories).
int  ch1_reqs = 0, ch1_off_phase = 0, ch1_at_reset = 0, since_reset = 0;
always @(posedge clk_core) begin
    since_reset <= reset ? 0 : since_reset + 1;
    if (!sys.upload && !reset && sd_ch1.ram_cs && !ch1_q) begin
        ch1_reqs++;
        if (!cpu_phase && since_reset < 16) ch1_at_reset++;
        else if (!cpu_phase) begin
            ch1_off_phase++;
            if (ch1_off_phase < 10) $display("%0t FAIL ch1 %s outside cpu_phase, address %h, %0d clk after the reset, CPU address %h mreq %b iorq %b rd %b wr %b m1 %b",
                $time, sd_ch1.rnw ? "read" : "write", sd_ch1.addr, since_reset, sys.MSX.cpu_bus.addr, sys.MSX.cpu_bus.mreq, sys.MSX.cpu_bus.iorq, sys.MSX.cpu_bus.rd, sys.MSX.cpu_bus.wr, sys.MSX.cpu_bus.m1);
        end
    end
end

// ------------------------------------------------------------------ SD card path of emu
wire        sdclk, sdmosi, sdmiso;
wire [31:0] sd_lba;
wire        sd_rd, sd_wr;
logic       sd_ack = 0, sd_buff_wr = 0, img_mounted = 0;
logic [8:0] sd_buff_addr = '0;
logic [7:0] sd_buff_dout = '0;
wire  [7:0] sd_buff_din;

spi_divmmc spi (
    .clk_sys(clk_core), .ext_SD_card_bus(ext_SD_card_bus), .ready(),
    .spi_ce(1'b1), .spi_clk(sdclk), .spi_di(sdmiso), .spi_do(sdmosi)
);

sd_card sd_card (
    .reset(reset), .clk_sys(clk_core), .img_mounted(img_mounted), .img_size(64'(img_bytes)),
    .sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
    .clk_spi(clk_sdram), .sdhc(1'b1), .sck(sdclk), .ss(1'b0), .mosi(sdmosi), .miso(sdmiso)
);

// HPS: a requested sector is streamed into sd_card after a short delay; a written sector is
// read from sd_card into the image
int sectors_read = 0, sectors_written = 0;
int hps_state = 0, hps_wait = 0, hps_idx = 0;
int unsigned hps_lba = 0;
always @(posedge clk_core) begin
    case (hps_state)
        0: if (sd_rd) begin hps_lba <= sd_lba; hps_wait <= 20; hps_state <= 1; end
           else if (sd_wr) begin hps_lba <= sd_lba; hps_wait <= 20; hps_state <= 10; end
        1: if (hps_wait == 0) begin sd_ack <= 1; hps_idx <= 0; hps_state <= 2; end
           else hps_wait <= hps_wait - 1;
        2: begin
               sd_buff_addr <= 9'(hps_idx);
               sd_buff_dout <= (hps_lba * 512 + hps_idx < img_bytes) ? img[hps_lba * 512 + hps_idx] : 8'h00;
               sd_buff_wr   <= 1;
               hps_state    <= 3;
           end
        3: begin
               sd_buff_wr <= 0;
               if (hps_idx == 511) hps_state <= 4;
               else begin hps_idx <= hps_idx + 1; hps_state <= 2; end
           end
        4: begin
               sd_ack <= 0; sectors_read <= sectors_read + 1; hps_wait <= 4; hps_state <= 5;
               if (sectors_read < 8 || sectors_read % 256 == 0)
                   $display("%0t SD read LBA %0d (sector %0d)", $time, hps_lba, sectors_read);
           end
        5: if (hps_wait == 0) hps_state <= 0; else hps_wait <= hps_wait - 1;
        10: if (hps_wait == 0) begin sd_ack <= 1; hps_idx <= 0; hps_state <= 11; end
            else hps_wait <= hps_wait - 1;
        11: begin sd_buff_addr <= 9'(hps_idx); hps_state <= 12; end
        12: hps_state <= 13;
        13: begin
                if (hps_lba * 512 + hps_idx < img_bytes) img[hps_lba * 512 + hps_idx] = sd_buff_din;
                if (hps_idx == 511) begin
                    sd_ack <= 0; sectors_written <= sectors_written + 1; hps_wait <= 4; hps_state <= 5;
                    if (sectors_written < 8 || sectors_written % 64 == 0)
                        $display("%0t SD write LBA %0d (written %0d)", $time, hps_lba, sectors_written);
                end else begin hps_idx <= hps_idx + 1; hps_state <= 11; end
            end
        default: hps_state <= 0;
    endcase
end

// ------------------------------------------------------------------ monitors
wire       ipl_en = sys.MSX.devices.ocm.ipl_en;
logic      ipl_q = 1'b0;
longint    t_ipl_end = 0;
int        vdp_writes = 0, main_m1 = 0, a8_writes = 0;   // VDP writes and MAIN M1 counted after the IPL
logic      req_q = 0;
always @(posedge clk_core) begin
    ipl_q <= ipl_en;
    if (ipl_q && !ipl_en) begin
        t_ipl_end = $time;
        $display("%0t IPL phase ended (first write to A8h), %0d sectors read", $time, sectors_read);
    end
    req_q <= sys.MSX.cpu_bus.req;
    if (sys.MSX.cpu_bus.req && !req_q && !reset) begin
        if (t_ipl_end != 0 && sys.MSX.cpu_bus.iorq && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[7:2] == 6'b100110) vdp_writes++;
        if (sys.MSX.cpu_bus.iorq && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[7:0] == 8'hA8) begin
            a8_writes++;
            if (a8_writes <= 4) $display("%0t OUT (A8h),%02h", $time, sys.MSX.cpu_bus.data);
        end
        if (!ipl_en && t_ipl_end != 0 && sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.m1 &&
            sys.MSX.active_slot == 2'd0 && sys.MSX.cpu_bus.addr < 16'h8000) main_m1++;
    end
end

// Port F4 (reset status): every access, with the stored value (bit 7 = 1: BIOS shows the logo)
wire [7:0] f4_reg = sys.MSX.devices.dev_reset_status.RESET_STATUS_DEV_INSTANCES[0].inst.latch_port_i.r_status;
int        boot = 1, f4_ipl_wr = 0, f4_bios_wr = 0;
logic [7:0] f4_first_read[int];
always @(posedge clk_core) begin
    if (sys.MSX.cpu_bus.req && !req_q && !reset && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 &&
        sys.MSX.cpu_bus.addr[7:0] == 8'hF4) begin
        if (sys.MSX.cpu_bus.wr) begin
            $display("%0t boot %0d: OUT (F4h),%02h (%s)", $time, boot, sys.MSX.cpu_bus.data, ipl_en ? "IPL" : "BIOS");
            if (ipl_en) f4_ipl_wr++; else f4_bios_wr++;
        end else begin
            $display("%0t boot %0d: IN (F4h) = %02h (%s)", $time, boot, f4_reg, ipl_en ? "IPL" : "BIOS");
            if (!ipl_en && !f4_first_read.exists(boot)) f4_first_read[boot] = f4_reg;
        end
    end
end

// ------------------------------------------------------------------ +dos monitors
bit dos = 0;
// Keyboard (keyboard.sv takes a new ps2_key value as an event): +keys=<ms> presses Space for
// 100 ms every <ms> once code runs from slot 2 (e.g. "HIT ANY KEY")
task automatic key_space(input bit down);
    ps2_key = {~ps2_key[10], down, 9'h029};
endtask
// Sound chip writes: PSG data (A1h), OPLL data (7Dh); OPLL output swing (min / max per status line)
int psg_wr = 0, opll_wr = 0;
int opll_lo = 1 << 30, opll_hi = -(1 << 30);
always @(posedge clk_core) begin
    if (int'(sys.MSX.devices.opll_sound) < opll_lo) opll_lo = int'(sys.MSX.devices.opll_sound);
    if (int'(sys.MSX.devices.opll_sound) > opll_hi) opll_hi = int'(sys.MSX.devices.opll_sound);
    if (sys.MSX.cpu_bus.req && !req_q && !reset && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.wr) begin
        if (sys.MSX.cpu_bus.addr[7:0] == 8'hA1) psg_wr++;
        if (sys.MSX.cpu_bus.addr[7:0] == 8'h7D) opll_wr++;
    end
end
// Switched I/O ports 40h-4Fh (OCM): writes and reads of 42h, slot modes
logic [1:0] slot2_mode_q = '0;
logic       slot1_mode_q = 1'b0;
int         swio_log = 0;
always @(posedge clk_core) begin
    if (dos && sys.MSX.cpu_bus.req && !req_q && !reset && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 &&
        sys.MSX.cpu_bus.addr[7:4] == 4'h4 && swio_log < 200) begin
        swio_log++;
        if (sys.MSX.cpu_bus.wr)
            $display("%0t SWIO OUT (%02Xh),%02h", $time, sys.MSX.cpu_bus.addr[7:0], sys.MSX.cpu_bus.data);
        else
            $display("%0t SWIO IN  (%02Xh)", $time, sys.MSX.cpu_bus.addr[7:0]);
    end
    slot1_mode_q <= sys.MSX.devices.ocm.Slot1Mode;
    slot2_mode_q <= sys.MSX.devices.ocm.Slot2Mode;
    if (dos && (slot1_mode_q != sys.MSX.devices.ocm.Slot1Mode || slot2_mode_q != sys.MSX.devices.ocm.Slot2Mode))
        $display("%0t Slot1Mode %b Slot2Mode %b", $time, sys.MSX.devices.ocm.Slot1Mode, sys.MSX.devices.ocm.Slot2Mode);
end

// Internal ESE-SCC / MegaRAM (mapper MEGARAM) per slot: RAM reads / writes, M1 fetches (code
// running from the slot), other writes (bank / mode / SCC registers), SCC sound register writes
// (9800-98FF, B800-B8FF); mode register writes (7FFE, BFFE) are logged
int ese_mode_log = 0;
int ese_rd[2] = '{0, 0}, ese_wr[2] = '{0, 0}, ese_m1[2] = '{0, 0}, ese_reg[2] = '{0, 0}, ese_snd[2] = '{0, 0};
always @(posedge clk_core) begin
    if (dos && sys.MSX.cpu_bus.req && !req_q && !reset && sys.MSX.cpu_bus.mreq &&
        sys.MSX.block_info.typ == MAPPER_MEGARAM) begin
        if (sys.MSX.cpu_bus.m1) ese_m1[sys.MSX.block_info.id]++;
        if (sys.MSX.memory_bus_slots.ram_cs) begin
            if (sys.MSX.cpu_bus.wr) ese_wr[sys.MSX.block_info.id]++;
            else                    ese_rd[sys.MSX.block_info.id]++;
        end else if (sys.MSX.cpu_bus.wr) begin
            ese_reg[sys.MSX.block_info.id]++;
            if (sys.MSX.cpu_bus.addr[15:8] == 8'h98 || sys.MSX.cpu_bus.addr[15:8] == 8'hB8)
                ese_snd[sys.MSX.block_info.id]++;
            if ((sys.MSX.cpu_bus.addr == 16'h7FFE || sys.MSX.cpu_bus.addr == 16'hBFFE) && ese_mode_log < 80) begin
                ese_mode_log++;
                $display("%0t ESE-SCC slot %0d mode %04h <= %02h", $time, sys.MSX.block_info.id + 1,
                         sys.MSX.cpu_bus.addr, sys.MSX.cpu_bus.data);
            end
        end
    end
end

// Shadow VRAM / VDP registers from the I/O ports, text screen dump
logic [7:0]  vram_sh [0:131071];
logic [7:0]  vreg [0:63];
logic [16:0] vaddr = '0;
logic [7:0]  v99_lat = '0;
bit          v99_second = 0;
always @(posedge clk_core) begin
    if (sys.MSX.cpu_bus.req && !req_q && !reset && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1) begin
        if (sys.MSX.cpu_bus.addr[7:0] == 8'h98) begin
            if (sys.MSX.cpu_bus.wr) vram_sh[vaddr] = sys.MSX.cpu_bus.data;
            vaddr = vaddr + 1'b1;
        end
        if (sys.MSX.cpu_bus.addr[7:0] == 8'h99) begin
            if (sys.MSX.cpu_bus.wr) begin
                if (!v99_second) begin v99_lat = sys.MSX.cpu_bus.data; v99_second = 1; end
                else begin
                    v99_second = 0;
                    if (sys.MSX.cpu_bus.data[7]) vreg[sys.MSX.cpu_bus.data[5:0]] = v99_lat;
                    else vaddr = {vreg[14][2:0], sys.MSX.cpu_bus.data[5:0], v99_lat};
                end
            end else v99_second = 0;
        end
    end
end

function automatic string screen_text();
    bit         t2   = vreg[1][4] && vreg[0][2];                    // TEXT2 80, TEXT1 40, else GRAPHIC1 32
    int         cols = vreg[1][4] ? (t2 ? 80 : 40) : 32;
    int unsigned base = t2 ? {vreg[2][6:2], 12'h000} : {vreg[2][6:0], 10'h000};
    string      txt  = "";
    for (int r = 0; r < 24; r++) begin
        string line = "";
        int    last = -1;
        for (int c = 0; c < cols; c++) begin
            logic [7:0] ch = vram_sh[17'(base + r * cols + c)];
            line = {line, string'((ch >= 8'h20 && ch < 8'h7F) ? ch : 8'h20)};
            if (ch > 8'h20 && ch < 8'h7F) last = c;
        end
        if (last >= 0) txt = {txt, $sformatf("  |%s\n", line.substr(0, last))};
    end
    return txt;
endfunction

// +vram_dump=<prefix>: VRAM as hex text (physical: 64 kB vram_lo, 64 kB vram_hi; GRAPHIC 6/7
// interleave even / odd bytes) and the VDP state, for an offline render of the screen
task automatic dump_vram(input string prefix, input int ms);
    int fd;
    fd = $fopen($sformatf("%s_%0d.hex", prefix, ms), "w");
    for (int i = 0; i < 65536; i++) $fwrite(fd, "%02x", sys.vram_lo.mem[i]);
    for (int i = 0; i < 65536; i++) $fwrite(fd, "%02x", sys.vram_hi.mem[i]);
    $fclose(fd);
    fd = $fopen($sformatf("%s_%0d.txt", prefix, ms), "w");
    $fdisplay(fd, "T1 %0d T2 %0d G1 %0d G2 %0d G3 %0d G4 %0d G5 %0d G6 %0d G7 %0d",
              sys.MSX.devices.v99.VDP_i.VDPMODETEXT1, sys.MSX.devices.v99.VDP_i.VDPMODETEXT2,
              sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC1, sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC2,
              sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC3, sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC4,
              sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC5, sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC6,
              sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC7);
    $fdisplay(fd, "R2 %02h R4 %02h R10R3 %03h R7 %02h DISP %0d YDOTS %0d R23 %02h YJK %0d YAE %0d",
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R2_PT_NAM_ADDR,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R4_PT_GEN_ADDR,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R10R3_COL_ADDR,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R7_FRAME_COL,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R1_DISP_ON,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R9_Y_DOTS,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R23_VSTART_LINE,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R25_YJK,
              sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R25_YAE);
    $fclose(fd);
endtask

function automatic bit contains(input string s, input string k);
    for (int i = 0; i + k.len() <= s.len(); i++) if (s.substr(i, i + k.len() - 1) == k) return 1;
    return 0;
endfunction

// ------------------------------------------------------------------ optional trace (+trace)
// histogram of M1 addresses of the IPL copy (FC00-FFFF), ESE bank / MegaSD register writes
bit trace = 0;
int pc_hist[int];
int bank_wr = 0;
always @(posedge clk_core) begin
    if (trace && sys.MSX.cpu_bus.req && !req_q && !reset && ipl_en) begin
        if (sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.addr >= 16'hFC00)
            pc_hist[int'(sys.MSX.cpu_bus.addr)]++;
        if (sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[15:13] == 3'b011 && bank_wr < 40) begin
            bank_wr++;
            $display("%0t ESE register %04h <= %02h", $time, sys.MSX.cpu_bus.addr, sys.MSX.cpu_bus.data);
        end
    end
end

task automatic print_trace();
    int n = 0;
    $display("M1 histogram (IPL, top addresses):");
    foreach (pc_hist[a]) if (pc_hist[a] > 1000) begin
        $display("  %04h: %0d", a, pc_hist[a]);
        if (++n > 40) break;
    end
endtask

// ------------------------------------------------------------------ run
initial begin
    string pack_name, img_name, bios_name, fw_name;
    int fd, c, errors = 0, run_ms = 20000;
    logic [127:0] st;
    int unsigned ese, ese_sd;

    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("img=%s", img_name) ||
        !$value$plusargs("bios=%s", bios_name)) begin
        $display("usage: +pack=<1chipMSX.msx> +img=<sd.img> +bios=<OCM-BIOS.rom>"); $finish;
    end
    fd = $fopen(pack_name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
    fd = $fopen(bios_name, "rb"); while ((c = $fgetc(fd)) != -1) bios.push_back(8'(c)); $fclose(fd);
    // the image up to the end of the BIOS file is enough (sectors are read from the start)
    img = new[4 * 1024 * 1024];
    fd = $fopen(img_name, "rb");
    img_bytes = 0;
    while (img_bytes < img.size() && (c = $fgetc(fd)) != -1) begin img[img_bytes] = 8'(c); img_bytes++; end
    $fclose(fd);
    $display("pack %0d B, BIOS %0d B, SD image %0d B loaded", pack.size(), bios.size(), img_bytes);

    trace = $test$plusargs("trace");
    dos   = $test$plusargs("dos");
    void'($value$plusargs("run_ms=%d", run_ms));
    status[11] = 1'b1;                                  // OCM internal mapper 4096 kB
    if ($value$plusargs("status=%h", st)) status = st;
    if ($value$plusargs("fw=%s", fw_name)) begin
        fd = $fopen(fw_name, "rb"); while ((c = $fgetc(fd)) != -1) fw.push_back(8'(c)); $fclose(fd);
    end
    $display("status %h, FW pack %0d B", status, fw.size());
    repeat (8) @(posedge clk_core);
    rst_core_async = 0;
    @(posedge clk_core); img_mounted = 1; @(posedge clk_core); img_mounted = 0;

    // HPS download of the FW pack (core start), then the MSX pack
    if (fw.size() > 0) begin
        ioctl_index = 16'd2; ioctl_download = 1;
        @(posedge clk_core); ioctl_addr = 27'(fw.size());
        @(posedge clk_core); ioctl_download = 0;
        wait (sys.upload);
        wait (!sys.upload);
        repeat (10) @(posedge clk_core);
    end
    ioctl_index = 16'd1; ioctl_download = 1;
    @(posedge clk_core); ioctl_addr = 27'(pack.size());
    @(posedge clk_core); ioctl_download = 0;
    wait (sys.upload);
    wait (!sys.upload);
    $display("%0t pack loaded, error=%0d", $time, sys.error);
    if (sys.error != ERR_NONE) begin $display("FAILED ocm_boot_tb: pack error"); $finish; end

    // until the BIOS runs, or timeout (about 7 s of MSX time; the BIOS load takes about 4 s)
    for (int i = 0; i < 600; i++) begin
        repeat (250_000) @(posedge clk_core);
        if (i % 40 == 0)
            $display("%0t progress: sectors=%0d ipl_en=%b A8 writes=%0d VDP writes=%0d MAIN M1=%0d",
                     $time, sectors_read, ipl_en, a8_writes, vdp_writes, main_m1);
        if (t_ipl_end != 0 && vdp_writes >= 16 && main_m1 >= 1000) break;
    end

    if (trace) print_trace();

    // +warm: wait until the BIOS marks the boot in F4 (after the logo), then a warm reset
    // (OSD Reset, status[21]); the BIOS must then see bit 7 = 0 and skip the logo
    if ($test$plusargs("warm")) begin
        for (int i = 0; i < 600 && f4_bios_wr == 0; i++) repeat (250_000) @(posedge clk_core);
        if (f4_bios_wr == 0) begin errors++; $display("FAIL BIOS did not write F4"); end
        repeat (200_000) @(posedge clk_core);
        $display("%0t warm reset (OSD)", $time);
        boot = 2; t_ipl_end = 0;
        status[21] = 1; repeat (4) @(posedge clk_core); status[21] = 0;
        for (int i = 0; i < 200 && !f4_first_read.exists(2); i++) repeat (250_000) @(posedge clk_core);
        if (!f4_first_read.exists(2)) begin errors++; $display("FAIL warm boot: BIOS did not read F4"); end
        else if (f4_first_read[2][7] !== 1'b0) begin errors++; $display("FAIL warm boot: F4 bit 7 = 1 (logo again)"); end
        else $display("warm boot: BIOS reads F4 = %02h, bit 7 = 0 (no logo)", f4_first_read[2]);
    end
    if (f4_first_read.exists(1) && f4_first_read[1][7] !== 1'b1) begin
        errors++; $display("FAIL cold boot: F4 bit 7 = 0 (no logo)");
    end

    // BIOS in ESE-RAM (SDRAM address = system address - 2^18)
    ese    = 32'(sys.memory_upload.ram_slots[sys.memory_upload.lay_slots[{2'd3, 2'd2, 2'd1}][19:16]][44:18]);   // RAM of block 3-2 page 1
    ese_sd = ese - (1 << 18);
    begin
        int bad = 0;
        foreach (bios[i]) if (sdram[ese_sd + i] !== bios[i]) bad++;
        if (bad) begin errors++; $display("FAIL ESE-RAM (%07h): %0d of %0d bytes differ from the BIOS", ese, bad, bios.size()); end
        else $display("ESE-RAM (%07h) holds the whole BIOS", ese);
    end
    if (t_ipl_end == 0)  begin errors++; $display("FAIL IPL phase did not end"); end
    if (main_m1 < 1000)  begin errors++; $display("FAIL BIOS does not run from MAIN ROM (%0d M1)", main_m1); end
    if (vdp_writes < 16) begin errors++; $display("FAIL BIOS did not set up the VDP (%0d writes)", vdp_writes); end
    $display("sectors read %0d, IPL end %0t, VDP writes %0d, MAIN M1 %0d", sectors_read, t_ipl_end, vdp_writes, main_m1);

    // +dos: run on; every 100 ms of MSX time a status line (if anything changed) and the text
    // screen (if changed). Ends on "No suitable" or +after_ms (default 1000) after code started
    // to run from slot 2 (more than 1000 M1 fetches there).
    if (dos) begin
        string last = "", now, st_last = "", st, dump = "";
        int    game_ms = -1, after_ms = 1000, keys = 0;
        void'($value$plusargs("after_ms=%d", after_ms));
        void'($value$plusargs("keys=%d", keys));
        void'($value$plusargs("vram_dump=%s", dump));
        for (int ms = 0; ms < run_ms; ms += 100) begin
            repeat (MSX::CLK_CORE_HZ / 10) @(posedge clk_core);
            st = $sformatf("SD rd %0d wr %0d | slot 1 rd %0d wr %0d m1 %0d reg %0d | slot 2 rd %0d wr %0d m1 %0d reg %0d snd %0d | PSG %0d OPLL %0d out %0d | mode %b %b | VDP R0 %02h R1 %02h R2 %02h",
                           sectors_read, sectors_written, ese_rd[0], ese_wr[0], ese_m1[0], ese_reg[0],
                           ese_rd[1], ese_wr[1], ese_m1[1], ese_reg[1], ese_snd[1], psg_wr, opll_wr, opll_hi - opll_lo,
                           sys.MSX.devices.ocm.Slot1Mode, sys.MSX.devices.ocm.Slot2Mode, vreg[0], vreg[1], vreg[2]);
            if (st != st_last) begin $display("%0t %0d ms: %s", $time, ms, st); st_last = st; end
            opll_lo = 1 << 30; opll_hi = -(1 << 30);
            now = screen_text();
            if (now != last) begin
                $display("%0t screen (%0d ms):\n%s", $time, ms, now);
                last = now;
            end
            if (game_ms < 0 && ese_m1[1] > 1000) begin
                game_ms = ms;
                $display("%0t code runs from slot 2 (ESE-SCC): %0d M1 fetches", $time, ese_m1[1]);
            end
            if (dump != "" && game_ms >= 0 && (ms - game_ms) % 1000 == 0) dump_vram(dump, ms);
            if (keys > 0 && game_ms >= 0 && ms > game_ms) begin
                if ((ms - game_ms) % keys == 0)   begin key_space(1); $display("%0t %0d ms: Space down", $time, ms); end
                if ((ms - game_ms) % keys == 100) key_space(0);
            end
            if (contains(now, "No suitable") || (game_ms >= 0 && ms >= game_ms + after_ms)) break;
        end
        $display("%0t final screen:\n%s", $time, screen_text());
        $display("ESE-SCC traffic: slot 1 rd %0d wr %0d m1 %0d, slot 2 rd %0d wr %0d m1 %0d, slot 2 SCC sound writes %0d",
                 ese_rd[0], ese_wr[0], ese_m1[0], ese_rd[1], ese_wr[1], ese_m1[1], ese_snd[1]);
        if (game_ms < 0) begin errors++; $display("FAIL: no code run from slot 2 (SofaROM did not start the ROM)"); end
    end

    $display("SDRAM ch1 requests of the machine: %0d, outside cpu_phase: %0d (right after a reset: %0d)",
             ch1_reqs, ch1_off_phase, ch1_at_reset);
    if (ch1_off_phase != 0 || ch1_reqs == 0) errors++;
    if (errors == 0) $display("PASS ocm_boot_tb");
    else             $display("FAILED ocm_boot_tb: %0d errors", errors);
    $finish;
end

endmodule
