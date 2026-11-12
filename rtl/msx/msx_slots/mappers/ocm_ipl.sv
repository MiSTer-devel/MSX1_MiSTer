// OCM IPL ROM
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

// ROM contents: iplrom.vhd of MSX_MiSTer (https://github.com/MiSTer-devel/MSX_MiSTer), ESE Artists' factory / KdL.
// IPL ROM of OCM (slot 3-3): visible only before the OCM-BIOS is loaded, i.e. from
// reset until the first write to PPI port A8h (ipl_en from dev_ocm, OCM ff_ldbios_n).
module mapper_ocm_ipl (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,
    input                   ipl_en,
    output MSX::mapper_out_t out
);
    wire        cs       = block_info.typ == MAPPER_OCM_IPL && ipl_en && cpu_bus.mreq && cpu_bus.rd;
    wire [26:0] ram_addr = {11'b0, block_info.offset_ram, cpu_bus.addr[13:0]};
    wire        ram_cs   = cs && ram_addr < {2'b00, block_info.rom_size};

    assign out.ram_cs  = ram_cs;
    assign out.addr    = ram_cs ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
