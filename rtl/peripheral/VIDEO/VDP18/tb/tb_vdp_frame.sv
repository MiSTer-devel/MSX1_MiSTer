// Frame-level wrapper for tb_vdp_frame.cpp: vdp18_core with a 16K VRAM that
// has the 1-cycle read latency of the VRAM BRAM. The C++ side
// fills VRAM through the backdoor port and writes registers via the CPU port.

module tb_vdp_frame (
  input  logic        clk,
  input  logic        reset_n,
  input  logic        border,       // 1 = blanking signals of the chip, 0 = window
  input  logic        pal,

  input  logic        csr_n,
  input  logic        csw_n,
  input  logic        mode,
  input  logic [7:0]  cd_i,
  output logic [7:0]  cd_o,

  input  logic        poke,
  input  logic [13:0] poke_a,
  input  logic [7:0]  poke_d,

  output logic [7:0]  rgb_r,
  output logic [7:0]  rgb_g,
  output logic [7:0]  rgb_b,
  output logic        hblank,
  output logic        vblank,
  output logic        hsync_n,
  output logic        vsync_n,
  output logic        ce_pix
);
  logic ce_10m7 = 1'b0;               // clk_sys / 2, as in rtl/clock.sv
  always_ff @(posedge clk) ce_10m7 <= !ce_10m7;

  logic [7:0]  vram [16384];
  logic        vram_we;
  logic [13:0] vram_a;
  logic [7:0]  vram_do, vram_di;

  always_ff @(posedge clk) begin
    if (poke)         vram[poke_a] <= poke_d;
    else if (vram_we) vram[vram_a] <= vram_do;
    vram_di <= vram[vram_a];
  end

  vdp18_core vdp (
    .clk_i(clk),
    .clk_en_10m7_i(ce_10m7),
    .reset_n_i(reset_n),
    .csr_n_i(csr_n),
    .csw_n_i(csw_n),
    .mode_i(mode),
    .int_n_o(),
    .cd_i(cd_i),
    .cd_o(cd_o),
    .vram_we_o(vram_we),
    .vram_a_o(vram_a),
    .vram_d_o(vram_do),
    .vram_d_i(vram_di),
    .border_i(border),
    .is_pal_i(pal),
    .col_o(),
    .rgb_r_o(rgb_r),
    .rgb_g_o(rgb_g),
    .rgb_b_o(rgb_b),
    .hsync_n_o(hsync_n),
    .vsync_n_o(vsync_n),
    .blank_n_o(),
    .hblank_o(hblank),
    .vblank_o(vblank),
    .comp_sync_n_o(),
    .ce_pix(ce_pix)
  );
endmodule
