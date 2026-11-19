// ASCII16-X mapper
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

// https://www.grauw.nl/projects/ascii-x/ascii16-x/ (XL 8 MB cartridge, S29GL064S flash)
//   4000-7FFF, C000-FFFF: bank register 0, written at x6xxx / x2xxx, xAxxx, xExxx
//   8000-BFFF, 0000-3FFF: bank register 1, written at x7xxx / x3xxx, xBxxx, xFxxx
//   bank number = {address bits 11-8, data}; 8 MB = 512 banks, the upper bits are ignored
// Every write also goes to the flash, addressed through the bank before the write.
module mapper_ascii16x (
    cpu_bus_if.device_mp     cpu_bus,
    flash_bus_if.device_mp   flash_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out
);

    localparam logic [24:0] FLASH_SIZE = 25'h0800000;

    wire cs = block_info.typ == MAPPER_ASCII16X && cpu_bus.mreq;

    logic [8:0] bank[2][2];                             // [cartridge][register]

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank[0] <= '{9'd0, 9'd0};
            bank[1] <= '{9'd0, 9'd0};
        end else if (cs && cpu_bus.wr && cpu_bus.req && cpu_bus.addr[13]) begin
            bank[block_info.id][cpu_bus.addr[12]] <= {cpu_bus.addr[8], cpu_bus.data};
        end
    end

    wire [22:0] flash_addr = {bank[block_info.id][~cpu_bus.addr[14]], cpu_bus.addr[13:0]};

    // The flash is the memory of the cartridge (ROM image, padded to the flash size by the loader)
    wire [24:0] area_size  = block_info.rom_size < FLASH_SIZE ? block_info.rom_size : FLASH_SIZE;
    wire        backed     = {2'b00, flash_addr} < area_size;

    wire flash_rd = cs && cpu_bus.rd;
    wire flash_wr = cs && cpu_bus.wr;
    wire ram_cs   = flash_rd && backed && ~flash_bus.data_valid;

    assign flash_bus.ce            = flash_rd || flash_wr;
    assign flash_bus.we            = flash_wr;
    assign flash_bus.addr          = cs ? flash_addr : '0;
    assign flash_bus.data_to_flash = flash_wr ? cpu_bus.data : '0;
    assign flash_bus.base_addr     = cs ? 27'd0 - block_info.base_ram : '0;
    assign flash_bus.area_lo       = '0;
    assign flash_bus.area_size     = cs ? area_size[23:0] : '0;
    assign flash_bus.chip          = cs;
    assign flash_bus.id            = cs && block_info.id;

    assign out.ram_cs  = ram_cs;
    assign out.addr    = cs ? {4'b0000, flash_addr} : {27{1'b1}};
    assign out.rnw     = 1'b1;
    assign out.data    = flash_rd && flash_bus.data_valid ? flash_bus.data_from_flash : 8'hFF;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;

endmodule
