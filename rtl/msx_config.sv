parameter CONF_STR_SLOT_A = {
    "O[20:17],Slot1,ROM,FDC,SCC,SCC+,FM-PAC,MegaSCC+ 1MB, MegaFlashROM SCC+ SD,GameMaster2,Empty;"
};
parameter CONF_STR_SLOT_B = {
    "O[32:29],Slot2,ROM,FDC,SCC,SCC+,FM-PAC,MegaSCC+ 2MB,MegaRAM ASCII-8K 1MB,MegaRAM ASCII-16K 2MB,Empty;"
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
            4'd5: cart_conf[0].typ = ocmMode ? MEGARAM : CART_MEGASCC1;
            4'd6: cart_conf[0].typ = CART_TYP_MFRSD;
            4'd7: cart_conf[0].typ = CART_TYP_GM2;
            default: cart_conf[0].typ = CART_TYP_EMPTY;
        endcase
    end

    cart_typ_t cart_B;
    always_comb begin : Slot2
        case(slot_B_select)
            4'd0: cart_conf[1].typ = CART_TYP_ROM;
            4'd1: cart_conf[1].typ = CART_TYP_FDC;
            4'd2: cart_conf[1].typ = CART_TYP_SCC;
            4'd3: cart_conf[1].typ = CART_TYP_SCC2;
            4'd4: cart_conf[1].typ = CART_TYP_FM_PAC;
            4'd5: cart_conf[1].typ = ocmMode ? MEGARAM : CART_MEGASCC2;
            4'd6: cart_conf[1].typ = ocmMode ? MEGARAM : CART_MEGA_ASCII_8;
            4'd7: cart_conf[1].typ = ocmMode ? MEGARAM : CART_MEGA_ASCII_16;
            default: cart_conf[1].typ = CART_TYP_EMPTY;
        endcase
    end
    
    logic       ocm_slot1;
    logic [1:0] ocm_slot2;
    
    assign      ocm_slot1 = HPS_status[20:17] == 4'd5;     // MegaSCC+ 1MB (CONF_STR_SLOT_A)
    
    always_comb begin : Slot2_OCM
        case (HPS_status[32:29])
            4'd5:    ocm_slot2 = 2'b10;     // MegaSCC+ 2MB
            4'd6:    ocm_slot2 = 2'b01;     // MegaRAM ASCII-8K 1MB
            4'd7:    ocm_slot2 = 2'b11;     // MegaRAM ASCII-16K 2MB
            default: ocm_slot2 = 2'b00;
        endcase
    end

assign msx_user_config.cas_audio_src         = cas_audio_src_t'(HPS_status[40]);
assign msx_user_config.border                = HPS_status[41];


// OCM DIP-SW (as MSX_MiSTer ff_dip_req): 7 MegaSD on, 6 mapper 4096 kB, 5:4 slot 2
// (OCM reads Slot2Mode = {bit 4, bit 5}), 3 slot 1, 2:1 display (11), 0 turbo
assign msx_user_config.ocm_dip  = {1'b1, HPS_status[11], ocm_slot2[0], ocm_slot2[1], ocm_slot1, 2'b11, HPS_status[15]};

assign ROM_A_load_hide    = cart_conf[0].typ != CART_TYP_ROM;
assign ROM_B_load_hide    = cart_conf[1].typ != CART_TYP_ROM;

logic  [7:0] lastConfig;
wire [7:0] act_config = {cart_conf[1].typ, cart_conf[0].typ};

always_ff @(posedge clk) begin
    if (reload) lastConfig <= act_config;
end

assign reload = ~reset & lastConfig != act_config;

endmodule
