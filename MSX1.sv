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

assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;

assign AUDIO_S = 1;
assign AUDIO_L = audio;
assign AUDIO_R = audio;
assign AUDIO_MIX = 0;

assign LED_POWER = 0;
assign LED_USER  = vsd_sel & sd_act;
assign LED_DISK  = {1'b1, ~vsd_sel & sd_act};
assign BUTTONS = 0;

localparam VDNUM = 6;

MSX::user_config_t msxConfig;
MSX::bios_config_t bios_config;
MSX::config_cart_t cart_conf[2];
MSX::block_t       slot_layout[64];
MSX::lookup_RAM_t  lookup_RAM[16];
MSX::lookup_SRAM_t lookup_SRAM[4];

wire             forced_scandoubler;
wire      [21:0] gamma_bus;
wire       [1:0] buttons;
wire      [63:0] status;
wire      [10:0] ps2_key;
wire      [24:0] ps2_mouse;
wire       [5:0] joy0, joy1;
wire             ioctl_download;
wire      [15:0] ioctl_index;
wire             ioctl_wr;
wire      [26:0] ioctl_addr;
wire       [7:0] ioctl_dout;
wire      [31:0] sd_lba[0:VDNUM-1];
wire [VDNUM-1:0] sd_rd;
wire [VDNUM-1:0] sd_wr;
wire [VDNUM-1:0] sd_ack;
wire      [13:0] sd_buff_addr;
wire       [7:0] sd_buff_dout;
wire       [7:0] sd_buff_din[0:VDNUM-1];
wire             sd_buff_wr;
wire [VDNUM-1:0] img_mounted;
wire      [31:0] img_size;
wire             img_readonly;
wire      [15:0] sdram_sz;
wire      [64:0] rtc;

//[0]     RESET
//[2:1]   Aspect ratio
//[4:3]   Scanlines
//[6:5]   Scale
//[7]     Vertical crop
//[8]     Tape input
//[9]     Tape rewind
//[10]    Reset & Detach
//[11]    MSX type
//[12]    MSX1 VideoMode 
//[14:13] MSX2 VideoMode
//[16:15] MSX2 RAM Size
//[19:17] SLOT A CART TYPE
//[23:20] ROM A TYPE MAPPER
//[25:24] RESERVA
//[28:26] SRAM SIZE 
//[31:29] SLOT B CART TYPE
//[34:32] ROM B TYPE MAPPER
//[37:35] RESERVA
//[38]    BORDER
`include "build_id.v" 
localparam CONF_STR = {
   "MSX1;",
   "-;",
   "FC1,MSX,Load ROM PACK,30000000;",
   "FC2,MSX,Load FW  PACK,30300000;",   
   CONF_STR_SLOT_A,
   "H3FS3,ROM,Load,30C00000;",
   CONF_STR_MAPPER_A,
   CONF_STR_SRAM_SIZE_A,
   "-;",
   CONF_STR_SLOT_B,
   "H4F4,ROM,Load,31100000;",
   CONF_STR_MAPPER_B,
   "H6-;",
   "H6R[38],SRAM Save;",
   "H6R[39],SRAM Load;",
   "h1-;",
   "h1S5,DSK,Mount Drive A:;",
   "S4,VHD,Load SD card;",
   "-;",
   "O[8],Tape Input,File,ADC;",
   "H0F5,CAS,Cas File,31600000;",
   "H0T9,Tape Rewind;",
   "-;",
   "P1,Video settings;",
   "H2P1O[14:13],Video mode,AUTO,PAL,NTSC;",
   "h2P1O[12],Video mode,PAL,NTSC;",
   "P1O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
   "P1O[4:3],Scanlines,No,25%,50%,75%;",
   "P1O[6:5],Scale,Normal,V-Integer,Narrower HV-Integer,Wider HV-Integer;",
   "P1O[7],Vertical Crop,No,Yes;",
   //"h2P1O[38],Border,No,Yes;",   //TODO
   "-;",
   "T[0],Reset;",
   "R[10],Reset & Detach ROM Cartridge;",					
   "R[0],Reset and close OSD;",
   "V,v",`BUILD_DATE 
};

wire [7:0] status_menumask;
wire [1:0] sdram_size;
assign status_menumask[0] = msxConfig.cas_audio_src == CAS_AUDIO_ADC;
assign status_menumask[1] = fdc_enabled;
assign status_menumask[2] = bios_config.use_FDC;
assign status_menumask[3] = ROM_A_load_hide;
assign status_menumask[4] = ROM_B_load_hide;
assign status_menumask[5] = sram_A_select_hide;
assign status_menumask[6] = lookup_SRAM[0].size + lookup_SRAM[1].size + lookup_SRAM[2].size + lookup_SRAM[3].size == 0;
assign sdram_size         = sdram_sz[15] ? sdram_sz[1:0] : 2'b00;

hps_io #(.CONF_STR(CONF_STR),.VDNUM(VDNUM)) hps_io
(
   .clk_sys(clk21m),
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
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din),
   .sd_buff_wr(sd_buff_wr),
   .sdram_sz(sdram_sz),
   .RTC(rtc)
);

/////////////////   CONFIG   /////////////////
wire [5:0] mapper_A, mapper_B;
wire       reload, sram_A_select_hide, fdc_enabled, ROM_A_load_hide, ROM_B_load_hide;

msx_config msx_config 
(
   .clk(clk21m),
   .reset(reset),
   .bios_config(bios_config),
   .HPS_status(status),
   .scandoubler(scandoubler),
   .sdram_size(sdram_size),
   .cart_conf(cart_conf),
   .reload(reload),
   .rom_loaded(rom_loaded),
   .sram_A_select_hide(sram_A_select_hide),
   .ROM_A_load_hide(ROM_A_load_hide),
   .ROM_B_load_hide(ROM_B_load_hide),
   .fdc_enabled(fdc_enabled),
   .msxConfig(msxConfig)
);

/////////////////   CLOCKS   /////////////////
wire clk21m, clk_sdram, locked_sdram;
wire ce_10m7_p, ce_10m7_n, ce_5m39_p, ce_5m39_n, ce_3m58_p, ce_3m58_n, ce_10hz;
pll pll
(
   .refclk(CLK_50M),
   .rst(0),
   .outclk_0(clk_sdram), //85.909090
   .outclk_1(clk21m),    //21.477270
   .locked(locked_sdram)
);

clock clock
(
   .*
);

/////////////////    RESET   /////////////////
wire reset = RESET | status[0] | status[10] | reset_rq;

///////////////// Computer /////////////////
wire  [7:0] R, G, B, cpu_din, cpu_dout;
wire [15:0] cpu_addr, audio;
wire        hsync, vsync, blank_n, hblank, vblank, ce_pix;
wire        cpu_wr, cpu_rd, cpu_mreq, cpu_iorq, cpu_m1;
wire [26:0] ram_addr;
wire  [7:0] ram_din, ram_dout;
wire        ram_rnw, sdram_ce, bram_ce;
wire        sd_tx, sd_rx;
wire  [7:0] d_to_sd, d_from_sd;

dev_typ_t    cart_device[2];
dev_typ_t    msx_device;
wire   [3:0] msx_dev_ref_ram[8];
mapper_typ_t selected_mapper[2];
assign selected_mapper[0] = cart_conf[0].selected_mapper;
assign selected_mapper[1] = cart_conf[1].selected_mapper;
msx MSX
(
   .HS(hsync),
   .DE(blank_n),
   .VS(vsync),
   .cas_motor(motor),
   .cas_audio_in(msxConfig.cas_audio_src == CAS_AUDIO_FILE  ? CAS_dout : tape_in),
   .rtc_time(rtc),
   .sram_save(status[38]),
   .sram_load(status[39]),
   .ioctl_addr(ioctl_addr[26:0]),
   .img_mounted(img_mounted[5]),
   .img_size(img_size),
   .img_readonly(img_readonly),
   .sd_rd(sd_rd[5]),
   .sd_wr(sd_wr[5]),
   .sd_ack(sd_ack[5]),
   .sd_lba(sd_lba[5]),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din[5]),
   .sd_buff_wr(sd_buff_wr),
   .slot_layout(slot_layout),
   .lookup_RAM(lookup_RAM),
   .lookup_SRAM(lookup_SRAM),
   .bios_config(bios_config),
   .cart_device(cart_device),
   .msx_device(msx_device),
   .msx_dev_ref_ram(msx_dev_ref_ram),
   .selected_mapper(selected_mapper),
   .flash_addr(flash_addr),
   .flash_din(flash_din),
   .flash_req(flash_req),
   .flash_ready(flash_ready),
   .flash_done(flash_done),
   .d_to_sd(d_to_sd),
   .d_from_sd(d_from_sd),
   .sd_tx(sd_tx),
   .sd_rx(sd_rx),
   .*
);

//////////////////   SD   ///////////////////
wire sdclk;
wire sdmosi;
wire vsdmiso;
wire sdmiso = vsd_sel ? vsdmiso : SD_MISO;

reg vsd_sel = 0;
always @(posedge clk21m) if(img_mounted[4]) vsd_sel <= |img_size;

assign SD_CS   = vsd_sel;
assign SD_SCK  = sdclk  & ~vsd_sel;
assign SD_MOSI = sdmosi & ~vsd_sel;

reg sd_act;

always @(posedge clk21m) begin
    reg old_mosi, old_miso;
    integer timeout = 0;

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
   .clk_sys(clk21m),
   .tx(sd_tx),
   .rx(sd_rx),
   .din(d_to_sd),
   .dout(d_from_sd),
   .ready(),

   .spi_ce(1'b1),
   .spi_clk(sdclk),
   .spi_di(sdmiso),
   .spi_do(sdmosi)
);

sd_card sd_card
(
    .*,
    .clk_sys(clk21m),
    .img_mounted(img_mounted[4]),
    .img_size(img_size),
    .sd_lba(sd_lba[4]),
    .sd_rd(sd_rd[4]),
    .sd_wr(sd_wr[4]),
    .sd_ack(sd_ack[4]),
    .sd_buff_addr(sd_buff_addr),
    .sd_buff_dout(sd_buff_dout),
    .sd_buff_din(sd_buff_din[4]),
    .sd_buff_wr(sd_buff_wr),
    
    .clk_spi(clk_sdram),
    .sdhc(1),
    .sck(sdclk),
    .ss(~vsd_sel),
    .mosi(sdmosi),
    .miso(vsdmiso)
);

/////////////////  VIDEO  /////////////////
logic [9:0] vcrop;
logic wide;
wire scandoubler, vcrop_en, vga_de;
wire [1:0] ar;

assign CLK_VIDEO   = clk21m;
assign CE_PIXEL    = ce_10m7_p;
assign VGA_SL      = status[4:3];
assign vcrop_en    = status[7];
assign ar          = status[2:1];
assign scandoubler = forced_scandoubler || status[4:3];

always @(posedge CLK_VIDEO) begin
	vcrop <= 0;
	wide <= 0;
	if(HDMI_WIDTH >= (HDMI_HEIGHT + HDMI_HEIGHT[11:1]) && !scandoubler) begin
		if(HDMI_HEIGHT == 480)  vcrop <= 240;
		if(HDMI_HEIGHT == 600)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 720)  vcrop <= 240;
		if(HDMI_HEIGHT == 768)  vcrop <= 256; // NTSC mode has 250 visible lines only!
		if(HDMI_HEIGHT == 800)  begin vcrop <= 200; wide <= vcrop_en; end
		if(HDMI_HEIGHT == 1080) vcrop <= 10'd216;
		if(HDMI_HEIGHT == 1200) vcrop <= 240;
	end
	else if(HDMI_WIDTH >= 1440 && !scandoubler) begin
		// 1920x1440 and 2048x1536 are 4:3 resolutions and won't fit in the previous if statement ( width > height * 1.5 )
		if(HDMI_HEIGHT == 1440) vcrop <= 240;
		if(HDMI_HEIGHT == 1536) vcrop <= 256;
	end
end

video_freak video_freak
(
	.*,
	.VGA_DE_IN(vga_de),
   .VGA_VS(vsync),
	.ARX((!ar) ? (wide ? 12'd340 : 12'd400) : (ar - 1'd1)),
	.ARY((!ar) ? 12'd300 : 12'd0),
	.CROP_SIZE(vcrop_en ? vcrop : 10'd0),
	.CROP_OFF(0),
	.SCALE(status[6:5])
);

gamma_fast gamma
(
	.clk_vid(CLK_VIDEO),
	.ce_pix(CE_PIXEL),
	.gamma_bus(gamma_bus),
	.HSync(hsync),
	.VSync(vsync),
	.DE(blank_n),
	.RGB_in({R,G,B}),
	.HSync_out(VGA_HS),
	.VSync_out(VGA_VS),
	.DE_out(vga_de),
	.RGB_out({VGA_R,VGA_G,VGA_B})
);

/////////////////  Tape In   /////////////////
wire tape_adc, tape_adc_act, tape_in;

assign tape_in = tape_adc_act & tape_adc;

ltc2308_tape #(.ADC_RATE(120000), .CLK_RATE(21477272)) tape
(
   .clk(clk21m),
   .ADC_BUS(ADC_BUS),
   .dout(tape_adc),
   .active(tape_adc_act)
);

/////////////////  LOAD PACK   /////////////////

wire upload_ram_ce, upload_sdram_rq, upload_bram_rq, upload_ram_ready, reset_rq;
wire  [7:0] upload_ram_din, config_msx;
wire [26:0] upload_ram_addr;
wire  [7:0] kbd_din;
wire  [8:0] kbd_addr;
wire        kbd_request, kbd_we;
wire        load_sram;
wire  [1:0] rom_loaded;
memory_upload memory_upload(
    .clk(clk21m),
    .reset_rq(reset_rq),
    .ioctl_download(ioctl_download),
    .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr),
    .rom_eject(status[10]),
    .reload(reload),
    .ddr3_addr(ddr3_addr_download),
    .ddr3_rd(ddr3_rd_download),
    .ddr3_wr(),
    .ddr3_dout(ddr3_dout),
    .ddr3_ready(ddr3_ready),
    .ddr3_request(ddr3_request_download),
    .ram_addr(upload_ram_addr),
    .ram_din(upload_ram_din),
    .ram_dout(),
    .ram_ce(upload_ram_ce),
    .sdram_ready(upload_ram_ready),
    .sdram_rq(upload_sdram_rq),
    .bram_rq(upload_bram_rq),
    .kbd_request(kbd_request),
    .kbd_addr(kbd_addr),
    .kbd_din(kbd_din),
    .kbd_we(kbd_we),
    .sdram_size(sdram_size),
    .slot_layout(slot_layout),
    .lookup_RAM(lookup_RAM),
    .lookup_SRAM(lookup_SRAM),
    .bios_config(bios_config),
    .cart_conf(cart_conf),
    .rom_loaded(rom_loaded),
    .cart_device(cart_device),
    .msx_device(msx_device),
    .msx_dev_ref_ram(msx_dev_ref_ram),
    .load_sram(load_sram)
);

wire [27:0] ddr3_addr, ddr3_addr_download, ddr3_addr_cas;
wire  [7:0] ddr3_dout, ddr3_din_download;
wire        ddr3_rd, ddr3_rd_download, ddr3_rd_cas, ddr3_wr_download, ddr3_ready, ddr3_request_download;

assign ddr3_addr = ddr3_request_download ? ddr3_addr_download : ddr3_addr_cas ;
assign ddr3_rd   = ddr3_request_download ? ddr3_rd_download   : ddr3_rd_cas   ;
assign DDRAM_CLK = clk21m;

ddram buffer
(
   .DDRAM_CLK(clk21m),
   .addr(ddr3_addr),
   .dout(ddr3_dout),
   .din(),
   .we(),
   .rd(ddr3_rd),
   .ready(ddr3_ready),
   .reset(reset),
   .*
);

assign ram_dout = sdram_ce ? sdram_dout :
                  bram_ce  ? bram_dout  :
                             8'hFF;

wire         sdram_ready, sdram_rnw, dw_sdram_we, dw_sdram_ready, flash_ready, flash_req, flash_done;
wire  [26:0] sdram_addr;
wire  [24:0] dw_sdram_addr;
wire  [26:0] flash_addr;
wire   [7:0] sdram_dout, bram_dout, dw_sdram_din, flash_din;
sdram sdram
(
   .init(~locked_sdram),
   .clk(clk_sdram),
   .doRefresh(1'd0),
   
   .ch1_dout(),
   .ch1_din(upload_ram_din),
   .ch1_addr(upload_ram_addr),
   .ch1_req(upload_ram_ce & upload_sdram_rq),
   .ch1_rnw(1'd0),
   .ch1_ready(upload_ram_ready),   
  
   .ch2_dout(sdram_dout),
   .ch2_din(ram_din),
   .ch2_addr(ram_addr),
   .ch2_req(sdram_ce),
   .ch2_rnw(ram_rnw),
   .ch2_ready(sdram_ready),

   .ch3_addr(flash_addr),
   .ch3_dout(),
   .ch3_din(flash_din),
   .ch3_req(flash_req),
   .ch3_rnw(0),
   .ch3_ready(flash_ready),
   .ch3_done(flash_done),
   .*
);    

dpram #(.addr_width(18)) systemRAM
(
   .clock(clk21m),
   .address_a(18'(upload_bram_rq ? upload_ram_addr : ram_addr)          ),
   .wren_a( upload_bram_rq ? upload_ram_ce         : bram_ce & ~ram_rnw ),
   .data_a( upload_bram_rq ? upload_ram_din        : ram_din            ),
   .q_a(bram_dout),
   .address_b(18'(sram_addr)),
   .wren_b(sram_we),
   .data_b(sd_buff_dout),
   .q_b(sram_dout)
);

///////////////// NVRAM BACKUP ////////////////
wire [26:0] sram_addr;
wire  [7:0] sram_dout;
wire        sram_we;
nvram_backup nvram_backup
(
   .clk(clk21m),
   .lookup_SRAM(lookup_SRAM),
   .load_req(status[39] | load_sram),
   .save_req(status[38]),
   .img_mounted(img_mounted[3:0]),
   .img_readonly(img_readonly),
   .img_size(img_size),
   .sd_lba(sd_lba[0:3]),
   .sd_rd(sd_rd[3:0]),
   .sd_wr(sd_wr[3:0]),
   .sd_ack(sd_ack[3:0]),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_din(sd_buff_din[0:3]),
   .ram_addr(sram_addr),
   .ram_dout(sram_dout),
   .ram_we(sram_we)
);

///////////////// CAS EMULATE /////////////////
wire ioctl_isCAS, buff_mem_ready, motor, CAS_dout, play, rewind;
logic cas_load = 0;
always @(posedge clk21m) begin
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
   .clk(clk21m),
   .ce_5m3(ce_5m39_p),
   .cas_out(CAS_dout),
   .ram_a(ddr3_addr_cas),
   .ram_di(ddr3_dout),
   .ram_rd(ddr3_rd_cas),
   .buff_mem_ready(ddr3_ready),
   .play(play),
   .rewind(rewind)
);

endmodule
