// VRAM access timing of the VDP command engine, after openMSX (VDPAccessSlots.cc,
// VDPCmdEngine.cc, VDP.cc; the model of doc/internal/vdp-vram-timing/
// 2026-measurement-analysis.md, fitted to logic-analyser captures of a V9938).
//
// openMSX: every command access waits at least DELTA memory cycles after the previous access
// (the first one after the write to R#46) and then for the next slot of a table measured on a
// real V9938 (1368 cycles per line, one table per display state). Memory cycles: the padding
// in the horizontal blanking is not counted. With sprites on every step is one cycle longer, a
// step from a 'tight' slot (6 cycles after the previous slot) one cycle too. A CPU VRAM access
// takes its slot 29 + 16 memory cycles after the port access (2 more in a 'late' slot), never
// in a tight slot, with a single request buffer (a request that comes too early is lost); the
// command engine loses a slot it wanted to the CPU and takes the next one.
//
// Here that time is followed on its own: the order of the accesses of each command is fixed,
// so a token is issued at every openMSX access time without waiting for the engine, and the
// arbiter performs the access at its next free command slot. DELTA counts from the token, not
// from the real access, so the arbiter latency does not add up. The real CPU accesses are not
// moved (and never lost); only their effect on the command engine is modelled.
// doc/vdp-prikazy.md describes the model and the measurements.

module VDP_ACCESS_SLOTS (
    input  logic        RESET,
    input  logic        CLK21M,

    input  logic [10:0] H_CNT,
    input  logic        SLOT_AREA,      // display access grid: tick 162 of the line before the
                                        // display to tick 162 of the line after it
    input  logic        DISP_ON,        // R#1 BL
    input  logic        SPRITES,        // sprites enabled (R#8 SPD = 0)
    input  logic        BITMAP,         // GRAPHIC 4-7
    input  logic        TEXT,

    input  logic [7:4]  VDP_COMMAND,
    input  logic        CE,
    input  logic        START,          // command started (R#46 written 4 cycles before)
    input  logic        XFER,           // the arbiter performed a command access
    input  logic        ROWSTEP,        // block command went to the next row
    input  logic        MINORSTEP,      // LINE stepped its minor axis
    input  logic        CPU_WR_REQ,     // toggles: CPU VRAM write / read request (1 cycle
    input  logic        CPU_RD_REQ,     //   after the port access)

    input  logic        VDPSPEEDMODE,
    output logic        ACTIVE
);
    // BEGIN slot tables: gen_access_slots.py from openMSX VDPAccessSlots.cc, do not edit.
    // Bit n = an access slot at line cycle 2n (openMSX cycle numbering).
    // ScreenOff: 154 slots
    localparam logic [683:0] SLOT_OFF =
        684'h111084444444400004444440444444444444444044444444444444404444444444444440444444444444444044444444444444404444444444444440444444444444444044444444444444400001111111111111111;
    // SpritesOn: 31 slots
    localparam logic [683:0] SLOT_SPON =
        684'h000020000000100000040000000400040004000000040004000400000004000400040000000400040004000000040004000400000004000400040000000400040004000000040004000402200000000400000004000;
    // SpritesOff: 88 slots
    localparam logic [683:0] SLOT_SPOFF =
        684'h888842222222200000048000800480048004800080048004800480008004800480048000800480048004800080048004800480008004800480048000800480048004800080048004800482200000888888888888888;
    // Char: 31 slots
    localparam logic [683:0] SLOT_CHAR =
        684'h000080000000400000040000000400040004000000040004000400000004000400040000000400040004000000040004000400000004000400040000000400040004000000040004000408800000001000000010000;
    // Text: 47 slots
    localparam logic [683:0] SLOT_TEXT =
        684'h222108888888888888888001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000008888888800000000000222222222;
    // END slot tables

    typedef enum logic [2:0] { T_OFF, T_SPON, T_SPOFF, T_CHAR, T_TEXT } tab_t;


    // memory cycles of line padding completing at cycle c (VDPAccessSlots.cc Timing::pad)
    function automatic logic [1:0] pad_at(input tab_t t, input logic [10:0] c);
        case (t)
            T_SPON:  return (c == 11'd1330) ? 2'd2 : (c == 11'd1337 || c == 11'd1348) ? 2'd1 : 2'd0;
            T_SPOFF: return (c == 11'd1332 || c == 11'd1342) ? 2'd2 : 2'd0;
            T_OFF:   return (c == 11'd1334 || c == 11'd1344) ? 2'd2 : 2'd0;
            default: return 2'd0;
        endcase
    endfunction

    // CPU slot that wants 2 cycles more lookahead (Timing::lateLead / plainSlots)
    function automatic logic late_at(input tab_t t, input logic [10:0] c);
        return (t == T_SPON && c != 11'd162 && c != 11'd170) ||
               (t == T_CHAR && c != 11'd166 && c != 11'd174);
    endfunction

    // openMSX cycle = H_CNT + 1 (the same alignment as VBLANK / HSCAN, vdp_ssg)
    logic [10:0] tick, tick_inc, tick_n;
    assign tick_inc = H_CNT + 11'd1;
    assign tick   = (tick_inc == 11'd1368) ? 11'd0 : tick_inc;
    assign tick_n = (tick == 11'd1367) ? 11'd0 : tick + 11'd1;

    // slots of all tables at the next cycle (one lookup per table), now and 5 / 6 cycles ago
    logic [4:0] sv_n, sv_q, sv_h [6];
    always_comb begin
        sv_n[T_OFF]   = ~tick_n[0] & SLOT_OFF[tick_n[10:1]];
        sv_n[T_SPON]  = ~tick_n[0] & SLOT_SPON[tick_n[10:1]];
        sv_n[T_SPOFF] = ~tick_n[0] & SLOT_SPOFF[tick_n[10:1]];
        sv_n[T_CHAR]  = ~tick_n[0] & SLOT_CHAR[tick_n[10:1]];
        sv_n[T_TEXT]  = ~tick_n[0] & SLOT_TEXT[tick_n[10:1]];
    end
    always_ff @(posedge CLK21M) begin
        sv_q     <= sv_n;
        sv_h[0]  <= sv_q;
        for (int i = 1; i < 6; i++) sv_h[i] <= sv_h[i - 1];
    end
    wire [4:0] tight_v   = (tick   >= 11'd6) ? (sv_q & sv_h[5]) : 5'd0;
    wire [4:0] tight_v_n = (tick_n >= 11'd6) ? (sv_n & sv_h[4]) : 5'd0;
    // a slot 6 cycles after the previous one is 'tight' (only the sprites-off table has them)

    tab_t cur;          // table of the current display state
    always_comb begin
        if (TEXT)                         cur = T_TEXT;
        else if (!BITMAP)                 cur = T_CHAR;
        else if (!(SLOT_AREA && DISP_ON)) cur = T_OFF;
        else if (SPRITES)                 cur = T_SPON;
        else                              cur = T_SPOFF;
    end

    // ---------------------------------------------------------------- CPU access slots
    // the request reaches the arbiter 29 cycles after the port access (CPU_REQUEST_DELAY) and
    // gets the first slot 16 memory cycles later (Delta::CPU_16), 18 for a late slot

    logic       wr_q, rd_q;
    logic [4:0] dly_q;                       // request in flight: cycles to the arbiter
    logic       dly_on_q;
    tab_t       dly_tab_q;                   // table at the port access

    logic       s_on_q, s_any_q;             // search for the granted slot / the 'any' slot
    tab_t       s_tab_q;
    logic signed [9:0] s_since_q;            // memory cycles since the request
    logic [7:0] s_real_q;                    // cycles since the request
    logic       s_next_q;                    // a second request waits for the running search
    tab_t       s_next_tab_q;
    logic signed [9:0] s_next_since_q;
    logic [7:0] s_next_real_q;

    logic signed [9:0] g_since_q;            // memory cycles since the last grant (saturating)
    logic       g_late_q;

    logic signed [9:0] s_since_n;
    assign s_since_n = s_since_q + 10'sd1 - $signed({8'd0, pad_at(s_tab_q, tick_n)});

    wire lead_ok = s_since_q >= (late_at(s_tab_q, tick) ? 10'sd18 : 10'sd16);
    wire grant   = s_on_q && sv_q[s_tab_q] && !tight_v[s_tab_q] && lead_ok;
    // the slot the CPU would have had if it could use every slot: a tight one costs the
    // command engine that slot (a dummy read), when the request came 18..21 cycles before it
    wire any_hit = s_on_q && s_any_q && sv_q[s_tab_q] && lead_ok;
    wire dummy   = any_hit && tight_v[s_tab_q] && s_real_q >= 8'd18 && s_real_q < 8'd22;
    // will the search grant in the next cycle (a late slot accepts a request 1 cycle early)
    wire grant_n = s_on_q && sv_n[s_tab_q] && !tight_v_n[s_tab_q] &&
                   s_since_n >= (late_at(s_tab_q, tick_n) ? 10'sd18 : 10'sd16);

    wire req_now = dly_on_q && dly_q == 5'd0;            // the request reaches the arbiter
    // single request buffer: free from 1 memory cycle after a plain slot, 1 before a late one
    wire accept  = req_now && (
        (!s_on_q && (g_late_q || g_since_q >= 10'sd1)) ||
        ( s_on_q && grant   && late_at(s_tab_q, tick)) ||
        ( s_on_q && grant_n && late_at(s_tab_q, tick_n)));
    wire steal   = grant || dummy;

    always_ff @(posedge CLK21M) begin
        if (RESET) begin
            wr_q <= CPU_WR_REQ; rd_q <= CPU_RD_REQ;
            dly_on_q <= 1'b0; dly_q <= '0; dly_tab_q <= T_OFF;
            s_on_q <= 1'b0; s_any_q <= 1'b0; s_tab_q <= T_OFF; s_since_q <= '0; s_real_q <= '0;
            s_next_q <= 1'b0; s_next_tab_q <= T_OFF; s_next_since_q <= '0; s_next_real_q <= '0;
            g_since_q <= 10'sd500; g_late_q <= 1'b0;
        end else begin
            wr_q <= CPU_WR_REQ; rd_q <= CPU_RD_REQ;
            // the port access was one cycle ago: the arbiter sees it CPU_REQUEST_DELAY after it
            if ((CPU_WR_REQ != wr_q) || (CPU_RD_REQ != rd_q)) begin
                dly_on_q  <= 1'b1;
                dly_q     <= 5'd27;           // CPU_REQUEST_DELAY - 2
                dly_tab_q <= cur;
            end else if (dly_on_q) begin
                if (dly_q == 5'd0) dly_on_q <= 1'b0;
                else               dly_q <= dly_q - 5'd1;
            end

            if (grant) begin
                g_since_q <= 10'sd1 - $signed({8'd0, pad_at(s_tab_q, tick_n)});
                g_late_q  <= late_at(s_tab_q, tick);
            end else if (g_since_q < 10'sd500)
                g_since_q <= g_since_q + 10'sd1 - $signed({8'd0, pad_at(cur, tick_n)});

            if (any_hit) s_any_q <= 1'b0;
            if (s_on_q) begin
                s_since_q <= s_since_n;
                if (s_real_q != 8'hFF) s_real_q <= s_real_q + 8'd1;
            end
            if (grant) s_on_q <= 1'b0;

            // a new search: now, or after the grant of the one still running
            if (accept && !s_on_q) begin
                s_on_q <= 1'b1; s_any_q <= 1'b1; s_tab_q <= dly_tab_q;
                s_since_q <= 10'sd1 - $signed({8'd0, pad_at(dly_tab_q, tick_n)});
                s_real_q  <= 8'd1;
            end else if (accept) begin
                s_next_q <= 1'b1; s_next_tab_q <= dly_tab_q;
                s_next_since_q <= 10'sd1 - $signed({8'd0, pad_at(dly_tab_q, tick_n)});
                s_next_real_q  <= 8'd1;
            end
            if (s_next_q) begin
                s_next_since_q <= s_next_since_q + 10'sd1 - $signed({8'd0, pad_at(s_next_tab_q, tick_n)});
                s_next_real_q  <= s_next_real_q + 8'd1;
                if (!s_on_q) begin
                    s_next_q <= 1'b0;
                    s_on_q <= 1'b1; s_any_q <= 1'b1; s_tab_q <= s_next_tab_q;
                    s_since_q <= s_next_since_q + 10'sd1 - $signed({8'd0, pad_at(s_next_tab_q, tick_n)});
                    s_real_q  <= s_next_real_q + 8'd1;
                end
            end
        end
    end

    // ---------------------------------------------------------------- command engine
    localparam logic [3:0] C_SRCH = 4'b0110, C_LINE = 4'b0111, C_LMMV = 4'b1000, C_LMMM = 4'b1001,
                           C_LMCM = 4'b1010, C_LMMC = 4'b1011, C_HMMV = 4'b1100, C_HMMM = 4'b1101,
                           C_YMMM = 4'b1110, C_HMMC = 4'b1111, C_PSET = 4'b0101, C_POINT = 4'b0100;

    // kind of the next access: source read, destination read, write
    typedef enum logic [1:0] { A_RS, A_RD, A_WR } acc_t;
    logic       first_q, row_q, minor_q, after_wr_q;
    logic [1:0] ph_q;                   // position in the access sequence of the command
    logic [1:0] tokens_q;               // tokens not yet used by the arbiter
    logic [1:0] settle_q;               // cycles until ROWSTEP / MINORSTEP of the last access
    tab_t       tab_q;                  // table of the current step (openMSX: at its start)
    logic signed [9:0] since_q;         // memory cycles since the last access / the R#46 write

    acc_t kind;
    always_comb begin
        case (VDP_COMMAND)
            C_HMMV:                 kind = A_WR;
            C_HMMM, C_YMMM:         kind = ph_q[0] ? A_WR : A_RS;
            C_LMMV, C_LINE, C_PSET: kind = ph_q[0] ? A_WR : A_RD;
            C_LMMM:                 kind = ph_q == 2'd0 ? A_RS : ph_q == 2'd1 ? A_RD : A_WR;
            default:                kind = A_RS;      // SRCH, POINT
        endcase
    end

    // DELTA before the next access (openMSX VDPCmdEngine, Delta::CMD_*); 0 = not timed (CPU paced)
    logic [7:0] delta;
    always_comb begin
        if (first_q)
            case (VDP_COMMAND)                          // Delta::CMD_START_*
                C_POINT:                 delta = 8'd63;
                C_LMMM:                  delta = 8'd64;
                C_LMMV, C_PSET, C_SRCH:  delta = 8'd88;
                C_HMMM, C_YMMM:          delta = 8'd100;
                C_HMMV, C_LINE:          delta = 8'd112;
                default:                 delta = 8'd0;
            endcase
        else
            case (VDP_COMMAND)
                C_HMMV:  delta = row_q ? 8'd104 : 8'd46;
                C_HMMM:  delta = kind == A_WR ? 8'd24 : (row_q ? 8'd128 : 8'd60);
                C_YMMM:  delta = kind == A_WR ? 8'd24 : (row_q ? 8'd104 : 8'd36);
                C_LMMV:  delta = kind == A_WR ? 8'd24 : (row_q ? 8'd130 : 8'd72);
                C_LMMM:  delta = kind == A_WR ? 8'd24 : kind == A_RD ? 8'd32 : (row_q ? 8'd128 : 8'd60);
                C_LINE:  delta = kind == A_WR ? 8'd24 : (minor_q ? 8'd120 : 8'd84);
                C_SRCH:  delta = 8'd88;
                C_PSET:  delta = 8'd24;
                default: delta = 8'd0;
            endcase
    end
    wire timed = delta != 8'd0;
    wire signed [9:0] step = $signed({2'b00, delta}) + ((tab_q == T_SPON) ? 10'sd1 : 10'sd0);
    // the delay after a write may depend on the end of a row / a minor step: wait until the
    // engine has done that write
    wire hold = after_wr_q && (tokens_q != 2'd0 || settle_q != 2'd0);
    wire fire = CE && timed && tokens_q != 2'd3 && !hold && sv_q[tab_q] &&
                since_q >= step && !steal;

    always_ff @(posedge CLK21M) begin
        if (RESET || !CE || START) begin
            first_q    <= 1'b1;
            row_q      <= 1'b0;
            minor_q    <= 1'b0;
            after_wr_q <= 1'b0;
            ph_q       <= '0;
            tokens_q   <= '0;
            settle_q   <= '0;
            tab_q      <= cur;
            since_q    <= 10'sd5;           // the R#46 write was 5 cycles before the next one
        end else begin
            if (fire) begin
                first_q    <= 1'b0;
                row_q      <= 1'b0;
                minor_q    <= 1'b0;
                after_wr_q <= kind == A_WR;
                ph_q       <= (VDP_COMMAND == C_LMMM && ph_q == 2'd2) ? 2'd0 : ph_q + 2'd1;
                tab_q      <= cur;
                // a step from a tight slot counts as one from the next cycle
                since_q    <= tight_v[cur] ? 10'sd0 : 10'sd1 - $signed({8'd0, pad_at(cur, tick_n)});
            end else begin
                if (ROWSTEP)   row_q   <= 1'b1;
                if (MINORSTEP) minor_q <= 1'b1;
                if (since_q < 10'sd500)
                    since_q <= since_q + 10'sd1 - $signed({8'd0, pad_at(tab_q, tick_n)});
            end
            if (fire && !(XFER && tokens_q != 2'd0))
                tokens_q <= tokens_q + 2'd1;
            else if (!fire && XFER && tokens_q != 2'd0)
                tokens_q <= tokens_q - 2'd1;
            if (XFER)                  settle_q <= 2'd3;
            else if (settle_q != 2'd0) settle_q <= settle_q - 2'd1;
        end
    end

    assign ACTIVE = VDPSPEEDMODE | !timed | (tokens_q != 2'd0);

endmodule
