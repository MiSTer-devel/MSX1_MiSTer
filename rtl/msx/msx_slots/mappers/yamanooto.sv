// Yamanooto mapper
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
// As openMSX Yamanooto.cc. 8 MB flash (S29GL064N, here the S29GL064S of flash.sv), SCC/SCC+;
// the PSG at 10h-11h is a device of the block, ECHO (also A0h-A1h) goes out as psg_echo.
// 0000-3FFF mirrors 8000-BFFF, C000-FFFF mirrors 4000-7FFF; the registers are not mirrored.
//   7FFF ENAR (always writable): 0 REGEN (7FFC-7FFE writable, 7FFC-7FFF readable), 4 WREN
//   7FFE OFFR, added to a bank when it is written: bank = data + {OFFR, CFGR[5:4]} (10 bit)
//   7FFD CFGR: 0 MDIS, 1 ECHO, 2 ROMDIS, 3 Konami4 (no SCC), 5-4 SUBOFF, 6 FPGA_EN
//   7FFC FPGA register (ID read sequence)
// With WREN every write goes to the flash and nothing else. A register write takes effect for
// the rest of the same write (bank, flash).
module mapper_yamanooto (
    cpu_bus_if.device_mp     cpu_bus,
    flash_bus_if.device_mp   flash_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out,
    output MSX::device_bus_t device_out,     // SCC (en, mode)
    output                   psg_echo        // PSG of the cartridge also on A0h-A1h
);

    localparam logic [24:0] FLASH_SIZE = 25'h0800000;

    wire        cs   = block_info.typ == MAPPER_YAMANOOTO && cpu_bus.mreq;
    wire        id   = block_info.id;
    wire [15:0] a    = cpu_bus.addr;
    wire [15:0] am   = {~a[14], a[14:0]};                   // the mirrors folded onto 4000-BFFF
    wire  [1:0] page = {am[15], am[13]};
    wire        regs = a[15:2] == 14'h1FFF;                 // 7FFC-7FFF, not mirrored

    logic [7:0] enable_reg[2], offset_reg[2], config_reg[2], scc_mode[2];
    logic [9:0] bank[2][4];
    logic [7:0] raw[2][4];                                  // bank as written (SCC enable)
    logic [2:0] fpga_fsm[2];

    // register values as this write leaves them
    wire        wr      = cs && cpu_bus.wr;
    wire        regen   = enable_reg[id][0];
    wire  [7:0] en_new  = wr && a == 16'h7FFF          ? cpu_bus.data : enable_reg[id];
    wire  [7:0] cfg_new = wr && a == 16'h7FFD && regen ? cpu_bus.data : config_reg[id];
    wire  [7:0] off_new = wr && a == 16'h7FFE && regen ? cpu_bus.data : offset_reg[id];
    wire  [9:0] bank_wr = {2'b00, cpu_bus.data} + {off_new, cfg_new[5:4]};

    wire scc_area = ~config_reg[id][3] &&
                    (scc_mode[id][5] ? raw[id][3][7]         && am[15:11] == 5'b10111 && am[10:1] != 10'h3FF
                                     : raw[id][2][5:0] == '1 && am[15:11] == 5'b10011);

    wire k4_wr  = cfg_new[3] && ~cfg_new[0] && am[15:13] != 3'b010;      // 6000-BFFF
    wire scc_wr = ~cfg_new[3] && ~cfg_new[0] && am[12:11] == 2'b10;      // x000-x7FF of 5/7/9/B

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            for (int c = 0; c < 2; c++) begin
                enable_reg[c] <= '0;
                offset_reg[c] <= '0;
                config_reg[c] <= '0;
                scc_mode[c]   <= '0;
                fpga_fsm[c]   <= '0;
                bank[c]       <= '{10'd0, 10'd1, 10'd2, 10'd3};
                raw[c]        <= '{8'd0, 8'd1, 8'd2, 8'd3};
            end
        end else if (wr && cpu_bus.req) begin
            enable_reg[id] <= en_new;
            config_reg[id] <= cfg_new;
            offset_reg[id] <= off_new;
            if (a == 16'h7FFC && regen && config_reg[id][6])
                case (fpga_fsm[id])
                    3'd0:    if (cpu_bus.data == 8'h9F) fpga_fsm[id] <= 3'd1;
                    3'd4:    fpga_fsm[id] <= 3'd0;
                    default: fpga_fsm[id] <= fpga_fsm[id] + 3'd1;
                endcase
            if (~en_new[4]) begin
                if (k4_wr || scc_wr) begin
                    bank[id][page] <= bank_wr;
                    raw[id][page]  <= cpu_bus.data;
                end
                if (~cfg_new[3] && am[15:1] == 15'h5FFF) scc_mode[id] <= cpu_bus.data;   // BFFE, BFFF
            end
        end
    end

    // registers read back
    logic [7:0] reg_q;
    always_comb begin
        case (a[1:0])
            2'd0:    case (fpga_fsm[id])
                         3'd1:    reg_q = 8'h1F;
                         3'd2:    reg_q = 8'h23;
                         3'd3,
                         3'd4:    reg_q = 8'h00;
                         default: reg_q = 8'hFF;
                     endcase
            2'd1:    reg_q = config_reg[id] | 8'h80;        // FPGA ready
            2'd2:    reg_q = offset_reg[id];
            default: reg_q = enable_reg[id];
        endcase
        if (a[1:0] == 2'd0 && ~config_reg[id][6]) reg_q = 8'hFF;
    end

    wire [22:0] flash_addr = {bank[id][page], am[12:0]};
    wire [24:0] area_size  = block_info.rom_size < FLASH_SIZE ? block_info.rom_size : FLASH_SIZE;
    wire        backed     = {2'b00, flash_addr} < area_size;

    wire reg_rd   = cs && cpu_bus.rd && regs && regen;
    wire flash_rd = cs && cpu_bus.rd && ~reg_rd && ~scc_area && ~config_reg[id][2];
    wire flash_wr = wr && en_new[4] && ~cfg_new[2];

    assign flash_bus.ce            = flash_rd || flash_wr;
    assign flash_bus.we            = flash_wr;
    assign flash_bus.addr          = cs ? flash_addr : '0;
    assign flash_bus.data_to_flash = flash_wr ? cpu_bus.data : '0;
    assign flash_bus.base_addr     = cs ? 27'd0 - block_info.base_ram : '0;
    assign flash_bus.area_lo       = '0;
    assign flash_bus.area_size     = cs ? area_size[23:0] : '0;
    assign flash_bus.chip          = cs;                    // S29GL064
    assign flash_bus.id            = cs && id;

    assign out.ram_cs  = flash_rd && backed && ~flash_bus.data_valid;
    assign out.addr    = cs ? {4'b0000, flash_addr} : {27{1'b1}};
    assign out.rnw     = 1'b1;
    assign out.data    = reg_rd                             ? reg_q                     :
                         flash_rd && flash_bus.data_valid ? flash_bus.data_from_flash : 8'hFF;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;

    // the SCC sees the access unless the register read or WREN takes it
    assign device_out.en         = cs && scc_area && ((cpu_bus.rd && ~reg_rd) || (cpu_bus.wr && ~en_new[4]));
    assign device_out.mode       = cs ? scc_mode[id][5] : 1'b1;
    assign device_out.param      = 1'b1;                    // SCC+ chip
    assign device_out.we         = 1'b0;
    assign device_out.device_ref = 3'd0;

    assign psg_echo = config_reg[0][1] | config_reg[1][1];

endmodule
