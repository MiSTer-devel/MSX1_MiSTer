// OPL4 (YMF278B) wave table synthesis: 24 tones of 8 / 12 / 16 bit samples
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

// Behaviour after openMSX YMF278 (doc/moonsound.md, tb/opl4_wave_gold.py). Two activities:
//   - the frame: every sample period the 24 tones are computed one after another, 4 clk each,
//     from the two samples around the play position kept per tone;
//   - the memory side: reads those two samples whenever a position moved, loads the wave
//     header after a wave number write and serves the memory data register.
// A tone that starts again waits for its first samples (no output, no advance). A playing tone
// never waits: when the memory is late it goes on with the samples it has.

module opl4_wave (
    input                      clk,
    input                      reset,
    input                      smp_tick,    // one clk: next sample (44.1 kHz)
    input                [4:0] ram_chunks,  // sample RAM in 128 kB units, 0..16
    // registers; reg_wr / reg_rd only while busy = 0
    input                      reg_wr,      // one clk
    input                      reg_rd,      // one clk: reg_rdata was taken (memory data: next address)
    input                [7:0] reg_addr,
    input                [7:0] reg_wdata,
    output               [7:0] reg_rdata,   // one clk after reg_addr
    output                     busy,        // header load or memory access under way
    output logic         [5:0] mix_fm,      // register F8h
    // sample memory, 4 MB image: ROM at 0, RAM at 200000h
    output logic               mem_req,     // held until mem_ack
    output logic               mem_we,      // byte write, else word read
    output logic        [21:0] mem_addr,
    output logic         [7:0] mem_wdata,
    input                      mem_ack,     // one clk
    input               [15:0] mem_rdata,   // bytes at the even (7:0) and odd (15:8) address of the word
    output logic signed [20:0] out_l,
    output logic signed [20:0] out_r,
    output logic               out_valid,   // one clk
    output logic               late,        // one clk: a tone computed with samples of an older position
    output                     idle         // nothing pending (test bench)
);

    localparam logic [2:0] EG_OFF = 3'd0, EG_REL = 3'd1, EG_SUS = 3'd2, EG_DEC = 3'd3, EG_ATT = 3'd4;
    localparam logic [9:0] MAX_ATT = 10'h280;

    // ------------------------------------------------------------------ functions
    // gain 1, 3/4, 1/2, 3/8, 1/4, 3/16, 1/8, 0
    function automatic logic signed [20:0] gain8(input logic signed [20:0] x, input logic [2:0] i);
        logic signed [22:0] x3;
        x3 = {x[20], x[20], x} + {x[20], x, 1'b0};
        case (i)
            3'd0:    gain8 = x;
            3'd1:    gain8 = x3[22:2];
            3'd2:    gain8 = {x[20], x[20:1]};
            3'd3:    gain8 = {x3[22], x3[22:3]};
            3'd4:    gain8 = {{2{x[20]}}, x[20:2]};
            3'd5:    gain8 = {{2{x3[22]}}, x3[22:4]};
            3'd6:    gain8 = {{3{x[20]}}, x[20:3]};
            default: gain8 = 21'sd0;
        endcase
    endfunction

    // attenuation v (0.09375 dB steps) as a 16 bit factor, 8000h = 1; silent from -60 dB
    function automatic logic [15:0] vol_f(input logic [9:0] v);
        logic [15:0] m;
        m = {8'h80 - {2'b00, v[5:0]}, 8'h00};
        vol_f = v >= MAX_ATT ? 16'd0 : m >> v[9:6];
    endfunction

    function automatic logic [3:0] eg_inc(input logic [3:0] r, input logic [2:0] c);
        logic p, q;
        case (r[1:0])
            2'd0: begin p = c[0];                 q = 1'b0; end
            2'd1: begin p = c[0] | (c == 3'd4);   q = c[1:0] == 2'd3; end
            2'd2: begin p = c[1:0] != 2'd0;       q = c[0]; end
            2'd3: begin p = c != 3'd0;            q = c[1:0] != 2'd0; end
        endcase
        case (r[3:2])
            2'd0:    eg_inc = {3'b000, p};
            2'd1:    eg_inc = q ? 4'd2 : 4'd1;
            2'd2:    eg_inc = q ? 4'd4 : 4'd2;
            default: eg_inc = r == 4'd12 ? 4'd4 : 4'd0;    // 14: rate 0
        endcase
    endfunction

    function automatic logic [5:0] lfo_step(input logic [2:0] i);
        case (i)
            3'd0: lfo_step = 6'd1;  3'd1: lfo_step = 6'd12; 3'd2: lfo_step = 6'd19; 3'd3: lfo_step = 6'd25;
            3'd4: lfo_step = 6'd31; 3'd5: lfo_step = 6'd35; 3'd6: lfo_step = 6'd37; 3'd7: lfo_step = 6'd42;
        endcase
    endfunction

    function automatic logic [7:0] am_depth(input logic [2:0] i);
        case (i)
            3'd0: am_depth = 8'h00; 3'd1: am_depth = 8'h14; 3'd2: am_depth = 8'h20; 3'd3: am_depth = 8'h28;
            3'd4: am_depth = 8'h30; 3'd5: am_depth = 8'h40; 3'd6: am_depth = 8'h50; 3'd7: am_depth = 8'h80;
        endcase
    endfunction

    function automatic logic [2:0] div3(input logic [3:0] x);
        div3 = x >= 4'd15 ? 3'd5 : x >= 4'd12 ? 3'd4 : x >= 4'd9 ? 3'd3 : x >= 4'd6 ? 3'd2 : x >= 4'd3 ? 3'd1 : 3'd0;
    endfunction

    // ------------------------------------------------------------------ registers
    logic        init = 1'b1;
    logic  [7:0] init_cnt = '0;
    logic        ild_run = 1'b0;            // wave 0 header into every tone after reset
    logic  [4:0] ild_cnt;

    logic  [4:0] reg2;
    logic  [5:0] reg3;
    logic  [7:0] reg4;
    logic  [5:0] mix_pcm;
    logic [21:0] memadr;
    logic  [7:0] rd_buf;
    logic [23:0] keyon_r, wave8, ev_kon, ev_wave, ev_tl;
    logic [23:0] need, hold, v1, wcv;       // samples to read; tone waits for them; s1 / word cache valid

    // tone registers: row = (register - 8) / 24, tone = (register - 8) % 24
    wire   [7:0] rx    = reg_addr - 8'd8;
    wire         rslot = reg_addr >= 8'h08 && reg_addr <= 8'hF7;
    wire   [3:0] wrow  = rx >= 8'd216 ? 4'd9 : rx >= 8'd192 ? 4'd8 : rx >= 8'd168 ? 4'd7 : rx >= 8'd144 ? 4'd6 :
                         rx >= 8'd120 ? 4'd5 : rx >= 8'd96 ? 4'd4 : rx >= 8'd72 ? 4'd3 : rx >= 8'd48 ? 4'd2 :
                         rx >= 8'd24 ? 4'd1 : 4'd0;
    wire   [7:0] wr24  = {1'b0, wrow, 3'b000} + {wrow, 4'b0000};
    wire   [7:0] wsl8  = rx - wr24;
    wire   [4:0] wslot = wsl8[4:0];
    wire         w_en  = reg_wr && ~init && ~ild_run;
    wire         w_row = w_en && rslot;

    // memory side: header load, memory data register
    logic        ld_pend, mw_pend, pf_pend;
    logic  [4:0] ld_slot;
    logic  [8:0] ld_wave;
    logic  [7:0] hbuf [12];
    logic        ld_commit;                 // one clk: header and tone registers 5-9 of ld_slot
    logic  [2:0] sh_cnt;                    // then the same five bytes into the read back copy
    logic        sh_run;
    logic [21:0] mw_addr;
    logic  [7:0] mw_data;
    assign busy = init || ild_run || ld_pend || mw_pend || pf_pend || sh_run;

    logic  [4:0] f_slot;                    // tone of the frame
    wire   [7:0] q0, q1, q2, q3, q4, q5, q6, q7, q8, q9, qtld;
    wire         row_clr = init && init_cnt[7:5] == 3'd0;
    wire   [4:0] row_wa  = init ? init_cnt[4:0] : ld_commit ? ld_slot : wslot;
    wire   [7:0] row_wd  = init ? 8'd0 : reg_wdata;
    opl_lutram #(8, 5) row0 (clk, row_clr || (w_row && wrow == 4'd0), row_wa, row_wd, f_slot, q0);
    opl_lutram #(8, 5) row1 (clk, row_clr || (w_row && wrow == 4'd1), row_wa, row_wd, f_slot, q1);
    opl_lutram #(8, 5) row2 (clk, row_clr || (w_row && wrow == 4'd2), row_wa, row_wd, f_slot, q2);
    opl_lutram #(8, 5) row3 (clk, row_clr || (w_row && wrow == 4'd3), row_wa, row_wd, f_slot, q3);
    opl_lutram #(8, 5) row4 (clk, row_clr || (w_row && wrow == 4'd4), row_wa, row_wd, f_slot, q4);
    opl_lutram #(8, 5) row5 (clk, row_clr || ld_commit || (w_row && wrow == 4'd5), row_wa, ld_commit ? hbuf[7]  : row_wd, f_slot, q5);
    opl_lutram #(8, 5) row6 (clk, row_clr || ld_commit || (w_row && wrow == 4'd6), row_wa, ld_commit ? hbuf[8]  : row_wd, f_slot, q6);
    opl_lutram #(8, 5) row7 (clk, row_clr || ld_commit || (w_row && wrow == 4'd7), row_wa, ld_commit ? hbuf[9]  : row_wd, f_slot, q7);
    opl_lutram #(8, 5) row8 (clk, row_clr || ld_commit || (w_row && wrow == 4'd8), row_wa, ld_commit ? hbuf[10] : row_wd, f_slot, q8);
    opl_lutram #(8, 5) row9 (clk, row_clr || ld_commit || (w_row && wrow == 4'd9), row_wa, ld_commit ? hbuf[11] : row_wd, f_slot, q9);
    // level written with "direct" set: loaded into the tone at its next sample
    wire   [7:0] tld_w = reg_wdata[7:1] == 7'h7F ? 8'hFF : {1'b0, reg_wdata[7:1]};
    opl_lutram #(8, 5) rtld (clk, w_row && wrow == 4'd3 && reg_wdata[0], wslot, tld_w, f_slot, qtld);

    // value written, for the read back
    logic  [7:0] shadow [256];
    logic  [7:0] shadow_q;
    wire   [7:0] sh_addr = (sh_cnt == 3'd0 ? 8'd128 : sh_cnt == 3'd1 ? 8'd152 : sh_cnt == 3'd2 ? 8'd176 :
                            sh_cnt == 3'd3 ? 8'd200 : 8'd224) + {3'b000, ld_slot};
    always_ff @(posedge clk) begin
        if (init)        shadow[init_cnt] <= init_cnt == 8'hF8 ? 8'h1B : 8'd0;    // FM mix level -9 dB
        else if (sh_run) shadow[sh_addr]  <= hbuf[4'd7 + {1'b0, sh_cnt}];
        else if (w_en)   shadow[reg_addr] <= reg_addr == 8'h03 ? {2'b00, reg_wdata[5:0]} : reg_wdata;
        shadow_q <= shadow[reg_addr];
    end
    assign reg_rdata = reg_addr == 8'h02 ? {3'b001, reg2} :
                       reg_addr == 8'h06 ? (reg2[0] ? rd_buf : 8'hFF) : shadow_q;

    // ------------------------------------------------------------------ tone state
    typedef struct packed {
        logic [15:0] sp;                    // fraction of the position
        logic [15:0] pos;
        logic  [9:0] env;
        logic  [2:0] egs;
        logic [17:0] lfo;
        logic  [7:0] tl;
        logic        kon;                   // key on seen
    } tone_t;
    tone_t       st_q, st_d;
    logic        st_we;
    wire  [71:0] st_qv;
    wire  [71:0] st_init = {16'd0, 16'd0, MAX_ATT, EG_OFF, 18'd0, 8'd0, 1'b0};
    wire   [4:0] st_wa   = init ? init_cnt[4:0] : f_slot;
    opl_lutram #(72, 5) rst (clk, row_clr || st_we, st_wa, init ? st_init : st_d, f_slot, st_qv);
    assign st_q = tone_t'(st_qv);

    // header: sample format and start for the memory side, loop and (negated) end for both
    logic  [4:0] m_slot;
    wire  [31:0] hf_q;
    wire  [55:0] hm_q;
    wire   [4:0] h_wa = init ? init_cnt[4:0] : ld_slot;
    wire  [55:0] h_wd = init ? 56'd0 : {hbuf[0][7:6], hbuf[0][5:0], hbuf[1], hbuf[2], hbuf[3], hbuf[4], hbuf[5], hbuf[6]};
    opl_lutram #(32, 5) rhf (clk, row_clr || ld_commit, h_wa, h_wd[31:0], f_slot, hf_q);
    opl_lutram #(56, 5) rhm (clk, row_clr || ld_commit, h_wa, h_wd,       m_slot, hm_q);
    wire  [15:0] f_loop  = hf_q[31:16], f_end = hf_q[15:0];
    wire   [1:0] m_bits  = hm_q[55:54];
    wire  [21:0] m_start = hm_q[53:32];
    wire  [15:0] m_loop  = hm_q[31:16], m_end = hm_q[15:0];

    // samples at the position (s0) and at the next one (s1), position held in s1
    logic        s0_we, s1_we;
    logic [15:0] s0_d, s1_d, s1_pos_d;
    wire  [15:0] s0_q, s1_q, s1m_q, c1pos_q, posm_q;
    opl_lutram #(16, 5) rs0  (clk, s0_we, m_slot, s0_d, f_slot, s0_q);
    opl_lutram #(16, 5) rs1  (clk, s1_we, m_slot, s1_d, f_slot, s1_q);
    opl_lutram #(16, 5) rs1m (clk, s1_we, m_slot, s1_d, m_slot, s1m_q);
    opl_lutram #(16, 5) rc1p (clk, s1_we, m_slot, s1_pos_d, m_slot, c1pos_q);
    opl_lutram #(16, 5) rpos (clk, row_clr || st_we, st_wa, init ? 16'd0 : st_d.pos, m_slot, posm_q);

    // ------------------------------------------------------------------ frame
    logic        f_run;
    logic  [1:0] f_step;
    logic [14:0] eg_cnt;
    logic  [3:0] tl_cnt;                    // eg_cnt % 9
    logic  [1:0] tl_step;                   // (eg_cnt / 9) % 3
    logic        l_kon, l_wave, l_tl, l_hold;   // events and state of the tone, latched at step 0

    wire   [9:0] r_fn    = {q2[2:0], q1[7:1]};
    wire signed [3:0] r_oct = q2[7:4];
    wire         r_prvb  = q2[3];
    wire   [7:0] r_tld   = q3[7:1] == 7'h7F ? 8'hFF : {1'b0, q3[7:1]};
    wire         r_keyon = q4[7], r_damp = q4[6], r_lfoff = q4[5];
    wire   [3:0] r_pan   = q4[4] ? 4'd8 : q4[3:0];                 // DO1 output: not connected
    wire   [2:0] r_lfo   = q5[5:3], r_vib = q5[2:0], r_am = q9[2:0];
    wire   [3:0] r_ar    = q6[7:4], r_d1r = q6[3:0], r_dl = q7[7:4], r_d2r = q7[3:0];
    wire   [3:0] r_rc    = q8[7:4], r_rr = q8[3:0];
    wire   [9:0] dl_val  = r_dl == 4'd15 ? 10'h3E0 : {1'b0, r_dl, 5'b00000};

    wire         restart = l_kon || l_wave;
    wire   [7:0] tl_e    = l_tl ? qtld : st_q.tl;
    wire   [2:0] egs_e   = (st_q.kon && ~r_keyon) ? EG_REL : st_q.egs;
    wire         play    = ~restart && ~l_hold && egs_e != EG_OFF;

    // rate of an envelope phase: 4 * value + rate correction (octave + RC, F-number bit 9);
    // damping and pseudo reverb replace the rate of the decay phases
    function automatic logic [5:0] eg_rate(input logic [3:0] val, input logic [3:0] oct,
                                           input logic [3:0] rc, input logic fn9);
        logic signed [5:0] t;
        logic        [3:0] c;
        logic        [6:0] r;
        t = {{2{oct[3]}}, oct} + {2'b00, rc};
        c = t[5] ? 4'd0 : t > 6'sd15 ? 4'd15 : t[3:0];
        r = {1'b0, val, 2'b00} + (rc == 4'd15 ? 7'd0 : {2'b00, c, 1'b0} + {6'd0, fn9});
        eg_rate = val == 4'd0 ? 6'd0 : val == 4'd15 ? 6'd63 : r[6] ? 6'd63 : r[5:0];
    endfunction

    wire   [5:0] rate_att = eg_rate(r_ar, q2[7:4], r_rc, r_fn[9]);
    wire   [3:0] dec_val  = egs_e == EG_DEC ? r_d1r : egs_e == EG_SUS ? r_d2r : r_rr;
    wire   [5:0] rate_dec = r_damp ? (st_q.env < 10'h080 ? 6'd48 : 6'd63) :
                            (r_prvb && st_q.env >= 10'h0C0) ? 6'd20 : eg_rate(dec_val, q2[7:4], r_rc, r_fn[9]);
    wire   [5:0] rate     = egs_e == EG_ATT ? rate_att : rate_dec;
    wire   [3:0] eg_sh    = rate < 6'd48 ? 4'd12 - rate[5:2] : 4'd0;
    wire  [14:0] eg_low   = eg_cnt & ~(15'h7FFF << eg_sh);
    wire  [14:0] eg_shf   = eg_cnt >> eg_sh;
    wire   [3:0] eg_row   = rate < 6'd4 ? 4'd14 : rate < 6'd52 ? {2'b00, rate[1:0]} :
                            rate < 6'd56 ? {2'b01, rate[1:0]} : rate < 6'd60 ? {2'b10, rate[1:0]} : 4'd12;
    wire   [3:0] eg_i     = eg_inc(eg_row, eg_shf[2:0]);
    wire         eg_fire  = eg_low == 15'd0;
    wire signed [10:0] env_m = -{1'b0, st_q.env} - 11'sd1;         // ~env
    wire signed [15:0] att_p = env_m * $signed({1'b0, eg_i});
    wire signed [11:0] env_a = {2'b00, st_q.env} + att_p[15:4];    // attack: env + (~env * inc >> 4)
    wire        [10:0] env_i = {1'b0, st_q.env} + {7'd0, eg_i};

    logic  [9:0] env_n;
    logic  [2:0] egs_n;
    always_comb begin
        env_n = st_q.env;
        egs_n = egs_e;
        case (egs_e)
            EG_ATT: if (rate_att != 6'd63 && eg_fire) begin
                env_n = env_a[9:0];
                if (env_a <= 12'sd0) begin
                    env_n = 10'd0;
                    egs_n = r_dl != 4'd0 ? EG_DEC : EG_SUS;
                end
            end
            EG_DEC: if (eg_fire) begin
                env_n = env_i[9:0];
                if (env_i >= {1'b0, dl_val}) egs_n = env_i < {1'b0, MAX_ATT} ? EG_SUS : EG_OFF;
            end
            EG_SUS, EG_REL: if (eg_fire) begin
                env_n = env_i[9:0];
                if (env_i >= {1'b0, MAX_ATT}) begin env_n = MAX_ATT; egs_n = EG_OFF; end
            end
            default: ;
        endcase
    end

    // LFO: tremolo into the envelope level, vibrato into the pitch
    wire         lfo_on  = ~r_lfoff;
    wire   [6:0] am_tri  = st_q.lfo[17] ? ~st_q.lfo[16:10] : st_q.lfo[16:10];
    wire  [14:0] am_p    = am_tri * am_depth(r_am);
    wire  [10:0] env_am  = {1'b0, st_q.env} + ((lfo_on && r_am != 3'd0) ? {3'b000, am_p[14:7]} : 11'd0);
    wire   [9:0] env_out = env_am >= {1'b0, MAX_ATT} ? MAX_ATT : env_am[9:0];
    wire   [3:0] vib_m   = st_q.lfo[16] ? ~st_q.lfo[15:12] : st_q.lfo[15:12];
    logic  [5:0] vib_v;                     // |lfo| * depth / 12
    always_comb begin
        case (r_vib)
            3'd0: vib_v = 6'd0;
            3'd1: vib_v = {3'd0, div3(vib_m) >> 1};
            3'd2: vib_v = {4'd0, vib_m[3:2]};
            3'd3: vib_v = {3'd0, div3(vib_m)};
            3'd4: vib_v = {3'd0, vib_m[3:1]};
            3'd5: vib_v = {2'd0, vib_m};
            3'd6: vib_v = {1'b0, vib_m, 1'b0};
            3'd7: vib_v = {vib_m, 2'b00};
        endcase
    end
    wire  [11:0] fn_v    = {2'b01, r_fn} + (~lfo_on ? 12'd0 : st_q.lfo[17] ? -{6'd0, vib_v} : {6'd0, vib_v});
    wire  [26:0] step_s  = {15'd0, fn_v} << {~r_oct[3], r_oct[2:0]};   // << (8 + octave); octave -8: tone stands
    wire  [23:0] step    = r_oct == 4'sh8 ? 24'd0 : step_s[26:3];

    // position: over the end back by the loop length
    wire  [24:0] sp_sum  = {9'd0, st_q.sp} + {1'b0, step};
    wire  [15:0] pos_a   = st_q.pos + {7'd0, sp_sum[24:16]};
    wire  [16:0] pos_e   = {1'b0, pos_a} + {1'b0, f_end};
    wire  [15:0] pos_n   = sp_sum[24:16] == 9'd0 ? st_q.pos : pos_e[16] ? pos_e[15:0] + f_loop : pos_a;

    // level ramp: down 1 step in 27 samples, up 1 step in 13.5
    wire   [7:0] tl_n    = tl_cnt != 4'd0 ? tl_e :
                           tl_step == 2'd0 ? (tl_e < r_tld ? tl_e + 8'd1 : tl_e) :
                                             (tl_e > r_tld ? tl_e - 8'd1 : tl_e);
    wire  [17:0] lfo_n   = ~lfo_on ? 18'd0 : st_q.lfo + {12'd0, lfo_step(r_lfo)};

    always_comb begin
        st_d = st_q;
        st_d.kon = r_keyon;
        st_d.egs = egs_e;
        st_d.tl  = tl_e;
        st_d.lfo = ~lfo_on ? 18'd0 : st_q.lfo;
        if (restart) begin
            st_d.sp  = 16'd0;
            st_d.pos = 16'd0;
            if (l_kon) begin
                st_d.env = rate_att != 6'd63 ? MAX_ATT : 10'd0;
                st_d.egs = rate_att != 6'd63 ? EG_ATT : r_dl != 4'd0 ? EG_DEC : EG_SUS;
                if (~r_keyon) st_d.egs = EG_REL;        // key on and off before this sample
            end
        end else if (~l_hold) begin
            if (egs_e != EG_OFF) begin
                st_d.sp  = sp_sum[15:0];
                st_d.pos = pos_n;
            end
            st_d.env = env_n;
            st_d.egs = egs_n;
            st_d.tl  = tl_n;
            st_d.lfo = lfo_n;
        end
    end

    // output: interpolation, envelope, level, panning; one multiplier
    logic signed [17:0] mul_a, mul_b;
    logic signed [35:0] prod;
    wire  signed [16:0] s_diff = {s1_q[15], s1_q} - {s0_q[15], s0_q};
    wire  signed [17:0] s_int  = {{2{s0_q[15]}}, s0_q} + prod[33:16];
    always_comb begin
        case (f_step)
            2'd0:    begin mul_a = {s_diff[16], s_diff};        mul_b = {2'b00, st_q.sp}; end
            2'd1:    begin mul_a = s_int;                        mul_b = {2'b00, vol_f(env_out)}; end
            default: begin mul_a = {{2{prod[30]}}, prod[30:15]}; mul_b = {2'b00, vol_f({tl_e, 2'b00})}; end
        endcase
    end
    wire signed [20:0] smp   = play ? {{5{prod[30]}}, prod[30:15]} : 21'sd0;
    wire         [2:0] pan_l = r_pan <= 4'd6 ? r_pan[2:0] : r_pan <= 4'd8 ? 3'd7 : 3'd0;
    wire         [4:0] pan_x = 5'd16 - {1'b0, r_pan};
    wire         [2:0] pan_r = r_pan <= 4'd7 ? 3'd0 : r_pan <= 4'd9 ? 3'd7 : pan_x[2:0];
    logic signed [20:0] acc_l, acc_r;
    wire signed  [20:0] acc_l_n = acc_l + gain8(smp, pan_l);
    wire signed  [20:0] acc_r_n = acc_r + gain8(smp, pan_r);

    // ------------------------------------------------------------------ memory side
    typedef enum logic [3:0] {M_IDLE, M_BYTE, M_BYTE_W, M_S_CALC, M_S_GET, M_S_WAIT,
                              M_LD, M_LD_COMMIT, M_MW, M_PF} mstate_t;
    mstate_t     m_state = M_IDLE, m_ret;
    logic  [4:0] m_scan;
    logic        m_abort, m_second, m_have_hi, m_have_lo;
    logic [15:0] m_p0, m_p1;
    logic  [3:0] ld_i;
    logic [21:0] bg_addr;
    logic  [7:0] bg_q, m_hi, m_lo;
    logic        wc_v;                      // last word read: of the tone being served, or of the
    logic [20:0] wc_tag, rq_tag;            // header / memory register access
    logic [15:0] wc;
    logic        wcs_we;                    // the word goes back to the tone
    wire  [36:0] wcs_q;
    opl_lutram #(37, 5) rwc (clk, wcs_we, m_slot, {wc_tag, wc}, m_slot, wcs_q);

    // address map: ROM below 200000h; RAM above it, or with memory type 1 its first 512 kB at 380000h
    function automatic logic [22:0] mem_map(input logic [21:0] a, input logic typ,      // {mapped, image address}
                                            input logic [4:0] chunks);
        logic [3:0] c;
        logic       ok;
        c  = typ ? a[20:17] - 4'd12 : a[20:17];
        ok = ~a[21] || ((~typ || a[20:19] == 2'b11) && {1'b0, c} < chunks);
        mem_map = {ok, a[21], a[21] ? c : a[20:17], a[16:0]};
    endfunction
    wire  [22:0] bg_map  = mem_map(bg_addr, reg2[1], ram_chunks);
    wire         wc_hit  = wc_v && wc_tag == bg_addr[21:1];
    wire  [22:0] mw_map  = mem_map(mw_addr, reg2[1], ram_chunks);

    // sample at position p: address of the high byte and of the byte with the low bits
    wire  [15:0] m_p     = m_second ? m_p1 : m_p0;
    wire  [21:0] p12     = {6'd0, m_p[15:1], 1'b0} + {7'd0, m_p[15:1]};
    wire  [21:0] a_hi    = m_bits == 2'd0 ? m_start + {6'd0, m_p} :
                           m_bits == 2'd1 ? m_start + p12 + {20'd0, m_p[0], 1'b0} :
                                            m_start + {5'd0, m_p, 1'b0};
    wire  [21:0] a_lo    = m_bits == 2'd1 ? m_start + p12 + 22'd1 : a_hi + 22'd1;
    wire  [22:0] hi_map  = mem_map(a_hi, reg2[1], ram_chunks);
    wire  [22:0] lo_map  = mem_map(a_lo, reg2[1], ram_chunks);
    wire         hi_ok   = m_have_hi || ~hi_map[22] || (wc_v && wc_tag == a_hi[21:1]) || m_bits == 2'd3;
    wire         lo_ok   = m_have_lo || ~lo_map[22] || (wc_v && wc_tag == a_lo[21:1]) || m_bits[0] == m_bits[1];
    wire   [7:0] hi_val  = m_have_hi ? m_hi : ~hi_map[22] ? 8'hFF : a_hi[0] ? wc[15:8] : wc[7:0];
    wire   [7:0] lo_val  = m_have_lo ? m_lo : ~lo_map[22] ? 8'hFF : a_lo[0] ? wc[15:8] : wc[7:0];
    wire  [15:0] m_smp   = m_bits == 2'd0 ? {hi_val, 8'h00} :
                           m_bits == 2'd1 ? {hi_val, m_p[0] ? lo_val[7:4] : lo_val[3:0], 4'h0} :
                           m_bits == 2'd2 ? {hi_val, lo_val} : 16'd0;
    wire  [15:0] np_a    = posm_q + 16'd1;
    wire  [16:0] np_e    = {1'b0, np_a} + {1'b0, m_end};
    wire  [15:0] np      = np_e[16] ? np_e[15:0] + m_loop : np_a;
    wire         m_reuse = v1[m_slot] && c1pos_q == posm_q;         // s1 is the sample of the new position
    wire  [21:0] ld_base = (ld_wave < 9'd384 || reg2[4:2] == 3'd0) ?
                               {10'd0, ld_wave, 3'b000} + {11'd0, ld_wave, 2'b00} :
                               {reg2[4:2], 19'd0} + {10'd0, ld_wave - 9'd384, 3'b000} + {11'd0, ld_wave - 9'd384, 2'b00};

    assign idle = ~busy && ~f_run && need == 24'd0 && m_state == M_IDLE;

    always_ff @(posedge clk) begin
        logic [23:0] need_n, hold_n, v1_n, wcv_n, ev_kon_n, ev_wave_n, ev_tl_n;
        need_n    = need;
        hold_n    = hold;
        v1_n      = v1;
        wcv_n     = wcv;
        ev_kon_n  = ev_kon;
        ev_wave_n = ev_wave;
        ev_tl_n   = ev_tl;

        st_we     <= 1'b0;
        out_valid <= 1'b0;
        late      <= 1'b0;
        ld_commit <= 1'b0;
        s0_we     <= 1'b0;
        s1_we     <= 1'b0;
        wcs_we    <= 1'b0;
        prod      <= mul_a * mul_b;

        // ---------------- memory side
        case (m_state)
            M_IDLE: begin
                if (mw_pend) begin
                    if (mw_map[22] && mw_map[21]) begin         // only the RAM is written
                        mem_req   <= 1'b1;
                        mem_we    <= 1'b1;
                        mem_addr  <= mw_map[21:0];
                        mem_wdata <= mw_data;
                        wcv_n     = '0;                         // any tone may hold that word
                        m_state   <= M_MW;
                    end else mw_pend <= 1'b0;
                end else if (ld_pend && ~sh_run) begin
                    ld_i    <= 4'd0;
                    bg_addr <= ld_base;
                    wc_v    <= 1'b0;
                    m_ret   <= M_LD;
                    m_state <= M_BYTE;
                end else if (pf_pend) begin
                    bg_addr <= memadr;
                    wc_v    <= 1'b0;
                    m_ret   <= M_PF;
                    m_state <= M_BYTE;
                end else if (need[m_scan]) begin
                    m_slot  <= m_scan;
                    m_abort <= 1'b0;
                    m_state <= M_S_CALC;
                end else m_scan <= m_scan == 5'd23 ? 5'd0 : m_scan + 5'd1;
            end

            // byte bg_addr -> bg_q, through the last word read
            M_BYTE: begin
                if (~bg_map[22]) begin
                    bg_q    <= 8'hFF;
                    m_state <= m_ret;
                end else if (wc_hit) begin
                    bg_q    <= bg_addr[0] ? wc[15:8] : wc[7:0];
                    m_state <= m_ret;
                end else begin
                    mem_req  <= 1'b1;
                    mem_we   <= 1'b0;
                    mem_addr <= bg_map[21:0];
                    m_state  <= M_BYTE_W;
                end
            end
            M_BYTE_W: if (mem_ack) begin
                mem_req <= 1'b0;
                wc      <= mem_rdata;
                wc_tag  <= bg_addr[21:1];
                wc_v    <= 1'b1;
                bg_q    <= bg_addr[0] ? mem_rdata[15:8] : mem_rdata[7:0];
                m_state <= m_ret;
            end

            // samples of tone m_slot. One further than last time: s1 becomes s0 and only s1 is
            // read. The last word read is kept with the tone, the next sample is often in it.
            M_S_CALC: begin
                m_p0      <= posm_q;
                m_p1      <= np;
                m_second  <= m_reuse;
                m_have_hi <= 1'b0;
                m_have_lo <= 1'b0;
                if (m_reuse) begin
                    s0_we <= 1'b1;
                    s0_d  <= s1m_q;
                end
                wc      <= wcs_q[15:0];
                wc_tag  <= wcs_q[36:16];
                wc_v    <= wcv[m_slot];
                m_state <= M_S_GET;
            end
            M_S_GET: begin
                if (hi_ok && lo_ok) begin
                    m_have_hi <= 1'b0;
                    m_have_lo <= 1'b0;
                    if (~m_second) begin
                        s0_we    <= 1'b1;
                        s0_d     <= m_smp;
                        m_second <= 1'b1;
                    end else begin
                        s1_we    <= 1'b1;
                        s1_d     <= m_smp;
                        s1_pos_d <= m_p1;
                        wcs_we   <= 1'b1;
                        if (~m_abort) begin
                            need_n[m_slot] = 1'b0;
                            hold_n[m_slot] = 1'b0;
                            v1_n[m_slot]   = 1'b1;
                            wcv_n[m_slot]  = wc_v;
                        end else
                            wcv_n[m_slot]  = 1'b0;
                        m_scan  <= m_slot == 5'd23 ? 5'd0 : m_slot + 5'd1;
                        m_state <= M_IDLE;
                    end
                end else begin
                    // keep the byte that is at hand, read the word of the other one
                    if (hi_ok)       begin m_hi <= hi_val; m_have_hi <= 1'b1; end
                    else if (lo_ok && m_bits != 2'd0) begin m_lo <= lo_val; m_have_lo <= 1'b1; end
                    mem_req  <= 1'b1;
                    mem_we   <= 1'b0;
                    mem_addr <= hi_ok ? lo_map[21:0] : hi_map[21:0];
                    rq_tag   <= hi_ok ? a_lo[21:1]   : a_hi[21:1];
                    m_state  <= M_S_WAIT;
                end
            end
            M_S_WAIT: if (mem_ack) begin
                mem_req <= 1'b0;
                wc      <= mem_rdata;
                wc_tag  <= rq_tag;
                wc_v    <= 1'b1;
                m_state <= M_S_GET;
            end

            // wave header: 12 bytes
            M_LD: begin
                hbuf[ld_i] <= bg_q;
                ld_i       <= ld_i + 4'd1;
                bg_addr    <= bg_addr + 22'd1;
                m_state    <= ld_i == 4'd11 ? M_LD_COMMIT : M_BYTE;
            end
            M_LD_COMMIT: if (~(f_run && f_slot == ld_slot)) begin
                ld_commit <= 1'b1;
                sh_run    <= 1'b1;
                sh_cnt    <= 3'd0;
                m_state   <= M_IDLE;
            end

            M_MW: if (mem_ack) begin
                mem_req <= 1'b0;
                mem_we  <= 1'b0;
                mw_pend <= 1'b0;
                m_state <= M_IDLE;
            end
            M_PF: begin
                rd_buf  <= bg_q;
                pf_pend <= 1'b0;
                m_state <= M_IDLE;
            end
            default: m_state <= M_IDLE;
        endcase

        // header of ld_slot is in place: the tone starts again, with a new envelope when keyed on
        if (ld_commit) begin
            if (keyon_r[ld_slot]) ev_kon_n[ld_slot]  = 1'b1;
            else                  ev_wave_n[ld_slot] = 1'b1;
        end
        if (sh_run) begin
            sh_cnt <= sh_cnt + 3'd1;
            if (sh_cnt == 3'd4) begin
                sh_run  <= 1'b0;
                ld_pend <= 1'b0;
            end
        end

        // ---------------- frame
        if (smp_tick && ~init && ~ild_run && ~f_run) begin
            eg_cnt  <= eg_cnt + 15'd1;
            tl_cnt  <= tl_cnt == 4'd8 ? 4'd0 : tl_cnt + 4'd1;
            if (tl_cnt == 4'd8) tl_step <= tl_step == 2'd2 ? 2'd0 : tl_step + 2'd1;
            acc_l   <= '0;
            acc_r   <= '0;
            f_slot  <= '0;
            f_step  <= '0;
            f_run   <= 1'b1;
        end
        if (f_run) begin
            f_step <= f_step + 2'd1;
            case (f_step)
                2'd0: begin
                    l_kon  <= ev_kon[f_slot];
                    l_wave <= ev_wave[f_slot];
                    l_tl   <= ev_tl[f_slot];
                    l_hold <= hold[f_slot];
                    late   <= need[f_slot] && ~hold[f_slot] && ~ev_kon[f_slot] && ~ev_wave[f_slot] &&
                              st_q.egs != EG_OFF;
                end
                2'd2: st_we <= 1'b1;                    // written at the end of step 3
                2'd3: begin
                    acc_l <= acc_l_n;
                    acc_r <= acc_r_n;
                    if (l_kon)  ev_kon_n[f_slot]  = 1'b0;
                    if (l_wave) ev_wave_n[f_slot] = 1'b0;
                    if (l_tl)   ev_tl_n[f_slot]   = 1'b0;
                    if (restart) begin
                        need_n[f_slot] = 1'b1;
                        hold_n[f_slot] = 1'b1;
                        v1_n[f_slot]   = 1'b0;
                    end else if (~l_hold && st_d.pos != st_q.pos)
                        need_n[f_slot] = 1'b1;
                    // the tone moved while its samples were being read: read again
                    if ((restart || st_d.pos != st_q.pos) && m_slot == f_slot) m_abort <= 1'b1;
                    f_slot <= f_slot + 5'd1;
                    if (f_slot == 5'd23) begin
                        f_run     <= 1'b0;
                        out_l     <= gain8(acc_l_n, mix_pcm[2:0]);
                        out_r     <= gain8(acc_r_n, mix_pcm[5:3]);
                        out_valid <= 1'b1;
                    end
                end
                default: ;
            endcase
        end

        // ---------------- register writes
        if (w_en) begin
            if (rslot) begin
                case (wrow)
                    4'd0: begin
                        ld_pend <= 1'b1;
                        ld_slot <= wslot;
                        ld_wave <= {wave8[wslot], reg_wdata};
                    end
                    4'd1: wave8[wslot] <= reg_wdata[0];
                    4'd3: if (reg_wdata[0]) ev_tl_n[wslot] = 1'b1;
                    4'd4: begin
                        keyon_r[wslot] <= reg_wdata[7];
                        if (reg_wdata[7] && ~keyon_r[wslot]) ev_kon_n[wslot] = 1'b1;
                    end
                    default: ;
                endcase
            end else begin
                case (reg_addr)
                    8'h02: begin
                        reg2    <= reg_wdata[4:0];
                        pf_pend <= 1'b1;
                        if (reg_wdata[1] != reg2[1]) begin  // other address map: read everything again
                            wc_v    <= 1'b0;
                            wcv_n   = '0;
                            need_n  = '1;
                            v1_n    = '0;
                            m_abort <= 1'b1;
                        end
                    end
                    8'h03: reg3 <= reg_wdata[5:0];
                    8'h04: reg4 <= reg_wdata;
                    8'h05: begin memadr <= {reg3, reg4, reg_wdata}; pf_pend <= 1'b1; end
                    8'h06: if (reg2[0]) begin
                        mw_pend <= 1'b1;
                        mw_addr <= memadr;
                        mw_data <= reg_wdata;
                        memadr  <= memadr + 22'd1;
                        pf_pend <= 1'b1;
                    end
                    8'hF8: mix_fm  <= reg_wdata[5:0];
                    8'hF9: mix_pcm <= reg_wdata[5:0];
                    default: ;
                endcase
            end
        end
        if (reg_rd && ~init && ~ild_run && reg_addr == 8'h06 && reg2[0]) begin
            memadr  <= memadr + 22'd1;
            pf_pend <= 1'b1;
        end

        need    <= need_n;
        hold    <= hold_n;
        v1      <= v1_n;
        wcv     <= wcv_n;
        ev_kon  <= ev_kon_n;
        ev_wave <= ev_wave_n;
        ev_tl   <= ev_tl_n;

        // ---------------- reset: memories, then the header of wave 0 into every tone
        if (ild_run && ~ld_pend && ~sh_run) begin
            if (ild_cnt == 5'd24) ild_run <= 1'b0;
            else begin
                ld_pend <= 1'b1;
                ld_slot <= ild_cnt;
                ld_wave <= 9'd0;
                ild_cnt <= ild_cnt + 5'd1;
            end
        end
        if (init) begin
            init_cnt <= init_cnt + 8'd1;
            if (init_cnt == 8'd255) begin
                init    <= 1'b0;
                ild_run <= 1'b1;
            end
            ild_cnt <= '0;
            m_state <= M_IDLE; m_scan <= '0; m_slot <= '0;
            mem_req <= 1'b0; mem_we <= 1'b0; wc_v <= 1'b0;
            ld_pend <= 1'b0; mw_pend <= 1'b0; pf_pend <= 1'b0; sh_run <= 1'b0;
            f_run <= 1'b0; f_slot <= '0; f_step <= '0;
            eg_cnt <= '0; tl_cnt <= '0; tl_step <= '0;
            out_l <= '0; out_r <= '0;
            reg2 <= '0; reg3 <= '0; reg4 <= '0; memadr <= '0; rd_buf <= 8'hFF;
            mix_fm <= 6'h1B; mix_pcm <= '0;
            keyon_r <= '0; wave8 <= '0;
            need <= '0; hold <= '0; v1 <= '0; wcv <= '0; ev_kon <= '0; ev_wave <= '0; ev_tl <= '0;
        end
        if (reset) begin
            init     <= 1'b1;
            init_cnt <= '0;
            ild_run  <= 1'b0;
        end
    end

endmodule
