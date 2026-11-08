// mappers
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

module mappers (
    clock_bus_if.base_mp        clock_bus,          // Interface for clock
    cpu_bus_if.device_mp        cpu_bus,            // Interface for CPU communication
    ext_sd_card_if.device_mp    ext_SD_card_bus,    // Interface Ext SD card
    flash_bus_if.device_mp      flash_bus,          // Interface to emulate FLASH
    input  MSX::block_info_t block_info,         // Active block (slot layout entry)
    output MSX::device_bus_t device_bus,         // Cartridge device control (to devices)
    memory_bus_if.device_mp     memory_bus,         // Interface for memory control
    output                [7:0] data,               // Data output from the active mapper; defaults to FF if no mapper is active
    input                 [7:0] data_to_mapper,
    output                      slot_expander_force_en,
    input                       ocm_megaSD_enable,
    input                       ocm_slot1_mode,
    input                 [1:0] ocm_slot2_mode,
    input                       ocm_ipl_en,         // OCM IPL ROM visible (before BIOS load)
    output                      ocm_mmc_on          // MegaSD window of the ESE-RAM mapped
);

    // One entry per mapper instance. New mapper: add its name before M_COUNT
    // (D_COUNT if it also controls a device) and connect .out(mapper_out[M_<name>]).
    typedef enum {
        M_OFFSET, M_MIRROR, M_MSX2_RAM, M_ASCII8, M_ASCII16, M_GENERIC8K, M_GENERIC16K,
        M_FM_PAC, M_YAMAHA_SFG, M_KONAMI, M_KONAMI_SCC, M_GM2, M_CROSS_BLAIM, M_NATIONAL,
        M_HARRY_FOX, M_ZEMINA80, M_ZEMINA90, M_MFRSD, M_ESE_RAM, M_MEGA_RAM, M_OCM_IPL,
        M_COUNT
    } mapper_idx_t;

    typedef enum {
        D_FM_PAC, D_YAMAHA_SFG, D_KONAMI_SCC, D_MFRSD, D_MEGA_RAM,
        D_COUNT
    } device_idx_t;

    MSX::mapper_out_t mapper_out[M_COUNT];
    MSX::device_bus_t device_out[D_COUNT];

    mapper_offset offset (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_OFFSET])
    );

    mapper_mirror mirror (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_MIRROR])
    );

    mapper_msx2_ram msx2_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_MSX2_RAM]),
        .data_to_mapper(data_to_mapper)
    );

    mapper_ascii8 ascii8 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ASCII8])
    );

    mapper_ascii16 ascii16 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ASCII16])
    );

    mapper_generic8k mapper_generic8k (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_GENERIC8K])
    );

    mapper_generic16k mapper_generic16k (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_GENERIC16K])
    );

    mapper_fm_pac fm_pac (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_FM_PAC]),
        .device_out(device_out[D_FM_PAC])
    );

    mapper_yamaha_sfg yamaha_sfg (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_YAMAHA_SFG]),
        .device_out(device_out[D_YAMAHA_SFG])
    );

    mapper_konami konami (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_KONAMI])
    );

    mapper_konami_scc konami_scc (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_KONAMI_SCC]),
        .device_out(device_out[D_KONAMI_SCC])
    );

    mapper_gamemaster2 gm2 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_GM2])
    );

    mapper_crossBlaim mapper_crossBlaim (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_CROSS_BLAIM])
    );

    mapper_national national (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_NATIONAL])
    );

    mapper_harryFox mapper_harryFox (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_HARRY_FOX])
    );

    mapper_zemina80 mapper_zemina80 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ZEMINA80])
    );

    mapper_zemina90 mapper_zemina90 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ZEMINA90]),
        .data_to_mapper(data_to_mapper)
    );
    
    ext_sd_card_if ext_SD_card_mfrsd();
    mapper_mfrsd  mapper_mfrsd (
        .cpu_bus(cpu_bus),
        .ext_SD_card_bus(ext_SD_card_mfrsd),
        .flash_bus(flash_bus),
        .block_info(block_info),
        .out(mapper_out[M_MFRSD]),
        .data_to_mapper(data_to_mapper),
        .device_out(device_out[D_MFRSD]),
        .slot_expander_force_en(slot_expander_force_en)
    );

    ext_sd_card_if ext_SD_card_ese();
    mapper_eseRam ese_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ESE_RAM]),
        .ext_SD_card_bus(ext_SD_card_ese),
        .megaSD_enable(ocm_megaSD_enable),
        .mmc_on(ocm_mmc_on)
    );

    mapper_megaram mega_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_MEGA_RAM]),
        .device_out(device_out[D_MEGA_RAM]),
        .ocm_slot1_mode(ocm_slot1_mode),
        .ocm_slot2_mode(ocm_slot2_mode)
    );

    mapper_ocm_ipl ocm_ipl (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .ipl_en(ocm_ipl_en),
        .out(mapper_out[M_OCM_IPL])
    );

    // Merge: inactive mappers output MSX::*_IDLE, so AND / OR over all entries
    // selects the active one. Same logic as a hand-written wired-AND / OR.
    MSX::mapper_out_t mapper_merged;
    MSX::device_bus_t device_merged;

    always_comb begin
        mapper_merged = MSX::MAPPER_OUT_IDLE;
        for (int i = 0; i < M_COUNT; i++)
            mapper_merged = MSX::mapper_out_merge(mapper_merged, mapper_out[i]);

        device_merged = MSX::DEVICE_BUS_IDLE;
        for (int i = 0; i < D_COUNT; i++)
            device_merged = MSX::device_bus_merge(device_merged, device_out[i]);
    end

    assign data               = mapper_merged.data;
    assign memory_bus.addr    = mapper_merged.addr;
    assign memory_bus.rnw     = mapper_merged.rnw;
    assign memory_bus.ram_cs  = mapper_merged.ram_cs;
    assign memory_bus.sram_cs = mapper_merged.sram_cs;
    assign memory_bus.data    = '1;

    assign device_bus.we         = device_merged.we;
    assign device_bus.en         = device_merged.en;
    assign device_bus.mode       = device_merged.mode;
    assign device_bus.param      = device_merged.param;
    assign device_bus.device_ref = cpu_bus.mreq ? block_info.device_ref : '0;

    // SDCARD
    assign ext_SD_card_bus.rx             = ext_SD_card_ese.rx         |  ext_SD_card_mfrsd.rx;
    assign ext_SD_card_bus.tx             = ext_SD_card_ese.tx         |  ext_SD_card_mfrsd.tx;
    assign ext_SD_card_bus.data_to_SD     = ext_SD_card_ese.data_to_SD &  ext_SD_card_mfrsd.data_to_SD;
    assign ext_SD_card_mfrsd.data_from_SD = ext_SD_card_bus.data_from_SD;
    assign ext_SD_card_ese.data_from_SD   = ext_SD_card_bus.data_from_SD;

endmodule
