// Yamaha SFG mapper
//
// Copyright (c) 2025 Molekula
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

module mapper_yamaha_sfg (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    input  MSX::block_info_t block_info,    // Active block (slot layout entry)
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    output MSX::device_bus_t device_out     // Cartridge device control
);

    

    wire cs = (block_info.typ == MAPPER_YAMAHA_SFG) && cpu_bus.mreq;

    logic rom_cs, dev_en, dev_we;
    always_comb begin
        dev_en = 1'b0;
        dev_we = 1'b0;
        rom_cs        = 1'b0;
        if (cs) begin
            case(cpu_bus.addr[13:0])
                14'h3FF0,
                14'h3FF1:
                    dev_en = 1'b1;
                14'h3FF2,
                14'h3FF3,
                14'h3FF4,
                14'h3FF5,
                14'h3FF6:                   
                    dev_we = 1'b1;
                14'h3FF7:                   
                    ;
                default: 
                    rom_cs = 1'b1;
            endcase
        end
    end

    assign device_out.en   = dev_en;
    assign device_out.we   = dev_we;

    // Multiplexing output data
    assign out.ram_cs   = rom_cs && cpu_bus.rd;
    assign out.rnw      = '1;
    assign out.addr     = rom_cs ? {11'd0, (cpu_bus.addr & (block_info.rom_size[15:0] - 16'd1))} : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;
    assign device_out.device_ref = 3'd0;
    assign device_out.mode       = 1'b1;
    assign device_out.param      = 1'b1;

endmodule
