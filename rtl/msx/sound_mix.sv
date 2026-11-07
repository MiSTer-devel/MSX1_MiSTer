// Sound mixer: the only place where audio is clipped.
// Sources are summed at full width, then gain x2 and saturation to 16 bit.
// Output is registered: it leaves the core to the audio clock domain.
module sound_mix (
    input                      clk,
    input  MSX::sound_t        opll,
    input  MSX::sound_t        scc,
    input  MSX::sound_t        psg,
    input  MSX::sound_t        dac,
    input  MSX::sound_t        opm_L,
    input  MSX::sound_t        opm_R,
    input                      keybeep,
    input                      tape,        // tape monitor
    output logic signed [15:0] sound_L,
    output logic signed [15:0] sound_R
);

    localparam int W = 22;                   // 6 terms of 18 bit + sign

    wire signed [W-1:0] sys    = $signed({12'd0, keybeep, 9'd0}) + $signed({13'd0, tape, 8'd0});
    wire signed [W-1:0] common = opll + scc + psg + dac + sys;
    wire signed [W-1:0] mix_L  = common + opm_L;
    wire signed [W-1:0] mix_R  = common + opm_R;

    function automatic logic signed [15:0] clip_x2(input logic signed [W-1:0] v);
        if (v > 16383)       return 16'sh7FFF;
        else if (v < -16384) return 16'sh8000;
        else                 return {v[14:0], 1'b0};
    endfunction

    always_ff @(posedge clk) begin
        sound_L <= clip_x2(mix_L);
        sound_R <= clip_x2(mix_R);
    end

endmodule
