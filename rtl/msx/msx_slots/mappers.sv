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
    input                 [1:0] ocm_slot2_mode
);

    MSX::mapper_out_t offset_out;
    mapper_offset offset (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(offset_out)
    );

    MSX::mapper_out_t mirror_out;
    mapper_mirror mirror (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mirror_out)
    );

    MSX::mapper_out_t msx2_ram_out;
    mapper_msx2_ram msx2_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(msx2_ram_out),
        .data_to_mapper(data_to_mapper)
    );

    MSX::mapper_out_t ascii8_out;
    mapper_ascii8 ascii8 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(ascii8_out)
    );

    MSX::mapper_out_t ascii16_out;
    mapper_ascii16 ascii16 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(ascii16_out)
    );

    MSX::mapper_out_t generic8k_out;
    mapper_generic8k mapper_generic8k (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(generic8k_out)
    );

    MSX::mapper_out_t generic16k_out;
    mapper_generic16k mapper_generic16k (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(generic16k_out)
    );

    MSX::mapper_out_t fm_pac_out;
    MSX::device_bus_t fm_pac_device_out;
    mapper_fm_pac fm_pac (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(fm_pac_out),
        .device_out(fm_pac_device_out)
    );

    MSX::mapper_out_t yamaha_sfg_out;
    MSX::device_bus_t yamaha_sfg_device_out;
    mapper_yamaha_sfg yamaha_sfg (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(yamaha_sfg_out),
        .device_out(yamaha_sfg_device_out)
    );

    MSX::mapper_out_t konami_out;
    mapper_konami konami (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(konami_out)
    );

    MSX::mapper_out_t konami_SCC_out;
    MSX::device_bus_t konami_SCC_device_out;
    mapper_konami_scc konami_scc (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(konami_SCC_out),
        .device_out(konami_SCC_device_out)
    );

    MSX::mapper_out_t gm2_out;
    mapper_gamemaster2 gm2 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(gm2_out)
    );

    MSX::mapper_out_t crossBlaim_out;
    mapper_crossBlaim mapper_crossBlaim (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(crossBlaim_out)
    );

    MSX::mapper_out_t national_out;
    mapper_national national (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(national_out)
    );

    MSX::mapper_out_t harryFox_out;
    mapper_harryFox mapper_harryFox (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(harryFox_out)
    );

    MSX::mapper_out_t zemina80_out;
    mapper_zemina80 mapper_zemina80 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(zemina80_out)
    );

    MSX::mapper_out_t zemina90_out;
    mapper_zemina90 mapper_zemina90 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(zemina90_out),
        .data_to_mapper(data_to_mapper)
    );
    
    MSX::mapper_out_t mfrsd_out;
    MSX::device_bus_t mfrsd_device_out;
    ext_sd_card_if ext_SD_card_mfrsd();
    mapper_mfrsd  mapper_mfrsd (
        .cpu_bus(cpu_bus),
        .ext_SD_card_bus(ext_SD_card_mfrsd),
        .flash_bus(flash_bus),
        .block_info(block_info),
        .out(mfrsd_out),
        .data_to_mapper(data_to_mapper),
        .device_out(mfrsd_device_out),
        .slot_expander_force_en(slot_expander_force_en)
    );

    MSX::mapper_out_t ese_ram_out;
    ext_sd_card_if ext_SD_card_ese();
    mapper_eseRam ese_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(ese_ram_out),
        .ext_SD_card_bus(ext_SD_card_ese),
        .megaSD_enable(ocm_megaSD_enable)
    );

    MSX::mapper_out_t mega_ram_out;
    MSX::device_bus_t mega_ram_device_out;
    mapper_megaram mega_ram (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(mega_ram_out),
        .device_out(mega_ram_device_out),
        .ocm_slot1_mode(ocm_slot1_mode),
        .ocm_slot2_mode(ocm_slot2_mode)
    );

    assign data                 = fm_pac_out.data 
                                & national_out.data 
                                & mfrsd_out.data 
                                & ese_ram_out.data;

    assign memory_bus.addr      = offset_out.addr
                                & mirror_out.addr
                                & msx2_ram_out.addr
                                & ascii8_out.addr
                                & ascii16_out.addr
                                & generic8k_out.addr
                                & generic16k_out.addr
                                & fm_pac_out.addr
                                & yamaha_sfg_out.addr
                                & konami_out.addr
                                & konami_SCC_out.addr
                                & gm2_out.addr
                                & national_out.addr
                                & crossBlaim_out.addr
                                & harryFox_out.addr
                                & zemina80_out.addr
                                & zemina90_out.addr
                                & mfrsd_out.addr
                                & ese_ram_out.addr
                                & mega_ram_out.addr;

    assign memory_bus.rnw       = offset_out.rnw
                                & mirror_out.rnw
                                & msx2_ram_out.rnw
                                & ascii8_out.rnw
                                & ascii16_out.rnw
                                & fm_pac_out.rnw
                                & konami_SCC_out.rnw
                                & gm2_out.rnw
                                & national_out.rnw
                                & mfrsd_out.rnw
                                & ese_ram_out.rnw
                                & mega_ram_out.rnw;

    assign memory_bus.ram_cs    = offset_out.ram_cs
                                | mirror_out.ram_cs
                                | msx2_ram_out.ram_cs
                                | ascii8_out.ram_cs
                                | ascii16_out.ram_cs
                                | generic8k_out.ram_cs
                                | generic16k_out.ram_cs
                                | fm_pac_out.ram_cs
                                | yamaha_sfg_out.ram_cs
                                | konami_out.ram_cs
                                | konami_SCC_out.ram_cs
                                | gm2_out.ram_cs
                                | crossBlaim_out.ram_cs
                                | national_out.ram_cs
                                | harryFox_out.ram_cs
                                | zemina80_out.ram_cs
                                | zemina90_out.ram_cs
                                | mfrsd_out.ram_cs
                                | ese_ram_out.ram_cs
                                | mega_ram_out.ram_cs;

    assign memory_bus.sram_cs   = ascii8_out.sram_cs
                                | ascii16_out.sram_cs
                                | fm_pac_out.sram_cs
                                | gm2_out.sram_cs
                                | national_out.sram_cs;

    assign memory_bus.data      = '1;

    assign device_bus.we        = fm_pac_device_out.we 
                                | yamaha_sfg_device_out.we;

    assign device_bus.en        = fm_pac_device_out.en 
                                | yamaha_sfg_device_out.en 
                                | konami_SCC_device_out.en 
                                | mfrsd_device_out.en 
                                | mega_ram_device_out.en;

    assign device_bus.mode      = konami_SCC_device_out.mode 
                                & mfrsd_device_out.mode;

    assign device_bus.param     = konami_SCC_device_out.param 
                                & mfrsd_device_out.param;

    assign device_bus.device_ref = cpu_bus.mreq ? block_info.device_ref : '0;
    assign device_bus.data       = 8'hFF;               // no mapper drives device data

    // SDCARD
    assign ext_SD_card_bus.rx             = ext_SD_card_ese.rx         |  ext_SD_card_mfrsd.rx;
    assign ext_SD_card_bus.tx             = ext_SD_card_ese.tx         |  ext_SD_card_mfrsd.tx;
    assign ext_SD_card_bus.data_to_SD     = ext_SD_card_ese.data_to_SD &  ext_SD_card_mfrsd.data_to_SD;
    assign ext_SD_card_mfrsd.data_from_SD = ext_SD_card_bus.data_from_SD;
    assign ext_SD_card_ese.data_from_SD   = ext_SD_card_bus.data_from_SD;

endmodule
