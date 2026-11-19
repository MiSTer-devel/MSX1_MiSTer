// Shift enable generator with a fractional period
//
// SystemVerilog port of rtl/LIB/sftfrac.vhd of PC88_MiSTer (commit 6a42cb2, 2026-10-18,
// https://github.com/MiSTer-devel/PC88_MiSTer), Copyright (C) 2026 Yoshiaki Okuyama, published
// there as GPL-2.0-or-later and used here under GPL-3.0. Port: Molekula.
//
// len is in 1/256 clocks; the remainder is carried, so the pulses average len/256 clocks. As
// sftgen, len is taken when a pulse is given and the first pulse comes on the first clock
// after reset. A len that is a multiple of 256 gives the pulses of sftgen with len/256.
//
// SPDX-License-Identifier: GPL-3.0-only

module sftfrac #(
    parameter int maxlen = 100*256
)(
    input  logic [$clog2(maxlen+1)-1:0]  len,
    output logic                         sft,
    input  logic                         clk,
    input  logic                         rstn
);

    localparam int W = $clog2(maxlen + 257);
    logic [W-1:0] count;
    wire  [W-1:0] next = count + W'(len);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            count <= W'(256);
            sft   <= 1'b0;
        end else if (count > W'(256)) begin
            count <= count - W'(256);
            sft   <= 1'b0;
        end else begin
            sft   <= 1'b1;
            count <= next > W'(256) ? next - W'(256) : W'(256);   // under one clock: every clock
        end
    end

endmodule
