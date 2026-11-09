// Turbo R FDC ROM mapper
//
// Copyright (c) 2025-2026 Molekula
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

// Disk ROM of the memory mapped TC8566AF of the MSX turbo R (Panasonic FS-A1ST / FS-A1GT):
// 16 KB banks in 4000-7FFF, the bank written at 7FF0 exactly and masked by the ROM size;
// no ROM in 8000-BFFF (the controller registers there come from dev_TC8566AF, which also
// reads the bank back). Behaviour as openMSX src/fdc/TurboRFDC.cc (writeMem, peekMem).
module mapper_turbor_fdc (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);

    wire       cs   = block_info.typ == MAPPER_TURBO_R_FDC && cpu_bus.mreq;
    wire [7:0] mask = 8'(block_info.rom_size[22:14] - 1'b1);    // banks - 1

    logic [7:0] bank[2];
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset)
            bank <= '{8'd0, 8'd0};
        else if (cs && cpu_bus.wr && cpu_bus.req && cpu_bus.addr == 16'h7FF0)
            bank[block_info.id] <= cpu_bus.data & mask;
    end

    wire rom = cs && cpu_bus.rd && cpu_bus.addr[15:14] == 2'b01;

    assign out.ram_cs  = rom;
    assign out.addr    = rom ? {5'b0, bank[block_info.id], cpu_bus.addr[13:0]} : {27{1'b1}};
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
