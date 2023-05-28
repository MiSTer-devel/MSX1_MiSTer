parameter CONF_STR_SLOT_A = {
    "h2O[19:17],SLOT A,ROM,SCC,SCC+,FM-PAC,MegaFlashROM SCC+ SD,GameMaster2,FDC,Empty;",
    "H2O[19:17],SLOT A,ROM,SCC,SCC+,FM-PAC,MegaFlashROM SCC+ SD,GameMaster2,Empty;"
};
parameter CONF_STR_SLOT_B = {
    "O[31:29],SLOT B,ROM,SCC,SCC+,FM-PAC,Empty;"
};
parameter CONF_STR_MAPPER_A = {
    "H3O[23:20],Mapper type,auto,none,ASCII8,ASCII16,Konami,KonamiSCC,KOEI,linear64,R-TYPE,WIZARDRY;"
};
parameter CONF_STR_MAPPER_B = {
    "H4O[35:32],Mapper type,auto,none,ASCII8,ASCII16,Konami,KonamiSCC,KOEI,linear64,R-TYPE,WIZARDRY;"
};
parameter CONF_STR_SRAM_SIZE_A = {
    "H7H5O[28:26],SRAM size,auto,1kB,2kB,4kB,8kB,16kB,32kB,none;",
    "h7H5O[28:26],SRAM size,auto,1kB,2kB,4kB,8kB,none;"
};
parameter CONF_STR_RAM_SIZE = {
    "H7H2P2O[16:15],RAM Size,128kB,64kB,512kB,256kB;"
};

module msx_config
(
    input                     clk,
    input                     reset,
    input MSX_typ_t           msx_type,
    input              [63:0] HPS_status,
    input                     scandoubler,
    input               [5:0] mapper_detected[2],
    input               [2:0] sram_size_detected[2],
    input               [1:0] sdram_size,

    output MSX::config_cart_t cart_conf[2],
    
    //output         [2:0] cart_type[2],
    output              [2:0] sram_size[2],
    //output         [2:0] sram_B_size,
    //output         [5:0] mapper_A,
    //output         [5:0] mapper_B,
    output                    sram_A_select_hide,
    output                    sram_loadsave_hide,
    output                    ROM_A_load_hide,
    output                    ROM_B_load_hide, //4
    output                    fdc_enabled,
    output MSX::user_config_t msxConfig,
    output                    reset_request,
    output                    cart_changed
    //output         [1:0] rom_eject
);
/*verilator tracing_off*/
cart_typ_t   cart_typ_A, cart_typ_B;
mapper_typ_t selected_mapper_A, selected_mapper_B;
logic  [7:0] selected_sram_size_A;

wire [2:0] slot_A_select   = HPS_status[19:17];
wire [2:0] slot_B_select   = HPS_status[31:29];
wire [2:0] sram_A_select   = HPS_status[28:26];
wire [3:0] mapper_A_select = HPS_status[23:20];
wire [3:0] mapper_B_select = HPS_status[35:32]; 

assign cart_conf[0].typ     = cart_typ_t'(slot_A_select < CART_TYP_FDC  ? slot_A_select   :
                              msx_type == MSX2                          ? CART_TYP_EMPTY  :
                              slot_A_select == CART_TYP_FDC             ? CART_TYP_FDC    :
                                                                          CART_TYP_EMPTY );

assign cart_conf[1].typ     = slot_B_select < CART_TYP_MFRSD ? cart_typ_t'(slot_B_select) : CART_TYP_EMPTY;
// 0-auto 1-ASCII8 2-ASCII16 3-Konami 4-KonamiSCC 5-KOEI 6-linear64 7-R-TYPE 8-WIZARDRY 9-none
//{MAPPER_AUTO, MAPPER_NONE, MAPPER_LINEAR, MAPPER_OFFSET, MAPPER_KONAMI_SCC, MAPPER_KONAMI, MAPPER_ASCII8, MAPPER_ASCII16, MAPPER_FMPAC, MAPPER_MFRSD1,MAPPER_MFRSD2, MAPPER_MFRSD3, MAPPER_UNUSED, MAPPER_RAM} mapper_typ_t;

assign cart_conf[0].selected_mapper    = mapper_typ_t'(mapper_A_select + 4'd2);
assign cart_conf[1].selected_mapper    = mapper_typ_t'(mapper_B_select + 4'd2);
assign cart_conf[0].selected_sram_size = sram_A_select_hide ? 8'd0 : 8'd0; // TODO dopočti
assign cart_conf[1].selected_sram_size = 8'd0;

//assign MSXconf.typ = MSX_typ_t'(HPS_status[11]);
assign msxConfig.typ = msx_type;
assign msxConfig.scandoubler = scandoubler;
assign msxConfig.video_mode = video_mode_t'(msx_type == MSX1 ? (HPS_status[12] ? 2'd2 : 2'd1) : HPS_status[14:13]);
assign msxConfig.cas_audio_src = cas_audio_src_t'(HPS_status[8]);
//assign msxConfig.ram_size = sdram_size == 2'd0 ? SIZE64 : ram_size_t'(HPS_status[16:15]);
assign msxConfig.border = HPS_status[38];

assign sram_loadsave_hide = sram_size[0] == 0 & sram_size[1] == 0;
assign ROM_A_load_hide    = cart_typ_A != CART_TYP_ROM;
assign ROM_B_load_hide    = cart_typ_B != CART_TYP_ROM;
assign sram_A_select_hide = cart_typ_A != CART_TYP_ROM | mapper_A_select == 4'd0; 
assign fdc_enabled = msx_type == MSX2 | cart_typ_A == CART_TYP_FDC;


reg  [16:0] lastConfig;
reg  [5:0]  last_cart_type;

wire [16:0] act_config = {cart_typ_B, cart_typ_A, mapper_A_select, mapper_B_select, sram_A_select};
wire [5:0]  act_cart_type = {cart_typ_B, cart_typ_A};

always @(posedge clk) begin
    if (reset) lastConfig <= act_config;
    last_cart_type <= act_cart_type;
end

assign reset_request = lastConfig != act_config;
assign cart_changed = last_cart_type[5:0] != act_cart_type[5:0];
//assign rom_eject = {cart_conf[1].typ == CART_TYP_ROM ? HPS_status[10] : 1'b0, cart_conf[0].typ == CART_TYP_ROM ? HPS_status[10] : 1'b0};

/*
cart_conf conf_A
(
   .typ(cart_typ_A),
   .selected_mapper(selected_mapper_A),
   .selected_sram_size(selected_sram_size_A),
   .config_cart(cart_conf[0])
);

cart_conf conf_B
(
   .typ(cart_typ_B),
   .selected_mapper(selected_mapper_B),
   .selected_sram_size(8'd0),
   .config_cart(cart_conf[1])
); */

endmodule
/*
module cart_conf
(
   input  cart_typ_t         typ,
   input  mapper_typ_t       selected_mapper,
   input  logic [       7:0] selected_sram_size,
   output MSX::config_cart_t config_cart
   
);


assign                           {config_cart.mapper, config_cart.mem_device, config_cart.io_device, config_cart.rom_id, config_cart.mode, config_cart.param, config_cart.sram_size} = 
      typ == CART_TYP_ROM      ? {selected_mapper   , DEVICE_NONE           , DEVICE_NONE          , ROM_ROM           , 8'hAA           , 8'b11100100      , selected_sram_size } :
      typ == CART_TYP_SCC      ? {MAPPER_UNUSED     , DEVICE_NONE           , DEVICE_NONE          , ROM_NONE          , 8'h00           , 8'h00            , 8'd0               } :
      typ == CART_TYP_SCC2     ? {MAPPER_UNUSED     , DEVICE_NONE           , DEVICE_NONE          , ROM_NONE          , 8'h00           , 8'h00            , 8'd0               } :
      typ == CART_TYP_FM_PAC   ? {MAPPER_FMPAC      , DEVICE_NONE           , DEVICE_OPL3          , ROM_FMPAC         , 8'h08           , 8'h00            , 8'd8               } : //4000 - 7FFF
      typ == CART_TYP_MFRSD    ? {MAPPER_UNUSED     , DEVICE_NONE           , DEVICE_NONE          , ROM_NONE          , 8'h00           , 8'h00            , 8'd0               } :
      typ == CART_TYP_GM2      ? {MAPPER_UNUSED     , DEVICE_NONE           , DEVICE_NONE          , ROM_NONE          , 8'h00           , 8'h00            , 8'd8               } :
      typ == CART_TYP_FDC      ? {MAPPER_NONE       , DEVICE_FDC            , DEVICE_NONE          , ROM_FDC           , 8'h08           , 8'h00            , 8'd0               } :
      typ == CART_TYP_EMPTY      {MAPPER_UNUSED     , DEVICE_NONE           , DEVICE_NONE          , ROM_NONE          , 8'h00           , 8'h00            , 8'd0               } ;
         
endmodule */
