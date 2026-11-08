// MSX slots
//
// Copyright (c) 2024 Molekula
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

module msx_slots (
    clock_bus_if.base_mp        clock_bus,
    cpu_bus_if.device_mp        cpu_bus,
    ext_sd_card_if.device_mp    ext_SD_card_bus,
    flash_bus_if.device_mp      flash_bus,
    memory_bus_if.device_mp     memory_bus,
    output MSX::block_info_t block_info,   
    input MSX::slot_expander_t  slot_expander[4],
    input MSX::block_t          slot_layout[64],
    input MSX::lookup_RAM_t     lookup_RAM[16],
    input MSX::lookup_SRAM_t    lookup_SRAM[4],
    input                 [1:0] active_slot,      // Currently active slot
    output                [7:0] data,
    output                      data_oe_rq,       // Priority output
    output MSX::device_bus_t device_bus,
    input                 [7:0] data_to_mapper,
    input                       ocm_megaSD_enable,
    input                       ocm_slot1_mode,
    input                 [1:0] ocm_slot2_mode,
    input                       ocm_ipl_en,
    output                      ocm_mmc_on
);

    memory_bus_if memory_bus_mappers();

    wire [1:0] active_subslot;
    wire       subslot_output_rq;
    wire [7:0] subslot_data;


    //TODO zjistit jak zápis a čtení ovlivňuje ostatní. Paměť, atd. dle  MFRSD nedojde k zápisu do RAM a čtení z RAM. (Write není blokováno v MFRSD)
    subslot subslot
    (
        .cpu_bus(cpu_bus),
        .slot_expander_conf(slot_expander),
        .data(subslot_data),
        .active_subslot(active_subslot),
        .expander_force_en(slot_expander_force_en),
        .output_rq(subslot_output_rq),
        .active_slot(active_slot)
    );

    wire [5:0] layout_id = {active_slot, active_subslot, cpu_bus.addr[15:14]};
    MSX::block_t active_block;
    MSX::lookup_RAM_t active_RAM;
    MSX::lookup_SRAM_t active_SRAM;

    assign active_block = slot_layout[layout_id];
    assign active_RAM = lookup_RAM[active_block.ref_ram];
    assign active_SRAM = lookup_SRAM[active_block.ref_sram];

    wire [1:0] offset_ram = active_block.offset_ram;
    wire       cart_num   = active_block.cart_num;

    assign block_info.typ        = active_block.mapper;
    assign block_info.device_ref = active_block.device_ref;
    assign block_info.base_ram   = active_RAM.addr;

    wire [26:0] base_ram   = active_RAM.addr;
    wire [16:0] ram_blocks = active_RAM.size;
    wire        ram_ro     = active_RAM.ro;
    wire [26:0] base_sram  = active_SRAM.addr;
    wire [15:0] sram_size  = active_SRAM.size;

    assign data       = subslot_output_rq ? subslot_data : mapper_data;
    assign data_oe_rq = subslot_output_rq;

    assign memory_bus.addr    = (memory_bus_mappers.sram_cs ? 27'(base_sram) : base_ram) + memory_bus_mappers.addr;
    assign memory_bus.rnw     = memory_bus_mappers.rnw | (memory_bus_mappers.ram_cs & ram_ro);
    assign memory_bus.data    = cpu_bus.data;
    assign memory_bus.ram_cs  = ~subslot_output_rq && (memory_bus_mappers.ram_cs || memory_bus_mappers.sram_cs);
    assign memory_bus.sram_cs = '0;

    assign memory_bus_mappers.q = memory_bus.q;

    assign block_info.rom_size   = 25'(ram_blocks) << 13;
    assign block_info.sram_size  = sram_size;
    assign block_info.id         = cart_num;
    assign block_info.offset_ram = offset_ram;

    wire [7:0] mapper_data;
    wire slot_expander_force_en;
    mappers mappers_inst (
        .clock_bus(clock_bus),
        .cpu_bus(cpu_bus),
        .device_bus(device_bus),
        .memory_bus(memory_bus_mappers),
        .ext_SD_card_bus(ext_SD_card_bus),
        .flash_bus(flash_bus),
        .block_info(block_info),
        .data(mapper_data),
        .data_to_mapper(data_to_mapper),
        .slot_expander_force_en(slot_expander_force_en),
        .ocm_megaSD_enable(ocm_megaSD_enable),
        .ocm_slot1_mode(ocm_slot1_mode),
        .ocm_slot2_mode(ocm_slot2_mode),
        .ocm_ipl_en(ocm_ipl_en),
        .ocm_mmc_on(ocm_mmc_on)
    );

endmodule
