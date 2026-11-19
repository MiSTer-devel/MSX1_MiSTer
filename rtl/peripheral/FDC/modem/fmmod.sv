// FM modulator
//
// Shared floppy modem library (rtl/peripheral/FDC/modem): drive (fdd) and controllers.
//
// SystemVerilog port of rtl/FDC/fmmod.vhd of X68000_MiSTer
// (https://github.com/MiSTer-devel/X68000_MiSTer), licensed under the GNU General Public
// License version 3. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module fmmod (
    input  logic [7:0]  txdat,
    input  logic        txwr,
    input  logic        txmf8,
    input  logic        txmfb,
    input  logic        txmfc,
    input  logic        txmfe,
    input  logic        brk,
    input  logic        sft,
    input  logic        clk,
    input  logic        rstn,

    output logic        txemp,
    output logic        txend,
    output logic        bitout,
    output logic        writeen
);

    logic [14:0] cursft;
    logic [15:0] nxtsft;
    logic [3:0]  bitcount;
    logic        getnext;
    logic        nxtemp;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            nxtemp <= 1'b1;
            nxtsft <= 16'b0;
        end else if (brk) begin
            nxtsft <= 16'b0;
            nxtemp <= 1'b1;
        end else if (nxtemp) begin
            if (txwr) begin
                nxtsft <= {1'b1, txdat[7], 1'b1, txdat[6], 1'b1, txdat[5], 1'b1, txdat[4],
                           1'b1, txdat[3], 1'b1, txdat[2], 1'b1, txdat[1], 1'b1, txdat[0]};
                nxtemp <= 1'b0;
            end else if (txmf8) begin
                nxtsft <= 16'b1111010101101010;
                nxtemp <= 1'b0;
            end else if (txmfb) begin
                nxtsft <= 16'b1111010101101111;
                nxtemp <= 1'b0;
            end else if (txmfc) begin
                nxtsft <= 16'b1111011101111010;
                nxtemp <= 1'b0;
            end else if (txmfe) begin
                nxtsft <= 16'b1111010101111110;
                nxtemp <= 1'b0;
            end
        end else if (getnext) begin
            nxtemp <= 1'b1;
        end
    end

    assign txemp = nxtemp & ~(txwr | txmf8 | txmfb | txmfc | txmfe);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            getnext  <= 1'b0;
            cursft   <= 15'b111111111111111;
            bitout   <= 1'b0;
            writeen  <= 1'b0;
            bitcount <= 4'd0;
            txend    <= 1'b1;
        end else begin
            bitout  <= 1'b0;
            getnext <= 1'b0;

            if (brk) begin
                writeen  <= 1'b0;
                bitcount <= 4'd0;
            end else if (sft) begin
                if (bitcount > 0) begin
                    bitout   <= cursft[14];
                    cursft   <= {cursft[13:0], 1'b1};
                    bitcount <= bitcount - 4'd1;
                end else begin
                    txend <= 1'b1;
                    if (!nxtemp) begin
                        txend    <= 1'b0;
                        getnext  <= 1'b1;
                        cursft   <= nxtsft[14:0];
                        bitout   <= nxtsft[15];
                        bitcount <= 4'd15;
                        writeen  <= 1'b1;
                    end else begin
                        writeen <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
