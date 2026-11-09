// Not ready detection
//
// SystemVerilog port of rtl/FDC/nrdet.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module nrdet #(
    parameter int TOms = 800
)(
    input  logic start,
    input  logic RDY,
    
    output logic NOTRDY,
    
    input  logic mssft,
    input  logic clk,
    input  logic rstn
);

    typedef enum logic {
        ST_IDLE,
        ST_WAIT
    } state_t;

    state_t state;
    int wcount;
    
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state   <= ST_IDLE;
            NOTRDY  <= 1'b0;
            wcount  <= 0;
        end else begin
            NOTRDY <= 1'b0;
            if (start) begin
                state  <= ST_WAIT;
                wcount <= TOms - 1;
            end else if (state == ST_WAIT) begin
                if (RDY) begin
                    state  <= ST_IDLE;
                    wcount <= 0;
                end else if (mssft) begin
                    if (wcount > 0) begin
                        wcount <= wcount - 1;
                    end else begin
                        NOTRDY <= 1'b1;
                        state  <= ST_IDLE;
                    end
                end
            end
        end
    end

endmodule
