//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_ctrl.vhd,v 1.26 2006/06/18 10:47:01 arnim Exp $
//
// Timing Controller
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
import vdp18_pack::*;

module vdp18_ctrl (
  input logic        clk_i,
  input logic        clk_en_5m37_i,
  input logic        reset_i,
  input opmode_t     opmode_i,
  input hv_t         num_pix_i,
  input hv_t         num_line_i,
  input logic        vert_inc_i,
  input logic        reg_blank_i,
  input logic        reg_size1_i,
  input logic        stop_sprite_i,
  output logic       clk_en_acc_o,
  output access_t    access_type_o,
  output logic       vert_active_o,
  output logic       hor_active_o,
  output logic       irq_o,
  output logic       window_v_o,
  output logic       window_h_o
);


  logic vert_active_q, hor_active_q;
  logic window_v_q, window_h_q;
  logic sprite_active_q, sprite_line_act_q;
  
  access_t access_type_s;
  
  hv_t num_pix_plus_6_v;
  hv_t num_pix_plus_8_v;
  hv_t num_pix_plus_32_v;
  hv_t mod_6_v;
  integer num_pix_spr_v;

   // Process decode_access
  always_comb begin
    // Default assignments to ensure purely combinational logic
    access_type_s = AC_CPU;
    num_pix_plus_6_v = '0;
    num_pix_plus_8_v = '0;
    num_pix_plus_32_v = '0;
    mod_6_v = '0;
    num_pix_spr_v = 0;

    num_pix_plus_6_v  = num_pix_i + 9'sd6;
    num_pix_plus_8_v  = num_pix_i + 9'sd8;
    num_pix_plus_32_v = num_pix_i + 9'sd32;
    num_pix_spr_v     = $signed({{23{num_pix_i[8]}}, (num_pix_i & 9'b111111110)});

    case (opmode_i)
      OPMODE_GRAPH1,
      OPMODE_GRAPH2,
      OPMODE_MULTIC: begin
        if (vert_active_q) begin
          if (num_pix_plus_8_v[8] == 1'b0) begin
            case (num_pix_plus_8_v[2:1])
              2'b01: access_type_s = AC_PNT;
              2'b10: if (opmode_i != OPMODE_MULTIC) access_type_s = AC_PCT;
              2'b11: access_type_s = AC_PGT;
              default: ;
            endcase
          end
        end
        if (sprite_line_act_q) begin
          if (num_pix_i[8] == 1'b0 && num_pix_i[8:3] != 6'b011111 && num_pix_i[2:1] == 2'b00 && num_pix_i[4:3] != 2'b00) access_type_s = AC_STST;
          if (num_pix_plus_32_v[8:4] == 5'b00000 || num_pix_plus_32_v[8:1] == 8'b00001000) access_type_s = AC_STST;
          case (num_pix_spr_v)
            250, -78, -62, -46: access_type_s = AC_SATY;
            254, -76, -60, -44: access_type_s = AC_SATX;
            252, -74, -58, -42: access_type_s = AC_SATN;
            -86, -70, -54, -38: access_type_s = AC_SATC;
            -84, -68, -52, -36: access_type_s = AC_SPTH;
            -82, -66, -50, -34: if (reg_size1_i) access_type_s = AC_SPTL;
            default: ;
          endcase;
        end
      end

      OPMODE_TEXTM: begin
        if (vert_active_q && num_pix_plus_6_v[8] == 1'b0 && num_pix_plus_6_v[8:4] != 5'b01111) begin
          mod_6_v = num_pix_plus_6_v % 9'sd6;
          case (mod_6_v[2:1])
            2'b00: access_type_s = AC_PNT;
            2'b10: access_type_s = AC_PGT;
            default: ;
          endcase;
        end
      end

      default: ;
    endcase
  end


  // Process vert_flags
  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      vert_active_q     <= 1'b0;
      sprite_active_q   <= 1'b0;
      sprite_line_act_q <= 1'b0;
      window_v_q        <= 1'b0;
    end else if (clk_en_5m37_i) begin
      if (sprite_active_q) begin
        if (vert_inc_i) sprite_line_act_q <= 1'b1;
        if (num_pix_i == hv_sprite_start_c) sprite_line_act_q <= 1'b1;
      end
      if (vert_inc_i) begin
        if (reg_blank_i) begin
          sprite_active_q   <= 1'b0;
          sprite_line_act_q <= 1'b0;
        end else if (num_line_i == -2) begin
          sprite_active_q   <= 1'b1;
          sprite_line_act_q <= 1'b1;
        end else if (num_line_i == 191) begin
          sprite_active_q   <= 1'b0;
          sprite_line_act_q <= 1'b0;
        end
        if (reg_blank_i) vert_active_q <= 1'b0;
        else if (num_line_i == -1) vert_active_q <= 1'b1;
        else if (num_line_i == 191) vert_active_q <= 1'b0;
        if (num_line_i == -1) window_v_q <= 1'b1;
        else if (num_line_i == 191) window_v_q <= 1'b0;
      end
      if (stop_sprite_i) sprite_line_act_q <= 1'b0;
    end
  end

  // Process hor_flags
  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      hor_active_q <= 1'b0;
      window_h_q   <= 1'b0;
    end else if (clk_en_5m37_i) begin
      if (num_pix_i == -1) begin
        window_h_q   <= 1'b1;
        if (!reg_blank_i) begin
          hor_active_q <= 1'b1;
        end
      end
      if (opmode_i == OPMODE_TEXTM) begin
        if (num_pix_i == 239) begin 
          hor_active_q <= 1'b0;
          window_h_q   <= 1'b0;
        end
      end else begin
        if (num_pix_i == 255) begin 
          hor_active_q <= 1'b0;
          window_h_q   <= 1'b0;
        end
      end
    end
  end

  // Output mapping
  assign clk_en_acc_o  = clk_en_5m37_i && num_pix_i[0];
  assign access_type_o = access_type_s;
  assign vert_active_o = vert_active_q;
  assign hor_active_o  = hor_active_q;
  assign irq_o         = vert_inc_i && (num_line_i == 9'sd191);
  assign window_v_o    = window_v_q;
  assign window_h_o    = window_h_q;

endmodule
