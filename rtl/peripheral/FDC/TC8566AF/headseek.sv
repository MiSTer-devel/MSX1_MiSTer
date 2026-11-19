// Head seek control
//
// SystemVerilog port of rtl/FDC/headseek.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer), with the fixes of PC88_MiSTer by Yoshiaki
// Okuyama: a9ab3e6 (not busy after a failed recalibrate, error cleared by the next seek) and
// fe0a425 (uPD765 timing: recalibrate steps out at most 77 times, a step takes four sft).
// The same FDC code is published under the GNU General Public License version 3 in
// X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module headseek #(
    parameter int maxtrack = 79,
    parameter int maxset   = 10,
    parameter int initseek = 0
)(
    input  int   desttrack,
    input  logic destset,
    input  int   setwait,                       // settling time in sft

    output int   curtrack,

    output logic reachtrack,
    output logic busy,

    input  logic track0,
    output logic seek,
    output logic sdir,

    input  logic init,
    output logic seekerr,

    input  logic sft,
    input  logic clk,
    input  logic rstn
);

    // RECALIBRATE steps out until TRACK0, giving up after 77 step pulses (uPD765)
    localparam int recalsteps = 77;

    typedef enum logic [2:0] {
        ST_INIWAIT,
        ST_INIOUT,
        ST_INIERR,
        ST_IDLE,
        ST_CONTROL,
        ST_WAITSET,
        ST_NOP
    } state_t;

    typedef enum logic [2:0] {
        MS_IDLE,
        MS_SEEKON,
        MS_SEEKOFF,
        MS_SEEKWAIT,
        MS_SEEKWAIT2
    } movestate_t;

    state_t     state;
    movestate_t movestate;

    int   current;
    logic movedir;
    logic move;
    logic intbusy;
    logic curdir;
    int   wsetcount;
    logic seekerrb;
    logic busyb;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            current    <= 0;
            movedir    <= 1'b1;
            move       <= 1'b0;
            reachtrack <= 1'b0;
            seekerrb   <= 1'b0;
            if (initseek == 0) begin
                busyb <= 1'b0;
                state <= ST_IDLE;
            end else begin
                busyb     <= 1'b1;
                current   <= recalsteps;
                wsetcount <= maxset;
                state     <= ST_INIWAIT;
            end
        end else begin
            reachtrack <= 1'b0;
            move       <= 1'b0;
            if (init) begin
                state     <= ST_INIWAIT;
                current   <= recalsteps;
                wsetcount <= maxset;
                seekerrb  <= 1'b0;
                busyb     <= 1'b1;
            end
            case (state)
                ST_INIWAIT: begin                   // let track0 follow the newly selected drive
                    if (wsetcount > 0)
                        wsetcount <= wsetcount - 1;
                    else
                        state <= ST_INIOUT;
                end
                ST_INIOUT: begin
                    if (!intbusy) begin
                        if (track0) begin
                            if (current > 0) begin
                                current <= current - 1;
                                movedir <= 1'b1;
                                move    <= 1'b1;
                            end else begin
                                state <= ST_INIERR;
                            end
                        end else begin
                            current   <= 0;
                            seekerrb  <= 1'b0;
                            wsetcount <= setwait;
                            state     <= ST_WAITSET;
                        end
                    end
                end
                ST_INIERR: begin                    // the failure one step period after the last step
                    if (sft) begin
                        seekerrb <= 1'b1;
                        busyb    <= 1'b0;
                        state    <= ST_IDLE;
                    end
                end
                ST_IDLE: begin
                    if (destset) begin
                        seekerrb <= 1'b0;
                        if (current == desttrack) begin
                            reachtrack <= 1'b1;
                            state      <= ST_NOP;
                            busyb      <= 1'b1;
                        end else begin
                            movedir <= (desttrack > current) ? 1'b0 : 1'b1;
                            state   <= ST_CONTROL;
                            busyb   <= 1'b1;
                        end
                    end
                end
                ST_NOP: begin
                    busyb <= 1'b0;
                    state <= ST_IDLE;
                end
                ST_CONTROL: begin
                    if (!intbusy) begin
                        if (current == desttrack) begin
                            wsetcount <= setwait;
                            state     <= ST_WAITSET;
                        end else begin
                            move    <= 1'b1;
                            current <= movedir ? current - 1 : current + 1;
                        end
                    end
                end
                ST_WAITSET: begin
                    if (sft) begin
                        if (wsetcount > 0) begin
                            wsetcount <= wsetcount - 1;
                        end else begin
                            reachtrack <= 1'b1;
                            busyb      <= 1'b0;
                            state      <= ST_IDLE;
                        end
                    end
                end
                default: state <= ST_IDLE;
            endcase
        end
    end

    // a step takes four sft periods, (16 - SRT) * 2 ms as the uPD765 at 4 MHz
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            seek      <= 1'b1;
            curdir    <= 1'b0;
            movestate <= MS_IDLE;
        end else if (move) begin
            curdir    <= movedir;
            movestate <= MS_SEEKON;
        end else if (sft) begin
            case (movestate)
                MS_SEEKON: begin
                    seek      <= 1'b0;
                    movestate <= MS_SEEKOFF;
                end
                MS_SEEKOFF: begin
                    seek      <= 1'b1;
                    movestate <= MS_SEEKWAIT;
                end
                MS_SEEKWAIT: movestate <= MS_SEEKWAIT2;
                default:     movestate <= MS_IDLE;
            endcase
        end
    end

    assign intbusy  = move || movestate != MS_IDLE;
    assign sdir     = curdir;
    assign curtrack = current;
    assign seekerr  = seekerrb & ~(destset | init);
    assign busy     = (destset || init) ? 1'b1 : busyb;

endmodule
