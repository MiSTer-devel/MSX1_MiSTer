// Wrapper around vdp18_addr_mux for tb_vdp_addr.cpp; enums are mapped here so
// the C++ side does not depend on their ordinals.

module tb_vdp_addr
  import vdp18_pack::*;
(
  input  logic        pgt,    // 0 = colour table, 1 = pattern generator
  input  logic [1:0]  mode,   // 0 Graphic I, 1 Graphic II, 2 Multicolor, 3 Text
  input  logic        bitmap, // M3 (bitmap text / bitmap multicolor)
  input  logic [8:0]  line,
  input  logic [7:0]  vr3,
  input  logic [2:0]  vr4,
  input  logic [7:0]  chr,
  output logic [13:0] addr
);
  opmode_t om;
  always_comb
    case (mode)
      2'd0:    om = OPMODE_GRAPH1;
      2'd1:    om = OPMODE_GRAPH2;
      2'd2:    om = OPMODE_MULTIC;
      default: om = OPMODE_TEXTM;
    endcase

  vdp18_addr_mux mux (
    .access_type_i(pgt ? AC_PGT : AC_PCT),
    .opmode_i(om),
`ifndef OLD_VDP           // vdp18_addr_mux before the undocumented modes
    .bitmap_i(bitmap),
`endif
    .num_line_i(line),
    .reg_ntb_i(4'd0),
    .reg_ctb_i(vr3),
    .reg_pgb_i(vr4),
    .reg_satb_i(7'd0),
    .reg_spgb_i(3'd0),
    .reg_size1_i(1'b0),
    .cpu_vram_a_i(14'd0),
    .pat_table_i(10'd0),
    .pat_name_i(chr),
    .spr_num_i(5'd0),
    .spr_line_i(4'd0),
    .spr_name_i(8'd0),
    .vram_a_o(addr)
  );
endmodule
