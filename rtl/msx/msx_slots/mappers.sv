// mappers
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

module mappers (
    clock_bus_if.base_mp        clock_bus,          // Interface for clock
    cpu_bus_if.device_mp        cpu_bus,            // Interface for CPU communication
    ext_sd_card_if.device_mp    ext_SD_card_bus,    // Interface Ext SD card
    flash_bus_if.device_mp      flash_bus,          // Interface to emulate FLASH
    input  MSX::block_info_t block_info,         // Active block (slot layout entry)
    output MSX::device_bus_t device_bus,         // Cartridge device control (to devices)
    memory_bus_if.device_mp     memory_bus,         // Interface for memory control
    output                      main_cs,            // memory_bus.addr is an offset in the main RAM
    output                [7:0] data,               // Data output from the active mapper; defaults to FF if no mapper is active
    input                 [7:0] data_to_mapper,
    output                      slot_expander_force_en,
    output                      mfrsd_expander_off, // MFRSD: slot expander off (register)
    input                       ocm_megaSD_enable,
    input                       ocm_slot1_mode,
    input                 [1:0] ocm_slot2_mode,
    input                       ocm_ipl_en,         // OCM IPL ROM visible (before BIOS load)
    output                      ocm_mmc_on,         // MegaSD window of the ESE-RAM mapped
    output                      ocm_mmc_wait        // CPU wait: MegaSD SPI busy
);

    // One entry per mapper instance. New mapper: add its name before M_COUNT
    // (D_COUNT if it also controls a device) and connect .out(mapper_out[M_<name>]).
    typedef enum {
        M_OFFSET, M_MIRROR, M_MSX2_RAM, M_ASCII8, M_ASCII16, M_GENERIC8K, M_GENERIC16K,
        M_FM_PAC, M_YAMAHA_SFG, M_KONAMI, M_KONAMI_SCC, M_GM2, M_CROSS_BLAIM, M_NATIONAL,
        M_HARRY_FOX, M_ZEMINA80, M_ZEMINA90, M_MFRSD, M_ESE_RAM, M_MEGA_RAM, M_OCM_IPL,
        M_TURBOR_FDC, M_PANASONIC, M_DRAM, M_ASCII16X, M_NEO,
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

    mapper_neo neo (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_NEO])
    );

    mapper_generic16k mapper_generic16k (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_GENERIC16K])
    );

    mapper_turbor_fdc turbor_fdc (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_TURBOR_FDC])
    );

    mapper_panasonic panasonic (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_PANASONIC])
    );

    mapper_dram dram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_DRAM])
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
    
    // One flash engine for MFRSD and the ASCII16-X cartridges: inactive mappers drive 0
    flash_bus_if flash_mfrsd();
    flash_bus_if flash_ascii16x();

    assign flash_bus.base_addr     = flash_mfrsd.base_addr     | flash_ascii16x.base_addr;
    assign flash_bus.addr          = flash_mfrsd.addr          | flash_ascii16x.addr;
    assign flash_bus.area_lo       = flash_mfrsd.area_lo       | flash_ascii16x.area_lo;
    assign flash_bus.area_size     = flash_mfrsd.area_size     | flash_ascii16x.area_size;
    assign flash_bus.chip          = flash_mfrsd.chip          | flash_ascii16x.chip;
    assign flash_bus.id            = flash_mfrsd.id            | flash_ascii16x.id;
    assign flash_bus.data_to_flash = flash_mfrsd.data_to_flash | flash_ascii16x.data_to_flash;
    assign flash_bus.we            = flash_mfrsd.we            | flash_ascii16x.we;
    assign flash_bus.ce            = flash_mfrsd.ce            | flash_ascii16x.ce;

    assign flash_mfrsd.data_from_flash    = flash_bus.data_from_flash;
    assign flash_mfrsd.data_valid         = flash_bus.data_valid;
    assign flash_ascii16x.data_from_flash = flash_bus.data_from_flash;
    assign flash_ascii16x.data_valid      = flash_bus.data_valid;

    mapper_ascii16x ascii16x (
        .cpu_bus(cpu_bus),
        .flash_bus(flash_ascii16x),
        .block_info(block_info),
        .out(mapper_out[M_ASCII16X])
    );

    ext_sd_card_if ext_SD_card_mfrsd();
    mapper_mfrsd  mapper_mfrsd (
        .cpu_bus(cpu_bus),
        .ext_SD_card_bus(ext_SD_card_mfrsd),
        .flash_bus(flash_mfrsd),
        .block_info(block_info),
        .out(mapper_out[M_MFRSD]),
        .data_to_mapper(data_to_mapper),
        .device_out(device_out[D_MFRSD]),
        .slot_expander_force_en(slot_expander_force_en),
        .expander_off(mfrsd_expander_off)
    );

    ext_sd_card_if ext_SD_card_ese();
    mapper_eseRam ese_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mapper_out[M_ESE_RAM]),
        .ext_SD_card_bus(ext_SD_card_ese),
        .megaSD_enable(ocm_megaSD_enable),
        .mmc_on(ocm_mmc_on),
        .mmc_wait(ocm_mmc_wait)
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
    assign main_cs            = mapper_merged.main_cs;
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
    assign ext_SD_card_mfrsd.busy         = ext_SD_card_bus.busy;
    assign ext_SD_card_ese.busy           = ext_SD_card_bus.busy;

endmodule
