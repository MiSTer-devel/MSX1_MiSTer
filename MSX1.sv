//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================
module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////
assign USER_OUT = '1;
assign {UART_RTS, UART_DTR} = 0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S   = 1;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign BUTTONS   = 0;

localparam VDNUM = 1 + 2*MSX::N_FDC;      // SD card + 2 drives per FDC position

/////////////////   CLOCKS   /////////////////
wire clk_core, clk_sdram, locked_sdram;
pll pll
(
   .refclk(CLK_50M),
   .rst(RESET),
   .outclk_0(clk_sdram),   // 85.909080 MHz = 4x clk_core
   .outclk_1(clk_core),    // 21.477270 MHz = MSX::CLK_CORE_HZ
   .locked(locked_sdram)
);

clock_bus_if clock_bus(clk_core, clk_sdram);
clock #(.sysCLK(MSX::CLK_CORE_HZ)) clock
(
   .clock_bus(clock_bus)
);

/////////////////   RESET   /////////////////
// Async sources (HPS reset, PLL not locked) are synchronized per clock domain
// (async assert, sync release); the core reset is registered in msx_system.
wire rst_core_async, sdram_init, reset;
reset_sync rst_sync_core  (.clk(clk_core),  .arst(RESET || ~locked_sdram), .rst(rst_core_async));
reset_sync rst_sync_sdram (.clk(clk_sdram), .arst(~locked_sdram),          .rst(sdram_init));

/////////////////   HPS   /////////////////
// status bits (O/T/R in CONF_STR, CONF_STR_SLOT_A/B in rtl/msx_config.sv):
//  [0]      reset (system menu)
//  [2:1]    aspect ratio
//  [5:3]    scandoubler Fx
//  [8:6]    scale
//  [9]      tape rewind
//  [10]     reset & detach ROM cartridge
//  [11]     OCM internal mapper size
//  [12]     OCM reset after SD mount
//  [13]     OCM joysticks swap
//  [14]     OCM mouse port
//  [15]     OCM CPU speed
//  [16]     OCM CPU type (R800: MULUB / MULUW)
//  [20:17]  slot A cartridge type (not OCM)
//  [21]     reset / reset and close OSD
//  [22]     OCM slot 1 (internal ESE-SCC)
//  [24:23]  OCM slot 2 (internal ESE-SCC / MegaRAM)
//  [25]     vertical crop
//  [26]     firmware switch (turbo R, machines with the Matsushita switched I/O)
//  [27]     pause when OSD open
//  [32:29]  slot B cartridge type (not OCM)
//  [38]     SRAM save
//  [39]     SRAM load
//  [40]     tape input (file / ADC)
//  [41]     border
//  [42]     tape monitor (0 = on)
// Free: [28], [37:33], [127:43]
`include "build_id.v"
localparam CONF_STR = {
   "MSX1;UART115200,MIDI;",
   "-;",
   // load addresses = MSX::DDR3_* (package.sv)
   "FC1,MSX,Load ROM PACK,30000000;",
   "FC2,MSX,Load FW  PACK,30800000;",
   "FC6,DB,Load DB MAPPERS,31600000;",
   "-;",
   // drives of FDC position 0 (internal FDC or FDC cartridge in slot A); N_FDC = 2 would add
   // "h6S3,DSK,Mount Drive 1;" and "h7S4,DSK,Mount Drive 2;" under slot A
   "h4S1,DSK,Mount Drive 1;",
   "h5S2,DSK,Mount Drive 2;",
   "H3-;",
   CONF_STR_SLOT_A,
   "H1FS3,ROM,Load,32000000;",
   "H3-;",
   CONF_STR_SLOT_B,
   "H2F4,ROM,Load,33000000;",
   "h0-;",
   "h0SC0,VHD,Load SD card;",
   "h3O[12],Reset after Mount,No,Yes;",
   "HA-;",
   "HAR[38],SRAM Save;",
   "HAR[39],SRAM Load;",
   // OCM (h3): same options and order as MSX_MiSTer
   "h3-;",
   "h3O[15],CPU speed,Normal,Turbo(+F11);",
   "h3O[16],CPU type,Z80,R800;",
   "h3-;",
   CONF_STR_OCM_SLOTS,
   "h3-;",
   "h3O[11],Internal Mapper,2048KB RAM,4096KB RAM;",
   "h3-;",
   "h3O[13],Joysticks Swap,No,Yes;",
   "h3O[14],Mouse,Port 1,Port 2;",
   // firmware switch (hC): machines with the S1990 or the Matsushita switched I/O
   "hC-;",
   "hCO[26],Firmware switch,Off,On;",
   "H3-;",
   "H3O[40],Tape Input,File,ADC;",
   "H3O[42],Tape Monitor,On,Off;",
   "HBF5,CAS,Cas File,31700000;",
   "HBT9,Tape Rewind;",
   "-;",
   "P1,Video settings;",
   "P1O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
   "P1O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
   "P1O[25],Vertical Crop,No,Yes;",
   "P1O[8:6],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
   "P1O[41],Border,No,Yes;",
   "-;",
   "O[27],Pause when OSD open,No,Yes;",
   "T[21],Reset;",
   "H3R[10],Reset & Detach ROM Cartridge;",
   "R[21],Reset and close OSD;",
   // joystick button names (joy bit 4 = trigger A, 5 = trigger B); not "J1", it forces
   // keyboard joystick emulation and takes the cursor keys
   "J,Fire 1,Fire 2;",
   "I,BAD MSX CONF,NOT SUPPORTED CONF,NOT SUPPORTED BLOCK,BAD MSX FW CONF,NOT FW CONF,DEVICE MISSING,Device not in this core build,No CRC32 DB,Not find CRC32 in DB,SMALL MEMORY,FDC already in machine,ROM too big;",
   "V,v",`BUILD_DATE
};

wire             forced_scandoubler;
wire      [21:0] gamma_bus;
wire       [1:0] buttons;
wire     [127:0] status;
wire      [15:0] status_menumask;
wire             info_req;
wire       [7:0] info;
wire      [10:0] ps2_key;
wire      [24:0] ps2_mouse;
wire      [31:0] joy0, joy1;
wire             ioctl_download;
wire      [15:0] ioctl_index;
wire             ioctl_wr;
wire      [26:0] ioctl_addr;
wire       [7:0] ioctl_dout;
wire      [31:0] sd_lba[0:VDNUM-1];
wire       [5:0] sd_blk_cnt[0:VDNUM-1];
wire [VDNUM-1:0] sd_rd;
wire [VDNUM-1:0] sd_wr;
wire [VDNUM-1:0] sd_ack;
wire      [13:0] sd_buff_addr;
wire       [7:0] sd_buff_dout;
wire       [7:0] sd_buff_din[0:VDNUM-1];
wire             sd_buff_wr;
wire [VDNUM-1:0] img_mounted;
wire      [63:0] img_size;
wire             img_readonly;
wire      [15:0] sdram_sz;
wire      [64:0] rtc;
wire      [31:0] uart_speed;

hps_io #(.CONF_STR(CONF_STR),.VDNUM(VDNUM)) hps_io
(
   .clk_sys(clock_bus.clk),
   .HPS_BUS(HPS_BUS),
   .EXT_BUS(),
   .gamma_bus(gamma_bus),
   .forced_scandoubler(forced_scandoubler),
   .buttons(buttons),
   .status(status),
   .status_menumask(status_menumask),
   .ps2_key(ps2_key),
   .ps2_mouse(ps2_mouse),
   .joystick_0(joy0),
   .joystick_1(joy1),
   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_wr(ioctl_wr),
   .ioctl_addr(ioctl_addr),
   .ioctl_dout(ioctl_dout),
   .img_mounted(img_mounted),
   .img_size(img_size),
   .img_readonly(img_readonly),
   .sd_lba(sd_lba),
   .sd_blk_cnt(sd_blk_cnt),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din),
   .sd_buff_wr(sd_buff_wr),
   .sdram_sz(sdram_sz),
   .RTC(rtc),
   .info_req(info_req),
   .info(info),
   .uart_speed(uart_speed)
);

// HPS image slots: 1..6 floppy drives, 0 virtual SD card
block_device_if block_device_FDD[2*MSX::N_FDC]();
block_device_if block_device_SD();
MSX::msx_config_t msx_config;

blockDevMux #(.VDNUM(VDNUM)) blockDevMux
(
   .clk(clock_bus.clk),
   .reset(reset),
   .msx_config(msx_config),
   .block_device_FDD(block_device_FDD),
   .block_device_SD(block_device_SD),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_lba(sd_lba),
   .sd_blk_cnt(sd_blk_cnt),
   .sd_buff_din(sd_buff_din),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_wr(sd_buff_wr),
   .img_mounted(img_mounted),
   .img_size(img_size),
   .img_readonly(img_readonly)
);

/////////////////   MSX SYSTEM   /////////////////
MSX::video_t     video_bus;
ext_sd_card_if   ext_SD_card_bus();
memory_bus_if    memory_bus_sdram_ch1();
memory_bus_if    memory_bus_sdram_ch2();
memory_bus_if    memory_bus_sdram_ch3();
wave_bus_if      wave_bus_sdram_ch4();
wire             cpu_phase;
wire             pause;
wire       [5:0] joy[2];

// paused machine: the scaler keeps the last frame (HDMI only, the OSD is drawn after it)
assign HDMI_FREEZE = pause;
wire             tape_in;
wire      [27:0] ddr3_addr;
wire       [7:0] ddr3_dout;
wire             ddr3_rd, ddr3_ready;

assign joy[0] = joy0[5:0];
assign joy[1] = joy1[5:0];

msx_system msx_system
(
   .clock_bus(clock_bus),
   .rst_core_async(rst_core_async),
   .reset(reset),
   .status(status),
   .status_menumask(status_menumask),
   .info_req(info_req),
   .info(info),
   .ps2_key(ps2_key),
   .ps2_mouse(ps2_mouse),
   .joy(joy),
   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_addr(ioctl_addr),
   .rtc(rtc),
   .sdram_sz(sdram_sz),
   .uart_speed(uart_speed),
   .img_readonly(img_readonly),
   .img_size(img_size),
   .sd_img_mounted(block_device_SD.img_mounted),
   .osd_status(OSD_STATUS),
   .block_device_FDD(block_device_FDD),
   .msx_config(msx_config),
   .video_bus(video_bus),
   .audio_L(AUDIO_L),
   .audio_R(AUDIO_R),
   .led_turbo(led_turbo),
   .led_pause(led_pause),
   .pause(pause),
   .uart_rxd(UART_RXD),
   .uart_txd(UART_TXD),
   .tape_adc(tape_in),
   .ext_SD_card_bus(ext_SD_card_bus),
   .memory_bus_sdram_ch1(memory_bus_sdram_ch1),
   .memory_bus_sdram_ch2(memory_bus_sdram_ch2),
   .memory_bus_sdram_ch3(memory_bus_sdram_ch3),
   .wave_bus_sdram_ch4(wave_bus_sdram_ch4),
   .cpu_phase(cpu_phase),
   .ddr3_addr(ddr3_addr),
   .ddr3_rd(ddr3_rd),
   .ddr3_dout(ddr3_dout),
   .ddr3_ready(ddr3_ready)
);

/////////////////   SD CARD   /////////////////
// Ext SD card of the MSX cartridges: real SD card on the SD-SPI pins,
// or the virtual SD image (block_device_SD) once one is mounted.
wire sdclk;
wire sdmosi;
wire vsdmiso;
wire sdmiso = vsd_sel ? vsdmiso : SD_MISO;

logic vsd_sel = 0;
// img_mounted is a level for the rest of the HPS transaction, img_size comes in an earlier
// one and stays stable: no edge detection needed (doc/top-level.md)
always_ff @(posedge clock_bus.clk) if(block_device_SD.img_mounted) vsd_sel <= |img_size;

assign SD_CS   = vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;

logic sd_act;
logic [31:0] timeout = 0;
always_ff @(posedge clock_bus.clk) begin
    logic old_mosi, old_miso;

    old_mosi <= sdmosi;
    old_miso <= sdmiso;

    sd_act <= 0;
    if(timeout < 1000000) begin
        timeout <= timeout + 1;
        sd_act <= 1;
    end

    if((old_mosi ^ sdmosi) || (old_miso ^ sdmiso)) timeout <= 0;
end

// turbo R: R800 on the user LED; machine pause / turbo R pause LED on the disk LED (VHD / SD activity otherwise)
wire   led_turbo, led_pause;
assign LED_USER = (vsd_sel & sd_act) | led_turbo;
assign LED_DISK = {1'b1, (~vsd_sel & sd_act) | led_pause};

spi_divmmc spi
(
   .clk_sys(clock_bus.clk),
   .ext_SD_card_bus(ext_SD_card_bus),
   .ready(),

   .spi_ce(1'b1),
   .spi_clk(sdclk),
   .spi_di(sdmiso),
   .spi_do(sdmosi)
);

sd_card sd_card
(
    .reset(reset),
    .clk_sys(clock_bus.clk),
    .img_mounted(block_device_SD.img_mounted),
    .img_size(img_size),
    .sd_lba(block_device_SD.lba),
    .sd_rd(block_device_SD.rd),
    .sd_wr(block_device_SD.wr),
    .sd_ack(block_device_SD.ack),
    .sd_buff_addr(block_device_SD.buff_addr[8:0]),
    .sd_buff_dout(block_device_SD.buff_dout),
    .sd_buff_din(block_device_SD.buff_din),
    .sd_buff_wr(block_device_SD.buff_wr),

    .clk_spi(clk_sdram),
    .sdhc(1),
    .sck(sdclk),
    .ss(~vsd_sel),
    .mosi(sdmosi),
    .miso(vsdmiso)
);

/////////////////   VIDEO   /////////////////
wire       vga_de;
wire       scandoubler;
wire [1:0] ar    = status[2:1];
wire [2:0] scale = status[5:3];
wire [2:0] sl    = scale != 0 ? scale - 1'd1 : 3'd0;

assign VGA_SL = sl[1:0];
assign CLK_VIDEO   = clk_sdram;
assign scandoubler = forced_scandoubler || scale != 0;

// Vertical crop as MSX_MiSTer: 216 lines on a 1080 line output, else 240, 480 with the scandoubler
logic [11:0] vcrop;
always_ff @(posedge CLK_VIDEO) begin
	vcrop <= (HDMI_HEIGHT == 12'd1080) ? 12'd216 : 12'd240;
	if (scandoubler) vcrop <= 12'd480;
end

video_freak video_freak
(
   .CLK_VIDEO(CLK_VIDEO),
   .CE_PIXEL(CE_PIXEL),
   .VGA_VS(video_bus.VS),
   .HDMI_WIDTH(HDMI_WIDTH),
   .HDMI_HEIGHT(HDMI_HEIGHT),
   .VGA_DE(VGA_DE),
   .VIDEO_ARX(VIDEO_ARX),
   .VIDEO_ARY(VIDEO_ARY),
   .VGA_DE_IN(vga_de),
   .ARX((ar == 0) ? 12'd4 : {10'b0, (ar - 1'd1)}),
   .ARY((ar == 0) ? 12'd3 : 12'd0),
   .CROP_SIZE(status[25] ? vcrop : 12'd0),
   .CROP_OFF(0),
   .SCALE(status[8:6])
);

video_mixer #(.GAMMA(1), .LINE_LENGTH(582)) video_mixer
(
   .CLK_VIDEO(CLK_VIDEO),
   .hq2x(scale==1),
   .scandoubler(scandoubler),
   .gamma_bus(gamma_bus),

   .ce_pix(video_bus.ce_pix),
   .R(video_bus.R),
   .G(video_bus.G),
   .B(video_bus.B),
   .HSync(video_bus.HS),
   .VSync(video_bus.VS),
   .HBlank(video_bus.hblank),
   .VBlank(video_bus.vblank),

   .HDMI_FREEZE(0),
   .freeze_sync(),

   .CE_PIXEL(CE_PIXEL),
   .VGA_R(VGA_R),
   .VGA_G(VGA_G),
   .VGA_B(VGA_B),
   .VGA_VS(VGA_VS),
   .VGA_HS(VGA_HS),
   .VGA_DE(vga_de)
);

/////////////////   TAPE INPUT (ADC)   /////////////////
wire tape_adc, tape_adc_act;
assign tape_in = tape_adc_act & tape_adc;

ltc2308_tape #(.ADC_RATE(120000), .CLK_RATE(MSX::CLK_CORE_HZ)) tape
(
   .clk(clock_bus.clk),
   .ADC_BUS(ADC_BUS),
   .dout(tape_adc),
   .active(tape_adc_act)
);

/////////////////   DDR3 (configuration packs, cassette images)   /////////////////
assign DDRAM_CLK = clock_bus.clk;

ddram buffer
(
   .reset(reset),
   .DDRAM_CLK(DDRAM_CLK),
   .DDRAM_BUSY(DDRAM_BUSY),
   .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
   .DDRAM_ADDR(DDRAM_ADDR),
   .DDRAM_DOUT(DDRAM_DOUT),
   .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
   .DDRAM_RD(DDRAM_RD),
   .DDRAM_DIN(DDRAM_DIN),
   .DDRAM_BE(DDRAM_BE),
   .DDRAM_WE(DDRAM_WE),
   .addr(ddr3_addr),
   .dout(ddr3_dout),
   .din(),
   .we(),
   .rd(ddr3_rd),
   .ready(ddr3_ready),
   .dout64()
);

/////////////////   SDRAM   /////////////////
sdram sdram
(
   .init(sdram_init),
   .clk(clk_sdram),
   .core_phase(clock_bus.ce_10m7_p),   // clkdiv4[0]: register toggling every clk_core cycle
   .doRefresh(1'd0),

   .SDRAM_DQ(SDRAM_DQ),
   .SDRAM_A(SDRAM_A),
   .SDRAM_DQML(SDRAM_DQML),
   .SDRAM_DQMH(SDRAM_DQMH),
   .SDRAM_BA(SDRAM_BA),
   .SDRAM_nCS(SDRAM_nCS),
   .SDRAM_nWE(SDRAM_nWE),
   .SDRAM_nRAS(SDRAM_nRAS),
   .SDRAM_nCAS(SDRAM_nCAS),
   .SDRAM_CKE(SDRAM_CKE),
   .SDRAM_CLK(SDRAM_CLK),

   .memory_bus_ch1(memory_bus_sdram_ch1),

   .ch2_dout (memory_bus_sdram_ch2.q),
   .ch2_din  (memory_bus_sdram_ch2.data),
   .ch2_addr (memory_bus_sdram_ch2.addr),
   .ch2_req  (memory_bus_sdram_ch2.ram_cs),
   .ch2_rnw  (memory_bus_sdram_ch2.rnw),
   .ch2_ready(memory_bus_sdram_ch2.sdram_ready),
   .ch2_done (memory_bus_sdram_ch2.sdram_done),

   .ch3_dout (memory_bus_sdram_ch3.q),
   .ch3_din  (memory_bus_sdram_ch3.data),
   .ch3_addr (memory_bus_sdram_ch3.addr),
   .ch3_req  (memory_bus_sdram_ch3.ram_cs),
   .ch3_rnw  (memory_bus_sdram_ch3.rnw),
   .ch3_ready(memory_bus_sdram_ch3.sdram_ready),
   .ch3_done (memory_bus_sdram_ch3.sdram_done),

   .ch4_dout (wave_bus_sdram_ch4.rdata),
   .ch4_din  (wave_bus_sdram_ch4.wdata),
   .ch4_addr (wave_bus_sdram_ch4.addr),
   .ch4_req  (wave_bus_sdram_ch4.req),
   .ch4_rnw  (~wave_bus_sdram_ch4.we),
   .ch4_done (wave_bus_sdram_ch4.ack),
   .cpu_phase(cpu_phase)
);

endmodule
