// Digital input filter
//
// SystemVerilog port of rtl/LIB/digifilter.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module digifilter(
    input D,
    output reg Q,

    input clk,
    input rstn
);
    logic LAST;

    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            LAST <= 1'b1;
            Q <= 1'b1;
        end else begin
            reg TMPA, TMPO;
            TMPA = LAST;
            TMPO = LAST;
            for (int i = 0; i < 1; i++) begin
                TMPA = TMPA & LAST;
                TMPO = TMPO | LAST;
            end

            if (TMPA == TMPO) begin
                Q <= LAST;
            end

            LAST <= D;
        end
    end
endmodule