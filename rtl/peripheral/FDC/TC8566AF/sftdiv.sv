// Shift enable divider
//
// SystemVerilog port of rtl/LIB/sftdiv.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module sftdiv #(
    parameter width = 8
) (
    input  logic [width-1:0] sel,
    input  logic sftin,
    output logic sftout,
    input  logic clk,
    input  logic rstn
);

    // Declare signal count as an integer
    integer count;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            count <= 0;
        end else begin
            if (sftin == 1) begin
                if (count == 0) begin
                    sftout <= 1'b1;
                    count <= { {32 - width{1'b0}} , sel };
                end else begin
                    sftout <= 1'b0;
                    count <= count - 1;
                end
            end else begin
                sftout <= 0;
            end
        end
    end

endmodule