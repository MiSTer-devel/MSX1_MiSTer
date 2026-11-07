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
   //Master input clock
   input         CLK_50M,

   //Async reset from top-level module.
   //Can be used as initial reset.
   input         RESET,

   //Must be passed to hps_io module
   inout  [48:0] HPS_BUS,

   //Base video clock. Usually equals to CLK_SYS.
   output        CLK_VIDEO,

   //Multiple resolutions are supported using different CE_PIXEL rates.
   //Must be based on CLK_VIDEO
   output        CE_PIXEL,

   //Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
   //if VIDEO_ARX[12] or VIDEO_ARY[12] is set then [11:0] contains scaled size instead of aspect ratio.
   output [12:0] VIDEO_ARX,
   output [12:0] VIDEO_ARY,

   output  [7:0] VGA_R,
   output  [7:0] VGA_G,
   output  [7:0] VGA_B,
   output        VGA_HS,
   output        VGA_VS,
   output        VGA_DE,    // = ~(VBlank | HBlank)
   output        VGA_F1,
   output [1:0]  VGA_SL,
   output        VGA_SCALER, // Force VGA scaler
   output        VGA_DISABLE, // analog out is off

   input  [11:0] HDMI_WIDTH,
   input  [11:0] HDMI_HEIGHT,
   output        HDMI_FREEZE,
   output        HDMI_BLACKOUT,
   output        HDMI_BOB_DEINT,

`ifdef MISTER_FB
   // Use framebuffer in DDRAM
   // FB_FORMAT:
   //    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
   //    [3]   : 0=16bits 565 1=16bits 1555
   //    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
   //
   // FB_STRIDE either 0 (rounded to 256 bytes) or multiple of pixel size (in bytes)
   output        FB_EN,
   output  [4:0] FB_FORMAT,
   output [11:0] FB_WIDTH,
   output [11:0] FB_HEIGHT,
   output [31:0] FB_BASE,
   output [13:0] FB_STRIDE,
   input         FB_VBL,
   input         FB_LL,
   output        FB_FORCE_BLANK,

`ifdef MISTER_FB_PALETTE
   // Palette control for 8bit modes.
   // Ignored for other video modes.
   output        FB_PAL_CLK,
   output  [7:0] FB_PAL_ADDR,
   output [23:0] FB_PAL_DOUT,
   input  [23:0] FB_PAL_DIN,
   output        FB_PAL_WR,
`endif
`endif

   output        LED_USER,  // 1 - ON, 0 - OFF.

   // b[1]: 0 - LED status is system status OR'd with b[0]
   //       1 - LED status is controled solely by b[0]
   // hint: supply 2'b00 to let the system control the LED.
   output  [1:0] LED_POWER,
   output  [1:0] LED_DISK,

   // I/O board button press simulation (active high)
   // b[1]: user button
   // b[0]: osd button
   output  [1:0] BUTTONS,

   input         CLK_AUDIO, // 24.576 MHz
   output [15:0] AUDIO_L,
   output [15:0] AUDIO_R,
   output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
   output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

   //ADC
   inout   [3:0] ADC_BUS,

   //SD-SPI
   output        SD_SCK,
   output        SD_MOSI,
   input         SD_MISO,
   output        SD_CS,
   input         SD_CD,

   //High latency DDR3 RAM interface
   //Use for non-critical time purposes
   output        DDRAM_CLK,
   input         DDRAM_BUSY,
   output  [7:0] DDRAM_BURSTCNT,
   output [28:0] DDRAM_ADDR,
   input  [63:0] DDRAM_DOUT,
   input         DDRAM_DOUT_READY,
   output        DDRAM_RD,
   output [63:0] DDRAM_DIN,
   output  [7:0] DDRAM_BE,
   output        DDRAM_WE,

   //SDRAM interface with lower latency
   output        SDRAM_CLK,
   output        SDRAM_CKE,
   output [12:0] SDRAM_A,
   output  [1:0] SDRAM_BA,
   inout  [15:0] SDRAM_DQ,
   output        SDRAM_DQML,
   output        SDRAM_DQMH,
   output        SDRAM_nCS,
   output        SDRAM_nCAS,
   output        SDRAM_nRAS,
   output        SDRAM_nWE,

`ifdef MISTER_DUAL_SDRAM
   //Secondary SDRAM
   //Set all output SDRAM_* signals to Z ASAP if SDRAM2_EN is 0
   input         SDRAM2_EN,
   output        SDRAM2_CLK,
   output [12:0] SDRAM2_A,
   output  [1:0] SDRAM2_BA,
   inout  [15:0] SDRAM2_DQ,
   output        SDRAM2_nCS,
   output        SDRAM2_nCAS,
   output        SDRAM2_nRAS,
   output        SDRAM2_nWE,
`endif

   input         UART_CTS,
   output        UART_RTS,
   input         UART_RXD,
   output        UART_TXD,
   output        UART_DTR,
   input         UART_DSR,

   // Open-drain User port.
   // 0 - D+/RX
   // 1 - D-/TX
   // 2..6 - USR2..USR6
   // Set USER_OUT to 1 to read from USER_IN.
   input   [6:0] USER_IN,
   output  [6:0] USER_OUT,

   input         OSD_STATUS
);


///////// Default values for ports not used in this core /////////
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_S = 1;
assign AUDIO_L = audio_L;
assign AUDIO_R = audio_R;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign LED_USER  = vsd_sel & sd_act;
assign LED_DISK  = {1'b1, ~vsd_sel & sd_act};
assign BUTTONS = 0;

localparam VDNUM = 7;
localparam sysCLK = 21477270;

video_bus_if video_bus();
clock_bus_if clock_bus(clk_core, clk_sdram);
ext_sd_card_if ext_SD_card_bus();
flash_bus_if flash_bus();
vram_bus_if vram_bus();
FDD_if FDD_bus[3]();
block_device_if block_device_FDD[6]();
block_device_if block_device_SD();
block_device_if block_device_nvram[4]();
memory_bus_if memory_bus_msx();
memory_bus_if memory_bus_upload();
memory_bus_if memory_bus_flash();
memory_bus_if memory_bus_backup();
memory_bus_if memory_bus_sdram_ch1();
memory_bus_if memory_bus_sdram_ch2();
memory_bus_if memory_bus_sdram_ch3();

MSX::user_config_t msx_user_config;
MSX::config_cart_t cart_conf[2];
MSX::block_t       slot_layout[64];
MSX::lookup_RAM_t  lookup_RAM[16];
MSX::lookup_SRAM_t lookup_SRAM[4];
MSX::io_device_t   io_device[32][3];
MSX::io_device_mem_ref_t io_memory[8];
MSX::slot_expander_t slot_expander[4];
MSX::msx_config_t msx_config;

wire             forced_scandoubler;
wire             scandoubler;
wire      [21:0] gamma_bus;
wire       [1:0] buttons;
wire     [127:0] status;
wire      [10:0] ps2_key;
wire      [24:0] ps2_mouse;
wire      [31:0] joy0, joy1;
wire       [5:0] joy[2];
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
logic            reset      = 1'b1;    // registered in clk_core, see CLOCKS / RESET
logic            hard_reset = 1'b1;
wire      [31:0] uart_speed;

//[0]     RESET
//[2:1]   Aspect ratio
//[5:3]   Scandoubler
//[8:6]   Scale
//[9]     Tape rewind
//[10]    Reset & Detach
//[11]    OCM INTERNAL MAPPER SIZE
//[12]    OCM Reset after mount
//[14:13] VideoMode
//[15]    OCM CPU SPEED
//[16]    OCM CPU TYPE
//[20:17] SLOT A CART TYPE
//21      Reset
//[23:22] RESERVA
//[25:24] RESERVA
//[28:26] RESERVA
//[32:29] SLOT B CART TYPE
//[34:33] RESERVA
//[37:35] RESERVA
//[38]    SRAM SAVE
//[39]    SRAM LOAD
//[40]    Tape input
//[41]    BORDER
`include "build_id.v"
localparam CONF_STR = {
   "MSX1;UART115200,MIDI;",
   "-;",
   "FC1,MSX,Load ROM PACK,30000000;",
   "FC2,MSX,Load FW  PACK,30300000;",
   "FC6,DB,Load DB MAPPERS,31600000;",
   "-;",
   "h8S5,DSK,Mount int. Drive 1;",
   "h9S6,DSK,Mount int. Drive 2;",
   "-;",
   CONF_STR_SLOT_A,
   "H1FS3,ROM,Load,30C00000;",
   "h4S1,DSK,Mount Drive 1;",
   "h5S2,DSK,Mount Drive 2;",
   "-;",
   CONF_STR_SLOT_B,
   "H2F4,ROM,Load,31100000;",
   "h6S3,DSK,Mount Drive 1;",
   "h7S4,DSK,Mount Drive 2;",
   "h0-;",
   "h0SC0,VHD,Load SD card;",
   "h3O[12],Reset after Mount,No,Yes;",
   "HA-;",
   "HAR[38],SRAM Save;",
   "HAR[39],SRAM Load;",
   "-;",
   "h3O[11],Internal Mapper,2048KB RAM,4096KB RAM;",

   "h3O[15],CPU speed,Normal,Turbo(+F11);",
	"h3O[16],CPU type,Z80,R800;",

   "O[40],Tape Input,File,ADC;",
   "HBF5,CAS,Cas File,31700000;",
   "HBT9,Tape Rewind;",
   "-;",
   "P1,Video settings;",
   "P1O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
   "P1O[5:3],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
   "P1O[8:6],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer,HV-Integer;",
   "P1O[41],Border,No,Yes;",
   "-;",
   "T[21],Reset;",
   "R[10],Reset & Detach ROM Cartridge;",
   "R[21],Reset and close OSD;",
   "I,BAD MSX CONF,NOT SUPPORTED CONF,NOT SUPPORTED BLOCK,BAD MSX FW CONF,NOT FW CONF,DEVICE MISSING,Exceeded number of IO_DEVICE,No CRC32 DB,Not find CRC32 in DB,SMALL MEMORY;",
   "V,v",`BUILD_DATE
};

wire [15:0] status_menumask;
wire [1:0] sdram_size;
wire [7:0] info;
wire info_req;

assign status_menumask[0] = io_device[DEV_OCM_BOOT][0].enable || cart_conf[0].typ == CART_TYP_MFRSD;
assign status_menumask[1] = ROM_A_load_hide || io_device[DEV_OCM_BOOT][0].enable ;
assign status_menumask[2] = ROM_B_load_hide || io_device[DEV_OCM_BOOT][0].enable ;
assign status_menumask[3] = io_device[DEV_OCM_BOOT][0].enable;
assign status_menumask[9:4] = msx_config.fdd[5:0];
assign status_menumask[10] = lookup_SRAM[0].size + lookup_SRAM[1].size + lookup_SRAM[2].size + lookup_SRAM[3].size == 0;
assign status_menumask[11] = msx_user_config.cas_audio_src == CAS_AUDIO_ADC;
assign status_menumask[15:12] = '0;
assign sdram_size         = sdram_sz[15] ? sdram_sz[1:0] : 2'b00;

assign info_req = error != ERR_NONE;
assign info     = 8'(error);

hps_io #(.CONF_STR(CONF_STR),.VDNUM(VDNUM)) hps_io
(
   .clk_sys(clock_bus.base_mp.clk),
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

/////////////////   CONFIG   /////////////////
wire [5:0] mapper_A, mapper_B;
wire       reload, ROM_A_load_hide, ROM_B_load_hide;
user_config user_config
(
   .clk(clock_bus.base_mp.clk),
   .reset(reset),
   .HPS_status(status[63:0]),
   .sdram_size(sdram_size),
   .cart_conf(cart_conf),
   .reload(reload),
   .ROM_A_load_hide(ROM_A_load_hide),
   .ROM_B_load_hide(ROM_B_load_hide),
   .msx_user_config(msx_user_config),
   .ocmMode(io_device[DEV_OCM_BOOT][0].enable)
);
/////////////////   CLOCKS   /////////////////
wire clk_core, clk_sdram, locked_sdram;
pll pll
(
   .refclk(CLK_50M),
   .rst(RESET),
   .outclk_0(clk_sdram),   //85.909090
   .outclk_1(clk_core),    //21.477270
   .locked(locked_sdram)
);

clock #(.sysCLK(sysCLK)) clock
(
   .clock_bus(clock_bus)
);

/////////////////   RESET   /////////////////
// Async sources (HPS reset, PLL not locked) are synchronized per clock domain
// (async assert, sync release); the core reset is then a single register.
wire rst_core_async, sdram_init;
reset_sync rst_sync_core  (.clk(clk_core),  .arst(RESET || ~locked_sdram), .rst(rst_core_async));
reset_sync rst_sync_sdram (.clk(clk_sdram), .arst(~locked_sdram),          .rst(sdram_init));

always_ff @(posedge clk_core) begin
   hard_reset <= rst_core_async || status[0] || upload_reset;
   reset      <= rst_core_async || status[0] || upload_reset || status[10] || status[21]
              || (status[12] && block_device_SD.device_mp.img_mounted && io_device[DEV_WD2793][0].enable);
end

///////////////// Computer /////////////////
wire  [7:0] R, G, B, cpu_din, cpu_dout;
wire [15:0] cpu_addr, audio_L, audio_R;
wire        cpu_wr, cpu_rd, cpu_mreq, cpu_iorq, cpu_m1;
wire        sd_tx, sd_rx;
wire  [7:0] d_to_sd, d_from_sd;
assign joy[0] = joy0[5:0];
assign joy[1] = joy1[5:0];
msx #(.sysCLK(sysCLK)) MSX
(
   .core_reset(reset),
   .core_hard_reset(hard_reset),
   .clock_bus(clock_bus.base_mp),
   .memory_bus(memory_bus_msx),
   .video_bus(video_bus),
   .vram_bus(vram_bus),
   .ext_SD_card_bus(ext_SD_card_bus),
   .flash_bus(flash_bus),
   .FDD_bus(FDD_bus),
   .tape_motor_on(motor),
   .tape_in(msx_user_config.cas_audio_src == CAS_AUDIO_FILE  ? CAS_dout : tape_in),
   .rtc_time(rtc),
   .sram_save(status[38]),
   .sram_load(status[39]),
   .ioctl_addr(ioctl_addr[26:0]),
   .slot_expander(slot_expander),
   .slot_layout(slot_layout),
   .lookup_RAM(lookup_RAM),
   .lookup_SRAM(lookup_SRAM),
   .io_device(io_device),
   .io_memory(io_memory),
   .msx_config(msx_config),
   .joy(joy),
   .kb_upload_memory(kb_upload_memory),
   .*
);

//////////////////   UART ///////////////////
wire [7:0] uart_rx_data;
wire       uart_rx;

uart_rx #(.sysCLK(sysCLK)) uart_rx_i
(
   .clk(clock_bus.base_mp.clk),
   .reset(reset),
   .rx(UART_RXD),
   .uart_speed(uart_speed),
   .data_rx(uart_rx),
   .data(uart_rx_data)
);

//////////////////   SD   ///////////////////
wire sdclk;
wire sdmosi;
wire vsdmiso;
wire sdmiso = vsd_sel ? vsdmiso : SD_MISO;

reg vsd_sel = 0;
always @(posedge clock_bus.base_mp.clk) if(block_device_SD.device_mp.img_mounted) vsd_sel <= |img_size; //TODO je potřeba hlídat náběžnou hranu img mounted

assign SD_CS   = vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;

reg sd_act;
reg [31:0] timeout = 0;
always @(posedge clock_bus.base_mp.clk) begin
    reg old_mosi, old_miso;

    old_mosi <= sdmosi;
    old_miso <= sdmiso;

    sd_act <= 0;
    if(timeout < 1000000) begin
        timeout <= timeout + 1;
        sd_act <= 1;
    end

    if((old_mosi ^ sdmosi) || (old_miso ^ sdmiso)) timeout <= 0;
end

//////////////////   SPI   ///////////////////
spi_divmmc spi
(
   .clk_sys(clock_bus.base_mp.clk),
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
    .clk_sys(clock_bus.base_mp.clk),
    .img_mounted(block_device_SD.device_mp.img_mounted),
    .img_size(img_size),
    .sd_lba(block_device_SD.device_mp.lba),
    .sd_rd(block_device_SD.device_mp.rd),
    .sd_wr(block_device_SD.device_mp.wr),
    .sd_ack(block_device_SD.device_mp.ack),
    .sd_buff_addr(block_device_SD.device_mp.buff_addr[8:0]),
    .sd_buff_dout(block_device_SD.device_mp.buff_dout),
    .sd_buff_din(block_device_SD.device_mp.buff_din),
    .sd_buff_wr(block_device_SD.device_mp.buff_wr),

    .clk_spi(clk_sdram),
    .sdhc(1),
    .sck(sdclk),
    .ss(~vsd_sel),
    .mosi(sdmosi),
    .miso(vsdmiso)
);
/////////////////  VIDEO  /////////////////
wire       vga_de;
wire [1:0] ar    = status[2:1];
wire [2:0] scale = status[5:3];
wire [2:0] sl    = scale != 0 ? scale - 1'd1 : 3'd0;

assign VGA_SL = sl[1:0];
assign CLK_VIDEO   = clk_sdram;
assign scandoubler = forced_scandoubler || scale != 0;

reg  en216p;
always @(posedge CLK_VIDEO) begin
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !scandoubler);
end

video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
   .VGA_VS(video_bus.display_mp.VS),
	.ARX((ar == 0) ? 12'd4 : {10'b0, (ar - 1'd1)}),
	.ARY((ar == 0) ? 12'd3 : 12'd0),
	.CROP_SIZE(en216p ? 12'd216 : 12'd0),
	.CROP_OFF(0),
	.SCALE(status[8:6])
);

video_mixer #(.GAMMA(1), .LINE_LENGTH(582)) video_mixer
(
   .CLK_VIDEO(CLK_VIDEO),
   .hq2x(scale==1),
   .scandoubler(scandoubler),
   .gamma_bus(gamma_bus),

   .ce_pix(video_bus.display_mp.ce_pix),
   .R(video_bus.display_mp.R),
   .G(video_bus.display_mp.G),
   .B(video_bus.display_mp.B),
   .HSync(video_bus.display_mp.HS),
   .VSync(video_bus.display_mp.VS),
   .HBlank(video_bus.display_mp.hblank),
   .VBlank(video_bus.display_mp.vblank),

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

/////////////////  Tape In   /////////////////
wire tape_adc, tape_adc_act, tape_in;

assign tape_in = tape_adc_act & tape_adc;

ltc2308_tape #(.ADC_RATE(120000), .CLK_RATE(21477272)) tape
(
   .clk(clock_bus.base_mp.clk),
   .ADC_BUS(ADC_BUS),
   .dout(tape_adc),
   .active(tape_adc_act)
);

/////////////////  LOAD PACK   /////////////////
wire upload_ram_ce, upload_sdram_rq, upload_bram_rq, upload, upload_reset;
wire  [7:0] upload_ram_din, config_msx;
wire [26:0] upload_ram_addr;
wire  [7:0] kbd_din;
wire  [8:0] kbd_addr;
wire        kbd_request, kbd_we;
wire        load_sram;
error_t     error;
MSX::kb_memory_t  kb_upload_memory;

memory_upload memory_upload(
    .clk(clock_bus.base_mp.clk),
    .upload(upload),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr),
    .rom_eject(status[10]),
    .reload(reload),
    .ddr3_addr(ddr3_addr_download),
    .ddr3_rd(ddr3_rd_download),
    .ddr3_dout(ddr3_dout),
    .ddr3_ready(ddr3_ready),
    .ddr3_request(ddr3_request_download),
    .memory_bus(memory_bus_upload),
    .kb_upload_memory(kb_upload_memory),
    .slot_expander(slot_expander),
    .slot_layout(slot_layout),
    .lookup_RAM(lookup_RAM),
    .lookup_SRAM(lookup_SRAM),
    .cart_conf(cart_conf),
    .load_sram(load_sram),
    .io_device(io_device),
    .io_memory(io_memory),
    .msx_config(msx_config),
    .error(error),
    .reset(upload_reset)
);
wire  [26:0] flash_addr;
wire   [7:0] flash_dout;
wire         flash_req, flash_ready, flash_done;
flash flash (
   .clk(clock_bus.base_mp.clk),
   .clk_sdram(clk_sdram),
   .flash_bus(flash_bus),

   .sdram_ready(flash_ready),
   .sdram_done(flash_done),
   .sdram_addr(flash_addr),
   .sdram_din(flash_dout),
   .sdram_req(flash_req)
);

// flash and NVRAM backup use system addresses: map them through system_memory like CPU
assign memory_bus_flash.addr     = flash_addr;
assign memory_bus_flash.data     = flash_dout;
assign memory_bus_flash.rnw      = 1'b0;
assign memory_bus_flash.ram_cs   = flash_req;
assign memory_bus_flash.sram_cs  = 1'b0;
assign flash_ready               = memory_bus_flash.sdram_ready;
assign flash_done                = memory_bus_flash.sdram_done;

assign memory_bus_backup.addr    = backup_ram_addr;
assign memory_bus_backup.data    = backup_ram_din;
assign memory_bus_backup.rnw     = backup_ram_rnw;
assign memory_bus_backup.ram_cs  = backup_ram_req;
assign memory_bus_backup.sram_cs = 1'b0;
assign backup_ram_dout           = memory_bus_backup.q;
assign backup_ram_ready          = memory_bus_backup.sdram_ready;

wire [27:0] ddr3_addr, ddr3_addr_download, ddr3_addr_cas;
wire  [7:0] ddr3_dout, ddr3_din_download;
wire        ddr3_rd, ddr3_rd_download, ddr3_rd_cas, ddr3_wr_download, ddr3_ready, ddr3_request_download;

assign ddr3_addr = ddr3_request_download ? ddr3_addr_download : ddr3_addr_cas ;
assign ddr3_rd   = ddr3_request_download ? ddr3_rd_download   : ddr3_rd_cas   ;
assign DDRAM_CLK = clock_bus.base_mp.clk;


logic [63:0] dout64;

ddram buffer
(
   .DDRAM_CLK(DDRAM_CLK),
   .addr(ddr3_addr),
   .dout(ddr3_dout),
   .dout64(dout64),
   .din(),
   .we(),
   .rd(ddr3_rd),
   .ready(ddr3_ready),
   .reset(reset),
   .*
);

system_memory #(.BRAM_WIDTH(18)) system_memory(
   .clk(clock_bus.base_mp.clk),
   .memory_bus_msx(memory_bus_msx),
   .memory_bus_upload(memory_bus_upload),
   .memory_bus_flash(memory_bus_flash),
   .memory_bus_backup(memory_bus_backup),
   .memory_bus_sdram_ch1(memory_bus_sdram_ch1),
   .memory_bus_sdram_ch2(memory_bus_sdram_ch2),
   .memory_bus_sdram_ch3(memory_bus_sdram_ch3),
   .upload(upload)
);

wire         sdram_ready, sdram_rnw, dw_sdram_we, dw_sdram_ready;
wire  [26:0] sdram_addr;
wire  [24:0] dw_sdram_addr;
wire   [7:0] sdram_dout, dw_sdram_din;
sdram sdram
(
   .init(sdram_init),
   .clk(clk_sdram),
   .core_phase(clock_bus.ce_10m7_p),   // clkdiv4[0]: register toggling every clk_core cycle
   .doRefresh(1'd0),

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
   .*
);
// VDP video RAM
spram #(.addr_width(16),.mem_name("VRA2")) vram_lo
(
   .clock(clock_bus.base_mp.clk),
   .address(vram_bus.vram_mp.addr),
   .wren(vram_bus.vram_mp.we_lo),
   .data(vram_bus.vram_mp.data),
   .q(vram_bus.vram_mp.q_lo)
);
spram #(.addr_width(16),.mem_name("VRA3")) vram_hi
(
   .clock(clock_bus.base_mp.clk),
   .address(vram_bus.vram_mp.addr),
   .wren(vram_bus.vram_mp.we_hi),
   .data(vram_bus.vram_mp.data),
   .q(vram_bus.vram_mp.q_hi)
);

///////////////// NVRAM BACKUP ////////////////
wire [26:0]  backup_ram_addr;
wire [7:0]   backup_ram_din, backup_ram_dout;
wire         backup_ram_req, backup_ram_rnw, backup_ram_ready;
nvram_backup nvram_backup
(
   .clk(clock_bus.base_mp.clk),
   .lookup_SRAM(lookup_SRAM),
   .load_req(status[39] | load_sram),
   .save_req(status[38]),
   .img_mounted(4'b0000 /*img_mounted[3:0]*/), //TODO
   .img_readonly(img_readonly),
   .img_size(img_size[31:0]),
   /*
   .sd_lba(sd_lba[0:3]),
   .sd_rd(sd_rd[3:0]),
   .sd_wr(sd_wr[3:0]),
   .sd_ack(sd_ack[3:0]),
   .sd_buff_wr(sd_buff_wr),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_din(sd_buff_din[0:3]),
   .sd_buff_dout(sd_buff_dout),
   */
   .ram_addr(backup_ram_addr),
   .ram_dout(backup_ram_dout),
   .ram_din(backup_ram_din),
   .ram_req(backup_ram_req),
   .ram_rnw(backup_ram_rnw),
   .ram_ready(backup_ram_ready)
);

///////////////// CAS EMULATE /////////////////
wire ioctl_isCAS, buff_mem_ready, motor, CAS_dout, play, rewind;
logic cas_load = 0;
always @(posedge clock_bus.base_mp.clk) begin
   logic ioctl_download_last;
   if (~ioctl_isCAS & ioctl_download_last )  begin
      cas_load <= 1'b1;
   end
   ioctl_download_last <= ioctl_isCAS;
end

assign play         = ~motor & cas_load;
assign ioctl_isCAS  = ioctl_download & (ioctl_index[5:0] == 6'd5);
assign rewind       = status[9] | ioctl_isCAS | reset;

tape cass
(
   .clk(clock_bus.base_mp.clk),
   .ce_5m3(clock_bus.base_mp.ce_5m39_p),
   .cas_out(CAS_dout),
   .ram_a(ddr3_addr_cas),
   .ram_di(ddr3_dout),
   .ram_di64(dout64),
   .ram_rd(ddr3_rd_cas),
   .buff_mem_ready(ddr3_ready),
   .play(play),
   .rewind(rewind),
   .enable(cas_load)
);

blockDevMux #(.VDNUM(VDNUM)) blockDevMux
(
   .clk(clock_bus.base_mp.clk),
   .reset(reset),
   .msx_config(msx_config),
   .block_device_FDD(block_device_FDD),
   .block_device_SD(block_device_SD),
   .block_device_nvram(block_device_nvram),
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
///////////////// FDD EMULATE /////////////////
// one FDD unit (2 drives) per WD2793 copy (MSX::N_WD2793)
generate
if (MSX::N_WD2793 > 0) begin : g_fdd0
   fdd #(.sysCLK(sysCLK), .SECTORS(9), .SECTOR_SIZE(512), .TRACKS(80), .ID("FDD0")) fdd0 (
      .clk(clock_bus.base_mp.clk),
      .reset(reset),
      .FDD_bus(FDD_bus[0]),
      .block_device(block_device_FDD[0:1]),
      // CONFIGURATION
      .speed(2'b00),
      .mfm(2'b11),
      .sides(2'b11),
      .sectors('{9,9}),                // sectors per track
      .sector_size('{2,2}),            // 0 - 128B / 1 - 256B / 2 - 512B / 3 - 1024B
      .density('{0,0})                // 0 - 250kbit     / 1 - 500kbit    / 2 - 1000kbit
   );
end else begin : g_fdd0_none   // no FDC 0: block devices idle
   assign block_device_FDD[0].rd = '0;
   assign block_device_FDD[0].wr = '0;
   assign block_device_FDD[0].lba = '0;
   assign block_device_FDD[0].blk_cnt = '0;
   assign block_device_FDD[0].buff_din = '0;
   assign block_device_FDD[1].rd = '0;
   assign block_device_FDD[1].wr = '0;
   assign block_device_FDD[1].lba = '0;
   assign block_device_FDD[1].blk_cnt = '0;
   assign block_device_FDD[1].buff_din = '0;
end
if (MSX::N_WD2793 > 1) begin : g_fdd1
   fdd #(.sysCLK(sysCLK), .SECTORS(9), .SECTOR_SIZE(512), .TRACKS(80), .ID("FDD1")) fdd1 (
      .clk(clock_bus.base_mp.clk),
      .reset(reset),
      .FDD_bus(FDD_bus[1]),
      .block_device(block_device_FDD[2:3]),
      // CONFIGURATION
      .speed(2'b00),
      .mfm(2'b11),
      .sides(2'b11),
      .sectors('{9,9}),                // sectors per track
      .sector_size('{2,2}),            // 0 - 128B / 1 - 256B / 2 - 512B / 3 - 1024B
      .density('{0,0})                // 0 - 250kbit     / 1 - 500kbit    / 2 - 1000kbit
   );
end else begin : g_fdd1_none   // no FDC 1: block devices idle
   assign block_device_FDD[2].rd = '0;
   assign block_device_FDD[2].wr = '0;
   assign block_device_FDD[2].lba = '0;
   assign block_device_FDD[2].blk_cnt = '0;
   assign block_device_FDD[2].buff_din = '0;
   assign block_device_FDD[3].rd = '0;
   assign block_device_FDD[3].wr = '0;
   assign block_device_FDD[3].lba = '0;
   assign block_device_FDD[3].blk_cnt = '0;
   assign block_device_FDD[3].buff_din = '0;
end
if (MSX::N_WD2793 > 2) begin : g_fdd2
   fdd #(.sysCLK(sysCLK), .SECTORS(9), .SECTOR_SIZE(512), .TRACKS(80), .ID("FDD2")) fdd2 (
      .clk(clock_bus.base_mp.clk),
      .reset(reset),
      .FDD_bus(FDD_bus[2]),
      .block_device(block_device_FDD[4:5]),
      // CONFIGURATION
      .speed(2'b00),
      .mfm(2'b11),
      .sides(2'b11),
      .sectors('{9,9}),                // sectors per track
      .sector_size('{2,2}),            // 0 - 128B / 1 - 256B / 2 - 512B / 3 - 1024B
      .density('{0,0})                // 0 - 250kbit     / 1 - 500kbit    / 2 - 1000kbit
   );
end else begin : g_fdd2_none   // no FDC 2: block devices idle
   assign block_device_FDD[4].rd = '0;
   assign block_device_FDD[4].wr = '0;
   assign block_device_FDD[4].lba = '0;
   assign block_device_FDD[4].blk_cnt = '0;
   assign block_device_FDD[4].buff_din = '0;
   assign block_device_FDD[5].rd = '0;
   assign block_device_FDD[5].wr = '0;
   assign block_device_FDD[5].lba = '0;
   assign block_device_FDD[5].blk_cnt = '0;
   assign block_device_FDD[5].buff_din = '0;
end

endgenerate
endmodule
