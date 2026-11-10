// VRAM access timing of the VDP command engine, after openMSX (VDPAccessSlots.cc,
// VDPCmdEngine.cc). Replaces the average-rate wait tables of vdp_wait_control.
//
// openMSX: every command access waits at least DELTA cycles after the previous access and
// then for the next free slot of a table measured on a real V9938 (1368 cycles per line,
// one table per display state). DELTA depends on the command, the kind of access and on
// the end of a block row / a LINE minor-axis step.
//
// Here that time is followed on its own: the order of the accesses of each command is fixed
// (e.g. LMMV: destination read, write, ...), so a token is issued at every openMSX access
// time without waiting for the engine, and the arbiter performs the access at its next free
// command slot. DELTA counts from the token, not from the real access, so the arbiter
// latency (up to ~30 cycles with sprites on) does not add up.
// doc/vdp-prikazy.md describes the model and the measurements.

module VDP_ACCESS_SLOTS (
    input  logic        RESET,
    input  logic        CLK21M,

    input  logic [10:0] H_CNT,
    input  logic        DISP_LINE,      // display line and display enabled (R#1 BL)
    input  logic        SPRITES,        // sprites enabled (R#8 SPD = 0)
    input  logic        BITMAP,         // GRAPHIC 4-7
    input  logic        TEXT,

    input  logic [7:4]  VDP_COMMAND,
    input  logic        CE,
    input  logic        XFER,           // the arbiter performed a command access
    input  logic        ROWSTEP,        // block command went to the next row
    input  logic        MINORSTEP,      // LINE stepped its minor axis

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
    // CharSpritesOn: 31 slots
    localparam logic [683:0] SLOT_CSPON =
        684'h000080000000400000040000000400040004000000040004000400000004000400040000000400040004000000040004000400000004000400040000000400040004000000040004000408800000001000000010000;
    // CharSpritesOff: 88 slots
    localparam logic [683:0] SLOT_CSPOFF =
        684'h222108888888800000240020002400240024002000240024002400200024002400240020002400240024002000240024002400200024002400240020002400240024002000240024002408800002222222222222222;
    // Text: 47 slots
    localparam logic [683:0] SLOT_TEXT =
        684'h222108888888888888888001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000001000000000008888888800000000000222222222;
    // END slot tables

    // openMSX cycle = H_CNT + 1 (the same alignment as VBLANK / HSCAN, vdp_ssg)

    localparam logic [3:0] C_SRCH = 4'b0110, C_LINE = 4'b0111, C_LMMV = 4'b1000, C_LMMM = 4'b1001,
                           C_HMMV = 4'b1100, C_HMMM = 4'b1101, C_YMMM = 4'b1110,
                           C_PSET = 4'b0101, C_POINT = 4'b0100;

    logic [10:0] tick, tick_inc;
    assign tick_inc = H_CNT + 11'd1;
    assign tick = (tick_inc == 11'd1368) ? 11'd0 : tick_inc;

    logic [683:0] tab;
    always_comb begin
        if (!DISP_LINE)    tab = SLOT_OFF;
        else if (TEXT)     tab = SLOT_TEXT;
        else if (BITMAP)   tab = SPRITES ? SLOT_SPON  : SLOT_SPOFF;
        else               tab = SPRITES ? SLOT_CSPON : SLOT_CSPOFF;
    end
    wire slot = ~tick[0] & tab[tick[10:1]];

    // kind of the next access: source read, destination read, write
    typedef enum logic [1:0] { A_RS, A_RD, A_WR } acc_t;
    logic       first_q, row_q, minor_q;
    logic [1:0] ph_q;                   // position in the access sequence of the command
    logic [1:0] tokens_q;               // tokens not yet used by the arbiter
    logic [7:0] since_q;                // cycles since the last token (saturating)

    acc_t kind;
    always_comb begin
        case (VDP_COMMAND)
            C_HMMV:                kind = A_WR;
            C_HMMM, C_YMMM:        kind = ph_q[0] ? A_WR : A_RS;
            C_LMMV, C_LINE, C_PSET: kind = ph_q[0] ? A_WR : A_RD;
            C_LMMM:                kind = ph_q == 2'd0 ? A_RS : ph_q == 2'd1 ? A_RD : A_WR;
            default:               kind = A_RS;      // SRCH, POINT
        endcase
    end

    // DELTA before the next access (openMSX VDPCmdEngine); 255 = not timed (CPU paced)
    logic [7:0] delta;
    always_comb begin
        case (VDP_COMMAND)
            C_HMMV:  delta = row_q ? 8'd104 : 8'd48;
            C_HMMM:  delta = kind == A_WR ? 8'd24 : (row_q ? 8'd128 : 8'd64);
            C_YMMM:  delta = kind == A_WR ? 8'd24 : 8'd40;
            C_LMMV:  delta = kind == A_WR ? 8'd24 : (row_q ? 8'd136 : 8'd72);
            C_LMMM:  delta = kind == A_WR ? 8'd24 : kind == A_RD ? 8'd32 : (row_q ? 8'd128 : 8'd64);
            C_LINE:  delta = kind == A_WR ? 8'd24 : (minor_q ? 8'd120 : 8'd88);
            C_SRCH:  delta = 8'd88;
            C_PSET:  delta = kind == A_WR ? 8'd24 : 8'd0;
            C_POINT: delta = 8'd0;
            default: delta = 8'd255;
        endcase
        if (first_q && delta != 8'd255) delta = 8'd0;
    end
    wire timed = delta != 8'd255;
    wire fire  = CE && timed && tokens_q != 2'd3 && since_q >= delta && slot;

    always_ff @(posedge CLK21M) begin
        if (RESET || !CE) begin
            first_q  <= 1'b1;
            row_q    <= 1'b0;
            minor_q  <= 1'b0;
            ph_q     <= '0;
            tokens_q <= '0;
            since_q  <= '1;
        end else begin
            if (fire) begin
                first_q <= 1'b0;
                row_q   <= 1'b0;
                minor_q <= 1'b0;
                ph_q    <= (VDP_COMMAND == C_LMMM && ph_q == 2'd2) ? 2'd0 : ph_q + 2'd1;
            end else begin
                if (ROWSTEP)   row_q   <= 1'b1;
                if (MINORSTEP) minor_q <= 1'b1;
            end
            if (fire)
                since_q <= 8'd1;
            else if (since_q != 8'hFF)
                since_q <= since_q + 8'd1;
            if (fire && !(XFER && tokens_q != 2'd0))
                tokens_q <= tokens_q + 2'd1;
            else if (!fire && XFER && tokens_q != 2'd0)
                tokens_q <= tokens_q - 2'd1;
        end
    end

    assign ACTIVE = VDPSPEEDMODE | !timed | (tokens_q != 2'd0);

endmodule
