// msx_system
//
// Copyright (c) 2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// MSX system: computer, configuration upload, memories, cassette, floppy drives.
// emu (MSX1.sv) only bridges it to the MiSTer framework: hps_io, PLL and clock
// enables, video output, SDRAM / DDR3 / SD card / ADC pins.
module msx_system (
    clock_bus_if.base_mp        clock_bus,
    input                       rst_core_async,         // RESET or PLL unlock, synchronized to clk_core
    output logic                reset,                  // core reset (registered)

    // hps_io
    input             [127:0]   status,
    output             [15:0]   status_menumask,
    output                      info_req,
    output              [7:0]   info,
    input              [10:0]   ps2_key,
    input              [24:0]   ps2_mouse,
    input               [5:0]   joy[2],
    input                       ioctl_download,
    input              [15:0]   ioctl_index,
    input              [26:0]   ioctl_addr,
    input              [64:0]   rtc,
    input              [15:0]   sdram_sz,
    input              [31:0]   uart_speed,
    input                       img_readonly,
    input              [63:0]   img_size,
    input                       sd_img_mounted,         // virtual SD card image (block_device_SD)
    input                       osd_status,             // OSD open (emu OSD_STATUS)
    block_device_if.device_mp   block_device_FDD[2*MSX::N_FDC],
    output MSX::msx_config_t    msx_config,

    // Peripherals
    output MSX::video_t         video_bus,
    output             [15:0]   audio_L,
    output             [15:0]   audio_R,
    output                      led_turbo,              // turbo R: R800 running (pause device bit 7)
    output                      led_pause,              // machine paused, or turbo R pause LED (A7h)
    input                       uart_rxd,
    input                       tape_adc,               // tape input from ADC
    ext_sd_card_if.device_mp    ext_SD_card_bus,

    // Memories
    memory_bus_if.device_mp     memory_bus_sdram_ch1,
    memory_bus_if.device_mp     memory_bus_sdram_ch2,
    memory_bus_if.device_mp     memory_bus_sdram_ch3,
    wave_bus_if.device_mp       wave_bus_sdram_ch4,     // OPL4 sample memory
    output                      cpu_phase,              // clk in which the CPU may start a bus access
    output             [27:0]   ddr3_addr,
    output                      ddr3_rd,
    input               [7:0]   ddr3_dout,
    input                       ddr3_ready
);

localparam int sysCLK = MSX::CLK_CORE_HZ;

flash_bus_if    flash_bus();
vram_bus_if     vram_bus();
FDD_if          FDD_bus[MSX::N_FDC]();
memory_bus_if   memory_bus_msx();
memory_bus_if   memory_bus_upload();
memory_bus_if   memory_bus_flash();
memory_bus_if   memory_bus_backup();
wave_bus_if     wave_bus();

MSX::user_config_t       msx_user_config;
MSX::config_cart_t       cart_conf[2];
wire               [5:0] layout_id;       // msx_slots -> memory_upload tables
MSX::block_t             active_block;
MSX::lookup_RAM_t        active_RAM, main_RAM;
MSX::lookup_SRAM_t       lookup_SRAM[4];
MSX::main_ram_t          main_ram;
MSX::io_device_t         io_device[32][3];
MSX::io_device_mem_ref_t io_memory[8];
MSX::slot_expander_t     slot_expander[4];
MSX::kb_memory_t         kb_upload_memory;
error_t                  error;

logic        hard_reset = 1'b1;
wire         reload, ROM_A_load_hide, ROM_B_load_hide;
wire         upload, upload_reset, load_sram;
wire   [7:0] uart_rx_data;
wire         uart_rx;
wire         motor, CAS_dout;
wire  [27:0] ddr3_addr_download, ddr3_addr_cas;
wire         ddr3_rd_download, ddr3_rd_cas, ddr3_request_download;
wire  [26:0] flash_addr;
wire   [7:0] flash_dout;
wire         flash_req, flash_ready, flash_done;
wire  [26:0] backup_ram_addr;
wire   [7:0] backup_ram_din, backup_ram_dout;
wire         backup_ram_req, backup_ram_rnw, backup_ram_ready;

/////////////////   OSD   /////////////////
assign status_menumask[0]     = io_device[DEV_OCM_BOOT][0].enable || cart_conf[0].typ == CART_TYP_MFRSD;
assign status_menumask[1]     = ROM_A_load_hide || io_device[DEV_OCM_BOOT][0].enable;
assign status_menumask[2]     = ROM_B_load_hide || io_device[DEV_OCM_BOOT][0].enable;
assign status_menumask[3]     = io_device[DEV_OCM_BOOT][0].enable;
assign status_menumask[9:4]   = msx_config.fdd[5:0];
assign status_menumask[10]    = lookup_SRAM[0].size + lookup_SRAM[1].size + lookup_SRAM[2].size + lookup_SRAM[3].size == 0;
assign status_menumask[11]    = msx_user_config.cas_audio_src == CAS_AUDIO_ADC || io_device[DEV_OCM_BOOT][0].enable;   // no CAS file (OCM: no tape)
assign status_menumask[12]    = io_device[DEV_S1990][0].enable;    // turbo R options (firmware switch)
assign status_menumask[15:13] = '0;

assign info_req = error != ERR_NONE;
assign info     = 8'(error);

user_config user_config
(
   .clk(clock_bus.clk),
   .reset(reset),
   .HPS_status(status[63:0]),
   .osd_status(osd_status),
   .sdram_size(sdram_sz[15] ? sdram_sz[1:0] : 2'b00),
   .cart_conf(cart_conf),
   .reload(reload),
   .ROM_A_load_hide(ROM_A_load_hide),
   .ROM_B_load_hide(ROM_B_load_hide),
   .msx_user_config(msx_user_config),
   .ocmMode(io_device[DEV_OCM_BOOT][0].enable)
);

/////////////////   RESET   /////////////////
initial reset = 1'b1;
always_ff @(posedge clock_bus.clk) begin
   hard_reset <= rst_core_async || status[0] || upload_reset;
   reset      <= rst_core_async || status[0] || upload_reset || status[10] || status[21]
              || (status[12] && sd_img_mounted && io_device[DEV_OCM_BOOT][0].enable);   // OCM: reset after VHD mount
end

/////////////////   COMPUTER   /////////////////
msx #(.sysCLK(sysCLK)) MSX
(
   .core_reset(reset),
   .core_hard_reset(hard_reset),
   .clock_bus(clock_bus),
   .video_bus(video_bus),
   .vram_bus(vram_bus),
   .ext_SD_card_bus(ext_SD_card_bus),
   .flash_bus(flash_bus),
   .memory_bus(memory_bus_msx),
   .wave_bus(wave_bus),
   .cpu_phase(cpu_phase),
   .audio_L(audio_L),
   .audio_R(audio_R),
   .ps2_key(ps2_key),
   .ps2_mouse(ps2_mouse),
   .joy(joy),
   .uart_rx_data(uart_rx_data),
   .uart_rx(uart_rx),
   .tape_motor_on(motor),
   .tape_in(msx_user_config.cas_audio_src == CAS_AUDIO_FILE ? CAS_dout : tape_adc),
   .rtc_time(rtc),
   .msx_user_config(msx_user_config),
   .sram_save(status[38]),
   .sram_load(status[39]),
   .led_turbo(led_turbo),
   .led_pause(led_pause),
   .ioctl_download(ioctl_download),
   .ioctl_index(ioctl_index),
   .ioctl_addr(ioctl_addr),
   .slot_expander(slot_expander),
   .layout_id(layout_id),
   .active_block(active_block),
   .active_RAM(active_RAM),
   .main_RAM(main_RAM),
   .lookup_SRAM(lookup_SRAM),
   .main_ram(main_ram),
   .io_device(io_device),
   .io_memory(io_memory),
   .msx_config(msx_config),
   .kb_upload_memory(kb_upload_memory),
   .FDD_bus(FDD_bus)
);

/////////////////   UART   /////////////////
uart_rx #(.sysCLK(sysCLK)) uart_rx_i
(
   .clk(clock_bus.clk),
   .reset(reset),
   .rx(uart_rxd),
   .uart_speed(uart_speed),
   .data_rx(uart_rx),
   .data(uart_rx_data)
);

/////////////////   CONFIGURATION UPLOAD   /////////////////
memory_upload memory_upload(
   .clk(clock_bus.clk),
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
   .layout_id(layout_id),
   .active_block(active_block),
   .active_RAM(active_RAM),
   .main_RAM(main_RAM),
   .lookup_SRAM(lookup_SRAM),
   .main_ram(main_ram),
   .cart_conf(cart_conf),
   .sdram_sz(sdram_sz),
   .load_sram(load_sram),
   .io_device(io_device),
   .io_memory(io_memory),
   .msx_config(msx_config),
   .error(error),
   .reset(upload_reset)
);

// DDR3: configuration upload has priority over the cassette player
assign ddr3_addr = ddr3_request_download ? ddr3_addr_download : ddr3_addr_cas;
assign ddr3_rd   = ddr3_request_download ? ddr3_rd_download   : ddr3_rd_cas;

/////////////////   MEMORY   /////////////////
flash flash (
   .clk(clock_bus.clk),
   .clk_sdram(clock_bus.clk_mem),
   .reset(reset),
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

system_memory #(.BRAM_WIDTH(MSX::BRAM_WIDTH)) system_memory(
   .clk(clock_bus.clk),
   .memory_bus_msx(memory_bus_msx),
   .memory_bus_upload(memory_bus_upload),
   .memory_bus_flash(memory_bus_flash),
   .memory_bus_backup(memory_bus_backup),
   .memory_bus_sdram_ch1(memory_bus_sdram_ch1),
   .memory_bus_sdram_ch2(memory_bus_sdram_ch2),
   .memory_bus_sdram_ch3(memory_bus_sdram_ch3),
   .wave_bus(wave_bus),
   .wave_bus_sdram_ch4(wave_bus_sdram_ch4),
   .upload(upload)
);

// VDP video RAM
spram #(.addr_width(16),.mem_name("VRA2")) vram_lo
(
   .clock(clock_bus.clk),
   .address(vram_bus.addr),
   .wren(vram_bus.we_lo),
   .data(vram_bus.data),
   .q(vram_bus.q_lo)
);
spram #(.addr_width(16),.mem_name("VRA3")) vram_hi
(
   .clock(clock_bus.clk),
   .address(vram_bus.addr),
   .wren(vram_bus.we_hi),
   .data(vram_bus.data),
   .q(vram_bus.q_hi)
);

/////////////////   NVRAM BACKUP   /////////////////
nvram_backup nvram_backup
(
   .clk(clock_bus.clk),
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

/////////////////   CASSETTE   /////////////////
wire  ioctl_isCAS = ioctl_download & (ioctl_index[5:0] == 6'd5);
logic cas_load    = 0;
always_ff @(posedge clock_bus.clk) begin
   logic ioctl_download_last;
   if (~ioctl_isCAS & ioctl_download_last )  begin
      cas_load <= 1'b1;
   end
   ioctl_download_last <= ioctl_isCAS;
end

// File size: sent by HPS at the start of a download straight into DDR3, held in ioctl_addr
logic [26:0] cas_size = '0;
always_ff @(posedge clock_bus.clk) if (ioctl_isCAS) cas_size <= ioctl_addr;

tape cass
(
   .clk(clock_bus.clk),
   .ce_5m3(clock_bus.ce_5m39_p),
   .cas_out(CAS_dout),
   .ram_a(ddr3_addr_cas),
   .ram_di(ddr3_dout),
   .ram_rd(ddr3_rd_cas),
   .buff_mem_ready(ddr3_ready),
   .play(~motor & cas_load),
   .rewind(status[9] | ioctl_isCAS | reset),
   .enable(cas_load),
   .size(cas_size)
);

/////////////////   FLOPPY DRIVES   /////////////////
// One FDD unit (2 drives) per FDC position (MSX::N_FDC), fed by the WD2793 of that position
// or, at position 0, by the TC8566AF.
// Drive properties from its XML parameters: bit 4 single_sided, WD2793 bits 1:0 style 0 Philips,
// 1 National, 2 Sony (openMSX MSXFDC: TRACK0 / WPROT need the motor only for Philips or without
// a style; Sony motor keeps running 4 s, motor_off_timeout_ms of all Sony machines).
genvar fi;
generate
   for (fi = 0; fi < MSX::N_FDC; fi++) begin : g_fdd
      // TC8566AF (no connection style: signals need the motor, motor stops at once)
      wire       tc_enable  = fi == 0 && MSX::N_TC8566AF > 0 && io_device[DEV_TC8566AF][fi].enable;
      wire [7:0] fdc_param  = tc_enable ? {io_device[DEV_TC8566AF][fi].param[7:2], 2'd0}
                                        : io_device[DEV_WD2793][fi].param;
      wire       fdc_enable = tc_enable || io_device[DEV_WD2793][fi].enable;
      fdd #(.sysCLK(sysCLK), .ID(fi == 0 ? "FDD0" : "FDD1")) fdd_i (
         .clk(clock_bus.clk),
         .reset(reset),
         .FDD_bus(FDD_bus[fi]),
         .block_device(block_device_FDD[2*fi:2*fi+1]),
         .drive_ds(fdc_param[4] ? 2'b00 : 2'b11),
         .need_motor(!fdc_enable || fdc_param[1:0] == 2'd0),
         .motor_off_ms(fdc_enable && fdc_param[1:0] == 2'd2 ? 16'd4000 : 16'd0)
      );
   end
endgenerate

endmodule
