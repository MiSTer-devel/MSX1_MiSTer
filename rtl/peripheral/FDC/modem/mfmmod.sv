// MFM modulator
//
// Shared floppy modem library (rtl/peripheral/FDC/modem): drive (fdd) and controllers.
//
// SystemVerilog port of rtl/FDC/mfmmod.vhd of X68000_MiSTer
// (https://github.com/MiSTer-devel/X68000_MiSTer), licensed under the GNU General Public
// License version 3. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module mfmmod (
    input  logic [7:0] txdat,
    input  logic       txwr,
    input  logic       txma1,
    input  logic       txmc2,
    input  logic       brk,
    
    output logic       txemp,
    output logic       txend,
    
    output logic       bitout,
    output logic       writeen,
    
    input  logic       sft,
    input  logic       clk,
    input  logic       rstn
);

    logic [14:0] cursft;
    logic [14:0] nxtsft;
    int          bitcount;
    logic        getnext;
    logic        nxtemp;
    logic        lastlsb;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            nxtemp <= 1'b1;
            nxtsft <= '0;
        end else begin
            if (brk) begin
                nxtemp <= 1'b1;
                nxtsft <= '0;
            end else if (nxtemp) begin
                if (txwr) begin
                    for (int i = 0; i < 7; i++) begin
                        nxtsft[i*2]   <= txdat[i];
                        nxtsft[i*2+1] <= (txdat[i] == 1'b0 && txdat[i+1] == 1'b0) ? 1'b1 : 1'b0;
                    end
                    nxtsft[14] <= txdat[7];
                    nxtemp <= 1'b0;
                end else if (txma1) begin
                    nxtsft <= 15'b100010010001001;
                    nxtemp <= 1'b0;
                end else if (txmc2) begin
                    nxtsft <= 15'b101001000100100;
                    nxtemp <= 1'b0;
                end
            end else begin
                if (getnext)
                    nxtemp <= 1'b1;
            end
        end
    end

    assign txemp = nxtemp & ~(txwr | txma1 | txmc2);

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            getnext  <= 1'b0;
            cursft   <= '1;
            bitout   <= 1'b0;
            writeen  <= 1'b0;
            bitcount <= 0;
            txend    <= 1'b1;
            lastlsb  <= 1'b1;
        end else begin
            bitout  <= 1'b0;
            getnext <= 1'b0;
            if (brk) begin
                writeen  <= 1'b0;
                bitcount <= 0;
            end else if (sft) begin
                if (bitcount > 0) begin
                    bitout   <= cursft[14];
                    cursft   <= {cursft[13:0], 1'b1};
                    bitcount <= bitcount - 1;
                end else begin
                    txend <= 1'b1;
                    if (!nxtemp) begin
                        txend    <= 1'b0;
                        getnext  <= 1'b1;
                        cursft   <= nxtsft;
                        bitout   <= (lastlsb == 1'b0 && nxtsft[14] == 1'b0) ? 1'b1 : 1'b0;
                        lastlsb  <= nxtsft[0];
                        bitcount <= 15;
                        writeen  <= 1'b1;
                    end else begin
                        writeen <= 1'b0;
                    end
                end
            end
        end
    end

endmodule
