package vdp18_pack;

  typedef enum logic [1:0] {
    OPMODE_GRAPH1,
    OPMODE_GRAPH2,
    OPMODE_MULTIC,
    OPMODE_TEXTM
  } opmode_t;
  
  typedef enum logic [3:0] {
    AC_CPU,
    AC_PNT,
    AC_PCT,
    AC_PGT,
    AC_STST,
    AC_SATY,
    AC_SATX,
    AC_SATN,
    AC_SATC,
    AC_SPTH,
    AC_SPTL
  } access_t;

  typedef logic signed [8:0] hv_t;
  
  parameter hv_t hv_first_pix_text_c = -9'sd102;
  parameter hv_t hv_last_pix_text_c = 9'sd239;
  parameter hv_t hv_first_pix_graph_c = -9'sd86;
  parameter hv_t hv_last_pix_graph_c = 9'sd255;

  // PAL: 13 blanking + 51 border above, 51 border + 3 + 3 below (TI, MAME)
  parameter hv_t hv_first_line_pal_c = -9'sd64;
  parameter hv_t hv_last_line_pal_c = 9'sd249;
  parameter hv_t hv_first_line_ntsc_c = -9'sd40;
  parameter hv_t hv_last_line_ntsc_c = 9'sd222;
  parameter hv_t hv_vertical_inc_c = -9'sd32;
  parameter hv_t hv_sprite_start_c = 9'sd247;

endpackage : vdp18_pack