//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_sprite.vhd,v 1.11 2006/06/18 10:47:06 arnim Exp $
//
// Sprite Generation Controller
//
// Copyright (c) 2006, Arnim Laeuger (arnim.laeuger@gmx.net)
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
//
// Redistributions in synthesized form must reproduce the above copyright
// notice, this list of conditions and the following disclaimer in the
// documentation and/or other materials provided with the distribution.
//
// Neither the name of the author nor the names of other contributors may
// be used to endorse or promote products derived from this software without
// specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//
// Please report bugs to the author, but before you do so, please
// make sure that this is not a derivative work and that
// you have the latest version of this file.
//
//-------------------------------------------------------------------------------
import vdp18_pack::*;

module vdp18_sprite (
  input  logic        clk_i,
  input  logic        clk_en_5m37_i,
  input  logic        clk_en_acc_i,
  input  logic        reset_i,
  input  access_t     access_type_i,
  input  hv_t         num_pix_i,
  input  hv_t         num_line_i,
  input  logic [7:0]  vram_d_i,
  input  logic        vert_inc_i,
  input  logic        reg_size1_i,
  input  logic        reg_mag1_i,
  output logic        spr_5th_o,
  output logic [4:0]  spr_5th_num_o,
  output logic        stop_sprite_o,
  output logic        spr_coll_o,
  output logic [4:0]  spr_num_o,
  output logic [3:0]  spr_line_o,
  output logic [7:0]  spr_name_o,
  output logic [3:0]  spr0_col_o,
  output logic [3:0]  spr1_col_o,
  output logic [3:0]  spr2_col_o,
  output logic [3:0]  spr3_col_o
);

  typedef logic [4:0] sprite_number_t;
  typedef sprite_number_t sprite_numbers_t [3:0];
  sprite_numbers_t sprite_numbers_q;

  logic [4:0] sprite_num_q;
  logic [4:0] stat_num_q;   // status bits 4-0: sprite where the last scan stopped (real chip)
  logic [2:0] sprite_idx_q;
  logic [7:0] sprite_name_q;

  typedef logic [7:0] sprite_x_pos_t;
  typedef sprite_x_pos_t sprite_xpos_t [3:0];
  sprite_xpos_t sprite_xpos_q;

  typedef logic sprite_ec_t [3:0];
  sprite_ec_t sprite_ec_q;

  typedef logic sprite_xtog_t [3:0];
  sprite_xtog_t sprite_xtog_q;

  typedef logic [3:0] sprite_col_t;
  typedef sprite_col_t sprite_cols_t [3:0];
  sprite_cols_t sprite_cols_q;

  typedef logic [15:0] sprite_pat_t;
  typedef sprite_pat_t sprite_pats_t [3:0];
  sprite_pats_t sprite_pats_q;

  logic [3:0] sprite_line_s, sprite_line_q;
  logic sprite_visible_s;

  logic signed [8:0] sprite_line_v; // Ensure correct usage of signed keyword here
  logic [2:0] num_spr_pix_v;  // Changed unsigned to normal logic

  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      sprite_numbers_q <= '{default: '0};
      sprite_num_q     <= '0;
      stat_num_q       <= '0;
      sprite_idx_q     <= '0;
      sprite_line_q    <= '0;
      sprite_name_q    <= '0;
      sprite_cols_q    <= '{default: '0};
      sprite_xpos_q    <= '{default: '0};
      sprite_ec_q      <= '{default: '0};
      sprite_xtog_q    <= '{default: '0};
      sprite_pats_q    <= '{default: '0};
    end else begin
      if (clk_en_5m37_i) begin
        if (num_pix_i == hv_sprite_start_c && sprite_idx_q > 0) begin
          sprite_idx_q <= sprite_idx_q - 1'd1;
        end
        for (int idx = 0; idx < 4; idx++) begin
          if (num_pix_i[8] == 0 || (sprite_ec_q[idx] == 1 && num_pix_i[8:5] == 4'b1111)) begin
            if (sprite_xpos_q[idx] != 0) begin
              sprite_xpos_q[idx] <= sprite_xpos_q[idx] - 1'd1;
            end else begin
              sprite_xtog_q[idx] <= !sprite_xtog_q[idx];
            end
          end
          if (sprite_xpos_q[idx] == 0) begin
            if (num_pix_i[8] == 0 || (sprite_ec_q[idx] == 1 && num_pix_i[8:5] == 4'b1111)) begin
              if (!reg_mag1_i || sprite_xtog_q[idx]) begin
                sprite_pats_q[idx] <= {sprite_pats_q[idx][14:0], 1'b0};
              end
            end
          end
          if (num_pix_i == 9'b011111111) begin
            sprite_pats_q[idx] <= '0;
          end
        end
      end
      if (vert_inc_i) begin
        sprite_num_q <= '0;
        sprite_idx_q <= '0;
      end else if (clk_en_acc_i) begin
        case (access_type_i)
          AC_STST: begin
            sprite_num_q <= sprite_num_q + 1'd1;
            stat_num_q   <= sprite_num_q;
            if (sprite_visible_s && sprite_idx_q < 4) begin
              sprite_numbers_q[sprite_idx_q[1:0]] <= sprite_num_q; // Adjusting to index properly
              sprite_idx_q <= sprite_idx_q + 1'd1;
            end
          end
          AC_SATY: sprite_line_q <= sprite_line_s;
          AC_SATX: begin
            sprite_xpos_q[sprite_idx_q[1:0]] <= vram_d_i;
            sprite_xtog_q[sprite_idx_q[1:0]] <= '0;
          end
          AC_SATN: sprite_name_q <= vram_d_i;
          AC_SATC: begin
            sprite_cols_q[sprite_idx_q[1:0]] <= vram_d_i[3:0];
            sprite_ec_q[sprite_idx_q[1:0]] <= vram_d_i[7];
          end
          AC_SPTH: begin
            sprite_pats_q[sprite_idx_q[1:0]][15:8] <= vram_d_i;
            sprite_pats_q[sprite_idx_q[1:0]][7:0] <= '0;
            if (!reg_size1_i) begin
              sprite_idx_q <= sprite_idx_q - 1'd1;
            end
          end
          AC_SPTL: begin
            sprite_pats_q[sprite_idx_q[1:0]][7:0] <= vram_d_i;
            sprite_idx_q <= sprite_idx_q - 1'd1;
          end
          default: ;
        endcase
      end
    end
  end

  always_comb begin
    sprite_visible_s = 0;
    stop_sprite_o = 0;

    sprite_line_v = $signed(num_line_i) - $signed(vram_d_i); // Ensure correct usage of signed arithmetic
    if (sprite_line_v < -31) begin
      sprite_line_v[8] = 0;
    end

    if (reg_mag1_i) begin
      sprite_line_v = sprite_line_v >>> 1;
    end

    if (sprite_line_v >= 0) begin
      if (reg_size1_i) begin
        if (sprite_line_v < 16) begin
          sprite_visible_s = 1;
        end
      end else begin
        if (sprite_line_v < 8) begin
          sprite_visible_s = 1;
        end
      end
    end

    sprite_line_s = sprite_line_v[3:0];

    if (clk_en_acc_i) begin
      if (access_type_i == AC_STST) begin
        if (vram_d_i == 8'd208 || sprite_idx_q == 4 || sprite_num_q == 31) begin
          stop_sprite_o = 1;
        end
      end

      if (sprite_idx_q == 0 && (access_type_i == AC_SPTL || (access_type_i == AC_SPTH && !reg_size1_i))) begin
        stop_sprite_o = 1;
      end
    end

    if (num_pix_i == hv_sprite_start_c && sprite_idx_q == 0) begin
      stop_sprite_o = 1;
    end
  end

  always_comb begin
    spr_5th_o = 0;
    spr_5th_num_o = (clk_en_acc_i && access_type_i == AC_STST) ? sprite_num_q : stat_num_q;

    if (clk_en_acc_i && access_type_i == AC_STST && sprite_visible_s && sprite_idx_q == 4) begin
      spr_5th_o = 1;
    end
  end

  always_comb begin
    spr0_col_o = '0;
    spr1_col_o = '0;
    spr2_col_o = '0;
    spr3_col_o = '0;
    num_spr_pix_v = '0;

    if (sprite_xpos_q[0] == 0 && sprite_pats_q[0][15] == 1) begin
      spr0_col_o = sprite_cols_q[0];
      num_spr_pix_v = num_spr_pix_v + 1'd1;
    end
    if (sprite_xpos_q[1] == 0 && sprite_pats_q[1][15] == 1) begin
      spr1_col_o = sprite_cols_q[1];
      num_spr_pix_v = num_spr_pix_v + 1'd1;
    end
    if (sprite_xpos_q[2] == 0 && sprite_pats_q[2][15] == 1) begin
      spr2_col_o = sprite_cols_q[2];
      num_spr_pix_v = num_spr_pix_v + 1'd1;
    end
    if (sprite_xpos_q[3] == 0 && sprite_pats_q[3][15] == 1) begin
      spr3_col_o = sprite_cols_q[3];
      num_spr_pix_v = num_spr_pix_v + 1'd1;
    end

    spr_coll_o = (num_spr_pix_v > 1);
  end

  assign spr_num_o = (access_type_i == AC_STST) ? sprite_num_q : sprite_numbers_q[sprite_idx_q[1:0]];
  assign spr_line_o = sprite_line_q;
  assign spr_name_o = sprite_name_q;

endmodule
