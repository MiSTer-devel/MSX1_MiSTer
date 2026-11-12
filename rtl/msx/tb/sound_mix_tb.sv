// sound_mix: full-width sum, single clipping (gain x2, saturation to 16 bit).
// Run: wsl.exe -- bash rtl/msx/tb/run_sound_mix.sh [alt_sound_mix.sv]
module sound_mix_tb;

logic clk = 0;
MSX::sound_t opll, scc, psg, dac, opm_L, opm_R;
MSX::sound_t pcm = '0;                  // turbo R PCM, set before apply
MSX::sound_t opl4_L = '0, opl4_R = '0;  // MoonSound, set before apply
logic mute = 0;                         // turbo R PCM: all sound muted
logic keybeep, tape;
logic signed [15:0] sound_L, sound_R;

sound_mix dut (.*);

int errors = 0, checked = 0;

function automatic logic signed [15:0] ref_clip(input int v);
    if (v > 16383)  return 16'sh7FFF;
    if (v < -16384) return 16'sh8000;
    return 16'(2 * v);
endfunction

task automatic apply(input int a, b, c, d, eL, eR, input logic kb, tp);
    int common;
    logic signed [15:0] expL, expR;
    opll = 18'(a); scc = 18'(b); psg = 18'(c); dac = 18'(d); opm_L = 18'(eL); opm_R = 18'(eR);
    keybeep = kb; tape = tp;
    common = a + b + c + d + int'(pcm) + (kb ? 512 : 0) + (tp ? 2048 : 0);
    expL = mute ? 16'sd0 : ref_clip(common + eL + int'(opl4_L));
    expR = mute ? 16'sd0 : ref_clip(common + eR + int'(opl4_R));
    #1 clk = 1; #1 clk = 0;
    checked++;
    if (sound_L !== expL || sound_R !== expR) begin
        errors++;
        if (errors <= 10)
            $display("FAIL opll=%0d scc=%0d psg=%0d dac=%0d opm=%0d/%0d kb=%b tape=%b: L=%0d exp %0d, R=%0d exp %0d",
                     a, b, c, d, eL, eR, kb, tp, sound_L, expL, sound_R, expR);
    end
endtask

// Uniform value in the range of one device type (3 x 16 bit signed)
function automatic int rnd_dev();
    return $signed($urandom_range(196607)) - 98304;
endfunction

initial begin
    // Quiet and small signals: exact gain x2
    apply(0, 0, 0, 0, 0, 0, 0, 0);
    apply(100, -50, 16, -128, 7, -7, 1, 0);
    apply(0, 0, 0, 0, 0, 0, 1, 1);
    // Clipping limits
    apply(16383, 0, 0, 0, 0, 0, 0, 0);
    apply(16384, 0, 0, 0, 0, 0, 0, 0);
    apply(-16384, 0, 0, 0, 0, 0, 0, 0);
    apply(-16385, 0, 0, 0, 0, 0, 0, 0);
    // Sum of sources above 16 bit must clip, not wrap
    apply(30000, 30000, 0, 0, 0, 0, 0, 0);
    apply(0, 0, 49104, 0, 0, 0, 0, 0);              // 3x PSG at maximum
    apply(-32768, 0, 0, -16384, -32768, -32768, 0, 0);
    apply(32767, 32767, 32767, 32767, 32767, -32768, 1, 1);
    apply(98301, 0, 0, 0, -98304, 98301, 0, 0);
    // turbo R PCM: one more source; mute silences everything
    pcm = 18'sd16256; apply(0, 0, 0, 0, 0, 0, 0, 0);
    pcm = -18'sd16384; apply(1000, 0, 0, 0, 0, 0, 1, 0);
    mute = 1; apply(30000, 0, 0, 0, 5, 5, 1, 1);
    mute = 0; pcm = '0;

    for (int i = 0; i < 200000; i++) begin
        pcm  = 18'($signed($urandom_range(32767)) - 16384);
        mute = $urandom_range(15) == 0;
        apply(rnd_dev(), rnd_dev(), rnd_dev(), rnd_dev(), rnd_dev(), rnd_dev(),
              1'($urandom), 1'($urandom));
    end
    mute = 0;
    // Mostly unclipped region
    for (int i = 0; i < 200000; i++)
        apply(rnd_dev() / 32, rnd_dev() / 32, rnd_dev() / 32, rnd_dev() / 32,
              rnd_dev() / 32, rnd_dev() / 32, 1'($urandom), 1'($urandom));

    if (errors == 0) $display("PASS sound_mix_tb (%0d vectors)", checked);
    else             $display("FAILED sound_mix_tb: %0d errors of %0d", errors, checked);
    $finish;
end

endmodule
