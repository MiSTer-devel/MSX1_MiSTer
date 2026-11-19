// Signal extender
//
// SystemVerilog port of rtl/LIB/signext.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module signext (
    input  int len,
    input  logic signin,
    output logic signout,
    input  logic clk,
    input  logic rstn
);

    int count;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn)
            count <= 0;
        else begin
            if (signin) begin
                count <= len;
                signout <= 1'b1;
            end else if (count > 0)
                count <= count - 1;
            else
                signout <= 1'b0;
        end
    end

endmodule
