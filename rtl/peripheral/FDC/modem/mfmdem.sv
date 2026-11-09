// MFM demodulator
//
// Shared floppy modem library (rtl/peripheral/FDC/modem): drive (fdd) and controllers.
//
// SystemVerilog port of rtl/FDC/mfmdem.vhd of X68000_MiSTer
// (https://github.com/MiSTer-devel/X68000_MiSTer), licensed under the GNU General Public
// License version 3. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module mfmdem #(
    parameter int bwidth = 88,
    parameter int fben   = 1
)(
    input  logic                   clk,
    input  logic                   rstn,
    input  logic                   init,
    input  logic                   brk,
    input  logic                   datin,
    input  logic  [31:0]           bitlen,

    output logic [7:0]             RXDAT,
    output logic                   RXED,
    output logic                   DetMA1,
    output logic                   DetMC2,
    output logic                   broken,
    output int                     curlen
);

    logic                 mfmsync;
    logic [31:0]          datsft;
    logic                 dpulse;
    logic [3:0]           ldatin;
    logic                 nodat;
    logic                 datum;
    logic                 sft;
    logic                 lsft;
    logic                 daterr;
    logic [3:0]           charcount;
    logic                 lastd, lasti;
    
    int                   lencount;
    int                   curwidth;
    int                   synccount;

    localparam int chksync = 40;

    logic last_datin;
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            dpulse  <= 1'b0;
        end else begin
            if (last_datin && ~datin) 
                dpulse <= 1'b1; 
            else 
                dpulse <= 1'b0;            
            last_datin <= datin;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            nodat      <= 1'b1;
            lencount   <= 0;
            curwidth   <= bwidth;
            datum      <= 1'b0;
            sft        <= 1'b0;
            lastd      <= 1'b0;
            lasti      <= 1'b0;
            synccount  <= chksync - 1;
        end else begin
            sft <= 1'b0;
            if (init) begin
                nodat     <= 1'b1;
                curwidth  <= bitlen;
                synccount <= chksync - 1;
            end else if (brk) begin
                nodat     <= 1'b1;
            end else if (nodat) begin
                if (dpulse) begin
                    lencount <= 1;
                    nodat    <= 1'b0;
                end
            end else if (daterr) begin
                synccount <= chksync - 1;
                curwidth  <= bitlen;
            end else begin
                if (dpulse) begin
                    if (synccount > 0) begin
                        synccount <= synccount - 1;
                    end else begin
                        datum <= 1'b1;
                        sft   <= 1'b1;
                    end

                    if (fben != 0) begin
                        if (lencount == curwidth) begin
                            lastd <= 1'b0;
                            lasti <= 1'b0;
                        end else if (lencount > curwidth) begin
                            if (curwidth < (bitlen + (bitlen / 2))) begin
                                if (lasti) begin
                                    curwidth <= curwidth + 1;
                                    lasti    <= 1'b0;
                                end else begin
                                    lasti <= 1'b1;
                                end
                                lastd <= 1'b0;
                            end
                        end else begin
                            if (curwidth > (bitlen / 2)) begin
                                if (lastd) begin
                                    curwidth <= curwidth - 1;
                                    lastd    <= 1'b0;
                                end else begin
                                    lastd <= 1'b1;
                                end
                                lasti <= 1'b0;
                            end
                        end
                    end
                    lencount <= 1;
                end else begin
                    if (lencount == (curwidth + (curwidth / 2))) begin
                        if (synccount == 0) begin
                            datum <= 1'b0;
                            sft   <= 1'b1;
                        end
                        lencount <= (curwidth / 2) + 1;
                    end else begin
                        lencount <= lencount + 1;
                    end
                end
            end
        end
    end

    assign curlen = curwidth;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            datsft <= 32'b0;
            lsft   <= 1'b0;
        end else begin
            if (brk || init) begin
                datsft <= 32'b0;
            end else if (sft) begin
                datsft <= {datsft[30:0], datum};
            end
            lsft <= sft;
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            RXDAT     <= 8'b0;
            RXED      <= 1'b0;
            DetMC2    <= 1'b0;
            DetMA1    <= 1'b0;
            mfmsync   <= 1'b0;
            charcount <= 4'b0;
            daterr    <= 1'b0;
        end else begin
            RXED      <= 1'b0;
            DetMC2    <= 1'b0;
            DetMA1    <= 1'b0;
            daterr    <= 1'b0;

            if (brk || init) begin
                mfmsync   <= 1'b0;
                charcount <= 4'b0;
            end else if (lsft) begin
                if (datsft[1:0] == 2'b11 || datsft[4:0] == 5'b10000) begin
                    mfmsync   <= 1'b0;
                    charcount <= 4'b0;
                    daterr    <= 1'b1;
                end
                if (datsft[15:0] == 16'b0100010010001001) begin
                    mfmsync   <= 1'b1;
                    charcount <= 4'b0;
                    DetMA1    <= 1'b1;
                    RXED      <= 1'b1;
                end else if (datsft == 32'b01010010001001000101001000100100) begin
                    mfmsync   <= 1'b1;
                    charcount <= 4'b0;
                    DetMC2    <= 1'b1;
                    RXED      <= 1'b1;
                end else if (mfmsync) begin
                    if (charcount == 4'd15) begin
                        RXED      <= 1'b1;
                        charcount <= 4'b0;
                    end else begin
                        charcount <= charcount + 4'd1;
                    end
                end
                RXDAT <= {datsft[14], datsft[12], datsft[10], datsft[8], datsft[6], datsft[4], datsft[2], datsft[0]};
            end
        end
    end

    assign broken = daterr;

endmodule
