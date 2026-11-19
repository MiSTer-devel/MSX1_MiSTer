//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_col_mux.vhd,v 1.10 2006/06/18 10:47:01 arnim Exp $
//
// Color Information Multiplexer
//
//-------------------------------------------------------------------------------
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
import vdp18_col_pack::*;

module vdp18_col_mux #(
  int compat_rgb_g = 0
)(
  input logic clk_i,
  input logic clk_en_5m37_i,
  input logic reset_i,
  input logic vert_active_i,
  input logic hor_active_i,
  input logic border_i,
  input logic blank_i,
  input logic hblank_i,
  input logic vblank_i,
  input logic window_v_i,
  input logic window_h_i,
  output logic blank_n_o,
  output logic hblank_n_o,
  output logic vblank_n_o,
  input logic [3:0] reg_col0_i,
  input logic [3:0] pat_col_i,
  input logic [3:0] spr0_col_i,
  input logic [3:0] spr1_col_i,
  input logic [3:0] spr2_col_i,
  input logic [3:0] spr3_col_i,
  output logic [3:0] col_o,
  output logic [7:0] rgb_r_o,
  output logic [7:0] rgb_g_o,
  output logic [7:0] rgb_b_o
);

  // Define a signal for color selection
  logic [3:0] col_s;

  // Process col_mux
  // Purpose:
  //   Multiplexes the color information from different sources.
  always_comb begin
    if (!blank_i) begin
      if (hor_active_i && vert_active_i) begin
        // priority decoder
        if (spr0_col_i != 4'b0000) begin
          col_s = spr0_col_i;
        end else if (spr1_col_i != 4'b0000) begin
          col_s = spr1_col_i;
        end else if (spr2_col_i != 4'b0000) begin
          col_s = spr2_col_i;
        end else if (spr3_col_i != 4'b0000) begin
          col_s = spr3_col_i;
        end else if (pat_col_i != 4'b0000) begin
          col_s = pat_col_i;
        end else begin
          col_s = reg_col0_i;
        end
      end else begin
        // display border
        col_s = reg_col0_i;
      end
    end else begin
      // blank color channels during horizontal and vertical trace back
      // required to initialize colors for each new scan line
      col_s = 4'b0000;
    end
  end

  // Process rgb_reg
  // Purpose:
  //   Converts the color information to simple RGB and saves these in
  //   output registers.
  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      rgb_r_o <= 8'b00000000;
      rgb_g_o <= 8'b00000000;
      rgb_b_o <= 8'b00000000;
    end else if (clk_en_5m37_i) begin
      // Define variables for color conversion
      int rgb_r_v, rgb_g_v, rgb_b_v;
      rgb_table_t rgb_table_v;

      // select requested RGB table
      if (compat_rgb_g == 1) begin
        rgb_table_v = compat_rgb_table_c;
      end else begin
        rgb_table_v = full_rgb_table_c;
      end

      // assign color to RGB channels
      rgb_r_v = rgb_table_v[col_s][r_c];
      rgb_g_v = rgb_table_v[col_s][g_c];
      rgb_b_v = rgb_table_v[col_s][b_c];

      rgb_r_o <= rgb_r_v[7:0];
      rgb_g_o <= rgb_g_v[7:0];
      rgb_b_o <= rgb_b_v[7:0];

      blank_n_o <= !blank_i;

      if (border_i == 1'b0) begin
        hblank_n_o <= window_h_i;
        vblank_n_o <= window_v_i;
      end else begin
        hblank_n_o <= !hblank_i;
        vblank_n_o <= !vblank_i;
      end
    end
  end

  // Output mapping
  assign col_o = col_s;

endmodule
