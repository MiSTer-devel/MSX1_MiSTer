//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_pattern.vhd,v 1.8 2006/06/18 10:47:06 arnim Exp $
//
// Pattern Generation Controller
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
module vdp18_pattern (
  input  logic        clk_i,
  input  logic        clk_en_5m37_i,
  input  logic        clk_en_acc_i,
  input  logic        reset_i,
  input  opmode_t     opmode_i,
  input  logic        illegal_i,    // M1+M2: fixed 4 fg + 2 bg pixels per column
  input  access_t     access_type_i,
  input  hv_t         num_line_i,
  input  logic [7:0]  vram_d_i,
  input  logic        vert_inc_i,
  input  logic        vsync_n_i,
  input  logic [3:0]  reg_col1_i,
  input  logic [3:0]  reg_col0_i,
  output logic [9:0]  pat_table_o,
  output logic [7:0]  pat_name_o,
  output logic [3:0]  pat_col_o
);

  logic [9:0] pat_cnt_q;
  logic [7:0] pat_name_q, pat_tmp_q, pat_shift_q, pat_col_q;
  logic pix_v;  // Přesunutí deklarace proměnné mimo always_comb blok

  always_ff @(posedge clk_i or posedge reset_i) begin
    if (reset_i) begin
      pat_cnt_q   <= '0;
      pat_name_q  <= '0;
      pat_tmp_q   <= '0;
      pat_shift_q <= '0;
      pat_col_q   <= '0;
    end else begin
      if (clk_en_5m37_i) begin
        // shift pattern with every pixel clock
        pat_shift_q[7:1] <= pat_shift_q[6:0];
      end

      if (clk_en_acc_i) begin
        // determine register update based on current access type
        case (access_type_i)
          AC_PNT: begin
            // store pattern name
            pat_name_q <= vram_d_i;
            // increment pattern counter
            pat_cnt_q <= pat_cnt_q + 1'd1;
          end
          AC_PCT: begin
            // store pattern color in temporary register
            pat_tmp_q <= vram_d_i;
          end
          AC_PGT: begin
            if (opmode_i == OPMODE_MULTIC) begin
              // set shift register to constant value
              // this value generates 4 bits of color1
              // followed by 4 bits of color0
              pat_shift_q <= 8'b11110000;
              // set pattern color from pattern generator memory
              pat_col_q <= vram_d_i;
            end else begin
              // all other modes:
              // store pattern line in shift register
              pat_shift_q <= illegal_i ? 8'hF0 : vram_d_i;
              // move pattern color from temporary register to color register
              pat_col_q <= pat_tmp_q;
            end
          end
          default: ;
        endcase
      end

      if (vert_inc_i) begin
        // redo patterns if there are more lines inside this pattern
        if (num_line_i[8] == 1'b0) begin
          case (opmode_i)
            OPMODE_TEXTM: begin
              if (num_line_i[2:0] != 3'b111) begin
                pat_cnt_q <= pat_cnt_q - 10'd40;
              end
            end
            OPMODE_GRAPH1,
            OPMODE_GRAPH2,
            OPMODE_MULTIC: begin
              if (num_line_i[2:0] != 3'b111) begin
                pat_cnt_q <= pat_cnt_q - 10'd32;
              end
            end
            default: ;
          endcase
        end
      end

      if (vsync_n_i == 1'b0) begin
        // reset pattern counter at end of active display area
        pat_cnt_q <= '0;
      end
    end
  end

  always_comb begin
    pat_col_o = 4'b0000;
    pix_v = pat_shift_q[7];  // Přiřazení hodnoty pix_v

    case (opmode_i)
      OPMODE_TEXTM: begin
        if (pix_v) begin
          pat_col_o = reg_col1_i;
        end else begin
          pat_col_o = reg_col0_i;
        end
      end
      OPMODE_GRAPH1,
      OPMODE_GRAPH2,
      OPMODE_MULTIC: begin
        if (pix_v) begin
          pat_col_o = pat_col_q[7:4];
        end else begin
          pat_col_o = pat_col_q[3:0];
        end
      end
      default: ;
    endcase
  end

  assign pat_table_o = pat_cnt_q;
  assign pat_name_o = pat_name_q;

endmodule
