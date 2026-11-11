// msx_config
//
// Copyright (c) 2023-2026 Molekula
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

// Generic cartridge slots are hidden for OCM (H3), which has its own slot options (MSX_MiSTer).
// An FDC cartridge only in slot A (MSX::N_FDC).
parameter CONF_STR_SLOT_A = {
    "H3O[20:17],Slot1,ROM,FDC,SCC,SCC+,FM-PAC,MegaSCC+ 1MB, MegaFlashROM SCC+ SD,GameMaster2,Empty,MoonSound;"
};
parameter CONF_STR_SLOT_B = {
    "H3O[32:29],Slot2,ROM,SCC,SCC+,FM-PAC,MegaSCC+ 2MB,MegaRAM ASCII-8K 1MB,MegaRAM ASCII-16K 2MB,Empty,MoonSound;"
};
parameter CONF_STR_OCM_SLOTS = {
    "h3O[22],Slot1,Empty,MegaSCC+ 1MB;",
    "h3O[24:23],Slot2,Empty,MegaSCC+ 2MB,MegaRAM ASCII-8K 1MB,MegaRAM ASCII-16K 2MB;"
};

module user_config
(
    input                     clk,
    input                     reset,
    input              [63:0] HPS_status,
    input               [1:0] sdram_size,
    output MSX::config_cart_t cart_conf[2],
    output                    ROM_A_load_hide, //3 
    output                    ROM_B_load_hide, //4
    output MSX::user_config_t msx_user_config,
    output                    reload,
    input                     ocmMode
);

wire [3:0] slot_A_select   = HPS_status[20:17];
wire [3:0] slot_B_select   = HPS_status[32:29];

    cart_typ_t cart_A;
    always_comb begin : Slot1
        case(slot_A_select)
            4'd0: cart_conf[0].typ = CART_TYP_ROM;
            4'd1: cart_conf[0].typ = CART_TYP_FDC;
            4'd2: cart_conf[0].typ = CART_TYP_SCC;
            4'd3: cart_conf[0].typ = CART_TYP_SCC2;
            4'd4: cart_conf[0].typ = CART_TYP_FM_PAC;
            4'd5: cart_conf[0].typ = CART_MEGASCC1;
            4'd6: cart_conf[0].typ = CART_TYP_MFRSD;
            4'd7: cart_conf[0].typ = CART_TYP_GM2;
            4'd9: cart_conf[0].typ = CART_TYP_MOONSOUND;
            default: cart_conf[0].typ = CART_TYP_EMPTY;
        endcase
    end

    cart_typ_t cart_B;
    always_comb begin : Slot2
        case(slot_B_select)
            4'd0: cart_conf[1].typ = CART_TYP_ROM;
            4'd1: cart_conf[1].typ = CART_TYP_SCC;
            4'd2: cart_conf[1].typ = CART_TYP_SCC2;
            4'd3: cart_conf[1].typ = CART_TYP_FM_PAC;
            4'd4: cart_conf[1].typ = CART_MEGASCC2;
            4'd5: cart_conf[1].typ = CART_MEGA_ASCII_8;
            4'd6: cart_conf[1].typ = CART_MEGA_ASCII_16;
            4'd8: cart_conf[1].typ = CART_TYP_MOONSOUND;
            default: cart_conf[1].typ = CART_TYP_EMPTY;
        endcase
    end
    

assign msx_user_config.cas_audio_src         = cas_audio_src_t'(HPS_status[40]);
assign msx_user_config.border                = HPS_status[41];
assign msx_user_config.joy_swap              = HPS_status[13];
assign msx_user_config.mouse_port            = HPS_status[14];


// OCM DIP-SW as MSX_MiSTer pDip: 7 MegaSD on, 6 mapper 4096 kB, 5:4 slot 2 option
// (Slot2Mode = {bit 4, bit 5}), 3 slot 1 option, 2:1 display (11), 0 turbo
assign msx_user_config.ocm_dip  = {1'b1, HPS_status[11], HPS_status[24:23], HPS_status[22], 2'b11, HPS_status[15]};
assign msx_user_config.ocm_r800 = ocmMode && HPS_status[16];
assign msx_user_config.turbor_firmware = HPS_status[26];

assign ROM_A_load_hide    = cart_conf[0].typ != CART_TYP_ROM;
assign ROM_B_load_hide    = cart_conf[1].typ != CART_TYP_ROM;

logic  [7:0] lastConfig;
wire [7:0] act_config = {cart_conf[1].typ, cart_conf[0].typ};

always_ff @(posedge clk) begin
    if (reload) lastConfig <= act_config;
end

assign reload = ~reset & lastConfig != act_config;

endmodule
