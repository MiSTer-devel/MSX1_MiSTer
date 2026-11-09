// Shift enable generator
//
// SystemVerilog port of rtl/LIB/sftgen.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module sftgen (
    input  logic              clk,
    input  logic              rstn,
    input  int unsigned       len,
    output logic              sft
);

    int unsigned count;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            count <= 0;
            sft   <= 0;
        end else begin
            if (count > 1) begin
                count <= count - 1;
                sft   <= 0;
            end else begin
                sft   <= 1;
                count <= len;
            end
        end
    end
endmodule
