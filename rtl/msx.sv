// msx
//
// Copyright (c) 2020-2026 Molekula
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

module msx #(parameter sysCLK)
(
   input                    core_reset,
   input                    core_hard_reset,
   //Clock
   clock_bus_if.base_mp     clock_bus,
   //Video
   output MSX::video_t      video_bus,
   vram_bus_if.device_mp    vram_bus,
   //Ext SD card
   ext_sd_card_if.device_mp ext_SD_card_bus,
   //Flash acces to SDRAM
   flash_bus_if.device_mp   flash_bus,
   memory_bus_if.device_mp  memory_bus,
   wave_bus_if.device_mp    wave_bus,             // OPL4 sample memory
   output                   cpu_phase,            // clk in which the CPU may start a bus access
   //I/O
   output            [15:0] audio_L,
   output            [15:0] audio_R,
   input             [10:0] ps2_key,
   input             [24:0] ps2_mouse,
   input              [5:0] joy[2],
   //UART
   input              [7:0] uart_rx_data,
   input                    uart_rx,
   //Cassete
   output                   tape_motor_on,
   input                    tape_in,
   //MSX config
   input             [64:0] rtc_time,
   input MSX::user_config_t msx_user_config,
   input                    sram_save,
   input                    sram_load,
   output                   led_turbo,            // turbo R: R800 LED (pause device bit 7)
   output                   led_pause,
   //IOCTL
   input                    ioctl_download,
   input             [15:0] ioctl_index,
   input             [26:0] ioctl_addr,
   //SDRAM/BRAM
   input MSX::slot_expander_t slot_expander[4],
   output             [5:0] layout_id,
   input MSX::block_t       active_block,
   input MSX::lookup_RAM_t  active_RAM,
   input MSX::lookup_RAM_t  main_RAM,
   input MSX::lookup_SRAM_t lookup_SRAM[4],
   input MSX::main_ram_t    main_ram,
   input MSX::io_device_t   io_device[32][3],
   input MSX::io_device_mem_ref_t io_memory[8],
   input MSX::msx_config_t  msx_config,
   //KBD
   input MSX::kb_memory_t   kb_upload_memory,
   //SD FDC
   FDD_if.FDC_mp           FDD_bus[MSX::N_FDC]

   /*
   input                    img_mounted,
   input             [31:0] img_size,
   input                    img_readonly,
   output            [31:0] sd_lba,
   output                   sd_rd,
   output                   sd_wr,
   input                    sd_ack,
   input             [13:0] sd_buff_addr,
   input              [7:0] sd_buff_dout,
   output             [7:0] sd_buff_din,
   input                    sd_buff_wr
	*/
);

//  -----------------------------------------------------------------------------
//  -- Internal signals
//  -----------------------------------------------------------------------------
logic                reset = '0;
logic                iack;
wire                 cpu_interrupt;
wire           [7:0] d_to_cpu;
wire                 m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n;
wire           [1:0] active_slot;
logic                bus_read;
wire           [7:0] device_data;
wire                 device_oe_rq;
wire           [7:0] d_from_slots;
wire                 slot_oe_rq;
wire           [7:0] data_to_mapper;
wire           [7:0] slot_config;
wire                 keybeep;
wire                 reset_lock, reset_request;
wire                 ocm_megaSD_enable, ocm_slot1_mode;
wire           [1:0] ocm_slot2_mode;
wire                 ocm_ipl_en, ocm_mmc_on, ocm_mmc_wait, opll_wait, opl4_wait;
wire                 turbor_r800, turbor_dram, turbor_pause;
MSX::cpu_speed_t     cpu_speed;
wire signed   [15:0] device_sound_L, device_sound_R;

MSX::device_bus_t    device_bus;
MSX::block_info_t    block_info;
cpu_bus_if           cpu_bus(clock_bus.clk, reset);
memory_bus_if        memory_bus_slots();
memory_bus_if        memory_bus_devices();

//  -----------------------------------------------------------------------------
//  -- reset
//  -----------------------------------------------------------------------------
   always_ff @(posedge clock_bus.clk) begin
      reset <= core_hard_reset || (core_reset && ~reset_lock) || reset_request;
   end

//  -----------------------------------------------------------------------------
//  -- Audio (mixed, key click and tape added, clipped in devices/sound_mix)
//  -----------------------------------------------------------------------------
assign audio_L = device_sound_L;
assign audio_R = device_sound_R;

//  -----------------------------------------------------------------------------
//  -- T80 CPU
//  -----------------------------------------------------------------------------
assign cpu_bus.mreq    = ~mreq_n;
assign cpu_bus.iorq    = ~iorq_n;
assign cpu_bus.m1      = ~m1_n;
assign cpu_bus.rd      = ~rd_n;
assign cpu_bus.wr      = ~wr_n;
assign cpu_bus.rfsh    = ~rfsh_n;
assign cpu_bus.int_rq  = cpu_interrupt;
assign cpu_bus.req     = ~((iorq_n & mreq_n) | (wr_n & rd_n) | iack);

always_ff @(posedge cpu_bus.clk) begin
   if (cpu_bus.reset)
   iack <= 0;
   else begin
   if (iorq_n && mreq_n)
      iack <= 0;
   else
      if (cpu_bus.req)
         iack <= 1;
   end
end


msx_cpu cpu (
   .clock_bus (clock_bus),
   .reset     (reset),
   .clock_sel (cpu_speed.en ? cpu_speed.clock_sel : msx_config.cpu_clock_sel[1:0]),
   .m1_wait   (msx_config.wait_count),
   .mem_wait  (cpu_speed.mem_wait),
   .io_wait   (cpu_speed.io_wait),
   .ext_wait  (ocm_mmc_wait || opll_wait || opl4_wait || turbor_pause),
   .r800      (msx_config.cpu == R800 || msx_user_config.ocm_r800),
   .r800_sel  (turbor_r800),
   .turbor    (io_device[DEV_S1990][0].enable),
   .cold_reset(core_hard_reset),
   .r800_active(),
   .bus_phase (cpu_phase),
   .int_rq    (cpu_interrupt),
   .di        (d_to_cpu),
   .m1_n      (m1_n),
   .mreq_n    (mreq_n),
   .iorq_n    (iorq_n),
   .rd_n      (rd_n),
   .wr_n      (wr_n),
   .rfsh_n    (rfsh_n),
   .addr      (cpu_bus.addr),
   .dout      (cpu_bus.data)
);

//  -----------------------------------------------------------------------------
//  -- Slots
//  -----------------------------------------------------------------------------
assign active_slot =    //~map_valid                ? default_slot   :
                        cpu_bus.addr[15:14] == 2'b00 ? slot_config[1:0] :
                        cpu_bus.addr[15:14] == 2'b01 ? slot_config[3:2] :
                        cpu_bus.addr[15:14] == 2'b10 ? slot_config[5:4] :
                                                    slot_config[7:6] ;

//  -----------------------------------------------------------------------------
//  -- CPU data multiplex
//  -----------------------------------------------------------------------------
assign bus_read = cpu_bus.rd || (cpu_bus.iorq && cpu_bus.m1);
assign d_to_cpu = ~bus_read               ? 8'hFF           :
                  device_oe_rq            ? device_data     :                       // prior data
                  slot_oe_rq              ? d_from_slots    :                       // prior data
                                            device_data & memory_bus.q & d_from_slots;


//  -----------------------------------------------------------------------------
//  -- devices and slots split
//  -----------------------------------------------------------------------------

assign memory_bus.addr    = memory_bus_slots.addr    & memory_bus_devices.addr;
assign memory_bus.ram_cs  = memory_bus_slots.ram_cs  | memory_bus_devices.ram_cs;
assign memory_bus.sram_cs = memory_bus_slots.sram_cs | memory_bus_devices.sram_cs;
assign memory_bus.rnw     = memory_bus_slots.rnw     & memory_bus_devices.rnw;
assign memory_bus.data    = memory_bus_slots.data    & memory_bus_devices.data;

assign memory_bus_slots.q   = memory_bus.q;
assign memory_bus_devices.q = memory_bus.q;

devices #(.sysCLK(sysCLK)) devices
(
   .clock_bus(clock_bus),
   .hard_reset(core_hard_reset),
   .cpu_bus(cpu_bus),
   .device_bus(device_bus),
   .FDD_bus(FDD_bus),
   .io_device(io_device),
   .io_memory(io_memory),
   .sound_L(device_sound_L),
   .sound_R(device_sound_R),
   .data(device_data),
   .data_oe_rq(device_oe_rq),
   .data_to_mapper(data_to_mapper),
   .memory_bus(memory_bus_devices),
   .wave_bus(wave_bus),
   .block_info(block_info),
   .vram_bus(vram_bus),
   .video_bus(video_bus),
   .cpu_interrupt(cpu_interrupt),
   .kb_upload_memory(kb_upload_memory),
   .ps2_key(ps2_key),
   .ps2_mouse(ps2_mouse),
   .rtc_time(rtc_time),
   .uart_rx(uart_rx),
   .uart_rx_data(uart_rx_data),
   .joy(joy),
   .tape_in(tape_in),
   .tape_motor_on(tape_motor_on),
   .slot_config(slot_config),
   .keybeep(keybeep),
   .msx_user_config(msx_user_config),
   .reset_lock(reset_lock),
   .reset_request(reset_request),
   .cpu_speed(cpu_speed),
   .opll_wait(opll_wait),
   .opl4_wait(opl4_wait),
   .turbor_r800(turbor_r800),
   .turbor_dram(turbor_dram),
   .turbor_pause(turbor_pause),
   .turbor_pause_led(led_pause),
   .turbor_turbo_led(led_turbo),
   .ocm_mmc_on(ocm_mmc_on),
   .ocm_megaSD_enable(ocm_megaSD_enable),
   .ocm_slot1_mode(ocm_slot1_mode),
   .ocm_slot2_mode(ocm_slot2_mode),
   .ocm_ipl_en(ocm_ipl_en)
);

msx_slots msx_slots
(
   .clock_bus(clock_bus),
   .cpu_bus(cpu_bus),
   .device_bus(device_bus),
   .ext_SD_card_bus(ext_SD_card_bus),
   .flash_bus(flash_bus),
   .slot_expander(slot_expander),
   .layout_id(layout_id),
   .active_block(active_block),
   .active_RAM(active_RAM),
   .main_RAM(main_RAM),
   .lookup_SRAM(lookup_SRAM),
   .main_ram(main_ram),
   .dram(turbor_dram),
   .data(d_from_slots),
   .data_oe_rq(slot_oe_rq),
   .memory_bus(memory_bus_slots),
   .block_info(block_info),
   .active_slot(active_slot),
   .data_to_mapper(data_to_mapper),
   .ocm_megaSD_enable(ocm_megaSD_enable),
   .ocm_slot1_mode(ocm_slot1_mode),
   .ocm_slot2_mode(ocm_slot2_mode),
   .ocm_ipl_en(ocm_ipl_en),
   .ocm_mmc_on(ocm_mmc_on),
   .ocm_mmc_wait(ocm_mmc_wait)
);

endmodule
