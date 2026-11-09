// FM demodulator
//
// Shared floppy modem library (rtl/peripheral/FDC/modem): drive (fdd) and controllers.
//
// SystemVerilog port of rtl/FDC/fmdem.vhd of X68000_MiSTer
// (https://github.com/MiSTer-devel/X68000_MiSTer), licensed under the GNU General Public
// License version 3. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module fmdem #(
    parameter int bwidth = 22
)(
    input  int                bitlen,
    input  logic              datin,
    input  logic              init,
    input  logic              brk,
    output logic [7:0]        RXDAT,
    output logic              RXED,
    output logic              DetMF8,
    output logic              DetMFB,
    output logic              DetMFC,
    output logic              DetMFE,
    //output logic              broken,
    output int                curlen,
    input  logic              clk,
    input  logic              rstn
);

    logic fmsync;
    logic [31:0] datsft;
    int lencount;
    int curwidth;
    logic dpulse;
    logic [3:0] ldatin;
    logic nodat;
    logic datum;
    logic sft;
    logic lsft;
//    logic daterr;
    int charcount;
    localparam int chksync = 20;
    int synccount;

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
            synccount  <= chksync - 1;
        end else begin
            sft <= 1'b0;
            if (init) begin 
                nodat     <= 1'b1;
                curwidth  <= bitlen;
                synccount <= chksync - 1;
//            end else if (daterr) begin
//            ;
            end else if (brk) begin
                nodat <= 1'b1;
            end else if (nodat) begin
                if (dpulse) begin
                    lencount <= 0;
                    nodat    <= 1'b0;
                end
            end else begin
                if (dpulse) begin
                    if (synccount > 0)
                        synccount <= synccount - 1;
                    else begin
                        datum <= 1'b1;
                        sft   <= 1'b1;
                    end
                    if (lencount > curwidth) begin
                        if (curwidth < (bitlen + (bitlen >> 1)))
                            curwidth <= curwidth + 1;
                    end else begin
                        if (curwidth > (bitlen >> 1))
                            curwidth <= curwidth - 1;
                    end
                    lencount <= 0;
                end else begin
                    if (lencount == (curwidth + (curwidth >> 1))) begin
                        if (synccount == 0) begin
                            datum <= 1'b0;
                            sft   <= 1'b1;
                        end
                        lencount <= (curwidth >> 1) + 1;
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
            datsft <= '0;
            lsft   <= 1'b0;
        end else begin
            if (brk)
                datsft <= '0;
            else if (sft)
                datsft <= {datsft[30:0], datum};
            lsft <= sft;
        end
    end

    // wire [15:0] dbg_datsft_clk = {datsft[31], datsft[29], datsft[27], datsft[25], datsft[23], datsft[21], datsft[19], datsft[17], datsft[15], datsft[13], datsft[11], datsft[9], datsft[7], datsft[5], datsft[3], datsft[1]};
    // wire [15:0] dbg_datsft_dat = {datsft[30], datsft[28], datsft[26], datsft[24], datsft[22], datsft[20], datsft[18], datsft[16], datsft[14], datsft[12], datsft[10], datsft[8], datsft[6], datsft[4], datsft[2], datsft[0]};
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            RXDAT    <= '0;
            RXED     <= 1'b0;
            DetMF8   <= 1'b0;
            DetMFB   <= 1'b0;
            DetMFC   <= 1'b0;
            DetMFE   <= 1'b0;
            fmsync   <= 1'b0;
            charcount <= 0;
//            daterr   <= 1'b0;
        end else begin
            RXED     <= 1'b0;
            DetMF8   <= 1'b0;
            DetMFB   <= 1'b0;
            DetMFC   <= 1'b0;
            DetMFE   <= 1'b0;
//            daterr   <= 1'b0;
            if (brk || init) begin
                fmsync   <= 1'b0;
                charcount <= 0;
            end else if (lsft) begin
                case (datsft)
                    32'b10101010101010101111010101101010: begin fmsync <= 1'b1; RXED <= 1'b1; charcount <= 0; DetMF8 <= 1'b1; end
                    32'b10101010101010101111010101101111: begin fmsync <= 1'b1; RXED <= 1'b1; charcount <= 0; DetMFB <= 1'b1; end
                    32'b10101010101010101111011101111010: begin fmsync <= 1'b1; RXED <= 1'b1; charcount <= 0; DetMFC <= 1'b1; end
                    32'b10101010101010101111010101111110: begin fmsync <= 1'b1; RXED <= 1'b1; charcount <= 0; DetMFE <= 1'b1; end
                    default: begin
                        if (fmsync && (charcount % 2 == 0) && !datsft[0]) begin
                            fmsync <= 1'b0;
                            charcount <= 0;
//                            daterr <= 1'b1;
                        end else if (fmsync) begin
                            if (charcount == 15) begin
                                RXED <= 1'b1;
                                charcount <= 0;
                            end else
                                charcount <= charcount + 1;
                        end
                    end
                endcase
                RXDAT <= {datsft[14], datsft[12], datsft[10], datsft[8], datsft[6], datsft[4], datsft[2], datsft[0]};
            end
        end
    end

    //assign broken = daterr;
endmodule
