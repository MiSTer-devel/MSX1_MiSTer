//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_addr_mux.vhd,v 1.10 2006/06/18 10:47:01 arnim Exp $
//
// Address Multiplexer / Generator
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
//-----------------------------------------------------------------------------
import vdp18_pack::*;

module vdp18_addr_mux (
  input  access_t access_type_i,
  input  opmode_t opmode_i,
  input  logic bitmap_i,          // M3 with text or multicolor
  input  hv_t num_line_i,
  input  logic [3:0] reg_ntb_i,
  input  logic [7:0] reg_ctb_i,
  input  logic [2:0] reg_pgb_i,
  input  logic [6:0] reg_satb_i,
  input  logic [2:0] reg_spgb_i,
  input  logic reg_size1_i,
  input  logic [13:0] cpu_vram_a_i,
  input  logic [9:0] pat_table_i,
  input  logic [7:0] pat_name_i,
  input  logic [4:0] spr_num_i,
  input  logic [3:0] spr_line_i,
  input  logic [7:0] spr_name_i,
  output logic [13:0] vram_a_o
);

  // Internal signal for num_line
  logic [8:0] num_line_v;

  always_comb begin
    // default assignment
    vram_a_o = '0;
    num_line_v = num_line_i;

    case (access_type_i)
      // CPU Access
      AC_CPU: vram_a_o = cpu_vram_a_i;

      // Pattern Name Table Access
      AC_PNT: begin
        vram_a_o[13:10] = reg_ntb_i;
        vram_a_o[9:0] = pat_table_i;
      end

      // Pattern Color Table Access
      AC_PCT: begin
        case (opmode_i)
          OPMODE_GRAPH1: begin
            vram_a_o[13:6] = reg_ctb_i;
            vram_a_o[5] = 1'b0;
            vram_a_o[4:0] = pat_name_i[7:3];
          end

          OPMODE_GRAPH2: begin
            // Mask = VR3[6:0] over address bits 12..6 (third, name[7:3]).
            vram_a_o[13] = reg_ctb_i[7];
            vram_a_o[12:11] = num_line_v[7:6] & reg_ctb_i[6:5];
            vram_a_o[10:3] = pat_name_i & {reg_ctb_i[4:0], 3'b111};
            vram_a_o[2:0] = num_line_v[2:0];
          end

          default: ;
        endcase
      end

      // Pattern Generator Table Access
      AC_PGT: begin
        case (opmode_i)
          OPMODE_TEXTM, OPMODE_GRAPH1, OPMODE_MULTIC: begin
            // Bitmap text / multicolor: one table per third like Graphic II,
            // but the name is never masked (mask 7FF, reference).
            if (bitmap_i && opmode_i != OPMODE_GRAPH1) begin
              vram_a_o[13] = reg_pgb_i[2];
              vram_a_o[12:11] = num_line_v[7:6] & reg_pgb_i[1:0];
            end else begin
              vram_a_o[13:11] = reg_pgb_i;
            end
            vram_a_o[10:3] = pat_name_i;
            vram_a_o[2:0] = (opmode_i == OPMODE_MULTIC) ? num_line_v[4:2] : num_line_v[2:0];
          end

          OPMODE_GRAPH2: begin
            // Thirds masked by VR4[1:0], name by the colour table mask (VR3).
            vram_a_o[13] = reg_pgb_i[2];
            vram_a_o[12:11] = num_line_v[7:6] & reg_pgb_i[1:0];
            vram_a_o[10:3] = pat_name_i & {reg_ctb_i[4:0], 3'b111};
            vram_a_o[2:0] = num_line_v[2:0];
          end

          default: ;
        endcase
      end

      // Sprite Test and Attribute Table Access
      AC_STST, AC_SATY: begin
        vram_a_o[13:7] = reg_satb_i;
        vram_a_o[6:2] = spr_num_i;
        vram_a_o[1:0] = 2'b00;
      end

      AC_SATX: begin
        vram_a_o[13:7] = reg_satb_i;
        vram_a_o[6:2] = spr_num_i;
        vram_a_o[1:0] = 2'b01;
      end

      AC_SATN: begin
        vram_a_o[13:7] = reg_satb_i;
        vram_a_o[6:2] = spr_num_i;
        vram_a_o[1:0] = 2'b10;
      end

      AC_SATC: begin
        vram_a_o[13:7] = reg_satb_i;
        vram_a_o[6:2] = spr_num_i;
        vram_a_o[1:0] = 2'b11;
      end

      // Sprite Pattern Access
      AC_SPTH: begin
        vram_a_o[13:11] = reg_spgb_i;
        if (!reg_size1_i) begin
          // 8x8 sprite
          vram_a_o[10:3] = spr_name_i;
          vram_a_o[2:0] = spr_line_i[2:0];
        end else begin
          // 16x16 sprite
          vram_a_o[10:5] = spr_name_i[7:2];
          vram_a_o[4] = 1'b0;
          vram_a_o[3:0] = spr_line_i;
        end
      end

      AC_SPTL: begin
        vram_a_o[13:11] = reg_spgb_i;
        vram_a_o[10:5] = spr_name_i[7:2];
        vram_a_o[4] = 1'b1;
        vram_a_o[3:0] = spr_line_i;
      end

      default: ;
    endcase
  end

endmodule
