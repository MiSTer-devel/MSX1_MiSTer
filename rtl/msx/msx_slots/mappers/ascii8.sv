// ASCII8 mapper
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

module mapper_ascii8 (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,
    input  MSX::block_info_t block_info
);

    wire cs, mapped, mode_wizardy, mode_koei, mapper_en;

    assign mapped       = ^cpu_bus.addr[15:14];

    assign mapper_en    = (block_info.typ == MAPPER_ASCII8) |
                          (block_info.typ == MAPPER_KOEI) |
                          (block_info.typ == MAPPER_WIZARDY);

    assign mode_wizardy = (block_info.typ == MAPPER_WIZARDY);
    assign mode_koei    = (block_info.typ == MAPPER_KOEI);

    assign cs           = mapped & mapper_en & cpu_bus.mreq;

    logic [7:0] bank[2][4];
    logic [7:0] sramBank[2][4];
    logic [7:0] sramEnable[2];

    wire        sram_exists   = (block_info.sram_size > 0);
    wire  [7:0] sram_mask     = (block_info.sram_size[10:3] > 0) ?
                                (block_info.sram_size[10:3] - 8'd1) : 8'd0;

    wire  [7:0] sramEnableBit = mode_wizardy ? 8'h80 : block_info.rom_size[20:13];
    wire  [7:0] sramPages     = mode_koei ? 8'h34 : 8'h30;
    wire  [1:0] region        = cpu_bus.addr[12:11];
    wire  [7:0] bank_base     = bank[block_info.id][{cpu_bus.addr[15], cpu_bus.addr[13]}];
    wire  [7:0] sram_bank_base = sramBank[block_info.id][{cpu_bus.addr[15], cpu_bus.addr[13]}];

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank       <= '{'{default: '0},'{default: '0}};
            sramBank   <= '{'{default: '0},'{default: '0}};
            sramEnable <= '{default: '0};
        end else if (cs & cpu_bus.wr & (cpu_bus.addr[15:13] == 3'b011) && cpu_bus.req) begin
            if (((cpu_bus.data & sramEnableBit) != 0) && sram_exists) begin
                sramEnable[block_info.id] <= sramEnable[block_info.id] |
                                        ((8'b00000100 << region) & sramPages);
                sramBank[block_info.id][region] <= cpu_bus.data & sram_mask;
            end else begin
                sramEnable[block_info.id] <= sramEnable[block_info.id] &
                                        ~(8'b00000100 << region);
                bank[block_info.id][region] <= cpu_bus.data;
            end
        end
    end

    wire        sram_en   = |((8'b00000001 << cpu_bus.addr[15:13]) & sramEnable[block_info.id]);
    wire [26:0] sram_addr = {6'b0, sram_bank_base, cpu_bus.addr[12:0]};
    wire [26:0] ram_addr  = {6'b0, bank_base, cpu_bus.addr[12:0]};
    wire        ram_valid = (out.addr < {2'b00, block_info.rom_size});

    wire sram_cs   = cs & sram_en & (cpu_bus.rd || cpu_bus.wr);
    wire ram_cs    = cs & ram_valid & ~sram_en & cpu_bus.rd;

    assign out.sram_cs = sram_cs;
    assign out.main_cs = 1'b0;
    assign out.ram_cs  = ram_cs;
    assign out.rnw     = ~(sram_cs & cpu_bus.wr);
    assign out.addr    = cs ? (sram_en ? sram_addr : ram_addr) : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.data    = 8'hFF;

endmodule
