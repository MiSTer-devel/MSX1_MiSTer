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

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_S = 1;
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign LED_USER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////
// Status Bit Map:
//              Upper                          Lower
// 0         1         2         3          4         5         6
// 01234567890123456789012345678901 23456789012345678901234567890123
// 0123456789ABCDEFGHIJKLMNOPQRSTUV 0123456789ABCDEFGHIJKLMNOPQRSTUV
// XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX XXXXXXXXXXXXXXXXXXXXXXXXXXXXX

`include "build_id.v" 
localparam CONF_STR = {
	"MSX1;;",
	"-;",
	"h2OHK,SLOT A,ROM mapper auto,ROM mapper none,ROM mapper gamemaster2,ROM mapper Konami,ROM mapper KonamiSCC,ROM mapper ASCII8,ROM mapper ASCII16,ROM mapper linear64k,ROM mapper R-TYPE,FDD VY0010;",   
	"H2OHK,SLOT A,Empty,FDD VY0010,Gamemaster2;",
	"h1S0,DSK,Mount Drive A:;",
	"H3F2,ROM,SLOT A load;",
	"OLO,SLOT B,ROM mapper Auto,ROM mapper none,ROM mapper gamemaster2,ROM mapper Konami,ROM mapper KonamiSCC,ROM mapper ASCII8,ROM mapper ASCII16,ROM mapper linear64k,ROM mapper R-TYPE;",
	"F3,ROM,SLOT B load;",
	"-;",
	"OC,Tape Input,File,ADC;",
	"H0F4,CAS,Cas File;",
	"H0TD,Tape Rewind;",
	"-;",
	"P1,Video settings;",
	"P1OG,Video mode,PAL,NTSC;",
	"P1O12,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1O3,Border,No,Yes;",
	"P1O79,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%;",
	"P1OAB,Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",	
	"P2,Advanced settings;",
	"P2F1,ROM,Load BIOS;",	
	"-;",
	"T0,Reset;",
	"RF,Reset & Detach ROM Cartridge;",
	"R0,Reset and close OSD;",
   "I,Unkn,NOmpaer,GM2,Konami,KonamiSCC,Ascii8,Ascii16;",
	"V,v",`BUILD_DATE 
};

wire forced_scandoubler;
wire [21:0] gamma_bus;
wire  [1:0] buttons;
wire [31:0] status;
wire [10:0] ps2_key;
wire [5:0]  joy0, joy1;
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire        ioctl_wait;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;
wire [31:0] sd_lba[1];
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din[1];
wire        sd_buff_wr;
wire        img_mounted;
wire [31:0] img_size;
wire        img_readonly;
wire [15:0] sdram_sz;
wire  [1:0] sdram_size  = sdram_sz[15] ? sdram_sz[1:0] : 2'b00;
wire        fdd_enable  = sdram_size ? status[20:17] == 9 : status[20:17]  == 1;
wire        romA_hide   = sdram_size ? status[20:17] == 9 : 1'b1;
wire        sdram_present = |sdram_size;
wire        cas_audio_in = status[12] ? tape_in : CAS_dout;
wire  [7:0] osd_info;
wire        osd_info_req;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(gamma_bus),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask({romA_hide, sdram_present, fdd_enable, status[12]}),
	
	.ps2_key(ps2_key),
	.joystick_0(joy0),
	.joystick_1(joy1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_readonly(img_readonly),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.sdram_sz(sdram_sz),
	.info(osd_info),
	.info_req(osd_info_req)
);
assign osd_info_req = buttons[1];
assign osd_info = {5'b00000,mapper_info}+1;

reg [1:0] rom_enabled = 2'b00;
wire ioctl_isBIOS = ioctl_download && ((ioctl_index[5:0] == 6'd1) || ! ioctl_index[5:0]);
wire ioctl_isFWBIOS = ioctl_download && ! ioctl_index[5:0] && ioctl_index[15:6];
wire ioctl_isROMA = ioctl_download && (ioctl_index[5:0] == 6'd2);
wire ioctl_isROMB = ioctl_download && (ioctl_index[5:0] == 6'd3);
wire ioctl_isCAS  = ioctl_download && (ioctl_index[5:0] == 6'd4);

always @(posedge ioctl_isROMA, posedge ioctl_isROMB, posedge status[15]) begin
   if (status[15])
      rom_enabled <= 2'b00;
   else
      if (ioctl_isROMA) 
         rom_enabled[0] <= 1;
      if (ioctl_isROMB) 
         rom_enabled[1] <= 1;
end 

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys, clk_sdram, locked_sdram;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_1(clk_sys),
	.outclk_0(clk_sdram),
	.locked(locked_sdram)
);

reg ce_10m7 = 0;
reg ce_5m3 = 0;
always @(posedge clk_sys) begin
	reg [2:0] div;
	
	div <= div+1'd1;
	ce_10m7 <= !div[1:0];
	ce_5m3  <= !div[2:0];
end

///////////////////////    RESET   ///////////////////////////////

reg [7:0] last_mapper = 8'h0;
always @(posedge clk_sys) begin
	last_mapper = status[24:17];
end

wire mapper_reset = last_mapper != status[24:17];
wire reset = RESET | status[0] | ioctl_isROMA | ioctl_isROMB | ioctl_isBIOS | mapper_reset | status[15];

//////////////////////////////////////////////////////////////////

wire [7:0] R,G,B;
wire hblank, vblank, hsync_n, vsync_n;
wire [15:0] audio;
wire ioctl_waitROM;
wire [2:0] mapper_info;
msx1 MSX1
(
	.clk(clk_sys),
	.ce_10m7(ce_10m7),
	.reset(reset),
	
	.border(status[3]),
	.R(R),
	.G(G),
	.B(B),
	.hsync_n(hsync_n),
	.vsync_n(vsync_n),
	.hblank(hblank),
	.vblank(vblank),
	.vdp_pal(~status[16]),
	.audio(audio),
	.ps2_key(ps2_key),
	.joy0(joy0),
	.joy1(joy1),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index[7:0]),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_isROMA(ioctl_isROMA),
	.ioctl_isROMB(ioctl_isROMB),
	.ioctl_isBIOS(ioctl_isBIOS),
	.ioctl_isFWBIOS(ioctl_isFWBIOS),
	.ioctl_wait(ioctl_waitROM),
	.rom_enabled(rom_enabled),
	.cas_motor(motor),
	.cas_audio_in(cas_audio_in),
	.slot_A(status[20:17]),
	.slot_B(status[24:21]),
	.mapper_info(mapper_info),
	.img_mounted(img_mounted), // signaling that new image has been mounted
	.img_size(img_size), // size of image in bytes
	.img_wp(img_readonly), // write protect
	.sd_lba(sd_lba[0]),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din[0]),
	.sd_buff_wr(sd_buff_wr),
	.sdram_dout(sdram_dout),
	.sdram_din(sdram_din),
	.sdram_addr(sdram_addr),
	.sdram_we(sdram_we),
	.sdram_rd(sdram_rd),
	.sdram_ready(sdram_ready),
	.sdram_size(sdram_size)
);

/////////////////  SDRAM  /////////////////////////
wire  [7:0] sdram_dout;
wire  [7:0] sdram_din;
wire [24:0] sdram_addr;
wire        sdram_we;
wire        sdram_rd;
wire        sdram_ready;

sdram sdram
(
    .init(~locked_sdram),
    .clk(clk_sdram),
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

    .dout(sdram_dout),
    .din (sdram_din),
    .addr(sdram_addr),
    .we(sdram_we),
    .rd(sdram_rd),
    .ready(sdram_ready)
);

/////////////////  VIDEO  /////////////////////////

assign CLK_VIDEO = clk_sys;

always @(posedge CLK_VIDEO) 
	en216p <= ((HDMI_WIDTH == 1920) && (HDMI_HEIGHT == 1080) && !forced_scandoubler && !scale);

wire [1:0] ar = status[2:1];
wire vga_de;
reg  en216p;
video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
	.ARX((!ar) ? 12'd4 : (ar - 1'd1)),
	.ARY((!ar) ? 12'd3 : 12'd0),
	.CROP_SIZE(en216p ? 10'd216 : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[11:10])
);

wire [2:0] scale = status[9:7];
wire [2:0] sl = scale ? scale - 1'd1 : 3'd0;
assign VGA_SL = sl[1:0];

reg hs_o, vs_o;
always @(posedge CLK_VIDEO) begin
	hs_o <= ~hsync_n;
	if(~hs_o & ~hsync_n) 
		vs_o <= ~vsync_n;
end

wire  freeze_sync;
video_mixer #(.LINE_LENGTH(290), .GAMMA(1)) video_mixer
(
	.*,
	.ce_pix(ce_5m3),

	.scandoubler(scale || forced_scandoubler),
	.hq2x(scale==1),

	.VGA_DE(vga_de),

	// Positive pulses.
	.HSync(hs_o),
	.VSync(vs_o),
	.HBlank(hblank),
	.VBlank(vblank)
);

/////////////////  Tape In   /////////////////////////

wire tape_in;
wire tape_adc, tape_adc_act;

assign tape_in = tape_adc_act & tape_adc;

ltc2308_tape #(.ADC_RATE(120000), .CLK_RATE(42954545)) tape
(
  .clk(clk_sys),
  .ADC_BUS(ADC_BUS),
  .dout(tape_adc),
  .active(tape_adc_act)
);


///////////// OSD CAS load //////////

wire buff_mem_ready;
assign  DDRAM_CLK = clk_sys;
assign ioctl_wait =  (ioctl_isCAS && ~buff_mem_ready) || ioctl_waitROM;
ddram buffer
(
	.*,
	.addr(ioctl_isCAS ? ioctl_addr[26:0] : CAS_addr),
	.dout(CAS_di),
	.din(ioctl_dout),
	.we(ioctl_wr && ioctl_isCAS),
	.rd(~ioctl_isCAS && CAS_rd),
	.ready(buff_mem_ready),
	.reset(reset)
);

wire motor;
wire CAS_dout;
wire play, rewind;
wire CAS_rd;
wire [26:0] CAS_addr;
wire [7:0] CAS_di;
assign play = ~motor;
assign rewind = status[13] | ioctl_isCAS | reset;

tape cass 
(
	.clk(clk_sys),
	.ce_5m3(ce_5m3),
	.cas_out(CAS_dout),
	.ram_a(CAS_addr),
	.ram_di(CAS_di),
	.ram_rd(CAS_rd),
	.buff_mem_ready(buff_mem_ready),
	.play(play),
	.rewind(rewind | ioctl_isCAS)
);

endmodule
