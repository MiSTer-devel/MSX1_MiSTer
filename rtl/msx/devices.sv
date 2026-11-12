// devices
//
// Copyright (c) 2024-2025 Molekula
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
//

module devices  #(parameter sysCLK)
(
    clock_bus_if.base_mp    clock_bus,                              // Clock interface
    input                   hard_reset,                             // cold reset (cpu_bus.reset is any reset)
    cpu_bus_if.device_mp    cpu_bus,                                // CPU bus interface
    input  MSX::device_bus_t device_bus,                             // Device control bus interface
    FDD_if.FDC_mp           FDD_bus[MSX::N_FDC],
    output MSX::video_t     video_bus,
    vram_bus_if.device_mp   vram_bus,
    memory_bus_if.device_mp memory_bus,
    wave_bus_if.device_mp   wave_bus,                               // OPL4 sample memory
    input  MSX::block_info_t block_info,
    input MSX::io_device_t  io_device[32][3],                       // Array of IO devices
    input MSX::io_device_mem_ref_t io_memory[8],                    // Array of memory references
    input MSX::kb_memory_t  kb_upload_memory,
    input MSX::user_config_t msx_user_config,
    input            [10:0] ps2_key,
    input            [24:0] ps2_mouse,
    input            [64:0] rtc_time,
    input             [7:0] uart_rx_data,
    input                   uart_rx,
    output    signed [15:0] sound_L,                                // Mixed and clipped audio (sound_mix)
    output    signed [15:0] sound_R,
    output            [7:0] data,                                   // Combined data output
    output                  data_oe_rq,                             // Priorite data
    output            [7:0] data_to_mapper,                         // Data output to mapper
    output                  cpu_interrupt,
    input             [5:0] joy[2],
    input                   tape_in,
    output                  tape_motor_on,
    output            [7:0] slot_config,
    output                  keybeep,
    output                  reset_lock,
    output                  reset_request,
    output MSX::cpu_speed_t cpu_speed,              // OCM turbo, '0 without OCM
    output                  opll_wait,              // CPU wait: OPLL busy (turbo)
    output                  opl4_wait,              // CPU wait: OPL4 wave part busy
    output                  turbor_r800,            // S1990: R800 selected
    output                  turbor_dram,            // S1990: DRAM mode (ROM read from the main RAM)
    output                  pause,                  // hold the CPU: machine pause or turbo R hardware pause
    output                  pause_led,
    output                  turbor_turbo_led,
    input                   ocm_mmc_on,
    output                  ocm_megaSD_enable,
    output                  ocm_slot1_mode,
    output [1:0]            ocm_slot2_mode,
    output                  ocm_ipl_en              // OCM IPL ROM visible (before BIOS load)
);

    MSX::video_t            video_bus_tms, video_bus_v99;
    vram_bus_if             vram_bus_tms();
    vram_bus_if             vram_bus_v99();

    // Výstupy kombinující jednotlivé zařízení
    assign data = scc_data & fdc_data & msx2_ram_data & tms_data & v99_data & rtc_data & psg_data & ppi_data & ocm_data & reset_status_data & opm_data & ym2148_data & systimer_data & s1990_data & turbor_pcm_data & turbor_pause_data & opl4_data;
    assign data_oe_rq = fdc_data_oe_rq;// | TC8566AF_data_oe_rq;
    assign data_to_mapper = msx2_ram_data_to_mapper & latch_port_data_to_mapper;

    assign reset_request = ocm_reset_request;
    assign reset_lock    = ocm_reset_lock;

    assign memory_bus.addr    = kanji_ram_addr;
    assign memory_bus.ram_cs  = kanji_ram_cs;
    assign memory_bus.sram_cs = '0;
    assign memory_bus.data    = '1;
    assign memory_bus.rnw     = '1;

    // VIDEO interfaces
    assign cpu_interrupt     = tms_interrupt | v99_interrupt | opm_irq | ym2148_irq | opl4_irq;

    assign video_bus         = video_bus_tms | video_bus_v99;     // only the enabled VDP drives

    assign vram_bus.addr     = vram_bus_tms.addr  & vram_bus_v99.addr;
    assign vram_bus.data     = vram_bus_tms.data  & vram_bus_v99.data;
    assign vram_bus.we_lo    = vram_bus_tms.we_lo | vram_bus_v99.we_lo;
    assign vram_bus.we_hi    = vram_bus_tms.we_hi | vram_bus_v99.we_hi;

    assign vram_bus_tms.q_lo = vram_bus.q_lo;
    assign vram_bus_tms.q_hi = vram_bus.q_hi;
    assign vram_bus_v99.q_lo = vram_bus.q_lo;
    assign vram_bus_v99.q_hi = vram_bus.q_hi;

    //MSX2 memory limiter

    // Definice instancí zařízení s výstupy pro propojení
    MSX::sound_t opll_sound;
    dev_opll opll (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .clock_bus(clock_bus),
        .io_device(io_device[DEV_OPLL]),
        .enawait(cpu_speed.en && cpu_speed.clock_sel != 2'b00),
        .wait_rq(opll_wait),
        .sound(opll_sound)
    );

    MSX::sound_t opm_sound_L, opm_sound_R;
    wire         [7:0] opm_data;
    wire               opm_irq;
    dev_opm opm (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .clock_bus(clock_bus),
        .io_device(io_device[DEV_OPM]),
        .irq(opm_irq),
        .data(opm_data),
        .sound_L(opm_sound_L),
        .sound_R(opm_sound_R)
    );

    MSX::sound_t opl4_sound_L, opl4_sound_R;
    wire         [7:0] opl4_data;
    wire               opl4_irq;
    dev_opl4 opl4 (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_OPL4]),
        .io_memory(io_memory),
        .wave_bus(wave_bus),
        .sound_L(opl4_sound_L),
        .sound_R(opl4_sound_R),
        .data(opl4_data),
        .irq(opl4_irq),
        .wait_rq(opl4_wait)
    );

    wire         [7:0] ym2148_data;
    wire               ym2148_irq;
    dev_YM2148 ym2148 (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .clock_bus(clock_bus),
        .irq(ym2148_irq),
        .io_device(io_device[DEV_YM2148]),
        .uart_rx_data(uart_rx_data),
        .uart_rx(uart_rx),
        .data(ym2148_data)
    );

    wire [7:0] scc_data;
    MSX::sound_t scc_sound;
    dev_scc scc (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .device_bus(device_bus),
        .io_device(io_device[DEV_SCC]),
        .sound(scc_sound),
        .data(scc_data)
    );

    wire [7:0] msx2_ram_data_to_mapper;
    wire [7:0] msx2_ram_data;
    dev_msx2_ram msx2_ram (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .io_device(io_device[DEV_MSX2_RAM]),
        .limit_internal_mapper(ocm_mapper_limit),
        .data(msx2_ram_data),
        .data_to_mapper(msx2_ram_data_to_mapper)
    );

    wire [7:0] latch_port_data_to_mapper;
    dev_latch_port latch_port (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .io_device(io_device[DEV_LATCH_PORT]),
        .data_to_mapper(latch_port_data_to_mapper)
    );

    wire [7:0] fdc_data;
    wire       fdc_data_oe_rq;
    dev_FDC #(.sysCLK(sysCLK)) FDC (
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .block_info(block_info),
        .io_device(io_device),
        .FDD_bus(FDD_bus),
        .data(fdc_data),
        .data_oe_rq(fdc_data_oe_rq)
    );

    wire [26:0] kanji_ram_addr;
    wire        kanji_ram_cs;
    wire        ocm_jis2_en;
    dev_kanji kanji (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_KANJI]),
        .io_memory(io_memory),
        .jis2_en(ocm_jis2_en),
        .ram_cs(kanji_ram_cs),
        .ram_addr(kanji_ram_addr)
    );

    wire  [7:0] ocm_data;
    wire        ocm_mapper_limit;
    wire        ocm_reset_request;
    wire        ocm_reset_lock;
    dev_ocm ocm (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .io_device(io_device[DEV_OCM_BOOT]),
        .ff_dip_req(msx_user_config.ocm_dip),
        .ps2_key(ps2_key),
        .mmc_on(ocm_mmc_on),
        .cpu_speed(cpu_speed),
        .data(ocm_data),
        .ipl_en(ocm_ipl_en),
        .jis2_en(ocm_jis2_en),
        .mapper_limit(ocm_mapper_limit),
        .megaSD_enable(ocm_megaSD_enable),
        .Slot1Mode(ocm_slot1_mode),
        .Slot2Mode(ocm_slot2_mode),
        .rst_key_lock(ocm_reset_lock),
        .swio_reset(ocm_reset_request)
    );

    wire  [7:0] tms_data;
    wire        tms_interrupt;
    dev_tms tms (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .video_bus(video_bus_tms),
        .vram_bus(vram_bus_tms),
        .io_device(io_device[DEV_VDP_TMS]),
        .data(tms_data),
        .interrupt(tms_interrupt),
        .border(msx_user_config.border)
    );

    wire  [7:0] v99_data;
    wire        v99_interrupt;
    dev_v99 v99 (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .video_bus(video_bus_v99),
        .vram_bus(vram_bus_v99),
        .io_device(io_device[DEV_VDP_V99xx]),
        .data(v99_data),
        .interrupt(v99_interrupt),
        .border(msx_user_config.border)
    );

    wire [7:0] rtc_data;
    dev_rtc dev_rtc
    (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .io_device(io_device[DEV_RTC]),
        .rtc_time(rtc_time),
        .data(rtc_data)
    );

    wire [7:0] psg_data;
    MSX::sound_t psg_sound;
    dev_psg dev_psg
    (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .io_device(io_device[DEV_PSG]),
        .sound(psg_sound),
        .data(psg_data),
        .joy(joy_sw),
        .ps2_mouse(ps2_mouse),
        .mouse_en(ocm_present),
        .mouse_port(msx_user_config.mouse_port),
        .tape_in(tape_in)
    );

    // OCM: joystick swap and PS/2 mouse (OSD options shown only for OCM)
    wire       ocm_present = io_device[DEV_OCM_BOOT][0].enable;
    wire       joy_swap    = ocm_present && msx_user_config.joy_swap;
    wire [5:0] joy_sw[2];
    assign joy_sw[0] = joy_swap ? joy[1] : joy[0];
    assign joy_sw[1] = joy_swap ? joy[0] : joy[1];

    MSX::sound_t dac_sound;
    dev_dac dev_dac
    (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .block_info(block_info),
        .io_device(io_device[DEV_DAC]),
        .sound(dac_sound)
    );

    // Turbo R: S1990 (E4h / E5h), PCM (A4h / A5h), pause (A7h); the firmware switch is an OSD
    // option, the pause key the PS/2 Pause key (doc/turboR.md)
    wire [7:0] s1990_data, turbor_pcm_data, turbor_pause_data;
    wire       turbor_mute, turbor_hw_pause, turbor_pause_led;
    wire       pause_key;                           // Pause key state (dev_ppi, keyboard.sv)
    MSX::sound_t turbor_pcm_sound;
    dev_s1990 dev_s1990 (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_S1990]),
        .firmware_sw(msx_user_config.turbor_firmware),
        .data(s1990_data),
        .r800(turbor_r800),
        .dram(turbor_dram)
    );
    dev_turbor_pcm dev_turbor_pcm (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_TURBOR_PCM]),
        .data(turbor_pcm_data),
        .sound(turbor_pcm_sound),
        .mute_all(turbor_mute)
    );
    dev_turbor_pause dev_turbor_pause (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_TURBOR_PAUSE]),
        .pause_key(pause_key),
        .data(turbor_pause_data),
        .hw_pause(turbor_hw_pause),
        .pause_led(turbor_pause_led),
        .turbo_led(turbor_turbo_led)
    );

    // Machine pause (doc/pauza.md): the open OSD with "Pause when OSD open", or the Pause key
    // unless the machine reads it itself (turbo R A7h). CPU held by WAIT, sound muted.
    wire       machine_pause = msx_user_config.osd_pause
                               || (pause_key && !io_device[DEV_TURBOR_PAUSE][0].enable);
    assign pause     = machine_pause || turbor_hw_pause;
    assign pause_led = machine_pause || turbor_pause_led;

    // Single clipping point for all sound sources
    sound_mix sound_mix (
        .clk(cpu_bus.clk),
        .opll(opll_sound),
        .scc(scc_sound),
        .psg(psg_sound),
        .dac(dac_sound),
        .pcm(turbor_pcm_sound),
        .mute(turbor_mute || machine_pause),
        .opm_L(opm_sound_L),
        .opm_R(opm_sound_R),
        .opl4_L(opl4_sound_L),
        .opl4_R(opl4_sound_R),
        .keybeep(keybeep),
        .tape(tape_in & ~tape_motor_on & msx_user_config.tape_monitor),
        .sound_L(sound_L),
        .sound_R(sound_R)
    );

    wire [7:0] ppi_data;
    dev_ppi dev_ppi
    (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_PPI]),
        .data(ppi_data),
        .kb_upload_memory(kb_upload_memory),
        .ps2_key(ps2_key),
        .slot_config(slot_config),
        .keybeep(keybeep),
        .tape_motor_on(tape_motor_on),
        .pause_key(pause_key)
    );

    wire [7:0] reset_status_data;
    dev_reset_status dev_reset_status (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_RESET_STATUS]),
        .hard_reset(hard_reset),
        .data(reset_status_data)
    );

    wire [7:0] systimer_data;
    dev_systimer dev_systimer (
        .cpu_bus(cpu_bus),
        .io_device(io_device[DEV_SYSTIMER]),
        .data(systimer_data)
    );

endmodule
