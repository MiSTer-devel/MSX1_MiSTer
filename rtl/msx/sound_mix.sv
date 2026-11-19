// sound_mix
//
// Copyright (c) 2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later

// Sound mixer: the only place where audio is clipped.
// Sources are summed at full width, then gain x2 and saturation to 16 bit.
// Output is registered: it leaves the core to the audio clock domain.
module sound_mix (
    input                      clk,
    input  MSX::sound_t        opll,
    input  MSX::sound_t        scc,
    input  MSX::sound_t        psg,
    input  MSX::sound_t        dac,
    input  MSX::sound_t        pcm,         // turbo R PCM
    input                      mute,        // turbo R PCM: all sound muted
    input  MSX::sound_t        opm_L,
    input  MSX::sound_t        opm_R,
    input  MSX::sound_t        opl4_L,      // MoonSound
    input  MSX::sound_t        opl4_R,
    input                      keybeep,
    input                      tape,        // tape monitor (gated by motor and OSD option)
    output logic signed [15:0] sound_L,
    output logic signed [15:0] sound_R
);

    localparam int W = 22;                   // 8 terms of 18 bit + sign

    wire signed [W-1:0] sys    = $signed({12'd0, keybeep, 9'd0}) + $signed({10'd0, tape, 11'd0});
    wire signed [W-1:0] common = opll + scc + psg + dac + pcm + sys;
    wire signed [W-1:0] mix_L  = common + opm_L + opl4_L;
    wire signed [W-1:0] mix_R  = common + opm_R + opl4_R;

    function automatic logic signed [15:0] clip_x2(input logic signed [W-1:0] v);
        if (v > 16383)       return 16'sh7FFF;
        else if (v < -16384) return 16'sh8000;
        else                 return {v[14:0], 1'b0};
    endfunction

    always_ff @(posedge clk) begin
        sound_L <= mute ? 16'sd0 : clip_x2(mix_L);
        sound_R <= mute ? 16'sd0 : clip_x2(mix_R);
    end

endmodule
