// Konami Ultimate Collection mapper
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
// As openMSX KonamiUltimateCollection.cc (documentation by Manuel Pazos, the author).
// 8 MB flash M29W640GB, SCC/SCC+ and a DAC. 4000-BFFF in four 8 kB pages.
//   7FFE offset, added to every bank (8 bit wrap)
//   7FFF 7-6 A21-A20, 5 Konami (1) / Konami SCC (0), 4 flash write, 3 4000-5FFF fixed in the
//        Konami mode + DAC, 2 7FFE/7FFF locked, 1 no bank switching
//   BFFE/BFFF SCC mode: 5 SCC+, 4 SCC off
// A write reaches every function at once (registers, banks, DAC, flash), the flash with the
// address from before the write; only a write to the SCC goes nowhere else.
module mapper_kuc (
    cpu_bus_if.device_mp     cpu_bus,
    flash_bus_if.device_mp   flash_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out,
    output MSX::device_bus_t device_out      // SCC (en, mode), DAC strobe (we)
);

    localparam logic [24:0] FLASH_SIZE = 25'h0800000;

    wire        cs   = block_info.typ == MAPPER_KUC && cpu_bus.mreq;
    wire        id   = block_info.id;
    wire [15:0] a    = cpu_bus.addr;
    wire        in_8k = a[15] ^ a[14];                      // 4000-BFFF
    wire  [1:0] page = {a[15], a[13]};

    logic [7:0] bank[2][4], mapper_reg[2], offset[2], scc_mode[2];

    // the register as this write leaves it: bank and DAC decoding use the new value
    wire        reg_wr = cs && cpu_bus.wr && ~mapper_reg[id][2] && a == 16'h7FFF;
    wire  [7:0] mr     = reg_wr ? cpu_bus.data : mapper_reg[id];
    wire        konami = mr[5];

    // SCC: address bit 8 must be 0 (leftover of a version with two SCCs)
    wire scc_area = ~scc_mode[id][4] && ~a[8] && a[10:1] != 10'h3FF &&
                    (scc_mode[id][5] ? bank[id][3][7]          && a[15:11] == 5'b10111
                                     : bank[id][2][5:0] == '1  && a[15:11] == 5'b10011);

    wire bank_wr = konami ? ~(mr[3] && page == 2'd0) && (page != 2'd0 || a[12:11] == 2'b10)
                          : a[12:11] == 2'b10;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            for (int c = 0; c < 2; c++) begin
                bank[c]       <= '{8'd0, 8'd1, 8'd2, 8'd3};
                mapper_reg[c] <= '0;
                offset[c]     <= '0;
                scc_mode[c]   <= '0;
            end
        end else if (cs && cpu_bus.wr && cpu_bus.req && in_8k && ~scc_area) begin
            if (~mapper_reg[id][2] && a == 16'h7FFF) mapper_reg[id] <= cpu_bus.data;
            if (~mapper_reg[id][2] && a == 16'h7FFE) offset[id]     <= cpu_bus.data;
            if (~mr[1]) begin
                if (bank_wr)                   bank[id][page] <= cpu_bus.data;
                if (a[15:1] == 15'h5FFF)       scc_mode[id]   <= cpu_bus.data;    // BFFE, BFFF
            end
        end
    end

    wire  [7:0] bank_eff   = bank[id][page] + offset[id];
    wire [22:0] flash_addr = {mapper_reg[id][7:6], bank_eff, a[12:0]};

    wire [24:0] area_size  = block_info.rom_size < FLASH_SIZE ? block_info.rom_size : FLASH_SIZE;
    wire        backed     = {2'b00, flash_addr} < area_size;

    wire flash_rd = cs && cpu_bus.rd && in_8k && ~scc_area;
    wire flash_wr = cs && cpu_bus.wr && in_8k && ~scc_area && mr[4];

    assign flash_bus.ce            = flash_rd || flash_wr;
    assign flash_bus.we            = flash_wr;
    assign flash_bus.addr          = cs ? flash_addr : '0;
    assign flash_bus.data_to_flash = flash_wr ? cpu_bus.data : '0;
    assign flash_bus.base_addr     = cs ? 27'd0 - block_info.base_ram : '0;
    assign flash_bus.area_lo       = '0;
    assign flash_bus.area_size     = cs ? area_size[23:0] : '0;
    assign flash_bus.chip          = 1'b0;                  // M29W640GB
    assign flash_bus.id            = cs && id;

    assign out.ram_cs  = flash_rd && backed && ~flash_bus.data_valid;
    assign out.addr    = cs ? {4'b0000, flash_addr} : {27{1'b1}};
    assign out.rnw     = 1'b1;
    assign out.data    = flash_rd && flash_bus.data_valid ? flash_bus.data_from_flash : 8'hFF;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;

    assign device_out.en         = cs && in_8k && scc_area && (cpu_bus.rd || cpu_bus.wr);
    assign device_out.mode       = cs ? scc_mode[id][5] : 1'b1;
    assign device_out.param      = 1'b1;                    // SCC+ chip
    assign device_out.we         = cs && cpu_bus.wr && mr[3] && page == 2'd0 && in_8k && ~a[4] && ~scc_area;
    assign device_out.device_ref = 3'd0;

endmodule
