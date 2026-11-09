// WD279x FDC
//
// Copyright (c) 2026 Molekula
//
// This program is free software: you can redistribute it and/or modify it under the terms of
// the GNU General Public License as published by the Free Software Foundation, either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
// without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with this program.
// If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: GPL-3.0-or-later
//

// Write side of the controller: bytes of the command state machines go out as MFM (or FM with
// DDENn) flux transitions through the modulators of the shared modem library. One byte is
// given while tx_req (the modulator buffers it and shifts the previous one), tx_crc sends the
// two CRC bytes of the field: the CRC is preset by the first A1 of a run (MFM) or by the mark
// (FM) and updated with every byte after it. byte_tick is a free running byte time for the
// gaps a command waits through with the gate closed.
module wd279x_modulator #(parameter sysCLK)
(
    input  logic        clk,
    input  logic        MRn,
    input  logic        DDENn,          // 1 = FM
    input  logic        wg,             // write gate of the command
    input  logic        tx_wr,          // data byte tx_data
    input  logic        tx_a1,          // MFM A1 with the missing clock
    input  logic        tx_c2,          // MFM C2 with the missing clock
    input  logic        tx_mark,        // address mark tx_data (FE FB F8 FC); FM with the missing clock
    input  logic        tx_crc,         // the two CRC bytes
    input  logic  [7:0] tx_data,
    output logic        tx_req,         // a byte can be given now
    output logic        tx_idle,        // nothing buffered, nothing shifting
    output logic        byte_tick,      // one byte time (1 clk), free running
    output logic        WG,
    output logic        WD              // 1 clk pulse per flux transition
);

    // Bit cell 500 kHz (250 kbit/s MFM); FM uses every second cell
    logic cell_en, half = 1'b0;
    clockEnabler #(.clkFreq(sysCLK), .targetFreq(500000)) CELL (.clk(clk), .en(cell_en));
    always_ff @(posedge clk) if (cell_en) half <= ~half;
    wire sft = DDENn ? cell_en && half : cell_en;

    logic [3:0] cell_cnt = '0;
    always_ff @(posedge clk) if (sft) cell_cnt <= cell_cnt + 4'd1;
    assign byte_tick = sft && cell_cnt == 4'd15;

    logic mfm_txemp, mfm_txend, mfm_bit, fm_txemp, fm_txend, fm_bit;

    // CRC of the field; the second CRC byte goes out by itself (registered strobe, the empty
    // flag of the modulator depends on the strobes) when the modulator takes the first one
    logic [15:0] crc;
    logic        a1_run, crc_lo, crc_lo_wr;
    wire         txemp_raw = DDENn ? fm_txemp : mfm_txemp;
    wire   [7:0] d         = crc_lo ? crc[7:0] : tx_crc ? crc[15:8] : tx_data;
    wire         wr        = tx_wr | tx_crc | crc_lo_wr;

    always_ff @(posedge clk) begin
        crc_lo_wr <= 1'b0;
        if (!MRn || !wg) begin
            crc    <= FDC::CRC_INIT;
            a1_run <= 1'b0;
            crc_lo <= 1'b0;
        end else begin
            if (tx_a1)     begin crc <= FDC::crc16(a1_run ? crc : FDC::CRC_INIT, 8'hA1); a1_run <= 1'b1; end
            if (tx_mark)   begin crc <= FDC::crc16(DDENn ? FDC::CRC_INIT : crc, tx_data); a1_run <= 1'b0; end
            if (tx_wr)     begin crc <= FDC::crc16(crc, tx_data); a1_run <= 1'b0; end
            if (tx_c2)     a1_run <= 1'b0;
            if (tx_crc)    begin crc_lo <= 1'b1; a1_run <= 1'b0; end
            if (crc_lo && txemp_raw && !crc_lo_wr) crc_lo_wr <= 1'b1;
            if (crc_lo_wr) crc_lo <= 1'b0;
        end
    end

    assign tx_req  = txemp_raw && !crc_lo;
    assign tx_idle = txemp_raw && !crc_lo && (DDENn ? fm_txend : mfm_txend);

    // Modulators: the unused one is held in break
    mfmmod mfm (
        .txdat(d), .txwr(wr | tx_mark), .txma1(tx_a1), .txmc2(tx_c2), .brk(!wg || DDENn),
        .txemp(mfm_txemp), .txend(mfm_txend), .bitout(mfm_bit), .writeen(),
        .sft(cell_en), .clk(clk), .rstn(MRn)
    );
    fmmod fm (
        .txdat(d), .txwr(wr),
        .txmf8(tx_mark && tx_data == 8'hF8), .txmfb(tx_mark && tx_data == 8'hFB),
        .txmfc(tx_mark && tx_data == 8'hFC), .txmfe(tx_mark && tx_data == 8'hFE),
        .brk(!wg || !DDENn), .sft(cell_en && half), .clk(clk), .rstn(MRn),
        .txemp(fm_txemp), .txend(fm_txend), .bitout(fm_bit), .writeen()
    );

    assign WG = wg;
    assign WD = DDENn ? fm_bit : mfm_bit;

endmodule
