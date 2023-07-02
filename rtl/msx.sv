module msx
(
   input                    reset,
   //Clock
   input                    clk21m,
   input                    ce_10m7_p,
   input                    ce_3m58_p,
   input                    ce_3m58_n,
   input                    ce_5m39_n,
   input                    ce_10hz,
   input                    clk_sdram,
   //Video
   output             [7:0] R,
   output             [7:0] G,
   output             [7:0] B,
   output                   DE,
   output                   HS,
   output                   VS,
   output                   hblank,
   output                   vblank,
   output                   ce_pix,
   //I/O
   output            [15:0] audio,
   input  [           10:0] ps2_key,
   input              [5:0] joy0,
   input              [5:0] joy1,
   //Cassete
   output                   cas_motor,
   input                    cas_audio_in,
   //MSX config
   input             [64:0] rtc_time,
   input MSX::bios_config_t bios_config,
   input MSX::user_config_t msxConfig,
   input  dev_typ_t         cart_device[2],
   input  dev_typ_t         msx_device,
   input              [3:0] msx_dev_ref_ram[8],
   input  mapper_typ_t      selected_mapper[2],
   input                    sram_save,
   input                    sram_load,
   //IOCTL
   input                    ioctl_download,
   input             [15:0] ioctl_index,
   input             [26:0] ioctl_addr,
   //SDRAM/BRAM
   output            [26:0] ram_addr,
   output             [7:0] ram_din,
   output                   ram_rnw,
   output                   sdram_ce,
   output                   bram_ce,
   input              [7:0] ram_dout,
   input              [1:0] sdram_size,
   input MSX::block_t       slot_layout[64],
   input MSX::lookup_RAM_t  lookup_RAM[16],
   input MSX::lookup_SRAM_t lookup_SRAM[4],
   //KBD
   input                    kbd_request,
   input              [8:0] kbd_addr,
   input              [7:0] kbd_din,
   input                    kbd_we,
   output            [26:0] flash_addr,
   output             [7:0] flash_din,
   output                   flash_req,
   input                    flash_ready,
   input                    flash_done,
   //SD FDC
   input                    img_mounted,
   input             [31:0] img_size,
   input                    img_readonly,
   output            [31:0] sd_lba,
   output                   sd_rd,
   output                   sd_wr,
   input                    sd_ack,
   input             [13:0] sd_buff_addr,
   input              [7:0] sd_buff_dout,
   output             [7:0] sd_buff_din,
   input                    sd_buff_wr,
   output             [7:0] d_to_sd,
   input              [7:0] d_from_sd,
   output                   sd_tx,
   output                   sd_rx
);

//  -----------------------------------------------------------------------------
//  -- Audio MIX
//  -----------------------------------------------------------------------------
wire  [9:0] audioPSG    = ay_ch_mix + {keybeep,5'b00000} + {(cas_audio_in & ~cas_motor),4'b0000};
wire [16:0] fm          = {3'b00, audioPSG, 4'b0000};
wire [16:0] audio_mix   = {cart_sound[15], cart_sound} + fm;
wire [15:0] compr[7:0]  = '{ {1'b1, audio_mix[13:0], 1'b0}, 16'h8000, 16'h8000, 16'h8000, 16'h7FFF, 16'h7FFF, 16'h7FFF,  {1'b0, audio_mix[13:0], 1'b0}};
assign audio            = compr[audio_mix[16:14]];

//  -----------------------------------------------------------------------------
//  -- T80 CPU
//  -----------------------------------------------------------------------------
wire [15:0] a;
wire [7:0] d_to_cpu, d_from_cpu;
wire mreq_n, wr_n, m1_n, iorq_n, rd_n, rfrsh_n;
t80pa #(.Mode(0)) T80
(
   .RESET_n(~reset),
   .CLK(clk21m),
   .CEN_p(ce_3m58_p),
   .CEN_n(ce_3m58_n),
   .WAIT_n(wait_n),
   .INT_n(vdp_int_n),
   .NMI_n(1),
   .BUSRQ_n(1),
   .M1_n(m1_n),
   .MREQ_n(mreq_n),
   .IORQ_n(iorq_n),
   .RD_n(rd_n),
   .WR_n(wr_n),
   .RFSH_n(rfrsh_n),
   .HALT_n(1),
   .BUSAK_n(),
   .A(a),
   .DI(d_to_cpu),
   .DO(d_from_cpu)
);

//  -----------------------------------------------------------------------------
//  -- WAIT CPU
//  -----------------------------------------------------------------------------
wire exwait_n = 1;

logic wait_n = 1'b0;
always @(posedge clk21m, negedge exwait_n, negedge u1_2_q) begin
   if (~exwait_n)
      wait_n <= 1'b0;
   else if (~u1_2_q)
      wait_n <= 1'b1;
   else if (ce_3m58_p)
      wait_n <= m1_n;
end

logic u1_2_q = 1'b0;
always @(posedge clk21m, negedge exwait_n) begin
   if (~exwait_n)
      u1_2_q <= 1'b1;
   else if (ce_3m58_p)
      u1_2_q <= wait_n;
end

logic map_valid = 0;
wire ppi_en = ~ppi_n;
wire [1:0] slot;

always @(posedge reset, posedge clk21m) begin
    if (reset)
        map_valid = 0;
    else if (ppi_en)
        map_valid = 1;
end

assign slot =    ~map_valid         ? 2'b00         :
                  a[15:14] == 2'b00 ? ppi_out_a[1:0] :
                  a[15:14] == 2'b01 ? ppi_out_a[3:2] :
                  a[15:14] == 2'b10 ? ppi_out_a[5:4] :
                                      ppi_out_a[7:6] ;

//  -----------------------------------------------------------------------------
//  -- IO Decoder
//  -----------------------------------------------------------------------------
wire psg_n  = ~((a[7:3] == 5'b10100)   & ~iorq_n & m1_n);
wire ppi_n  = ~((a[7:3] == 5'b10101)   & ~iorq_n & m1_n);
wire vdp_en =   (a[7:3] == 5'b10011)   & ~iorq_n & m1_n ;
wire rtc_en =   (a[7:1] == 7'b1011010) & ~iorq_n & m1_n & bios_config.MSX_typ == MSX2;

//  -----------------------------------------------------------------------------
//  -- 82C55 PPI
//  -----------------------------------------------------------------------------
wire [7:0] d_from_8255;
wire [7:0] ppi_out_a, ppi_out_c;
wire keybeep = ppi_out_c[7];
assign cas_motor =  ppi_out_c[4];
jt8255 PPI
(
   .rst(reset),
   .clk(clk21m),
   .addr(a[1:0]),
   .din(d_from_cpu),
   .dout(d_from_8255),
   .rdn(rd_n),
   .wrn(wr_n),
   .csn(ppi_n),
   .porta_din(8'h0),
   .portb_din(d_from_kb),
   .portc_din(8'h0),
   .porta_dout(ppi_out_a),
   .portb_dout(),
   .portc_dout(ppi_out_c)
 );

//  -----------------------------------------------------------------------------
//  -- CPU data multiplex
//  -----------------------------------------------------------------------------
assign d_to_cpu = rd_n   ? 8'hFF           :
                  vdp_en ? d_to_cpu_vdp    :
                  rtc_en ? d_from_rtc      :
                  ~psg_n ? d_from_psg      :
                  ~ppi_n ? d_from_8255     :
                           d_from_slots    ;
//  -----------------------------------------------------------------------------
//  -- Keyboard decoder
//  -----------------------------------------------------------------------------
wire [7:0] d_from_kb;
keyboard msx_key
(
   .reset(reset),
   .clk(clk21m),
   .ps2_key(ps2_key),
   .kb_row(ppi_out_c[3:0]),
   .kb_data(d_from_kb),
   .kbd_addr(kbd_addr),
   .kbd_din(kbd_din),
   .kbd_we(kbd_we),
   .kbd_request(kbd_request)
);

//  -----------------------------------------------------------------------------
//  -- Sound AY-3-8910
//  -----------------------------------------------------------------------------
wire [7:0] d_from_psg, psg_ioa, psg_iob;
wire [5:0] joy_a = psg_iob[4] ? 6'b111111 : {~joy0[5], ~joy0[4], ~joy0[0], ~joy0[1], ~joy0[2], ~joy0[3]};
wire [5:0] joy_b = psg_iob[5] ? 6'b111111 : {~joy1[5], ~joy1[4], ~joy1[0], ~joy1[1], ~joy1[2], ~joy1[3]};
wire [5:0] joyA = joy_a & {psg_iob[0], psg_iob[1], 4'b1111};
wire [5:0] joyB = joy_b & {psg_iob[2], psg_iob[3], 4'b1111};
assign psg_ioa = {cas_audio_in,1'b0, psg_iob[6] ? joyB : joyA};
wire [9:0] ay_ch_mix;

logic u21_1_q = 1'b0;
always @(posedge clk21m,  posedge psg_n) begin
   if (psg_n)
      u21_1_q <= 1'b0;
   else if (ce_3m58_p)
      u21_1_q <= ~psg_n;
end

logic u21_2_q = 1'b0;
always @(posedge clk21m, posedge psg_n) begin
   if (psg_n)
      u21_2_q <= 1'b0;
   else if (ce_3m58_p)
      u21_2_q <= u21_1_q;
end

wire psg_e = !(!u21_2_q | ce_3m58_p) | psg_n;
wire psg_bc   = !(a[0] | psg_e);
wire psg_bdir = !(a[1] | psg_e);
jt49_bus PSG
(
   .rst_n(~reset),
   .clk(clk21m),
   .clk_en(ce_3m58_p),
   .bdir(psg_bdir),
   .bc1(psg_bc),
   .din(d_from_cpu),
   .sel(0),
   .dout(d_from_psg),
   .sound(ay_ch_mix),
   .A(),
   .B(),
   .C(),
   .IOA_in(psg_ioa),
   .IOA_out(),
   .IOB_in(8'hFF),
   .IOB_out(psg_iob)
);

//  -----------------------------------------------------------------------------
//  -- RTC
//  -----------------------------------------------------------------------------
wire [7:0] d_from_rtc;
rtc rtc
(
   .clk21m(clk21m),
   .reset(reset),
   .setup(reset),
   .rt(rtc_time),
   .clkena(ce_10hz),
   .req(req & rtc_en),
   .ack(),
   .wrt(~wr_n),
   .adr(a),
   .dbi(d_from_rtc),
   .dbo(d_from_cpu)
);

//  -----------------------------------------------------------------------------
//  -- Video
//  -----------------------------------------------------------------------------
wire       VRAM_we_lo_vdp, VRAM_we_hi_vdp, vdp18, vdp ;
wire       vdp_int_n;
wire [7:0] d_to_cpu_vdp;

assign vdp18          = bios_config.MSX_typ == MSX1;
assign vdp            = bios_config.MSX_typ == MSX2;

//CPU access
assign d_to_cpu_vdp   = vdp18 ? d_from_vdp18                : d_from_vdp;
assign vdp_int_n      = vdp18 ? int_n_vdp18                 : int_n_vdp;

//Video access
assign R              = vdp18 ? R_vdp18                     : {R_vdp,R_vdp[5:4]};
assign G              = vdp18 ? G_vdp18                     : {G_vdp,G_vdp[5:4]};
assign B              = vdp18 ? B_vdp18                     : {B_vdp,B_vdp[5:4]};
assign HS             = vdp18 ? ~HS_n_vdp18                 : ~HS_n_vdp;
assign VS             = vdp18 ? ~VS_n_vdp18                 : ~VS_n_vdp;
assign DE             = vdp18 ? DE_vdp18                    : DE_vdp;
assign hblank         = vdp18 ? hblank_vdp18                : hblank_vdp_cor;
assign vblank         = vdp18 ? vblank_vdp18                : vblank_vdp;
assign ce_pix         = vdp18 ? ce_5m39_n                   : ~DHClk_vdp;

logic hblank_vdp_cor;
always @(posedge clk21m) begin
   if (hblank_vdp)
      hblank_vdp_cor <= 1'b1;
   else 
      if (DHClk_vdp & DLClk_vdp)
         hblank_vdp_cor <= 1'b0;
end


//VRAM access
assign VRAM_address   = vdp18 ? {2'b00, VRAM_address_vdp18} : VRAM_address_vdp[15:0];
assign VRAM_we_lo     = vdp18 ? VRAM_we_vdp18               : VRAM_we_lo_vdp;
assign VRAM_we_hi     = vdp18 ? 1'b0                        : VRAM_we_hi_vdp;
assign VRAM_do        = vdp18 ? VRAM_do_vdp18               : VRAM_do_vdp;

assign VRAM_we_lo_vdp = ~VRAM_we_n_vdp & DLClk_vdp & ~VRAM_address_vdp[16];
assign VRAM_we_hi_vdp = ~VRAM_we_n_vdp & DLClk_vdp &  VRAM_address_vdp[16];

logic iack;
always @(posedge clk21m) begin
   if (reset) iack <= 0;
   else begin
      if (iorq_n  & mreq_n)
         iack <= 0;
      else
         if (req)
            iack <= 1;
   end
end
wire req = ~((iorq_n & mreq_n) | (wr_n & rd_n) | iack);

wire        int_n_vdp18;
wire  [7:0] d_from_vdp18;
wire  [7:0] R_vdp18, G_vdp18, B_vdp18;
wire        HS_n_vdp18, VS_n_vdp18, DE_vdp18, DLClk_vdp18, hblank_vdp18, vblank_vdp18, Blank_vdp18;
wire [13:0] VRAM_address_vdp18;
wire  [7:0] VRAM_do_vdp18;
wire        VRAM_we_vdp18;
vdp18_core #(.compat_rgb_g(0)) vdp_vdp18
(
   .clk_i(clk21m),
   .clk_en_10m7_i(ce_10m7_p),
   .reset_n_i(~reset),
   .csr_n_i(~(vdp_en & vdp18) | rd_n),
   .csw_n_i(~(vdp_en & vdp18) | wr_n),
   .mode_i(a[0]),
   .cd_i(d_from_cpu),
   .cd_o(d_from_vdp18),
   .int_n_o(int_n_vdp18),
   .vram_we_o(VRAM_we_vdp18),
   .vram_a_o(VRAM_address_vdp18),
   .vram_d_o(VRAM_do_vdp18),
   .vram_d_i(VRAM_di_lo),
   .border_i(msxConfig.border),
   .rgb_r_o(R_vdp18),
   .rgb_g_o(G_vdp18),
   .rgb_b_o(B_vdp18),
   .hsync_n_o(HS_n_vdp18),
   .vsync_n_o(VS_n_vdp18),
   .hblank_o(hblank_vdp18),
   .vblank_o(vblank_vdp18),
   .blank_n_o(DE_vdp18),
   .is_pal_i(msxConfig.video_mode == PAL)
);

wire        int_n_vdp;
wire  [7:0] d_from_vdp;
wire  [5:0] R_vdp, G_vdp, B_vdp;
wire        HS_n_vdp, VS_n_vdp, DE_vdp, DLClk_vdp, DHClk_vdp, Blank_vdp, hblank_vdp, vblank_vdp;
wire [16:0] VRAM_address_vdp;
wire  [7:0] VRAM_do_vdp;
wire        VRAM_we_n_vdp;
vdp vdp_vdp 
(
   .CLK21M(clk21m),
   .RESET(reset),
   .REQ(req & vdp_en & vdp),
   .ACK(),
   .WRT(~wr_n),
   .ADR(a),
   .DBI(d_from_vdp),
   .DBO(d_from_cpu),
   .INT_N(int_n_vdp),
   .PRAMOE_N(),
   .PRAMWE_N(VRAM_we_n_vdp),
   .PRAMADR(VRAM_address_vdp),
   .PRAMDBI({VRAM_di_hi, VRAM_di_lo}),
   .PRAMDBO(VRAM_do_vdp),
   .VDPSPEEDMODE(0),
   .CENTERYJK_R25_N(0),
   .PVIDEOR(R_vdp),
   .PVIDEOG(G_vdp),
   .PVIDEOB(B_vdp),
   .PVIDEODE(DE_vdp),
   .BLANK_O(Blank_vdp),
   .HBLANK(hblank_vdp),
   .VBLANK(vblank_vdp),
   .PVIDEOHS_N(HS_n_vdp),
   .PVIDEOVS_N(VS_n_vdp),
   .PVIDEOCS_N(),
   .PVIDEODHCLK(DHClk_vdp),
   .PVIDEODLCLK(DLClk_vdp),
   .DISPRESO(/*msxConfig.scandoubler*/ 0),
   .LEGACY_VGA(1),
   .RATIOMODE(3'b000),
   .NTSC_PAL_TYPE(msxConfig.video_mode == AUTO),
   .FORCED_V_MODE(msxConfig.video_mode == PAL),
   .BORDER(msxConfig.border)
);

wire [15:0] VRAM_address;
wire  [7:0] VRAM_do, VRAM_di_lo, VRAM_di_hi;
wire        VRAM_we_lo, VRAM_we_hi;
spram #(.addr_width(16),.mem_name("VRA2")) vram_lo
(
   .clock(clk21m),
   .address(VRAM_address),
   .wren(VRAM_we_lo),
   .data(VRAM_do),
   .q(VRAM_di_lo)
);
spram #(.addr_width(16),.mem_name("VRA3")) vram_hi
(
   .clock(clk21m),
   .address(VRAM_address),
   .wren(VRAM_we_hi),
   .data(VRAM_do),
   .q(VRAM_di_hi)
);

wire         [7:0] d_from_slots;
wire signed [15:0] cart_sound;
msx_slots msx_slots
(
   .clk(clk21m),
   .clk_en(ce_3m58_p),
   .reset(reset),
   .cpu_addr(a),
   .cpu_din(d_from_slots),  
   .cpu_dout(d_from_cpu),
   .cpu_iorq(~iorq_n),
   .cpu_m1(~m1_n),
   .cpu_mreq(~mreq_n),
   .cpu_rd(~rd_n),
   .cpu_wr(~wr_n),
   .sound(cart_sound),
   .ram_addr(ram_addr),
   .ram_din(ram_din),
   .ram_rnw(ram_rnw),
   .ram_dout(ram_dout),
   .sdram_ce(sdram_ce),
   .bram_ce(bram_ce),
   .sdram_size(sdram_size),
   .flash_addr(flash_addr),
   .flash_din(flash_din),
   .flash_req(flash_req),
   .flash_ready(flash_ready),
   .flash_done(flash_ready),
   .slot_layout(slot_layout),
   .img_mounted(img_mounted),
   .img_size(img_size),
   .img_readonly(img_readonly),
   .sd_lba(sd_lba),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din),
   .sd_buff_wr(sd_buff_wr),
   .active_slot(slot),
   .lookup_RAM(lookup_RAM),
   .lookup_SRAM(lookup_SRAM),
   .bios_config(bios_config),
   .cart_device(cart_device),
   .msx_device(msx_device),
   .msx_dev_ref_ram(msx_dev_ref_ram),
   .selected_mapper(selected_mapper),
   .sd_tx(sd_tx),
   .sd_rx(sd_rx),
   .d_to_sd(d_to_sd),
   .d_from_sd(d_from_sd)
);

endmodule