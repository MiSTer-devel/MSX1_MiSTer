// MSX slots
//
// Copyright (c) 2024 Molekula
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

module msx_slots (
    clock_bus_if.base_mp        clock_bus,
    cpu_bus_if.device_mp        cpu_bus,
    ext_sd_card_if.device_mp    ext_SD_card_bus,
    flash_bus_if.device_mp      flash_bus,
    memory_bus_if.device_mp     memory_bus,
    output MSX::block_info_t block_info,   
    input MSX::slot_expander_t  slot_expander[4],
    output                [5:0] layout_id,        // block of the access: {slot, subslot, page}
    input MSX::block_t          active_block,     // its layout (memory_upload tables)
    input MSX::lookup_RAM_t     active_RAM,       // its memory
    input MSX::lookup_RAM_t     main_RAM,         // memory of main_ram.ref_ram
    input MSX::lookup_SRAM_t    lookup_SRAM[4],
    input MSX::main_ram_t       main_ram,         // turbo R: RAM other blocks may map (main_cs)
    input                       dram,             // turbo R S1990: DRAM mode
    input                 [1:0] active_slot,      // Currently active slot
    output                [7:0] data,
    output                      data_oe_rq,       // Priority output
    output MSX::device_bus_t device_bus,
    input                 [7:0] data_to_mapper,
    input                       ocm_megaSD_enable,
    input                       ocm_slot1_mode,
    input                 [1:0] ocm_slot2_mode,
    input                       ocm_ipl_en,
    output                      ocm_mmc_on,
    output                      ocm_mmc_wait
);

    memory_bus_if memory_bus_mappers();

    wire [1:0] active_subslot;
    wire       subslot_output_rq;
    wire       subslot_cs;
    wire [7:0] subslot_data;

    // FFFF of an expanded slot is the subslot register only: neither the memory nor the mapper
    // below sees the access (openMSX MSXCPUInterface, confirmed on turbo R GT).
    subslot subslot
    (
        .cpu_bus(cpu_bus),
        .slot_expander_conf(slot_expander),
        .data(subslot_data),
        .active_subslot(active_subslot),
        .expander_force_en(slot_expander_force_en),
        .output_rq(subslot_output_rq),
        .cs(subslot_cs),
        .active_slot(active_slot)
    );

    // rd/wr hidden, mreq kept: MFRSD derives slot_expander_force_en from mreq (no loop)
    cpu_bus_if cpu_bus_mappers(cpu_bus.clk, cpu_bus.reset);
    assign cpu_bus_mappers.mreq   = cpu_bus.mreq;
    assign cpu_bus_mappers.iorq   = cpu_bus.iorq;
    assign cpu_bus_mappers.rd     = cpu_bus.rd & ~subslot_cs;
    assign cpu_bus_mappers.wr     = cpu_bus.wr & ~subslot_cs;
    assign cpu_bus_mappers.m1     = cpu_bus.m1;
    assign cpu_bus_mappers.halt   = cpu_bus.halt;
    assign cpu_bus_mappers.rfsh   = cpu_bus.rfsh;
    assign cpu_bus_mappers.addr   = cpu_bus.addr;
    assign cpu_bus_mappers.data   = cpu_bus.data;
    assign cpu_bus_mappers.req    = cpu_bus.req;
    assign cpu_bus_mappers.int_rq = cpu_bus.int_rq;

    // MFRSD with its expander off: the whole slot is subslot 1 (openMSX getSubSlot), the
    // register keeps its last value. The slot is taken from any access to an MFRSD block
    // (the write that turns the expander off is one); registered, so no loop through the layout.
    wire       mfrsd_expander_off;
    logic      mfrsd_seen;
    logic [1:0] mfrsd_slot;
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset)
            mfrsd_seen <= 1'b0;
        else if (cpu_bus.mreq && (active_block.mapper == MAPPER_MFRSD0 || active_block.mapper == MAPPER_MFRSD1 ||
                                  active_block.mapper == MAPPER_MFRSD2 || active_block.mapper == MAPPER_MFRSD3)) begin
            mfrsd_seen <= 1'b1;
            mfrsd_slot <= active_slot;
        end
    end
    wire [1:0] layout_subslot = (mfrsd_expander_off && mfrsd_seen && active_slot == mfrsd_slot) ? 2'd1 : active_subslot;

    assign layout_id = {active_slot, layout_subslot, cpu_bus.addr[15:14]};
    MSX::lookup_SRAM_t active_SRAM;

    assign active_SRAM = lookup_SRAM[active_block.ref_sram];

    wire main_cs;

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

    assign memory_bus.addr    = (memory_bus_mappers.sram_cs ? 27'(base_sram) : main_cs ? main_RAM.addr : base_ram) + memory_bus_mappers.addr;
    assign memory_bus.rnw     = memory_bus_mappers.rnw | (memory_bus_mappers.ram_cs & ram_ro);
    assign memory_bus.data    = cpu_bus.data;
    assign memory_bus.ram_cs  = ~subslot_cs && (memory_bus_mappers.ram_cs || memory_bus_mappers.sram_cs || main_cs);
    assign memory_bus.sram_cs = '0;

    assign memory_bus_mappers.q = memory_bus.q;

    assign block_info.rom_size   = 25'(ram_blocks) << 13;
    assign block_info.sram_size  = sram_size;
    // OCM internal ESE-SCC (machine block): slot 2 follows Slot2Mode, slot 1 Slot1Mode
    assign block_info.id         = active_block.mapper == MAPPER_MEGARAM ? active_slot == 2'd2 : cart_num;
    assign block_info.offset_ram = offset_ram;
    assign block_info.mapper_param  = active_block.mapper_param;
    assign block_info.main_ram_size = main_ram.en ? main_RAM.size : 17'd0;
    assign block_info.dram          = dram;

    wire [7:0] mapper_data;
    wire slot_expander_force_en;
    mappers mappers_inst (
        .clock_bus(clock_bus),
        .cpu_bus(cpu_bus_mappers),
        .device_bus(device_bus),
        .memory_bus(memory_bus_mappers),
        .main_cs(main_cs),
        .ext_SD_card_bus(ext_SD_card_bus),
        .flash_bus(flash_bus),
        .block_info(block_info),
        .data(mapper_data),
        .data_to_mapper(data_to_mapper),
        .slot_expander_force_en(slot_expander_force_en),
        .mfrsd_expander_off(mfrsd_expander_off),
        .ocm_megaSD_enable(ocm_megaSD_enable),
        .ocm_slot1_mode(ocm_slot1_mode),
        .ocm_slot2_mode(ocm_slot2_mode),
        .ocm_ipl_en(ocm_ipl_en),
        .ocm_mmc_on(ocm_mmc_on),
        .ocm_mmc_wait(ocm_mmc_wait)
    );

endmodule
