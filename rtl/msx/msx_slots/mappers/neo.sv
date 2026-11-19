// NEO-8 and NEO-16 mappers
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
//

// As openMSX RomNeo8 / RomNeo16:
//   NEO-8:  6 x 8 KB banks at 0000-BFFF, register n written at x(1000+800n)-x(17FF+800n)
//   NEO-16: 3 x 16 KB banks at 0000-BFFF, register n written at x(1000+1000n)-x(17FF+1000n)
//   registers are 12 bit: even address = bits 7-0, odd address = bits 11-8 (data bits 3-0)
//   address bits 15-14 are ignored when writing; C000-FFFF reads FF; reset sets all banks to 0
//   bank >= ROM banks wraps with mask (banks - 1), as openMSX RomBlocks::setRom
module mapper_neo (
    cpu_bus_if.device_mp     cpu_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out
);

    wire neo8  = block_info.typ == MAPPER_NEO8;
    wire neo16 = block_info.typ == MAPPER_NEO16;
    wire cs    = (neo8 || neo16) && cpu_bus.mreq;

    logic [11:0] bank[2][6];                            // [cartridge][register]

    // Register written: NEO-8 3'b010..3'b111 -> 0..5, NEO-16 3'b010/100/110 -> 0..2
    wire [2:0] wsel   = cpu_bus.addr[13:11];
    wire       wvalid = neo8 ? wsel >= 3'd2 : (wsel >= 3'd2 && !wsel[0]);
    wire [2:0] wreg   = neo8 ? wsel - 3'd2 : {1'b0, wsel[2:1]} - 3'd1;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank <= '{'{default: '0}, '{default: '0}};
        end else if (cs && cpu_bus.wr && cpu_bus.req && wvalid) begin
            if (cpu_bus.addr[0])
                bank[block_info.id][wreg][11:8] <= cpu_bus.data[3:0];
            else
                bank[block_info.id][wreg][7:0]  <= cpu_bus.data;
        end
    end

    // Read: NEO-8 page = addr[15:13] (0..5), NEO-16 page = addr[15:14] (0..2)
    wire [2:0]  rreg    = neo8 ? cpu_bus.addr[15:13] : {1'b0, cpu_bus.addr[15:14]};
    wire        mapped  = cpu_bus.addr[15:14] != 2'b11;
    wire [11:0] block   = bank[block_info.id][rreg];

    // ROM size in banks (rounded up), 0 when empty
    wire [12:0] blocks8  = {1'b0, block_info.rom_size[24:13]} + {12'd0, |block_info.rom_size[12:0]};
    wire [11:0] blocks16 = {1'b0, block_info.rom_size[24:14]} + {11'd0, |block_info.rom_size[13:0]};
    wire [12:0] blocks   = neo8 ? blocks8 : {1'b0, blocks16};
    wire [12:0] mask     = blocks - 13'd1;
    wire [11:0] block_w  = {1'b0, block} < blocks ? block : block & mask[11:0];

    wire [26:0] ram_addr = neo8 ? {2'b00, block_w, cpu_bus.addr[12:0]}
                                : {1'b0,  block_w, cpu_bus.addr[13:0]};
    wire        ram_cs   = cs && cpu_bus.rd && mapped && ram_addr < {2'b00, block_info.rom_size};

    assign out.ram_cs  = ram_cs;
    assign out.addr    = ram_cs ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
