// Panasonic ROM mapper of the MSX turbo R / FS-A1WX family
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

// Behaviour as openMSX src/memory/RomPanasonic.cc. Eight 8 KB banks over 0000-FFFF, 9-bit bank
// numbers: below 80h a ROM block, 80h .. 80h + SRAM/8K the SRAM, from 180h a block of the main RAM,
// any other value a ROM block (masked by the number of blocks). Without a main RAM the banks from
// 180h are ROM too.
//   write 6000-7FEF: low 8 bits of the bank of region (A & 1C00h) >> 10, regions 5 and 6 swapped
//         (7400h -> C000-DFFF, 7800h -> A000-BFFF)
//   write 7FF8: bit n = bit 8 of bank n;  write 7FF9: control
//   read  7FF0-7FF7 (control bit 2): low 8 bits of bank A & 7;  7FF8 (bit 4): the bit 8 of the
//         banks;  7FF9 (bit 3): control
//   other writes go to the SRAM or RAM the bank selects (tested on an FS-A1GT, openMSX)
// Reset: control 0, every bank = ROM block 0.
// The main RAM (block with mapper PANASONIC_RAM) is reached through out.main_cs (msx_slots adds its
// base); the bank selects 8 KB block (bank - 180h) masked by the RAM size.
module mapper_panasonic (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    input  MSX::block_info_t block_info     // Active block (slot layout entry)
);

    wire cs = block_info.typ == MAPPER_PANASONIC && cpu_bus.mreq;

    logic [8:0] bank[8];
    logic [7:0] control;

    // the bank of a write to 6000-7FEF: regions 5 and 6 swapped
    wire [2:0] wregion = cpu_bus.addr[12:10] == 3'd5 ? 3'd6 :
                         cpu_bus.addr[12:10] == 3'd6 ? 3'd5 : cpu_bus.addr[12:10];
    wire       reg_area = cpu_bus.addr >= 16'h6000 && cpu_bus.addr < 16'h7FF0;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            for (int i = 0; i < 8; i++) bank[i] <= 9'd0;
            control <= 8'h00;
        end else if (cs && cpu_bus.wr && cpu_bus.req) begin
            if (reg_area)
                bank[wregion][7:0] <= cpu_bus.data;
            else if (cpu_bus.addr == 16'h7FF8)
                for (int i = 0; i < 8; i++) bank[i][8] <= cpu_bus.data[i];
            else if (cpu_bus.addr == 16'h7FF9)
                control <= cpu_bus.data;
        end
    end

    // register read back
    wire [7:0] hi_bits = {bank[7][8], bank[6][8], bank[5][8], bank[4][8], bank[3][8], bank[2][8], bank[1][8], bank[0][8]};
    wire rd_bank = control[2] && cpu_bus.addr >= 16'h7FF0 && cpu_bus.addr < 16'h7FF8;
    wire rd_hi   = control[4] && cpu_bus.addr == 16'h7FF8;
    wire rd_ctl  = control[3] && cpu_bus.addr == 16'h7FF9;
    wire rd_reg  = rd_bank || rd_hi || rd_ctl;

    // memory of the region
    wire [8:0] sel       = bank[cpu_bus.addr[15:13]];
    wire [7:0] sram_bnks = 8'(block_info.sram_size[10:3]);           // 8 KB SRAM banks
    wire       is_sram   = sram_bnks != 8'd0 && sel >= 9'h080 && sel < 9'h080 + {1'b0, sram_bnks};
    wire       is_ram    = block_info.main_ram_size != 17'd0 && sel >= 9'h180;
    wire [7:0] ram_block = 8'(sel - 9'h180) & 8'(block_info.main_ram_size - 1'b1);
    wire [9:0] nr_blocks = 10'(block_info.rom_size[24:13]);          // 8 KB ROM blocks (ST 256, GT 512)
    wire [8:0] rom_block = {1'b0, sel} < nr_blocks || nr_blocks == 10'd0 ? sel : sel & 9'(nr_blocks - 1'b1);
    wire [7:0] sram_bank = (sel[7:0] - 8'h80) & (sram_bnks - 1'b1);

    wire rom_rd  = cs && cpu_bus.rd && !is_sram && !is_ram && !rd_reg;
    wire mem_rw  = cs && (cpu_bus.rd ? !rd_reg : !(reg_area || cpu_bus.addr == 16'h7FF8 || cpu_bus.addr == 16'h7FF9));
    wire sram_rw = mem_rw && is_sram;
    wire ram_rw  = mem_rw && is_ram;

    assign out.ram_cs  = rom_rd;
    assign out.sram_cs = sram_rw;
    assign out.main_cs = ram_rw;
    assign out.rnw     = !((sram_rw || ram_rw) && cpu_bus.wr);
    assign out.addr    = sram_rw ? {6'b0, sram_bank, cpu_bus.addr[12:0]} :
                         ram_rw  ? {6'b0, ram_block, cpu_bus.addr[12:0]} :
                         rom_rd  ? {5'b0, rom_block, cpu_bus.addr[12:0]} : {27{1'b1}};
    assign out.data    = !(cs && cpu_bus.rd) ? 8'hFF :
                         rd_bank ? bank[cpu_bus.addr[2:0]][7:0] :
                         rd_hi   ? hi_bits :
                         rd_ctl  ? control : 8'hFF;

endmodule
