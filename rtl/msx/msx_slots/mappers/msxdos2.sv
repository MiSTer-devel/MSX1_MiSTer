// MSX-DOS2 mapper
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

// 16 KB bank in 4000-7FFF, nothing in the other pages (openMSX RomMSXDOS2).
// Bank register by mapper_param (openMSX picks it from ROM byte 94h):
//   0: 6000-6FFF (cartridge, 60h), 1: 7FF0 (00h), 2: 7FFE (7Fh, Aucnet NIA-2001)
module mapper_msxdos2 (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);

    wire cs = block_info.typ == MAPPER_MSXDOS2 && cpu_bus.mreq;

    logic reg_hit;
    always_comb begin
        case (block_info.mapper_param)
            2'd1:    reg_hit = cpu_bus.addr == 16'h7FF0;
            2'd2:    reg_hit = cpu_bus.addr == 16'h7FFE;
            default: reg_hit = cpu_bus.addr[15:12] == 4'h6;
        endcase
    end

    // openMSX setRom: block < blocks ? block : block & (blocks - 1)
    logic [11:0] nrBlocks, blockMask;
    assign nrBlocks  = {1'b0, block_info.rom_size[24:14]} + {11'd0, |block_info.rom_size[13:0]};
    assign blockMask = nrBlocks - 12'd1;

    wire [7:0] bank_data = {4'd0, cpu_bus.data} < nrBlocks ? cpu_bus.data : cpu_bus.data & blockMask[7:0];

    logic [7:0] bank[2];
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset)
            bank <= '{8'd0, 8'd0};
        else if (cs && cpu_bus.wr && cpu_bus.req && reg_hit)
            bank[block_info.id] <= bank_data;
    end

    wire rom = cs && cpu_bus.rd && cpu_bus.addr[15:14] == 2'b01;

    assign out.ram_cs  = rom;
    assign out.addr    = rom ? {5'b0, bank[block_info.id], cpu_bus.addr[13:0]} : {27{1'b1}};
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
