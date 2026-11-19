// Intel 8254 programmable interval timer
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
//

// Three counters, modes 0-5, counter latch, read-back, LSB / MSB / LSB+MSB access.
// Gates are tied high (MSX-MIDI), so the gate-triggered modes 1 and 5 never fire.
// Binary counting only (BCD bit stored and read back, as openMSX).
// tick[n] = one counting edge of CLKn. wr / rd_end = one pulse per CPU access.
module i8254 (
    input              clk,
    input              reset,
    input        [1:0] addr,
    input        [7:0] din,
    input              wr,          // write pulse
    input              rd_end,      // end of a read: advance the read byte order / latches
    output logic [7:0] dout,        // read data of addr (valid while reading)
    input        [2:0] tick,
    output       [2:0] out
);

    typedef struct packed {
        logic  [5:0] ctrl;          // RW[5:4] M[3:1] BCD[0]
        logic [15:0] cr;            // count register (last written count)
        logic [15:0] ce;            // counting element
        logic [15:0] ol;            // output latch
        logic        ol_valid;
        logic  [7:0] st;            // latched status
        logic        st_valid;
        logic        rd_msb;        // next read byte of an LSB+MSB access
        logic        wr_msb;        // next write byte of an LSB+MSB access
        logic  [7:0] wr_lsb;
        logic        out;
        logic        null_cnt;      // count written, not yet in CE
        logic        load;          // load CR into CE on the next tick
        logic        armed;         // a count was loaded since the control word
        logic        hold;          // mode 0: first byte of LSB+MSB written, counting stopped
        logic        odd_wait;      // mode 3, odd count: extra tick before OUT goes low
    } cnt_t;

    cnt_t c[3];

    localparam logic [1:0] RW_LATCH = 2'd0, RW_LSB = 2'd1, RW_MSB = 2'd2, RW_BOTH = 2'd3;

    assign out = {c[2].out, c[1].out, c[0].out};

    // mode with the don't-care bit 3 folded (6 -> 2, 7 -> 3)
    function automatic logic [2:0] mode_of(input logic [5:0] ctrl);
        return ctrl[3:2] == 2'b11 ? {1'b0, ctrl[2:1]} : ctrl[3:1];
    endfunction

    function automatic logic [15:0] reload3(input logic [15:0] cr);
        return {cr[15:1], 1'b0};    // mode 3 counts by two from the even part
    endfunction

    // read data
    cnt_t        rk;
    logic [15:0] rv;
    always_comb begin
        rk   = c[addr == 2'd3 ? 2'd0 : addr];
        rv   = rk.ol_valid ? rk.ol : rk.ce;
        dout = 8'hFF;
        if (addr != 2'd3) begin
            if (rk.st_valid)
                dout = rk.st;
            else case (rk.ctrl[5:4])
                RW_MSB:  dout = rv[15:8];
                RW_BOTH: dout = rk.rd_msb ? rv[15:8] : rv[7:0];
                default: dout = rv[7:0];
            endcase
        end
    end

    function automatic cnt_t latch_count(input cnt_t k);
        cnt_t r = k;
        if (!k.ol_valid) begin
            r.ol       = k.ce;
            r.ol_valid = 1'b1;
            r.rd_msb   = 1'b0;
        end
        return r;
    endfunction

    function automatic cnt_t latch_status(input cnt_t k);
        cnt_t r = k;
        if (!k.st_valid) begin
            r.st       = {k.out, k.null_cnt, k.ctrl};
            r.st_valid = 1'b1;
        end
        return r;
    endfunction

    // a complete count written
    function automatic cnt_t new_count(input cnt_t k, input logic [15:0] v);
        cnt_t r = k;
        r.cr       = v;
        r.null_cnt = 1'b1;
        r.hold     = 1'b0;
        case (mode_of(k.ctrl))
            3'd0, 3'd4: r.load = 1'b1;                 // (re)start on the next tick
            3'd2, 3'd3: if (!k.armed) r.load = 1'b1;   // running: new count at the period end
            default: ;                                 // 1, 5: on a gate trigger (never)
        endcase
        if (mode_of(k.ctrl) == 3'd0) r.out = 1'b0;
        return r;
    endfunction

    function automatic cnt_t count_tick(input cnt_t k);
        cnt_t r = k;
        if (k.load) begin
            r.load     = 1'b0;
            r.null_cnt = 1'b0;
            r.armed    = 1'b1;
            r.odd_wait = 1'b0;
            r.ce       = mode_of(k.ctrl) == 3'd3 ? reload3(k.cr) : k.cr;
        end else case (mode_of(k.ctrl))
            3'd0: if (!k.hold) begin
                r.ce = k.ce - 16'd1;
                if (k.armed && k.ce == 16'd1) r.out = 1'b1;
            end
            3'd2: begin
                if (k.armed && k.ce == 16'd1) begin
                    r.ce       = k.cr;
                    r.out      = 1'b1;
                    r.null_cnt = 1'b0;
                end else begin
                    r.ce = k.ce - 16'd1;
                    if (k.armed && k.ce == 16'd2) r.out = 1'b0;
                end
            end
            3'd3: begin
                if (k.armed && k.odd_wait) begin
                    r.odd_wait = 1'b0;
                    r.out      = 1'b0;
                    r.ce       = reload3(k.cr);
                    r.null_cnt = 1'b0;
                end else if (k.armed && k.ce == 16'd2) begin
                    if (k.out && k.cr[0]) begin
                        r.ce       = 16'd0;
                        r.odd_wait = 1'b1;
                    end else begin
                        r.out      = ~k.out;
                        r.ce       = reload3(k.cr);
                        r.null_cnt = 1'b0;
                    end
                end else
                    r.ce = k.ce - 16'd2;
            end
            3'd4: begin
                r.ce  = k.ce - 16'd1;
                r.out = !(k.armed && k.ce == 16'd1);
                if (k.armed && k.ce == 16'd1) r.armed = 1'b0;
            end
            default: r.ce = k.ce - 16'd1;              // 1, 5: never triggered
        endcase
        return r;
    endfunction

    always_ff @(posedge clk) begin
        cnt_t k;
        if (reset) begin
            for (int i = 0; i < 3; i++) begin
                c[i]      <= '0;
                c[i].ctrl <= 6'h30;     // LSB+MSB, mode 0, binary (openMSX)
            end
        end else begin
            for (int i = 0; i < 3; i++) begin
                k = c[i];
                if (tick[i]) k = count_tick(k);

                if (wr && addr == 2'(i)) begin
                    case (k.ctrl[5:4])
                        RW_LSB:  k = new_count(k, {k.cr[15:8], din});      // MSB kept (openMSX)
                        RW_MSB:  k = new_count(k, {din, k.cr[7:0]});
                        default: if (!k.wr_msb) begin
                            k.wr_msb = 1'b1;
                            k.wr_lsb = din;
                            if (mode_of(k.ctrl) == 3'd0) k.hold = 1'b1;
                        end else begin
                            k.wr_msb = 1'b0;
                            k = new_count(k, {din, k.wr_lsb});
                        end
                    endcase
                end

                if (wr && addr == 2'd3) begin
                    if (din[7:6] == 2'b11) begin                      // read-back
                        if (din[1 + i]) begin
                            if (!din[5]) k = latch_count(k);
                            if (!din[4]) k = latch_status(k);
                        end
                    end else if (din[7:6] == 2'(i)) begin
                        if (din[5:4] == RW_LATCH)
                            k = latch_count(k);
                        else begin                                    // new control word
                            k.ctrl     = din[5:0];
                            k.wr_msb   = 1'b0;
                            k.rd_msb   = 1'b0;
                            k.ol_valid = 1'b0;
                            k.st_valid = 1'b0;
                            k.load     = 1'b0;
                            k.armed    = 1'b0;
                            k.hold     = 1'b0;
                            k.odd_wait = 1'b0;
                            k.null_cnt = 1'b1;
                            k.out      = mode_of(din[5:0]) != 3'd0;
                        end
                    end
                end

                if (rd_end && addr == 2'(i)) begin
                    if (k.st_valid)
                        k.st_valid = 1'b0;
                    else case (k.ctrl[5:4])
                        RW_BOTH: begin
                            if (k.rd_msb) k.ol_valid = 1'b0;
                            k.rd_msb = ~k.rd_msb;
                        end
                        default: k.ol_valid = 1'b0;
                    endcase
                end
                c[i] <= k;
            end
        end
    end

endmodule
