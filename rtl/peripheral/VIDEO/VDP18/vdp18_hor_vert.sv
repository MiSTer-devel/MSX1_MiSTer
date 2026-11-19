//-------------------------------------------------------------------------------
//
// Synthesizable model of TI's TMS9918A, TMS9928A, TMS9929A.
//
// $Id: vdp18_hor_vert.vhd,v 1.11 2006/06/18 10:47:01 arnim Exp $
//
// Horizontal / Vertical Timing Generator
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

module vdp18_hor_vert (
    input logic clk_i,
    input logic clk_en_5m37_i,
    input logic reset_i,
    input opmode_t opmode_i,
    output hv_t num_pix_o,
    output hv_t num_line_o,
    output logic vert_inc_o,
    output logic hsync_n_o,
    output logic vsync_n_o,
    output logic blank_o,
    output logic hblank_o,
    output logic vblank_o,
    input logic is_pal_i
);

    hv_t last_line_s;
    hv_t first_line_s;

    hv_t first_pix_s;
    hv_t last_pix_s;

    hv_t cnt_hor_q;
    hv_t cnt_vert_q;

    logic vert_inc_s;

    logic hblank_q;
    logic vblank_q;

    // Prepare comparison signals for NTSC and PAL.
    assign first_line_s = is_pal_i ? hv_first_line_pal_c : hv_first_line_ntsc_c;
    assign last_line_s = is_pal_i ? hv_last_line_pal_c : hv_last_line_ntsc_c;

    // Process opmode_mux
    assign first_pix_s = (opmode_i == OPMODE_TEXTM) ? hv_first_pix_text_c : hv_first_pix_graph_c;
    assign last_pix_s = (opmode_i == OPMODE_TEXTM) ? hv_last_pix_text_c : hv_last_pix_graph_c;

    // Process counters
    // Sync reset: async reset with is_pal_i dependent first_line_s became latches
    always_ff @(posedge clk_i) begin
        if (reset_i) begin
            cnt_hor_q <= hv_first_pix_text_c;
            cnt_vert_q <= first_line_s;
            hsync_n_o <= 1'b1;
            vsync_n_o <= 1'b1;
            hblank_q <= 1'b0;
            vblank_q <= 1'b0;
        end else if (clk_en_5m37_i) begin
            // The horizontal counter
            if (cnt_hor_q == last_pix_s) begin
                cnt_hor_q <= first_pix_s;
            end else begin
                cnt_hor_q <= cnt_hor_q + 9'sd1;
            end

            // The vertical counter
            if (cnt_vert_q == last_line_s) begin
                cnt_vert_q <= first_line_s;
            end else if (vert_inc_s) begin
                // increment when horizontal counter is at trigger position
                cnt_vert_q <= cnt_vert_q + 9'sd1;
            end

            // Horizontal sync
            if (cnt_hor_q == -9'sd64) begin
                hsync_n_o <= 1'b0;
            end else if (cnt_hor_q == -9'sd38) begin
                hsync_n_o <= 1'b1;
            end
            if (cnt_hor_q == -9'sd72) begin
                hblank_q <= 1'b1;
            end else if (cnt_hor_q == -9'sd14) begin
                hblank_q <= 1'b0;
            end

            // Vertical sync
            if (cnt_vert_q == last_line_s - 9'sd3) begin
                vsync_n_o <= 1'b0;
            end else if (cnt_vert_q == last_line_s) begin
                vsync_n_o <= 1'b1;
            end
            if (cnt_vert_q == last_line_s - 9'sd6) begin
                vblank_q <= 1'b1;
            end else if (cnt_vert_q == first_line_s + 9'sd13) begin   // 13 lines top blanking (TI)
                vblank_q <= 1'b0;
            end
        end
    end

    // comparator for vertical line increment
    assign vert_inc_s = clk_en_5m37_i && (cnt_hor_q == hv_vertical_inc_c);

    // Output mapping
    assign num_pix_o = cnt_hor_q;
    assign num_line_o = cnt_vert_q;
    assign vert_inc_o = vert_inc_s;
    assign blank_o = hblank_q || vblank_q;
    assign vblank_o = vblank_q;
    assign hblank_o = hblank_q;

endmodule