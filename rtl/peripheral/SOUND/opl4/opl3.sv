// OPL3 (YMF262) FM synthesis
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

// One operator data path stepped through the 36 operators of a sample, 4 clk each. The
// arithmetic follows the chip as described by Nuked OPL3 1.8 (same sample values, see
// doc/moonsound.md and tb/run_opl3.sh); timers and status as openMSX YMF262.

// LUT RAM: synchronous write, asynchronous read
module opl_lutram #(parameter W = 8, parameter A = 6) (
    input                clk,
    input                we,
    input        [A-1:0] wa,
    input        [W-1:0] d,
    input        [A-1:0] ra,
    output       [W-1:0] q
);
    (* ramstyle = "MLAB, no_rw_check" *) logic [W-1:0] mem [2**A];
    always_ff @(posedge clk) if (we) mem[wa] <= d;
    assign q = mem[ra];
endmodule

module opl3 (
    input                      clk,
    input                      reset,
    input                      smp_tick,    // one clk: start of a sample
    input                      wr,          // one clk: register write
    input                [8:0] wr_addr,     // {array, register}
    input                [7:0] wr_data,
    input                [8:0] rd_addr,     // read back of the value written, rd_data one clk later
    output logic         [7:0] rd_data,
    output               [7:0] status,      // 7 IRQ, 6 timer 1, 5 timer 2
    output                     newm,        // register 105h bit 0: OPL3 mode
    output                     new2,        // register 105h bit 1 (OPL4)
    output                     ready,       // 0 while the registers are cleared after reset
    output logic signed [15:0] out_a,       // channel A (left) and B (right) of the sample
    output logic signed [15:0] out_b,
    output logic               out_valid    // one clk
);

    // values of the OPL2 ROMs (log sine, exponent): entry i at [12*i +: 12] / [11*i +: 11]
    localparam logic [3071:0] LOGSIN = 3072'h00000000000000000000000000100100100100100100100200200200200300300300400400400500500500600600700700700800800900900a00a00b00c00c00d00d00e00f00f01001101101201301401401501601701701801901a01b01c01d01e01f02002102202302402502602702802902a02b02d02e02f03003103303403503703803903b03c03e03f04004204304504604804a04b04d04e05005205305505705905b05c05e06006206406606806a06c06e07007207407607807a07d07f08108308608808a08d08f09209409709909c09f0a10a40a70a90ac0af0b20b50b80bb0be0c10c40c70ca0cd0d10d40d70db0de0e20e50e90ec0f00f40f80fb0ff10310710b10f11411811c12112512912e13313713c14114614b15015515b16016616b17117717c18218818f19519b1a21a91b01b71be1c51cd1d41dc1e41ec1f51fd20620f21822222c23624024b25626126d2792862932a02af2bd2cd2dc2ed2ff31132433934e36537e3983b53d33f541a4434714a64e452e58b6076c3859;
    localparam logic [2815:0] EXPROM = 2816'h80100e0340881703a08c1482d0660e41f8450961442a85b0c219c368730f21fc4288b12225c4e8a31522bc5a8bb18231c668d31b237c728eb1e23dc7e9052164448b91d2464a49893727a50ca49512ae574b196b2e25dcbe985316644cc99f34a6b4d99b938271ce79d53b678cf49f13ee7fd02a0d42686510a2945e8dd1ea4549694d2ca614d29bd3ba7d50aa3549a9b546aa558ab9582b1d67ad75beb9576af55fac0d85b13636c8d95b33672d05a4b516b2d85b4b716f2e05c4b91732e85d4bb1772f05e4bd17b2f85f5bf37f700e05c1383b09616c3587b11e27c578c31a638c7990722e49c9d94b2be5bcbf9933466dce39db3d67fd07a2346691d2ba6b4f6a3d51ab358eb5d75aff626c8d9bb4b6b6dbdc1b9774eeede7be37ef02e0dc2f88715e35c7f92729e5dccf9c73de85d1fa6751eadd6fb0765ed5dc3baf7aeffe13c578ff29e67cffa4f53ebbda7b9f7ff13e4fcffa9f6beffe4fd5fbffaffa;

    // the two ROMs: address = table index, output registered
    (* romstyle = "MLAB" *) logic [11:0] logsin_rom [256];
    (* romstyle = "MLAB" *) logic [10:0] exp_rom [256];
    initial begin
        for (int i = 0; i < 256; i++) begin
            logsin_rom[i] = LOGSIN[12 * i +: 12];
            exp_rom[i]    = EXPROM[11 * i +: 11];
        end
    end

    localparam logic [1:0] GEN_ATT = 2'd0, GEN_DEC = 2'd1, GEN_SUS = 2'd2, GEN_REL = 2'd3;
    localparam logic [1:0] MOD_ZERO = 2'd0, MOD_FB = 2'd1, MOD_PREV = 2'd2;

    // ------------------------------------------------------------------ registers
    logic        init = 1'b1;               // clears the memories, 512 clk
    logic  [8:0] init_cnt = '0;
    assign ready = ~init;

    logic        newm_r, new2_r, nts, dam, dvb;
    logic  [5:0] rhy, conn4;
    logic [17:0] con, cha, chb;
    logic [35:0] key_norm;
    logic  [7:0] t1_val, t2_val;
    logic        st1, st2;
    logic  [1:0] tflag, tmask;              // bit 1 timer 1, bit 0 timer 2
    logic        irq;
    assign newm   = newm_r;
    assign new2   = new2_r;
    assign status = {irq, tflag, 5'b00000};

    // OPL2 mode: array 1 is array 0, except register 105h
    wire         w_en  = wr && ~init;
    wire   [8:0] wa    = (~newm_r && wr_addr != 9'h105) ? {1'b0, wr_addr[7:0]} : wr_addr;
    wire   [4:0] wop   = wa[4:0];
    wire         wop_ok = wop[2:0] < 3'd6 && wop[4:3] != 2'd3;
    wire   [5:0] wslot = (wa[8] ? 6'd18 : 6'd0) + {1'b0, wop[4:3], 2'b00} + {2'b00, wop[4:3], 1'b0} + {3'b000, wop[2:0]};
    wire         wch_ok = wa[3:0] < 4'd9;
    wire   [4:0] wch   = (wa[8] ? 5'd9 : 5'd0) + {1'b0, wa[3:0]};
    wire         w_slot = w_en && wop_ok;
    wire         w_20   = w_slot && wa[7:5] == 3'b001;
    wire         w_40   = w_slot && wa[7:5] == 3'b010;
    wire         w_60   = w_slot && wa[7:5] == 3'b011;
    wire         w_80   = w_slot && wa[7:5] == 3'b100;
    wire         w_e0   = w_slot && wa[7:5] == 3'b111;
    wire         w_bd   = w_en && wa == 9'h0BD;
    wire         w_a0   = w_en && wa[7:4] == 4'hA && wch_ok;
    wire         w_b0   = w_en && wa[7:4] == 4'hB && wch_ok;
    wire         w_c0   = w_en && wa[7:4] == 4'hC && wch_ok;

    // value written, for the read back
    logic [7:0] shadow [512];
    always_ff @(posedge clk) begin
        if (init || w_en) shadow[init ? init_cnt : wa] <= init ? 8'd0 : wr_data;
        rd_data <= shadow[rd_addr];
    end

    // operator and channel registers
    wire        ram_clr = init && init_cnt[8:6] == 3'd0;
    wire  [5:0] sl_wa   = init ? init_cnt[5:0] : wslot;
    wire  [4:0] ch_wa   = init ? init_cnt[4:0] : wch;
    wire  [7:0] reg_d   = init ? 8'd0 : wr_data;
    logic [5:0] sidx;                       // operator being processed
    wire  [4:0] ch_own, ch_frq;             // its channel, channel of its frequency
    wire  [7:0] q20, q40, q60, q80, qa0;
    wire  [2:0] qe0, qfb;
    wire  [4:0] qb0;
    opl_lutram #(8, 6) r20 (clk, ram_clr || w_20, sl_wa, reg_d, sidx, q20);
    opl_lutram #(8, 6) r40 (clk, ram_clr || w_40, sl_wa, reg_d, sidx, q40);
    opl_lutram #(8, 6) r60 (clk, ram_clr || w_60, sl_wa, reg_d, sidx, q60);
    opl_lutram #(8, 6) r80 (clk, ram_clr || w_80, sl_wa, reg_d, sidx, q80);
    // waveforms 4-7 only when written in OPL3 mode
    opl_lutram #(3, 6) re0 (clk, ram_clr || w_e0, sl_wa, {reg_d[2] & newm_r, reg_d[1:0]}, sidx, qe0);
    opl_lutram #(8, 5) ra0 (clk, ram_clr || w_a0, ch_wa, reg_d,      ch_frq, qa0);
    opl_lutram #(5, 5) rb0 (clk, ram_clr || w_b0, ch_wa, reg_d[4:0], ch_frq, qb0);
    opl_lutram #(3, 5) rc0 (clk, ram_clr || w_c0, ch_wa, reg_d[3:1], ch_own, qfb);

    // key on of a channel reaches its operators; in a 4 operator pair only through the first
    // channel, which then keys all four
    wire [2:0] w_conn   = wa[8] ? conn4[5:3] : conn4[2:0];
    wire       w_second = wa[3:0] >= 4'd3 && wa[3:0] < 4'd6 && w_conn[wa[1:0] == 2'd3 ? 2'd0 : wa[1:0] + 2'd1];
    genvar gs;
    generate
        for (gs = 0; gs < 36; gs++) begin : g_key
            localparam int P   = gs % 18;                       // operator in its array
            localparam int ROW = P / 3;
            localparam int COL = P % 3;
            localparam int CH  = (gs / 18) * 9 + (ROW / 2) * 3 + COL;
            wire own  = wch == CH;
            wire pair = ROW >= 2 && ROW < 4 && wch == CH - 3 && conn4[(gs / 18) * 3 + COL];
            always_ff @(posedge clk) begin
                if (init) key_norm[gs] <= 1'b0;
                else if (w_b0 && ((own && ~w_second) || pair)) key_norm[gs] <= wr_data[5];
            end
        end
    endgenerate

    // timers: tick = 4 (timer 1) / 16 (timer 2) samples, counted from the start
    logic [3:0] t1_pre, t2_pre;
    logic [8:0] t1_cnt, t2_cnt;
    logic       smp_end;                    // one clk after the last operator

    always_ff @(posedge clk) begin
        logic [1:0] tf;
        tf = tflag;
        if (smp_end) begin
            if (st1) begin
                if (t1_pre == 4'd3) begin
                    t1_pre <= 4'd0;
                    if (t1_cnt == 9'd1) begin t1_cnt <= 9'd256 - {1'b0, t1_val}; tf[1] = 1'b1; end
                    else t1_cnt <= t1_cnt - 9'd1;
                end else t1_pre <= t1_pre + 4'd1;
            end
            if (st2) begin
                if (t2_pre == 4'd15) begin
                    t2_pre <= 4'd0;
                    if (t2_cnt == 9'd1) begin t2_cnt <= 9'd256 - {1'b0, t2_val}; tf[0] = 1'b1; end
                    else t2_cnt <= t2_cnt - 9'd1;
                end else t2_pre <= t2_pre + 4'd1;
            end
            if ((tf & tmask) != 2'b00) irq <= 1'b1;
        end

        if (w_en) begin
            case (wa)
                9'h002: t1_val <= wr_data;
                9'h003: t2_val <= wr_data;
                9'h004: begin
                    if (wr_data[7]) begin               // flags and IRQ off
                        tf  = 2'b00;
                        irq <= 1'b0;
                    end else begin
                        tmask <= ~wr_data[6:5];
                        tf    = tf & ~wr_data[6:5];     // masked flags are dropped
                        irq   <= tf != 2'b00;
                        st1   <= wr_data[0];
                        st2   <= wr_data[1];
                        if (wr_data[0] && ~st1) begin t1_pre <= 4'd0; t1_cnt <= 9'd256 - {1'b0, t1_val}; end
                        if (wr_data[1] && ~st2) begin t2_pre <= 4'd0; t2_cnt <= 9'd256 - {1'b0, t2_val}; end
                    end
                end
                9'h008: nts   <= wr_data[6];
                9'h104: conn4 <= wr_data[5:0];
                9'h105: begin newm_r <= wr_data[0]; new2_r <= wr_data[1]; end
                default: ;
            endcase
            if (w_bd) begin dam <= wr_data[7]; dvb <= wr_data[6]; rhy <= wr_data[5:0]; end
            if (w_c0) begin
                con[wch] <= wr_data[0];
                cha[wch] <= newm_r ? wr_data[4] : 1'b1;
                chb[wch] <= newm_r ? wr_data[5] : 1'b1;
            end
        end
        tflag <= tf;

        if (init) begin
            newm_r <= 1'b0; new2_r <= 1'b0; nts <= 1'b0; dam <= 1'b0; dvb <= 1'b0;
            rhy <= '0; conn4 <= '0; con <= '0; cha <= '1; chb <= '1;
            t1_val <= '0; t2_val <= '0; st1 <= 1'b0; st2 <= 1'b0;
            tflag <= '0; tmask <= '0; irq <= 1'b0;
        end
    end

    // ------------------------------------------------------------------ operator sequencer
    typedef enum logic [2:0] {S_IDLE, S_SLOT, S_MIXA, S_MIXB, S_END} state_t;
    state_t     state = S_IDLE;
    logic       bank;                       // sidx = 18 * bank + 3 * row + col
    logic [2:0] row;
    logic [1:0] col;
    logic [1:0] step;

    // channel of the operator and its role in the channel
    wire  [3:0] chl      = {row[2:1], 1'b0} + {2'b00, row[2:1]} + {2'b00, col};
    wire  [2:0] conn_b   = bank ? conn4[5:3] : conn4[2:0];
    wire  [8:0] con_b    = bank ? con[17:9] : con[8:0];
    wire        four     = row < 3'd4 && conn_b[col];          // operator of a 4 operator channel
    wire        drum     = ~bank && rhy[5] && row >= 3'd4;
    wire        con_f    = con_b[col];                          // 4 op: first / second channel
    wire        con_g    = con_b[{2'b00, col} + 4'd3];
    wire        con_own  = con_b[chl];
    assign      ch_own   = bank ? {1'b0, chl} + 5'd9 : {1'b0, chl};
    assign      ch_frq   = (four && row[1]) ? ch_own - 5'd3 : ch_own;
    wire  [4:0] ch_pan   = (four && ~row[1]) ? ch_own + 5'd3 : ch_own;

    logic [1:0] msel;                       // modulation input
    logic [1:0] wgt;                        // times the operator output goes to the mix
    always_comb begin
        msel = MOD_ZERO;
        wgt  = 2'd0;
        if (four) begin
            case (row[1:0])
                2'd0: begin msel = MOD_FB;                                 wgt = {1'b0, con_f}; end
                2'd1: begin msel = con_f ? MOD_ZERO : MOD_PREV;            wgt = {1'b0, ~con_f & con_g}; end
                2'd2: begin msel = (~con_f & con_g) ? MOD_ZERO : MOD_PREV; wgt = {1'b0, con_f & con_g}; end
                2'd3: begin msel = (con_f & con_g) ? MOD_ZERO : MOD_PREV;  wgt = 2'd1; end
            endcase
        end else if (drum) begin
            if (col != 2'd0) wgt = 2'd2;                                    // HH, SD, TOM, TC
            else if (~row[0]) msel = MOD_FB;                                // bass drum
            else begin msel = con_own ? MOD_ZERO : MOD_PREV; wgt = 2'd2; end
        end else begin
            if (~row[0]) begin msel = MOD_FB; wgt = {1'b0, con_own}; end
            else begin msel = con_own ? MOD_ZERO : MOD_PREV; wgt = 2'd1; end
        end
    end

    wire key_drum = rhy[5] && ((sidx == 6'd13 && rhy[0]) || (sidx == 6'd17 && rhy[1]) ||
                               (sidx == 6'd14 && rhy[2]) || (sidx == 6'd16 && rhy[3]) ||
                               ((sidx == 6'd12 || sidx == 6'd15) && rhy[4]));
    wire keyon    = key_norm[sidx] || key_drum;

    // operator state
    typedef struct packed {
        logic        [18:0] phase;
        logic         [8:0] rout;           // envelope level
        logic         [1:0] gen;
        logic signed [12:0] out;
        logic signed [12:0] prout;
    } opst_t;
    opst_t       st_q, st_d;
    logic        st_we;
    wire  [55:0] st_qv;
    opl_lutram #(56, 6) rst (clk, ram_clr || st_we, init ? init_cnt[5:0] : sidx,
                             init ? {19'd0, 9'h1FF, GEN_REL, 13'd0, 13'd0} : st_d, sidx, st_qv);
    assign st_q = opst_t'(st_qv);

    // global counters
    logic [15:0] timer;
    logic [35:0] eg_timer;
    logic        eg_timerrem, eg_state;
    logic  [3:0] eg_add;
    logic  [1:0] eg_timer_lo;
    logic  [7:0] tremolopos;
    logic  [6:0] tremolo;
    logic  [2:0] vibpos;
    logic [22:0] noise;
    logic        hh2, hh3, hh7, hh8, tc3, tc5;

    // ---- step 0: feedback, envelope
    wire        r_am   = q20[7], r_vib = q20[6], r_egt = q20[5], r_ksr = q20[4];
    wire  [3:0] r_mult = q20[3:0];
    wire  [1:0] r_ksl  = q40[7:6];
    wire  [5:0] r_tl   = q40[5:0];
    wire  [3:0] r_ar   = q60[7:4], r_dr = q60[3:0], r_rr = q80[3:0];
    wire  [4:0] r_sl   = q80[7:4] == 4'hF ? 5'h1F : {1'b0, q80[7:4]};
    wire  [9:0] fnum   = {qb0[1:0], qa0};
    wire  [2:0] block  = qb0[4:2];

    wire signed [13:0] fb_sum = st_q.prout + st_q.out;
    wire signed [13:0] fb_sh  = fb_sum >>> (4'd9 - {1'b0, qfb});
    wire signed [12:0] fbmod  = qfb == 3'd0 ? 13'sd0 : fb_sh[12:0];
    logic signed [12:0] hist1, hist2, hist3;   // outputs of the three operators before

    function automatic logic [6:0] kslrom(input logic [3:0] i);
        case (i)
            4'd0: kslrom = 7'd0;   4'd1: kslrom = 7'd32;  4'd2: kslrom = 7'd40;  4'd3: kslrom = 7'd45;
            4'd4: kslrom = 7'd48;  4'd5: kslrom = 7'd51;  4'd6: kslrom = 7'd53;  4'd7: kslrom = 7'd55;
            4'd8: kslrom = 7'd56;  4'd9: kslrom = 7'd58;  4'd10: kslrom = 7'd59; 4'd11: kslrom = 7'd60;
            4'd12: kslrom = 7'd61; 4'd13: kslrom = 7'd62; 4'd14: kslrom = 7'd63; default: kslrom = 7'd64;
        endcase
    endfunction

    wire        [9:0] ksl_a   = {1'b0, kslrom(fnum[9:6]), 2'b00};
    wire        [9:0] ksl_b   = {1'b0, 4'd8 - {1'b0, block}, 5'b00000};
    wire        [7:0] eg_ksl  = ksl_a < ksl_b ? 8'd0 : ksl_a[7:0] - ksl_b[7:0];
    wire        [7:0] ksl_v   = r_ksl == 2'd0 ? 8'd0 : r_ksl == 2'd1 ? {1'b0, eg_ksl[7:1]} :
                                r_ksl == 2'd2 ? {2'b00, eg_ksl[7:2]} : eg_ksl;
    wire       [10:0] eg_out  = {2'b00, st_q.rout} + {3'b000, r_tl, 2'b00} + {3'b000, ksl_v} +
                                (r_am ? {4'b0000, tremolo} : 11'd0);

    wire              eg_rst  = keyon && st_q.gen == GEN_REL;
    wire        [3:0] reg_rate = eg_rst ? r_ar :
                                 st_q.gen == GEN_ATT ? r_ar :
                                 st_q.gen == GEN_DEC ? r_dr :
                                 st_q.gen == GEN_SUS ? (r_egt ? 4'd0 : r_rr) : r_rr;
    wire        [3:0] ksv     = {block, nts ? fnum[8] : fnum[9]};
    wire        [3:0] ks      = r_ksr ? ksv : {2'b00, ksv[3:2]};
    wire        [6:0] rate    = {3'b000, ks} + {1'b0, reg_rate, 2'b00};
    wire        [3:0] rate_hi = rate[6] ? 4'hF : rate[5:2];
    wire        [1:0] rate_lo = rate[1:0];
    wire        [4:0] eg_shift = {1'b0, rate_hi} + {1'b0, eg_add};
    wire              incstep = rate_lo == 2'd1 ? eg_timer_lo == 2'd0 :
                                rate_lo == 2'd2 ? ~eg_timer_lo[0] :
                                rate_lo == 2'd3 ? eg_timer_lo != 2'd3 : 1'b0;
    logic       [2:0] shift;
    always_comb begin
        shift = 3'd0;
        if (reg_rate != 4'd0) begin
            if (rate_hi < 4'd12) begin
                if (eg_state) begin
                    case (eg_shift)
                        5'd12:   shift = 3'd1;
                        5'd13:   shift = {2'b00, rate_lo[1]};
                        5'd14:   shift = {2'b00, rate_lo[0]};
                        default: shift = 3'd0;
                    endcase
                end
            end else begin
                shift = {1'b0, rate_hi[1:0]} + {2'b00, incstep};
                if (shift[2]) shift = 3'd3;
                if (shift == 3'd0) shift = {2'b00, eg_state};
            end
        end
    end

    wire               eg_off  = st_q.rout[8:3] == 6'h3F;
    wire signed  [9:0] rout_inv = {1'b1, ~st_q.rout};                  // ~rout as a negative number
    logic        [8:0] rout_w, rout_n;
    logic signed [9:0] eg_inc;
    logic        [1:0] gen_n;
    always_comb begin
        rout_w = st_q.rout;
        if (eg_rst && rate_hi == 4'hF) rout_w = 9'd0;                  // instant attack
        if (st_q.gen != GEN_ATT && ~eg_rst && eg_off) rout_w = 9'h1FF;
        eg_inc = 10'sd0;
        gen_n  = st_q.gen;
        case (st_q.gen)
            GEN_ATT: begin
                if (st_q.rout == 9'd0) gen_n = GEN_DEC;
                else if (keyon && shift != 3'd0 && rate_hi != 4'hF) eg_inc = rout_inv >>> (3'd4 - shift);
            end
            GEN_DEC: begin
                if (st_q.rout[8:4] == r_sl) gen_n = GEN_SUS;
                else if (~eg_off && ~eg_rst && shift != 3'd0) eg_inc = 10'sd1 <<< (shift - 3'd1);
            end
            default: begin
                if (~eg_off && ~eg_rst && shift != 3'd0) eg_inc = 10'sd1 <<< (shift - 3'd1);
            end
        endcase
        rout_n = rout_w + eg_inc[8:0];
        if (eg_rst) gen_n = GEN_ATT;
        if (~keyon) gen_n = GEN_REL;
    end

    logic       [10:0] eg_out_r;
    logic        [8:0] rout_r;
    logic        [1:0] gen_r;
    logic              pg_rst_r;
    logic signed [12:0] mod_r;

    // ---- step 1: phase, waveform address
    function automatic logic [4:0] mult2(input logic [3:0] m);        // multiplier * 2
        case (m)
            4'd0: mult2 = 5'd1;   4'd1: mult2 = 5'd2;   4'd2: mult2 = 5'd4;   4'd3: mult2 = 5'd6;
            4'd4: mult2 = 5'd8;   4'd5: mult2 = 5'd10;  4'd6: mult2 = 5'd12;  4'd7: mult2 = 5'd14;
            4'd8: mult2 = 5'd16;  4'd9: mult2 = 5'd18;  4'd10: mult2 = 5'd20; 4'd11: mult2 = 5'd20;
            4'd12: mult2 = 5'd24; 4'd13: mult2 = 5'd24; default: mult2 = 5'd30;
        endcase
    endfunction

    wire  [2:0] vib_r0  = vibpos[1:0] == 2'd0 ? 3'd0 : vibpos[0] ? {1'b0, fnum[9:8]} : fnum[9:7];
    wire  [2:0] vib_rng = dvb ? vib_r0 : {1'b0, vib_r0[2:1]};
    wire [10:0] fnum_v  = ~r_vib ? {1'b0, fnum} :
                          vibpos[2] ? {1'b0, fnum} - {8'd0, vib_rng} : {1'b0, fnum} + {8'd0, vib_rng};
    wire [17:0] fshift  = {7'd0, fnum_v} << block;
    wire [16:0] basefreq = fshift[17:1];
    wire [21:0] pinc2   = basefreq * mult2(r_mult);
    wire [18:0] phase_n = (pg_rst_r ? 19'd0 : st_q.phase) + pinc2[19:1];
    wire  [9:0] phase   = st_q.phase[18:9];

    wire        hh2_n = sidx == 6'd13 ? phase[2] : hh2;
    wire        hh3_n = sidx == 6'd13 ? phase[3] : hh3;
    wire        hh7_n = sidx == 6'd13 ? phase[7] : hh7;
    wire        hh8_n = sidx == 6'd13 ? phase[8] : hh8;
    wire        tc3_n = (sidx == 6'd17 && rhy[5]) ? phase[3] : tc3;
    wire        tc5_n = (sidx == 6'd17 && rhy[5]) ? phase[5] : tc5;
    wire        rm_xor = (hh2_n ^ hh7_n) | (hh3_n ^ tc5_n) | (tc3_n ^ tc5_n);
    logic [9:0] pg_out;
    always_comb begin
        pg_out = phase;
        if (rhy[5]) begin
            case (sidx)
                6'd13:   pg_out = {rm_xor, 1'b0, (rm_xor ^ noise[0]) ? 8'hD0 : 8'h34};      // hi-hat
                6'd16:   pg_out = {hh8_n, hh8_n ^ noise[0], 8'h00};                         // snare
                6'd17:   pg_out = {rm_xor, 9'h080};                                         // top cymbal
                default: ;
            endcase
        end
    end

    wire  [9:0] ph    = pg_out + mod_r[9:0];
    wire  [2:0] wf    = qe0;
    // quarter wave address, mirrored in the second quarter; waveforms 4, 5 run at double speed
    wire  [7:0] sin_a = wf[2] ? {ph[7] ? ~ph[6:0] : ph[6:0], 1'b0} : (ph[8] ? ~ph[7:0] : ph[7:0]);
    logic       w_neg;
    logic [1:0] w_sel;                      // 0 sine ROM, 1 silence, 2 no attenuation, 3 ramp
    always_comb begin
        w_neg = 1'b0;
        w_sel = 2'd0;
        case (wf)
            3'd0: w_neg = ph[9];
            3'd1: if (ph[9]) w_sel = 2'd1;
            3'd2: ;
            3'd3: if (ph[8]) w_sel = 2'd1;
            3'd4: begin w_neg = ph[9:8] == 2'b01; if (ph[9]) w_sel = 2'd1; end
            3'd5: if (ph[9]) w_sel = 2'd1;
            3'd6: begin w_neg = ph[9]; w_sel = 2'd2; end
            3'd7: begin w_neg = ph[9]; w_sel = 2'd3; end
        endcase
    end
    wire  [11:0] ramp = {ph[9] ? ~ph[8:0] : ph[8:0], 3'b000};
    logic [11:0] sin_q;                     // log sine ROM, registered
    logic        neg_r, neg_r2;
    logic  [1:0] wsel_r;
    logic [11:0] ramp_r;
    logic [18:0] phase_r;

    // ---- step 2: attenuation of the output, step 3: exponent
    wire  [12:0] lvl   = wsel_r == 2'd0 ? {1'b0, sin_q} : wsel_r == 2'd1 ? 13'h1000 :
                         wsel_r == 2'd2 ? 13'd0 : {1'b0, ramp_r};
    wire  [14:0] level = {2'b00, lvl} + {1'b0, eg_out_r, 3'b000};
    wire  [12:0] lv_c  = level > 15'h1FFF ? 13'h1FFF : level[12:0];
    logic [10:0] exp_q;                     // exponent ROM, registered
    logic  [4:0] exp_sh;
    wire  [11:0] exp_v = {exp_q, 1'b0} >> exp_sh;
    wire signed [12:0] out_new = neg_r2 ? ~{1'b0, exp_v} : {1'b0, exp_v};

    // ---- mix: operator outputs of the channels, by the output selection of the channel
    logic signed [19:0] acc_a, acc_b, mix_b;
    wire signed  [12:0] mx_out = state == S_SLOT ? out_new : st_q.out;
    wire signed  [14:0] mx_val = wgt == 2'd0 ? 15'sd0 : wgt == 2'd1 ? {{2{mx_out[12]}}, mx_out} : {mx_out[12], mx_out, 1'b0};
    wire signed  [19:0] acc_a_n = acc_a + (cha[ch_pan] ? {{5{mx_val[14]}}, mx_val} : 20'sd0);
    wire signed  [19:0] acc_b_n = acc_b + (chb[ch_pan] ? {{5{mx_val[14]}}, mx_val} : 20'sd0);

    function automatic logic signed [15:0] clip(input logic signed [19:0] v);
        if (v > 20'sd32767)       clip = 16'sd32767;
        else if (v < -20'sd32768) clip = 16'sh8000;
        else                      clip = v[15:0];
    endfunction

    function automatic logic [3:0] low_bit(input logic [12:0] t);     // lowest set bit + 1, 0 = none
        casez (t)
            13'b????????????1: low_bit = 4'd1;
            13'b???????????10: low_bit = 4'd2;
            13'b??????????100: low_bit = 4'd3;
            13'b?????????1000: low_bit = 4'd4;
            13'b????????10000: low_bit = 4'd5;
            13'b???????100000: low_bit = 4'd6;
            13'b??????1000000: low_bit = 4'd7;
            13'b?????10000000: low_bit = 4'd8;
            13'b????100000000: low_bit = 4'd9;
            13'b???1000000000: low_bit = 4'd10;
            13'b??10000000000: low_bit = 4'd11;
            13'b?100000000000: low_bit = 4'd12;
            13'b1000000000000: low_bit = 4'd13;
            default:           low_bit = 4'd0;
        endcase
    endfunction

    wire [7:0] trpos_n = timer[5:0] != 6'h3F ? tremolopos : tremolopos == 8'd209 ? 8'd0 : tremolopos + 8'd1;
    wire [7:0] tr_tri  = trpos_n < 8'd105 ? trpos_n : 8'd210 - trpos_n;

    assign st_d = {phase_r, rout_r, gen_r, out_new, st_q.out};

    task automatic next_op;
        sidx <= sidx + 6'd1;
        if (col == 2'd2) begin
            col <= 2'd0;
            if (row == 3'd5) begin row <= 3'd0; bank <= 1'b1; end
            else row <= row + 3'd1;
        end else col <= col + 2'd1;
    endtask

    always_ff @(posedge clk) begin
        st_we     <= 1'b0;
        out_valid <= 1'b0;
        smp_end   <= 1'b0;
        sin_q     <= logsin_rom[sin_a];
        exp_q     <= exp_rom[lv_c[7:0]];

        case (state)
            S_IDLE: begin
                if (smp_tick && ~init) begin
                    out_b <= clip(mix_b);
                    acc_a <= '0;
                    acc_b <= '0;
                    sidx  <= '0;
                    bank  <= 1'b0;
                    row   <= '0;
                    col   <= '0;
                    step  <= '0;
                    state <= S_SLOT;
                end
            end

            S_SLOT: begin
                step <= step + 2'd1;
                case (step)
                    2'd0: begin
                        eg_out_r <= eg_out;
                        rout_r   <= rout_n;
                        gen_r    <= gen_n;
                        pg_rst_r <= eg_rst;
                        mod_r    <= msel == MOD_FB ? fbmod : msel == MOD_PREV ? hist3 : 13'sd0;
                    end
                    2'd1: begin
                        phase_r <= phase_n;
                        neg_r   <= w_neg;
                        wsel_r  <= w_sel;
                        ramp_r  <= ramp;
                        hh2 <= hh2_n; hh3 <= hh3_n; hh7 <= hh7_n; hh8 <= hh8_n;
                        tc3 <= tc3_n; tc5 <= tc5_n;
                        noise <= {noise[14] ^ noise[0], noise[22:1]};
                    end
                    2'd2: begin
                        exp_sh <= lv_c[12:8];
                        neg_r2 <= neg_r;
                        st_we  <= 1'b1;             // written at the end of step 3
                    end
                    2'd3: begin
                        hist3 <= hist2;
                        hist2 <= hist1;
                        hist1 <= out_new;
                        if (sidx < 6'd15) acc_a <= acc_a_n;
                        if (sidx < 6'd33) acc_b <= acc_b_n;
                        next_op();
                        if (sidx == 6'd14)      state <= S_MIXA;
                        else if (sidx == 6'd32) state <= S_MIXB;
                        else if (sidx == 6'd35) state <= S_END;
                    end
                endcase
            end

            // operators not processed yet go to the mix with the output of the last sample
            S_MIXA: begin
                acc_a <= acc_a_n;
                next_op();
                if (sidx == 6'd35) begin
                    out_a     <= clip(acc_a_n);
                    out_valid <= 1'b1;
                    sidx <= 6'd15; bank <= 1'b0; row <= 3'd5; col <= 2'd0;
                    state <= S_SLOT;
                end
            end
            S_MIXB: begin
                acc_b <= acc_b_n;
                next_op();
                if (sidx == 6'd35) begin
                    mix_b <= acc_b_n;
                    sidx <= 6'd33; bank <= 1'b1; row <= 3'd5; col <= 2'd0;
                    state <= S_SLOT;
                end
            end

            S_END: begin
                tremolopos <= trpos_n;
                tremolo    <= dam ? tr_tri[7:2] : {2'b00, tr_tri[7:4]};
                if (timer[9:0] == 10'h3FF) vibpos <= vibpos + 3'd1;
                timer <= timer + 16'd1;
                if (eg_state) begin
                    eg_add      <= low_bit(eg_timer[12:0]);
                    eg_timer_lo <= eg_timer[1:0];
                end
                if (eg_timerrem || eg_state) begin
                    if (eg_timer == 36'hFFFFFFFFF) begin eg_timer <= '0; eg_timerrem <= 1'b1; end
                    else begin eg_timer <= eg_timer + 36'd1; eg_timerrem <= 1'b0; end
                end
                eg_state <= ~eg_state;
                smp_end  <= 1'b1;
                state    <= S_IDLE;
            end
            default: state <= S_IDLE;
        endcase

        if (init) begin
            init_cnt <= init_cnt + 9'd1;
            if (init_cnt == 9'd511) init <= 1'b0;
            state <= S_IDLE;
            out_a <= '0; out_b <= '0; mix_b <= '0;
            hist1 <= '0; hist2 <= '0; hist3 <= '0;
            timer <= '0; eg_timer <= '0; eg_timerrem <= 1'b0; eg_state <= 1'b0;
            eg_add <= '0; eg_timer_lo <= '0;
            tremolopos <= '0; tremolo <= '0; vibpos <= '0;
            noise <= 23'd1;
            hh2 <= 1'b0; hh3 <= 1'b0; hh7 <= 1'b0; hh8 <= 1'b0; tc3 <= 1'b0; tc5 <= 1'b0;
        end
        if (reset) begin
            init     <= 1'b1;
            init_cnt <= '0;
        end
    end

endmodule
