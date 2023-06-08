module msx_slots
(
   input                       clk,
   input                       clk_sdram,
   input                       clk_en,
   input                       reset,
   //input                       rom_eject,
   //input                       cart_changed,
   //output                      need_reset,
   //input                       sram_save,
   //input                       sram_load,
   //output                      msx_type,
   //input MSX::config_cart_t    cart_conf[2],
   //CPU                
   input                [15:0] cpu_addr,
   input                 [7:0] cpu_dout,
   output                [7:0] cpu_din,
   input                       cpu_wr,
   input                       cpu_rd,
   input                       cpu_mreq,
   input                       cpu_iorq,
   input                       cpu_m1,

   output signed        [15:0] sound,
   //IOCTL
   //input                       ioctl_download,
   //input                [15:0] ioctl_index,
   //input                [26:0] ioctl_addr,
   //DDR3
   //output         logic [27:0] ddr3_addr,
   //output                      ddr3_rd,
   //output                      ddr3_wr,
   //input                 [7:0] ddr3_dout,
   //output                [7:0] ddr3_din,
   //input                       ddr3_ready,
   //output                      ddr3_request,
   //SDRAM
   output               [26:0] ram_addr,
   output                [7:0] ram_din,
   input                 [7:0] ram_dout,
   output                      ram_rnw,
   output                      sdram_ce,
   output                      bram_ce,
   //input                       sdram_ready,
   input                 [1:0] sdram_size,
   output               [26:0] flash_addr,
   output                [7:0] flash_din,
   output                      flash_req,
   input                       flash_ready,
   input                       flash_done,
   //output               [24:0] dw_sdram_addr,
   //output                [7:0] dw_sdram_din,
   //output                      dw_sdram_we,
   //input                       dw_sdram_ready,
   
   //output               [24:0] flash_addr,
   //output                [7:0] flash_din,
   //output                      flash_wr,
   //input                       flash_ready,
   //input                       flash_done,

   //KBD LAYOUT
   //output                [9:0] kbd_addr,
   //output                [7:0] kbd_din,
   //output                      kbd_we,
   //output                      kbd_request,
   //SD FDC
   input                       img_mounted,
   input                [31:0] img_size,
   input                       img_readonly,

   output               [31:0] sd_lba,
   output                      sd_rd,
   output                      sd_wr,
   input                       sd_ack,
   input                [13:0] sd_buff_addr,
   input                 [7:0] sd_buff_dout,
   output                [7:0] sd_buff_din,
   input                       sd_buff_wr,

   input                 [1:0] active_slot,
   input  MSX::block_t         slot_layout[64],
   input  MSX::lookup_RAM_t    lookup_RAM[16],
   input  MSX::lookup_RAM_t    lookup_SRAM[4],
   input  MSX::bios_config_t   bios_config,
   input  dev_typ_t            cart_device[2],
  //SD
   output             [7:0] d_to_sd,
   input              [7:0] d_from_sd,
   output                   sd_tx,
   output                   sd_rx,
   output                   debug_FDC_req,
   output                   debug_sd_card,
   output                   debug_erase


   //output                      spi_ss,
   //output                      spi_clk,
   //input                       spi_di,
   //output                      spi_do,
   //output                [2:0] debug_cpu_din_src
);

assign sound = sound_opll + scc_wave;
assign d_to_sd = cpu_dout;
assign debug_FDC_req = FDC_req;

logic [7:0] mapper_slot[4];
wire mapper_en, mapper_rd;
wire [7:0] slot_mapper_dout;

assign mapper_en = (cpu_addr == 16'hFFFF & bios_config.slot_expander_en[active_slot] & mapper_mask[active_slot] & cpu_mreq );
assign mapper_rd =  mapper_en & cpu_rd;
assign slot_mapper_dout  =  mapper_rd ? ~mapper_slot[active_slot] : 8'hFF;
always @(posedge clk) begin
   if (reset) begin
      mapper_slot[0] <= 8'h00;
      mapper_slot[1] <= 8'h00;
      mapper_slot[2] <= 8'h00;
      mapper_slot[3] <= 8'h00;
   end else begin
      if (mapper_en & cpu_wr )
         mapper_slot[active_slot] <= cpu_dout;
   end
end


mapper_typ_t        mapper;
device_typ_t        device;

wire          [1:0] block      = cpu_addr[15:14];
wire          [1:0] subslot    = mapper_slot[active_slot][(3'd2 * block) +:2];
wire          [5:0] layout_id  = {active_slot, subslot, block};
wire          [3:0] ref_ram    = slot_layout[layout_id].ref_ram;
wire          [1:0] offset_ram = slot_layout[layout_id].offset_ram;
wire                cart_num   = slot_layout[layout_id].cart_num;
assign              mapper     = slot_layout[layout_id].mapper;
assign              device     = slot_layout[layout_id].device;
wire         [26:0] base_ram   = lookup_RAM[ref_ram].addr;
wire         [15:0] size       = lookup_RAM[ref_ram].size;  //16kB * size
wire                ram_ro     = lookup_RAM[ref_ram].ro;
wire         [26:0] base_sram  = lookup_SRAM[cart_num ? 2'd3 :2'd2].addr;

assign ram_addr = (sram_cs ? base_sram : base_ram) + mapper_addr;

wire [26:0] mapper_addr = mem_unmaped                 ? 27'hDEAD                    :
                          mapper == MAPPER_NONE       ? 27'(mapper_none_addr)       :
                          mapper == MAPPER_RAM        ? 27'(mapper_ram_addr)        :
                          mapper == MAPPER_LINEAR     ? 27'(mapper_linear_addr)     :
                          mapper == MAPPER_OFFSET     ? 27'(mapper_offset_addr)     :
                          mapper == MAPPER_KONAMI     ? 27'(mapper_konami_addr)     :
                          mapper == MAPPER_KONAMI_SCC ? 27'(mapper_konami_scc_addr) :
                          mapper == MAPPER_FMPAC      ? 27'(fmpac_addr)             :
                          mapper == MAPPER_MFRSD1     ? 27'(mapper_mfrsd1_addr)     :
                          mapper == MAPPER_MFRSD2     ? 27'(mapper_mfrsd2_addr)     :
                          mapper == MAPPER_MFRSD3     ? 27'(mapper_mfrsd3_addr)     :
                          mapper == MAPPER_ASCII8     ? 27'(mapper_ascii8_addr)     :
                          mapper == MAPPER_ASCII16    ? 27'(mapper_ascii16_addr)    :
                                                        27'hDEAD                    ;

assign cpu_din          = mapper_ram_dout                        //IO
                        & mapper_mfrsd2_dout                     //IO
                        & slot_mapper_dout                       //UNMAPPED
                        & mapper_mfrsd3_dout                     //UNMAPPED
                        & fm_pac_dout                            //UNMAPPED
                        & d_to_cpu_FDC                           //UNMAPPED
                        & scc_sound_dout                         //UNMAPPED
                        & flash_dout
                        & (mem_unmaped  ? 8'hFF : ram_dout);

assign sdram_ce = (sdram_size != 2'd0 & ~sram_cs) & cpu_mreq & (cpu_rd | (cpu_wr & ~ram_ro)) & mapper != MAPPER_UNUSED & ~mem_unmaped;
assign bram_ce  = (sdram_size == 2'd0 | sram_cs)  & cpu_mreq & (cpu_rd | (cpu_wr & (~ram_ro | sram_cs))) & mapper != MAPPER_UNUSED & ~mem_unmaped;
assign ram_rnw  = cpu_rd;
assign ram_din  = cpu_dout;

wire mem_unmaped = mapper_konami_unmaped     | 
                   mapper_konami_scc_unmaped |
                   fmpac_mem_unmaped         | 
                   mapper_mfrsd1_unmaped     | 
                   mapper_mfrsd3_unmaped     | 
                   mapper_ascii8_unmaped     | 
                   mapper_ascii16_unmaped    | 
                   mapper_rd                 | 
                   FDC_req                   |
                   flash_rq                  ;
                   
wire [3:0] mapper_mask = mapper_mfrd_mask;
wire sram_cs     = fmpac_sram_cs;

wire debug_tick = mapper_none_addr == 27'(16'h8000) & active_slot == 2'd3 & cpu_mreq;

//MAPPER NONE
wire [26:0] mapper_none_addr = 27'(cpu_addr[13:0]) + (27'(offset_ram) << 14);

//MAPPER LINEAR
wire [26:0] mapper_linear_addr = 27'(cpu_addr[15:0]) & ((27'(size) << 14)-27'd1);

//NONE 
//wire [26:0] mapper_offset_addr  = 27'(cpu_addr) - 27'h2000;
wire [26:0] mapper_offset_addr  = 27'({(cpu_addr[15:14] - offset_ram),cpu_addr[13:0]});
wire mapper_offset_unmaped      = cpu_addr[15:14] < offset_ram; //TODO podm9nit mapperem



wire flash_rq;
wire [7:0] flash_dout;
flash flash 
(
   .clk(clk),
   .clk_sdram(clk_sdram),
   .addr(23'(mapper_mfrsd0_flash_rq ? flash_mfrsd0_addr :
             mapper_mfrsd3_flash_rq ? flash_mfrsd3_addr : 
                                      flash_mfrsd1_addr )),
   .din(cpu_dout),
   .dout(flash_dout),
   .data_valid(flash_rq),
   .we(cpu_mreq & cpu_wr),
   .ce((mapper_mfrsd3_flash_rq | mapper_mfrsd1_flash_rq | mapper_mfrsd0_flash_rq) & |(cart_device[cart_num] & DEV_FLASH)),
   .sdram_addr(flash_addr),
   .sdram_din(flash_din),
   .sdram_req(flash_req),
	.sdram_ready(flash_ready),
   .sdram_done(flash_done),
   .sdram_offset(mfrsd_base_ram[0]),
   .debug_erase(debug_erase)
);


wire [26:0] mfrsd_base_ram[2];
wire [22:0] flash_mfrsd0_addr;
wire        mapper_mfrsd0_flash_rq;
mapper_mfrsd0 mfrsd0
(
   .cs(device == DEVICE_MFRSD0),
   .mfrsd_base_ram(mfrsd_base_ram),
   .flash_addr(flash_mfrsd0_addr),
   .flash_rq(mapper_mfrsd0_flash_rq),
   .*
);

wire  [3:0] mapper_mfrd_mask;
wire [26:0] mapper_mfrsd1_addr;
wire        mapper_mfrsd1_unmaped;
wire  [7:0] mfrsd_configReg; 
wire [22:0] flash_mfrsd1_addr;
wire        mapper_mfrsd1_flash_rq;
wire        mapper_mfrdsd1_sccMode, mapper_mfrdsd1_sccReq;
mapper_mfrsd1 mfrsd1
(
   .slot(active_slot),
   .cs(mapper == MAPPER_MFRSD1), 
   .din(cpu_dout),
   .configReg(mfrsd_configReg),
   .mfrsd_base_ram(mfrsd_base_ram[0]),
   .mapper_mask(mapper_mfrd_mask),
   .mem_addr(mapper_mfrsd1_addr),
   .mem_unmaped(mapper_mfrsd1_unmaped),
   .flash_addr(flash_mfrsd1_addr),
   .flash_rq(mapper_mfrsd1_flash_rq),
   .scc_mode(mapper_mfrdsd1_sccMode),
   .scc_req(mapper_mfrdsd1_sccReq),
   .*
);

wire [21:0] mapper_mfrsd2_addr;
wire  [7:0] mapper_mfrsd2_dout;
mapper_mfrsd2 mfrsd2
(
   .mapper_dout(mapper_mfrsd2_dout),
   .mem_addr(mapper_mfrsd2_addr),
   .en(|(cart_device[cart_num] & DEV_MFRSD2)),
   .*
);

wire [26:0] mapper_mfrsd3_addr;
wire [22:0] flash_mfrsd3_addr;
wire        mapper_mfrsd3_unmaped, mfrsd3_oe;
wire  [7:0] mapper_mfrsd3_dout;
wire        mapper_mfrsd3_flash_rq;
mapper_mfrsd3 mfrsd3
(
   .cs(mapper == MAPPER_MFRSD3), 
   .din(cpu_dout),
   .mem_addr(mapper_mfrsd3_addr),
   .flash_addr(flash_mfrsd3_addr),
   .mem_unmaped(mapper_mfrsd3_unmaped),
   .sd_tx(sd_tx),
   .sd_rx(sd_rx),
   .d_from_sd(d_from_sd),
   .mfrsd_base_ram(mfrsd_base_ram[0]),
   .configReg(mfrsd_configReg),
   .mapper_dout(mapper_mfrsd3_dout),
   .flash_rq(mapper_mfrsd3_flash_rq),
   .debug_sd_card(debug_sd_card),
   .*
);


//MAPPER MSX RAM
wire [21:0] mapper_ram_addr;
wire  [7:0] mapper_ram_dout;
msx2_ram_mapper msx2_ram_mapper
(
   .en(bios_config.MSX_typ == MSX2),
   .ram_block_count(bios_config.ram_size),
   .mapper_dout(mapper_ram_dout),
   .mapper_addr(mapper_ram_addr),
   .*
);

wire [24:0] mapper_konami_addr;
wire        mapper_konami_unmaped;
cart_konami konami
(
   .rom_size(25'(size) << 14),
   .din(cpu_dout),
   .cs(mapper == MAPPER_KONAMI),
   .mem_unmaped(mapper_konami_unmaped),
   .mem_addr(mapper_konami_addr),
   .*
);

wire [24:0] mapper_ascii8_addr;
wire        mapper_ascii8_unmaped;
cart_ascii8 ascii8
(
   .rom_size(25'(size) << 14),
   .cpu_addr(cpu_addr),
   .din(cpu_dout),
   .cs(mapper == MAPPER_ASCII8),
   .mem_unmaped(mapper_ascii8_unmaped),
   .mem_addr(mapper_ascii8_addr),
   .*
);

wire [24:0] mapper_ascii16_addr;
wire        mapper_ascii16_unmaped;
cart_ascii16 ascii16
(
   .rom_size(25'(size) << 14),
   .din(cpu_dout),
   .cs(mapper == MAPPER_ASCII16),
   .mem_unmaped(mapper_ascii16_unmaped),
   .mem_addr(mapper_ascii16_addr),
   .*
);

wire [20:0] mapper_konami_scc_addr;
wire        mapper_konami_scc_unmaped;
wire        mapper_konami_scc_sccReq;
wire  [1:0] mapper_konami_scc_sccMode;
cart_konami_scc konami_scc
(
   .mem_size(25'(size) << 14),
   .din(cpu_dout),
   .cs(mapper == MAPPER_KONAMI_SCC),
   .mem_unmaped(mapper_konami_scc_unmaped),
   .mem_addr(mapper_konami_scc_addr), 
   .sccDevice(|(cart_device[cart_num] & DEV_SCC2)) ,
   .scc_req(mapper_konami_scc_sccReq),
   .scc_mode(mapper_konami_scc_sccMode),
   .*
);

wire        [7:0] scc_sound_dout;
wire signed [15:0] scc_wave;
scc_sound scc_sound
(
   .cs(mapper_konami_scc_sccReq | mapper_mfrdsd1_sccReq),  
   .cpu_addr(cpu_addr[7:0]),
   .din(cpu_dout),
   .scc_dout(scc_sound_dout),
   .oe({|(cart_device[1] & (DEV_SCC | DEV_SCC2)), |(cart_device[0] & (DEV_SCC | DEV_SCC2))}),
   .wave(scc_wave),
   .sccPlusChip({|(cart_device[1] & DEV_SCC2), |(cart_device[0] & DEV_SCC2)}),
   .sccPlusMode(mapper_mfrdsd1_sccReq ? {1'b0,mapper_mfrdsd1_sccMode} : mapper_konami_scc_sccMode),
   .*
);

wire  [7:0] fm_pac_dout;
wire [24:0] fmpac_addr;
wire        fmpac_req, fmpac_mem_unmaped, fmpac_sram_cs, fmpac_sram_wr;
wire  [1:0] fmpac_opll_io_enable, fmpac_opll_wr; 
cart_fm_pac fm_pac
(
   .din(cpu_dout),
   .mapper_dout(fm_pac_dout),  
   .cs(mapper == MAPPER_FMPAC),
   .sram_we(fmpac_sram_wr),
   .sram_cs(fmpac_sram_cs),
   .mem_unmaped(fmpac_mem_unmaped),
   .mem_addr(fmpac_addr),
   .opll_wr(fmpac_opll_wr),
   .opll_io_enable(fmpac_opll_io_enable),
   .*
);

wire opll_io_wr  = cpu_addr[7:1] == 7'b0111110 & cpu_iorq & ~cpu_m1 & cpu_wr; //7C - 7D
wire signed [15:0] sound_OPL_int, sound_OPL_EXT[2];
wire signed [15:0] sound_opll;
opll opll
(
   .rst(reset),
   .clk(clk),
   .cen(clk_en),
   .din(cpu_dout),
   .addr(cpu_addr[0]),
   .wr({1'b0, (opll_io_wr & fmpac_opll_io_enable[1]) | fmpac_opll_wr[1] , (opll_io_wr & fmpac_opll_io_enable[0]) | fmpac_opll_wr[0]}),
   .cs({1'b0, |(cart_device[1] & DEV_OPL3), |(cart_device[0] & DEV_OPL3)}),
   .sound(sound_opll)
);



wire        FDC_req;
wire  [7:0] d_to_cpu_FDC;
fdc fdc
(
   .clk(clk),
   .reset(reset),
   .clk_en(clk_en),
   .cs(device == DEVICE_FDC),
   .addr(cpu_addr[13:0]),
   .d_from_cpu(cpu_dout),
   .d_to_cpu(d_to_cpu_FDC),
   .output_en(FDC_req),
   .rd(cpu_rd & cpu_mreq),
   .wr(cpu_wr & cpu_mreq),
   .img_mounted(img_mounted),
   .img_size(img_size),
   .img_readonly(img_readonly),
   
   .sd_lba(sd_lba),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr[8:0]),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din),
   .sd_buff_wr(sd_buff_wr)
);

endmodule
