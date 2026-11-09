// CRC generator
//
// SystemVerilog port of rtl/LIB/CRCGENN.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer). The same FDC code is published under the
// GNU General Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module crcgenn #(
    parameter int DATWIDTH = 10,
    parameter int WIDTH = 3
)(
    input  logic [WIDTH:0]           POLY,
    input  logic [DATWIDTH-1:0]      DATA,
    input  logic                     DIR,
    input  logic                     WRITE,
    input  logic                     BITIN,
    input  logic                     BITWR,
    input  logic                     CLR,
    input  logic [WIDTH-1:0]         CLRDAT,
    output logic [WIDTH-1:0]         CRC,
    output logic                     BUSY,
    output logic                     DONE,
    output logic                     CRCZERO,
    input  logic                     clk,
    input  logic                     rstn
);

    logic [WIDTH-1:0] CRCbuf;
    logic [WIDTH-1:0] CRCdir;
    logic [WIDTH-1:0] CLRDATdir;
    logic [DATWIDTH-1:0] DATbuf;
    int COUNT;
    logic BUSYbuf;

    // Výpočet CRC
    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            CRCbuf   <= '0;
            DATbuf   <= '0;
            COUNT    <= 0;
            DONE     <= 0;
            BUSYbuf  <= 0;
        end else begin
            DONE <= 0;
            if (CLR) begin
                CRCbuf <= CLRDATdir;
                COUNT  <= 0;
            end else if (COUNT > 0) begin
                for (int i = 0; i < WIDTH-1; i++) begin
                    if (POLY[i+1]) begin
                        CRCbuf[i] <= CRCbuf[i+1] ^ CRCbuf[0] ^ DATbuf[0];
                    end else begin
                        CRCbuf[i] <= CRCbuf[i+1];
                    end
                end
                CRCbuf[WIDTH-1] <= (DATbuf[0] & POLY[WIDTH]) ^ CRCbuf[0];
                COUNT <= COUNT - 1;
                DATbuf <= {1'b0, DATbuf[DATWIDTH-1:1]};
                if (COUNT == 1) begin
                    DONE <= 1;
                    BUSYbuf <= 0;
                end
            end

            if (WRITE) begin
                if (DIR) begin
                    DATbuf <= DATA;
                end else begin
                    for (int i = 0; i < DATWIDTH; i++) begin
                        DATbuf[i] <= DATA[DATWIDTH-1-i];
                    end
                end
                COUNT <= DATWIDTH;
                BUSYbuf <= 1;
            end else if (BITWR) begin
                DATbuf <= '0;
                DATbuf[0] <= BITIN;
                COUNT <= 1;
                BUSYbuf <= 1;
            end
        end
    end

    // Otočení CRC a CLRDAT podle DIR
    always_comb begin
        for (int i = 0; i < WIDTH; i++) begin
            CRCdir[i]     = CRCbuf[WIDTH-1 - i];
            CLRDATdir[i]  = CLRDAT[WIDTH-1 - i];
        end
    end

    assign CRC  = (DIR) ? CRCbuf : CRCdir;
    assign BUSY = BUSYbuf | WRITE | BITWR;

    // Kontrola, zda CRC == 0
    assign CRCZERO = ~|CRCbuf;


endmodule
