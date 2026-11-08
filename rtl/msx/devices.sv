// devices
//
// Copyright (c) 2024-2025 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

module devices  #(parameter sysCLK)
(
    clock_bus_if.base_mp    clock_bus,                              // Clock interface
    input                   hard_reset,                             // cold reset (cpu_bus.reset is any reset)
    cpu_bus_if.device_mp    cpu_bus,                                // CPU bus interface
    input  MSX::device_bus_t device_bus,                             // Device control bus interface
    FDD_if.FDC_mp           FDD_bus[3],
    output MSX::video_t     video_bus,
    vram_bus_if.device_mp   vram_bus,
    memory_bus_if.device_mp memory_bus,
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
    assign data = scc_data & fdc_data & msx2_ram_data & tms_data & v99_data & rtc_data & psg_data & ppi_data & ocm_data & reset_status_data & opm_data & ym2148_data & systimer_data;// & TC8566AF_data;
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
    assign cpu_interrupt     = tms_interrupt | v99_interrupt | opm_irq | ym2148_irq;

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

    // Single clipping point for all sound sources
    sound_mix sound_mix (
        .clk(cpu_bus.clk),
        .opll(opll_sound),
        .scc(scc_sound),
        .psg(psg_sound),
        .dac(dac_sound),
        .opm_L(opm_sound_L),
        .opm_R(opm_sound_R),
        .keybeep(keybeep),
        .tape(tape_in & ~tape_motor_on),
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
        .tape_motor_on(tape_motor_on)
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
