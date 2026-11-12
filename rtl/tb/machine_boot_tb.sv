// Machine boot from a floppy: msx_system with a machine pack, blockDevMux and an HPS model
// serving a DSK image on drive 1 of FDC position 0 (VD 1, msx_config.fdd[0]). Logs the floppy
// controller traffic (TC8566AF: command and result bytes, the sectors the drive loads) and
// the text screen (VDP registers and VRAM).
// Checks: the pack loads, the drive loads the boot sector (LBA 0); with a TC8566AF the disk ROM
// runs (M1 fetches in the controller's block) and Read Data ends normally (ST0 IC = 00); with
// +expect=<text> that the text appears on the screen (e.g. printed by AUTOEXEC.BAS).
// +dsk=none: no disk in the drive (the boot must not hang on the empty drive).
// +key=<hex>: a key held down from the start until +key_ms (default 8000), PS/2 code with bit 8
// = extended, e.g. 171 = Delete (Panasonic FS-A1F: skips the A1 Cockpit firmware).
// Cartridge: +fw=<CART_FW_EN.msx> +db=<mappers.db> +rom=<game.rom> loads a ROM into slot A as the
// OSD does (FW pack, mapper database, ROM; the mapper comes from the CRC32 in the database).
// +slotb=<n>: OSD slot B item (CONF_STR_SLOT_B, 8 = MoonSound; needs +fw). +ch4_delay=<clk>: slower
// OPL4 sample memory. +audio=<file>: the sound output as raw 16 bit stereo, 44100 Hz.
// +audio_min=<n>: the left output must swing by at least n.
// +slota=<n>: OSD slot A item (CONF_STR_SLOT_A, 1 = FDC; needs +fw). +error=<n>: the pack load
// must stop with this error_t (e.g. 11 = ERR_FDC_PRESENT), then PASS.
// +frames=<prefix> +frame_ms=<ms> +frame_n=<n>: n frames of the video output (DE area) from
// frame_ms on as <prefix>_NNN.ppm.
// Turbo R: +firmware=1 turns the firmware switch on (OSD status[26]); +pause_ms=<ms> presses the
// Pause key (hps_io event 377h) at that time and checks that the BIOS lights the pause LED (A7h
// bit 0) and turns it off after a second press 500 ms later. The FS-A1ST BIOS pauses BASIC in
// software (A7h = 81h); when it enables the hardware pause (bit 1) the CPU must stop as well.
// Other machines: +pause_ms=<ms> the Pause key pauses the machine (CPU stopped, sound muted,
// pause LED), the second press 500 ms later resumes it.
// +osd_ms=<ms>: the OSD opens at that time with "Pause when OSD open" off (the machine runs),
// 200 ms later the option goes on (paused), 400 ms later the OSD closes (runs again).
// Run: wsl.exe -- bash rtl/tb/run_machine_boot.sh <machine.msx> <image.dsk> [expected text]
module machine_boot_tb;

// clk_sdram = 4x clk_core, phase aligned (as the PLL)
logic clk_sdram = 0, clk_core = 0;
always #1 clk_sdram = ~clk_sdram;
always #4 clk_core  = ~clk_core;

clock_bus_if clock_bus(clk_core, clk_sdram);
clock #(.sysCLK(MSX::CLK_CORE_HZ)) clock_i (.clock_bus(clock_bus));

// ------------------------------------------------------------------ files
byte unsigned pack[$], fwpk[$], db[$], rom[$];
byte unsigned dsk[];
int unsigned  dsk_bytes = 0;

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
wire          led_pause;
logic         osd_status = 0;
wire   [27:0] ddr3_addr;
wire          ddr3_rd, ddr3_ready;
wire    [7:0] ddr3_dout;

block_device_if block_device_FDD[2*MSX::N_FDC]();
block_device_if block_device_SD();
logic    [10:0] ps2_key = '0;                           // +key: {toggle, down, extended, code}
ext_sd_card_if  ext_SD_card_bus();
memory_bus_if   sd_ch1(), sd_ch2(), sd_ch3();
wave_bus_if     sd_ch4();
wire            cpu_phase;

msx_system sys (
    .clock_bus(clock_bus), .rst_core_async(rst_core_async), .reset(reset),
    .status(status), .status_menumask(status_menumask), .info_req(info_req), .info(info),
    .ps2_key(ps2_key), .ps2_mouse(25'd0), .joy(joy), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .rtc(65'd0), .sdram_sz(16'h8002), .uart_speed(32'd115200),
    .img_readonly(1'b0), .img_size(64'd0), .sd_img_mounted(1'b0),
    .block_device_FDD(block_device_FDD), .msx_config(msx_config),
    .video_bus(video_bus), .audio_L(audio_L), .audio_R(audio_R), .uart_rxd(1'b1), .tape_adc(1'b0),
    .led_pause(led_pause), .osd_status(osd_status),
    .ext_SD_card_bus(ext_SD_card_bus),
    .memory_bus_sdram_ch1(sd_ch1), .memory_bus_sdram_ch2(sd_ch2), .memory_bus_sdram_ch3(sd_ch3),
    .wave_bus_sdram_ch4(sd_ch4), .cpu_phase(cpu_phase),
    .ddr3_addr(ddr3_addr), .ddr3_rd(ddr3_rd), .ddr3_dout(ddr3_dout),
    .ddr3_ready(ddr3_ready)
);
assign ext_SD_card_bus.data_from_SD = 8'hFF;  assign ext_SD_card_bus.busy = 1'b0;

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
    .dout64()
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
                (a >= 32'h300000  && a - 32'h300000  < fwpk.size())  ? fwpk[a - 32'h300000] :
                (a >= MSX::DDR3_ROM_A && a - MSX::DDR3_ROM_A < rom.size()) ? rom[a - MSX::DDR3_ROM_A] :
                (a >= 32'h1600000 && a - 32'h1600000 < db.size())  ? db[a - 32'h1600000] : 8'hFF;
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

// the SDRAM controller starts ch4 accesses between the points where the CPU can ask for
// memory: every ch1 request of the running machine must begin in a cpu_phase cycle
// Not held to it: the first access after a reset (the OPL4 is still clearing its memories).
// (A write to FFFFh that mapped RAM into page 3 used to reach that RAM a clk later: C1.)
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

// sound output: range, and every 487th clk into a file (44.1 kHz); pause window: clk with sound
int audio_fd = 0, audio_min = 0, audio_lo = 0, audio_hi = 0, audio_div = 0;
bit pause_window = 0;
int pause_sound = 0;
always @(posedge clk_core) if (!reset) begin
    if (pause_window && (audio_L != 0 || audio_R != 0)) pause_sound++;
    if ($signed(audio_L) < audio_lo) audio_lo = $signed(audio_L);
    if ($signed(audio_L) > audio_hi) audio_hi = $signed(audio_L);
    audio_div <= audio_div == 486 ? 0 : audio_div + 1;
    if (audio_fd != 0 && audio_div == 0)
        $fwrite(audio_fd, "%c%c%c%c", audio_L[7:0], audio_L[15:8], audio_R[7:0], audio_R[15:8]);
end

// ------------------------------------------------------------------ floppy images: blockDevMux + HPS
localparam int VDNUM = 1 + 2*MSX::N_FDC;
localparam int VD    = 1;                               // drive 1 of FDC position 0 (msx_config.fdd[0])
wire [31:0] sd_lba[VDNUM];
wire  [5:0] sd_blk_cnt[VDNUM];
wire [VDNUM-1:0] sd_rd, sd_wr;
logic [VDNUM-1:0] sd_ack = '0;
logic [13:0] sd_buff_addr = '0;
logic  [7:0] sd_buff_dout = '0;
wire   [7:0] sd_buff_din[VDNUM];
logic        sd_buff_wr = 0;
logic [VDNUM-1:0] img_mounted = '0;
logic [63:0] img_size = '0;

blockDevMux #(.VDNUM(VDNUM)) bdmux (
    .clk(clk_core), .reset(reset), .msx_config(msx_config),
    .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
    .sd_buff_wr(sd_buff_wr), .img_mounted(img_mounted), .img_size(img_size),
    .img_readonly(1'b0), .block_device_FDD(block_device_FDD), .block_device_SD(block_device_SD)
);
assign block_device_SD.rd = 1'b0;  assign block_device_SD.wr = 1'b0;  assign block_device_SD.lba = '0;
assign block_device_SD.blk_cnt = '0;  assign block_device_SD.buff_din = '0;

int lba_reads = 0, lba0_reads = 0;
initial forever begin                                   // HPS: one request at a time
    @(posedge clk_core);
    if (sd_rd[VD]) begin
        int lba, cnt;
        lba = int'(sd_lba[VD]);
        cnt = (int'(sd_blk_cnt[VD]) + 1) * 512;
        if (lba_reads < 40) $display("%0t HPS read VD%0d LBA %0d, %0d sectors", $time, VD, lba, cnt / 512);
        lba_reads++;
        if (lba == 0) lba0_reads++;
        repeat (2000) @(posedge clk_core);
        sd_ack[VD] <= 1'b1;
        for (int i = 0; i < cnt; i++) begin
            int a = lba * 512 + i;
            @(posedge clk_core);
            sd_buff_addr <= 14'(i);
            sd_buff_dout <= a < dsk_bytes ? dsk[a] : 8'hFF;
            sd_buff_wr   <= 1'b1;
            @(posedge clk_core);
            sd_buff_wr   <= 1'b0;
        end
        @(posedge clk_core); sd_ack[VD] <= 1'b0;
    end
end

// ------------------------------------------------------------------ monitors
logic req_q = 0;
always @(posedge clk_core) req_q <= sys.MSX.cpu_bus.req;
wire  access = sys.MSX.cpu_bus.req && !req_q && !reset;

// Turbo R: writes to the S1990 (E5h) with the last M1 fetch, CPU / DRAM mode changes, accesses
// to the main RAM through main_cs (Panasonic RAM banks, DRAM mode)
logic [15:0] last_m1 = '0;
int          s1990_wr = 0, main_rd = 0, main_wr = 0, a7_wr = 0, m1_all = 0, vdp_wr = 0;
logic        r800_q = 0, dram_q = 0;
always @(posedge clk_core) begin
    if (access && sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.m1) begin last_m1 <= sys.MSX.cpu_bus.addr; m1_all++; end
    if (access && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[7:2] == 6'b100110) vdp_wr++;
    if (access && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[7:0] == 8'hA7
        && sys.io_device[DEV_TURBOR_PAUSE][0].enable) begin
        a7_wr++;
        if (a7_wr <= 20) $display("%0t pause A7 <= %02h (last M1 %04h)", $time, sys.MSX.cpu_bus.data, last_m1);
    end
    if (access && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.wr && sys.MSX.cpu_bus.addr[7:0] == 8'hE5
        && sys.io_device[DEV_S1990][0].enable) begin
        s1990_wr++;
        if (s1990_wr <= 40) $display("%0t S1990 E5 <= %02h (last M1 %04h)", $time, sys.MSX.cpu_bus.data, last_m1);
    end
    if (access && sys.MSX.msx_slots.main_cs) begin
        if (sys.MSX.cpu_bus.wr) main_wr++; else main_rd++;
    end
    r800_q <= sys.MSX.turbor_r800;
    dram_q <= sys.MSX.turbor_dram;
    if (!reset && r800_q != sys.MSX.turbor_r800) $display("%0t S1990: %s", $time, sys.MSX.turbor_r800 ? "R800" : "Z80");
    if (!reset && dram_q != sys.MSX.turbor_dram) $display("%0t S1990: %s mode", $time, sys.MSX.turbor_dram ? "DRAM" : "ROM");
end

// Floppy controller (TC8566AF at its fixed position): bytes written to / read from the data
// register; M1 fetches in its block (the disk ROM runs)
wire        tc_cs   = sys.MSX.devices.FDC.FDC_INSTANCES[0].tc.cs_dev;
wire [3:0]  tc_a    = sys.MSX.cpu_bus.addr[3:0];
wire        tc_win  = tc_cs && sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.addr[13:4] == 10'h3FF;
int         disk_m1 = 0, fdc_log = 0, fdc_lines = 0, fdc_rep = 0, reads_ok = 0, reads_bad = 0;
string      fdc_last = "";
logic [7:0] cmd[$], res[$];
always @(posedge clk_core) begin
    if (access && tc_cs && sys.MSX.cpu_bus.mreq && sys.MSX.cpu_bus.m1) disk_m1++;
    // command byte (7FFB / 7FF5 write)
    if (access && tc_win && sys.MSX.cpu_bus.wr && (tc_a == 4'hB || tc_a == 4'h5))
        cmd.push_back(sys.MSX.cpu_bus.data);
end
// data register reads: sampled at the end of the read (data valid then)
logic rd_dat_q = 0;
wire  rd_dat = tc_win && sys.MSX.cpu_bus.rd && (tc_a == 4'hB || tc_a == 4'h5);
wire  [7:0] tc_dout = sys.MSX.devices.FDC.FDC_INSTANCES[0].tc_data;
logic [7:0] dat_q;
always @(posedge clk_core) begin
    rd_dat_q <= rd_dat;
    if (rd_dat) dat_q <= tc_dout;
    // result bytes (RD_CMD); sector data of the execution phase is not logged
    if (rd_dat_q && !rd_dat && sys.MSX.devices.FDC.FDC_INSTANCES[0].tc.TC8566AF.fdc.RD_CMD)
        res.push_back(dat_q);
end
// log a command with its result once the controller is idle again (MSR = 80h)
wire idle = sys.MSX.devices.FDC.FDC_INSTANCES[0].tc.TC8566AF.fdc.datnum == 0;
logic idle_q = 1;
always @(posedge clk_core) begin
    idle_q <= idle;
    if (!idle_q && idle && cmd.size() > 0) begin
        string s = "";
        foreach (cmd[i]) s = {s, $sformatf(" %02h", cmd[i])};
        s = {s, " ->"};
        foreach (res[i]) s = {s, $sformatf(" %02h", res[i])};
        // a repeated line (Sense Interrupt polling) is only counted
        if (s == fdc_last) fdc_rep++;
        else begin
            if (fdc_rep > 0) $display("%0t FDC (previous line %0d times more)", $time, fdc_rep);
            if (fdc_lines < 400) $display("%0t FDC%s", $time, s);
            fdc_lines++;
            fdc_last = s;
            fdc_rep  = 0;
        end
        fdc_log++;
        if ((cmd[0] & 8'h1F) == 8'h06 && res.size() == 7) begin
            if (res[0][7:6] == 2'b00) reads_ok++; else reads_bad++;
        end
        cmd.delete(); res.delete();
    end
end

// Text screen of a TMS99xx (VDP18): Text 40 / Graphic 1-2 32 columns, name table R#2
function automatic string tms_text();
    logic [7:0]  r1   = sys.MSX.devices.tms.tms_i.cpu_io_b.ctrl_reg_q[1];
    logic [7:0]  r2   = sys.MSX.devices.tms.tms_i.cpu_io_b.ctrl_reg_q[2];
    int          cols = r1[4] ? 40 : 32;
    int unsigned base = {r2[3:0], 10'h000};
    string       txt  = "";
    if (r1[3]) return "";                                   // multicolor
    for (int r = 0; r < 24; r++) begin
        string line = "";
        int    last = -1;
        for (int c = 0; c < cols; c++) begin
            logic [7:0] ch = sys.vram_lo.mem[base + r * cols + c];
            line = {line, string'((ch >= 8'h20 && ch < 8'h7F) ? ch : 8'h20)};
            if (ch > 8'h20 && ch < 8'h7F) last = c;
        end
        if (last >= 0) txt = {txt, $sformatf("  |%s\n", line.substr(0, last))};
    end
    return txt;
endfunction

// Text screen from the VDP (mode, name table register) and the physical VRAM (vram_lo holds
// 0000-FFFF outside GRAPHIC 6 / 7); TEXT1 40, TEXT2 80, GRAPHIC 1-3 32 columns, else empty
function automatic string screen_text();
    bit          t1   = sys.MSX.devices.v99.VDP_i.VDPMODETEXT1;
    bit          t2   = sys.MSX.devices.v99.VDP_i.VDPMODETEXT2;
    bit          g13  = sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC1 || sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC2 ||
                        sys.MSX.devices.v99.VDP_i.VDPMODEGRAPHIC3;
    logic [6:0]  r2   = sys.MSX.devices.v99.VDP_i.U_VDP_REGISTER.REG_R2_PT_NAM_ADDR;
    int          cols = t2 ? 80 : t1 ? 40 : 32;
    int unsigned base = t2 ? {r2[6:2], 12'h000} : {r2, 10'h000};
    string       txt  = "";
    if (sys.MSX.devices.tms.io_device[0].enable) return tms_text();
    if (!(t1 || t2 || g13)) return "";
    for (int r = 0; r < 24; r++) begin
        string line = "";
        int    last = -1;
        for (int c = 0; c < cols; c++) begin
            int unsigned a  = base + r * cols + c;
            logic  [7:0] ch = a < 65536 ? sys.vram_lo.mem[a] : sys.vram_hi.mem[a - 65536];
            line = {line, string'((ch >= 8'h20 && ch < 8'h7F) ? ch : 8'h20)};
            if (ch > 8'h20 && ch < 8'h7F) last = c;
        end
        if (last >= 0) txt = {txt, $sformatf("  |%s\n", line.substr(0, last))};
    end
    return txt;
endfunction

// Text in the physical VRAM (as written, any text mode): 64 kB banks vram_lo / vram_hi and the
// linear view (GRAPHIC 6 / 7 interleave the banks)
function automatic bit vram_has(input string k);
    int n = k.len();
    for (int a = 0; a + n <= 131072; a++) begin
        bit lo = a + n <= 65536, hi = a + n <= 65536, li = 1;
        for (int i = 0; i < n && (lo || hi || li); i++) begin
            if (lo && sys.vram_lo.mem[a + i] != k[i]) lo = 0;
            if (hi && sys.vram_hi.mem[a + i] != k[i]) hi = 0;
            if (li && (((a + i) & 1) ? sys.vram_hi.mem[(a + i) >> 1] : sys.vram_lo.mem[(a + i) >> 1]) != k[i]) li = 0;
        end
        if (lo || hi || li) return 1;
    end
    return 0;
endfunction

// +vram_dump=<prefix>: VRAM as hex text and the VDP mode, for an offline render
task automatic dump_vram(input string prefix);
    int fd;
    fd = $fopen({prefix, ".hex"}, "w");
    for (int i = 0; i < 65536; i++) $fwrite(fd, "%02x", sys.vram_lo.mem[i]);
    for (int i = 0; i < 65536; i++) $fwrite(fd, "%02x", sys.vram_hi.mem[i]);
    $fclose(fd);
    fd = $fopen({prefix, ".txt"}, "w");
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

// Video capture: frames of the DE area as PPM
string      frame_prefix = "";
int         frame_left = 0, frame_idx = 0, fr_w = 0, fr_h = 0, fr_x = 0;
bit         frame_arm = 0, fr_on = 0, prev_vbl = 1;
int         frame_fd;
// +cmdlog: V99x8 command engine start / end (CE) with the command register R#46
bit cmdlog, ce_q;
initial cmdlog = $test$plusargs("cmdlog");
always @(posedge clk_core) if (cmdlog) begin
    if (sys.MSX.cpu_bus.req && sys.MSX.cpu_bus.iorq && !sys.MSX.cpu_bus.m1 && sys.MSX.cpu_bus.wr &&
        sys.MSX.cpu_bus.addr[7:2] == 6'b100110 && sys.MSX.cpu_bus.addr[1:0] != 2'd0)
        $display("%0t OUT (%02hh),%02hh", $time, sys.MSX.cpu_bus.addr[7:0], sys.MSX.cpu_bus.data);
    if (sys.MSX.devices.v99.VDP_i.VDPCMDCE != ce_q)
        $display("%0t CE %0d", $time, sys.MSX.devices.v99.VDP_i.VDPCMDCE);
    ce_q <= sys.MSX.devices.v99.VDP_i.VDPCMDCE;
end

always @(posedge clk_core) if (video_bus.ce_pix) begin
    if (video_bus.vblank && !prev_vbl && fr_on) begin            // frame done
        for (int y = fr_h; y < 240; y++) for (int i = 0; i < 256; i++) $fwrite(frame_fd, "%c%c%c", 8'd0, 8'd0, 8'd0);
        $fclose(frame_fd);
        $display("%0t frame %0d: %0dx%0d", $time, frame_idx, fr_w, fr_h);
        frame_idx++; frame_left--; fr_on = 0;
    end
    if (!video_bus.vblank && prev_vbl && frame_arm && frame_left > 0) begin   // frame starts
        frame_fd = $fopen($sformatf("%s_%03d.ppm", frame_prefix, frame_idx), "wb");
        $fwrite(frame_fd, "P6\n%0d %0d\n255\n", 256, 192 + 48);
        fr_on = 1; fr_w = 0; fr_h = 0; fr_x = 0;
    end
    prev_vbl = video_bus.vblank;
    if (fr_on && !video_bus.vblank) begin
        if (!video_bus.hblank) begin
            if (fr_x < 256 && fr_h < 240) $fwrite(frame_fd, "%c%c%c", video_bus.R, video_bus.G, video_bus.B);
            fr_x++;
        end else if (fr_x > 0) begin
            for (int i = fr_x; i < 256; i++) if (fr_h < 240) $fwrite(frame_fd, "%c%c%c", 8'd0, 8'd0, 8'd0);
            if (fr_x > fr_w) fr_w = fr_x;
            fr_h++; fr_x = 0;
        end
    end
end
final if (fr_on) begin
    for (int y = fr_h; y < 240; y++) for (int i = 0; i < 256; i++) $fwrite(frame_fd, "%c%c%c", 8'd0, 8'd0, 8'd0);
    $fclose(frame_fd);
end

function automatic bit contains(input string s, input string k);
    for (int i = 0; i + k.len() <= s.len(); i++) if (s.substr(i, i + k.len() - 1) == k) return 1;
    return 0;
endfunction

// ------------------------------------------------------------------ machine pause (key / OSD)
// m1_from: M1 count at the start of the window
task automatic check_paused(input string what, input int m1_from, inout int errors);
    if (m1_all != m1_from)           begin errors++; $display("FAIL %s: CPU runs in the pause (%0d M1)", what, m1_all - m1_from); end
    if (!led_pause)                  begin errors++; $display("FAIL %s: pause LED off", what); end
    if (!sys.MSX.devices.sound_mix.mute) begin errors++; $display("FAIL %s: sound not muted", what); end
    if (pause_sound != 0)            begin errors++; $display("FAIL %s: sound output in the pause (%0d clk)", what, pause_sound); end
    $display("%0t %s: paused, %0d M1, %0d clk with sound", $time, what, m1_all - m1_from, pause_sound);
endtask
task automatic check_running(input string what, input int m1_from, inout int errors);
    if (m1_all == m1_from)           begin errors++; $display("FAIL %s: CPU does not run", what); end
    if (led_pause)                   begin errors++; $display("FAIL %s: pause LED on", what); end
    if (sys.MSX.devices.sound_mix.mute) begin errors++; $display("FAIL %s: sound muted", what); end
    $display("%0t %s: runs, %0d M1", $time, what, m1_all - m1_from);
endtask

// ------------------------------------------------------------------ run
initial begin
    string pack_name, dsk_name, expect_txt = "", last = "", now, dump, fname;
    int frame_ms = 0;
    int fd, c, errors = 0, run_ms = 15000, found_ms = -1, key_ms = 8000, pause_ms = -1, fw = 0, m1_paused = 0;
    int slota = 0, slotb = 0, want_err = 0, osd_ms = -1;
    logic [8:0] key = '0;
    bit         use_key, no_disk, tc_used, turbor_pause;

    if (!$value$plusargs("pack=%s", pack_name) || !$value$plusargs("dsk=%s", dsk_name)) begin
        $display("usage: +pack=<machine.msx> +dsk=<image.dsk> [+expect=<text>] [+run_ms=<ms>]"); $finish;
    end
    void'($value$plusargs("expect=%s", expect_txt));
    void'($value$plusargs("run_ms=%d", run_ms));
    void'($value$plusargs("key_ms=%d", key_ms));
    use_key = $value$plusargs("key=%h", key);
    void'($value$plusargs("pause_ms=%d", pause_ms));
    void'($value$plusargs("osd_ms=%d", osd_ms));
    if ($value$plusargs("firmware=%d", fw)) status[26] = fw[0];
    if ($value$plusargs("slota=%d", slota)) status[20:17] = 4'(slota);
    if ($value$plusargs("slotb=%d", slotb)) status[32:29] = 4'(slotb);
    void'($value$plusargs("ch4_delay=%d", ch4_delay));
    void'($value$plusargs("audio_min=%d", audio_min));
    if ($value$plusargs("audio=%s", fname)) audio_fd = $fopen(fname, "wb");
    void'($value$plusargs("error=%d", want_err));
    fd = $fopen(pack_name, "rb"); while ((c = $fgetc(fd)) != -1) pack.push_back(8'(c)); $fclose(fd);
    if ($value$plusargs("fw=%s", fname))  begin fd = $fopen(fname, "rb"); while ((c = $fgetc(fd)) != -1) fwpk.push_back(8'(c));  $fclose(fd); end
    if ($value$plusargs("db=%s", fname))  begin fd = $fopen(fname, "rb"); while ((c = $fgetc(fd)) != -1) db.push_back(8'(c));  $fclose(fd); end
    if ($value$plusargs("rom=%s", fname)) begin fd = $fopen(fname, "rb"); while ((c = $fgetc(fd)) != -1) rom.push_back(8'(c)); $fclose(fd); end
    if ($value$plusargs("frames=%s", frame_prefix)) begin
        void'($value$plusargs("frame_ms=%d", frame_ms));
        frame_left = 10; void'($value$plusargs("frame_n=%d", frame_left));
    end
    if (rom.size() > 0) $display("FW pack %0d B, mapper DB %0d B, ROM %0d B", fwpk.size(), db.size(), rom.size());
    no_disk = dsk_name == "none";
    dsk = new[2 * 1024 * 1024];
    if (!no_disk) begin
        fd = $fopen(dsk_name, "rb");
        while (dsk_bytes < dsk.size() && (c = $fgetc(fd)) != -1) begin dsk[dsk_bytes] = 8'(c); dsk_bytes++; end
        $fclose(fd);
    end
    $display("pack %0d B, disk image %0d B", pack.size(), dsk_bytes);

    repeat (8) @(posedge clk_core);
    rst_core_async = 0;
    // HPS downloads as at the core start (FW pack, mapper DB), the MSX pack, then the ROM (OSD)
    if (fwpk.size() > 0) begin
        ioctl_index = 16'd2; ioctl_download = 1;
        @(posedge clk_core); ioctl_addr = 27'(fwpk.size());
        @(posedge clk_core); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
        wait (sys.upload); wait (!sys.upload);
        repeat (10) @(posedge clk_core);
    end
    if (db.size() > 0) begin
        ioctl_index = 16'd6; ioctl_download = 1;
        @(posedge clk_core); ioctl_addr = 27'(db.size());
        @(posedge clk_core); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
        repeat (10) @(posedge clk_core);
    end
    ioctl_index = 16'd1; ioctl_download = 1;
    @(posedge clk_core); ioctl_addr = 27'(pack.size());
    @(posedge clk_core); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
    wait (sys.upload);
    wait (!sys.upload);
    if (rom.size() > 0) begin
        repeat (10) @(posedge clk_core);
        ioctl_index = 16'd3; ioctl_download = 1;
        @(posedge clk_core); ioctl_addr = 27'(rom.size());
        @(posedge clk_core); ioctl_download = 0; ioctl_addr = ioctl_addr + 1'd1;   // hps_io: +1 at the end
        wait (sys.upload); wait (!sys.upload);
    end
    $display("%0t pack loaded, error=%0d, msx_config.fdd=%b", $time, sys.error, msx_config.fdd);
    if (want_err != 0) begin
        if (int'(sys.error) == want_err) $display("PASS machine_boot_tb: pack error %0d as expected", want_err);
        else                             $display("FAILED machine_boot_tb: pack error %0d, expected %0d", sys.error, want_err);
        $finish;
    end else if (sys.error != ERR_NONE) begin $display("FAILED machine_boot_tb: pack error"); $finish; end
    turbor_pause = sys.io_device[DEV_TURBOR_PAUSE][0].enable;
    if (!no_disk && !msx_config.fdd[VD - 1]) begin errors++; $display("FAIL msx_config.fdd[%0d] = 0: VD %0d not enabled", VD - 1, VD); end

    // key down once the keyboard map of the pack is loaded
    if (use_key) begin
        ps2_key = {1'b1, 1'b1, key};
        $display("%0t key %03h down", $time, key);
    end

    // image into the internal drive (as the OSD mount)
    if (!no_disk) begin
        @(posedge clk_core); img_size = 64'(dsk_bytes); img_mounted[VD] = 1'b1;
        @(posedge clk_core); img_mounted = '0;
    end

    for (int ms = 0; ms < run_ms; ms += 100) begin
        repeat (MSX::CLK_CORE_HZ / 10) @(posedge clk_core);
        if (frame_prefix != "" && ms + 100 >= frame_ms) frame_arm = 1;
        if (use_key && ps2_key[9] && ms + 100 >= key_ms) begin
            ps2_key = {~ps2_key[10], 1'b0, ps2_key[8:0]};
            use_key = 0;
            $display("%0t %0d ms: key %03h released", $time, ms, ps2_key[8:0]);
        end
        // hardware pause: Pause key, the CPU must stop; the key again, it must run
        if (pause_ms >= 0 && (ms == pause_ms || ms == pause_ms + 500)) begin
            ps2_key = {~ps2_key[10], 10'h377};
            $display("%0t %0d ms: Pause key, A7 = %02h", $time, ms, sys.MSX.devices.dev_turbor_pause.status);
        end
        if (pause_ms >= 0 && !turbor_pause) begin
            // machine without A7h: the Pause key pauses the whole machine
            if (ms == pause_ms + 100) begin m1_paused = m1_all; pause_sound = 0; pause_window = 1; end
            if (ms == pause_ms + 400) begin
                pause_window = 0;
                check_paused("Pause key", m1_paused, errors);
                m1_paused = m1_all;
            end
            if (ms == pause_ms + 800) check_running("second Pause key", m1_paused, errors);
        end
        if (osd_ms >= 0) begin
            if (ms == osd_ms) begin osd_status = 1; m1_paused = m1_all; $display("%0t %0d ms: OSD open, pause option off", $time, ms); end
            if (ms == osd_ms + 100) check_running("OSD open, option off", m1_paused, errors);
            if (ms == osd_ms + 200) begin status[27] = 1; $display("%0t %0d ms: pause option on", $time, ms); end
            if (ms == osd_ms + 300) begin m1_paused = m1_all; pause_sound = 0; pause_window = 1; end
            if (ms == osd_ms + 500) begin pause_window = 0; check_paused("OSD open, option on", m1_paused, errors); end
            if (ms == osd_ms + 600) begin osd_status = 0; m1_paused = m1_all; $display("%0t %0d ms: OSD closed", $time, ms); end
            if (ms == osd_ms + 800) check_running("OSD closed", m1_paused, errors);
        end
        if (pause_ms >= 0 && turbor_pause && ms == pause_ms + 100) m1_paused = m1_all;
        if (pause_ms >= 0 && turbor_pause && ms == pause_ms + 400) begin
            if (!sys.MSX.devices.dev_turbor_pause.paused) begin errors++; $display("FAIL the Pause key did not set the pause"); end
            if (!sys.MSX.devices.dev_turbor_pause.pause_led) begin errors++; $display("FAIL pause LED off after the Pause key (A7 = %02h)", sys.MSX.devices.dev_turbor_pause.status); end
            if (sys.MSX.devices.dev_turbor_pause.status[1]) begin
                if (!sys.MSX.devices.dev_turbor_pause.hw_pause) begin errors++; $display("FAIL no hardware pause with A7 bit 1"); end
                if (m1_all != m1_paused) begin errors++; $display("FAIL CPU runs in the hardware pause (%0d M1)", m1_all - m1_paused); end
                else $display("%0t %0d ms: hardware pause, CPU stopped", $time, ms);
            end else
                $display("%0t %0d ms: software pause by the BIOS (A7 = %02h), %0d M1 in 300 ms", $time, ms,
                         sys.MSX.devices.dev_turbor_pause.status, m1_all - m1_paused);
            m1_paused = m1_all;
        end
        if (pause_ms >= 0 && turbor_pause && ms == pause_ms + 800) begin
            if (sys.MSX.devices.dev_turbor_pause.paused) begin errors++; $display("FAIL still paused after the second Pause key"); end
            if (sys.MSX.devices.dev_turbor_pause.pause_led) begin errors++; $display("FAIL pause LED on after the second Pause key (A7 = %02h)", sys.MSX.devices.dev_turbor_pause.status); end
            if (m1_all == m1_paused) begin errors++; $display("FAIL CPU does not run after the pause"); end
            else $display("%0t %0d ms: CPU runs again (%0d M1)", $time, ms, m1_all - m1_paused);
        end
        now = screen_text();
        if (now != last) begin $display("%0t screen (%0d ms):\n%s", $time, ms, now); last = now; end
        if (ms % 1000 == 0)
            $display("%0t %0d ms: M1 %0d, VDP writes %0d, disk ROM M1 %0d, FDC commands %0d, reads ok %0d bad %0d, HPS reads %0d",
                     $time, ms, m1_all, vdp_wr, disk_m1, fdc_log, reads_ok, reads_bad, lba_reads);
        if (expect_txt != "" && (contains(now, expect_txt) || (ms % 500 == 0 && vram_has(expect_txt)))) begin
            found_ms = ms; break;
        end
    end
    $display("%0t final screen:\n%s", $time, screen_text());
    if (found_ms < 0 && expect_txt != "" && vram_has(expect_txt)) found_ms = run_ms;
    if ($value$plusargs("vram_dump=%s", dump)) dump_vram(dump);
    $display("disk ROM M1 %0d, FDC commands %0d, Read Data ok %0d / abnormal %0d, HPS reads %0d (LBA 0: %0d)",
             disk_m1, fdc_log, reads_ok, reads_bad, lba_reads, lba0_reads);
    if (sys.io_device[DEV_S1990][0].enable)
        $display("turbo R: S1990 E5 writes %0d, A7 writes %0d, main RAM via main_cs: %0d reads, %0d writes", s1990_wr, a7_wr, main_rd, main_wr);

    // controller checks only for the TC8566AF (a WD2793 machine checks the drive and the screen)
    tc_used = sys.io_device[DEV_TC8566AF][0].enable;
    if (!tc_used) $display("no TC8566AF in this machine: controller checks skipped");
    if (tc_used && disk_m1 < 1000) begin errors++; $display("FAIL disk ROM does not run (%0d M1)", disk_m1); end
    if (!no_disk && lba0_reads == 0) begin errors++; $display("FAIL boot sector (LBA 0) not loaded"); end
    if (tc_used && !no_disk && reads_ok == 0) begin errors++; $display("FAIL no Read Data with a normal end"); end
    $display("SDRAM ch1 requests of the machine: %0d, outside cpu_phase: %0d (right after a reset: %0d)",
             ch1_reqs, ch1_off_phase, ch1_at_reset);
    if (ch1_off_phase != 0) errors++;
    if (sys.io_device[DEV_OPL4][0].enable)
        $display("OPL4: %0d sample memory reads, %0d writes, sound output %0d .. %0d", ch4_reads, ch4_writes, audio_lo, audio_hi);
    if (audio_min > 0 && audio_hi - audio_lo < audio_min) begin
        errors++; $display("FAIL sound output %0d .. %0d, expected a swing of %0d", audio_lo, audio_hi, audio_min);
    end
    if (audio_fd != 0) $fclose(audio_fd);
    if (expect_txt != "") begin
        if (found_ms < 0) begin errors++; $display("FAIL \"%s\" not on the screen", expect_txt); end
        else $display("\"%s\" on the screen at %0d ms", expect_txt, found_ms);
    end
    if (errors == 0) $display("PASS machine_boot_tb");
    else             $display("FAILED machine_boot_tb: %0d errors", errors);
    $finish;
end

endmodule
