// WD279x FDC
//
// Copyright (c) 2024-2025 Molekula
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

module wd279x_demodulator #(parameter sysCLK)
(
    input  logic        clk,
    input  logic        MRn,
    input  logic        INDEXn,
    input  logic        DDENn,
    input  logic        RAWRDn,
    input  logic [1:0]  len_add,        // added to N of the ID for the data length (WD2795/7 L = 0: 1)
    output logic [7:0]  IDAM_data[6],
    output logic [7:0]  fdd_data,
    output logic        fdd_rx,
    output logic        IDAM_valid,
    output logic        IDAM_done,      // 1 clk: an ID field is complete (any CRC)
    output logic        IDAM_crc_ok,    // with IDAM_done
    output logic        DAM_valid,
    output logic        DAM_deleted,
    output logic        DAM_CRC_valid
);

    // Interní signály
    logic        IDAM;
    logic [7:0]  DAM_crc[2];
    logic [10:0] DATA_counter;          // up to 1024 bytes (N = 3)
    logic [1:0]  check_crc;
    logic [1:0]  a1_cnt;
    logic [2:0]  sec_id_cnt;
    logic        crc_calc, crcwr;

    // FM a MFM dekodér
    logic [7:0]  fm_data, mfm_data;
    logic        fm_rx, mfm_rx;
    logic        mfm_a1, mfm_c2;
    logic        fm_fe, fm_fb, fm_f8, fm_fc;        // FM marks (missing clocks), with fm_rx

    // Přepínání mezi FM a MFM
    assign fdd_data = DDENn ? fm_data : mfm_data;
    assign fdd_rx   = DDENn ? fm_rx   : mfm_rx;

    // Validace CRC pro DAM
    assign DAM_CRC_valid = crc_out == {DAM_crc[0], DAM_crc[1]};

    // CRC of the field: runs while crc_calc, the result is held in crc_out when it drops
    logic [15:0] crc_reg = FDC::CRC_INIT, crc_out;
    logic        crc_calc_q;
    always_ff @(posedge clk) begin
        crc_calc_q <= crc_calc;
        if (crc_calc) begin
            if (fdd_rx | crcwr) crc_reg <= FDC::crc16(crc_reg, fdd_data);
        end else if (crc_calc_q) begin
            crc_reg <= FDC::CRC_INIT;
            crc_out <= crc_reg;
        end
    end

    // --- FM dekodér: 4 us cells (250 kbit/s media written in FM) ---
    fmdem #(.bwidth(sysCLK / 250_000)) fmdem_i (
        .clk(clk),
        .rstn(MRn),
        .datin(RAWRDn),
        .bitlen(sysCLK / 250_000),
        .RXDAT(fm_data),
        .RXED(fm_rx),
        .DetMF8(fm_f8),
        .DetMFB(fm_fb),
        .DetMFC(fm_fc),
        .DetMFE(fm_fe)
    );

    // --- MFM dekodér: 2 us cells ---
    mfmdem mfmdem_i (
        .clk(clk),
        .rstn(MRn),
        .datin(RAWRDn),
        .bitlen(sysCLK / 500_000),
        .RXDAT(mfm_data),
        .RXED(mfm_rx),
        .DetMA1(mfm_a1),
        .DetMC2(mfm_c2)
    );

    // --- Hlavní stavový automat ---
    always_ff @(posedge clk) begin
        crcwr     <= 0;
        IDAM_done <= 0;

        if (~MRn) begin
            a1_cnt      <= 0;
            IDAM        <= 0;
            crc_calc    <= 0;
            IDAM_valid  <= 0;
            DAM_valid   <= 0;
        end else begin
            if (~INDEXn || mfm_c2 || (DDENn && fm_fc)) begin
                IDAM_valid <= 0;
                DAM_valid  <= 0;
                a1_cnt     <= 0;
            end

            // Marks are not looked for inside a data field: the chip counts 128 << N bytes
            if (!DDENn && mfm_a1 && !DAM_valid) begin
                a1_cnt     <= a1_cnt + 2'd1;
                crc_calc   <= 1;
                crcwr      <= (a1_cnt == 0);
            end else if (fdd_rx || mfm_c2) begin
                a1_cnt <= 0;
            end

            // Detekce ID Address Mark (0xFE): MFM after three A1
            if (!DDENn && a1_cnt == 3 && fdd_rx) begin
                if (mfm_data == 8'hFE) begin
                    IDAM_valid <= 0;
                    a1_cnt     <= 0;
                    sec_id_cnt <= 0;
                    IDAM       <= 1;
                end else if (IDAM_valid && (mfm_data == 8'hFB || mfm_data == 8'hF8)) begin
                    DATA_counter <= 11'd128 << 2'(IDAM_data[3][1:0] + len_add);
                    DAM_valid    <= 1;
                    DAM_deleted  <= (mfm_data == 8'hF8);
                end else begin
                    crc_calc <= 0;
                end
            end

            // FM: the marks carry their missing clocks; the CRC starts at the mark (crcwr)
            if (DDENn && fm_fe && !DAM_valid) begin
                IDAM_valid <= 0;
                sec_id_cnt <= 0;
                IDAM       <= 1;
                crc_calc   <= 1;
                crcwr      <= 1;
            end
            if (DDENn && (fm_fb || fm_f8) && IDAM_valid && !DAM_valid) begin
                DATA_counter <= 11'd128 << 2'(IDAM_data[3][1:0] + len_add);
                DAM_valid    <= 1;
                DAM_deleted  <= fm_f8;
                crc_calc     <= 1;
                crcwr        <= 1;
            end

            // Ukládání IDAM dat a CRC kontrola
            if (IDAM && fdd_rx) begin
                IDAM_data[sec_id_cnt] <= fdd_data;
                sec_id_cnt <= sec_id_cnt + 3'd1;

                if (sec_id_cnt == 3)
                    crc_calc <= 0;

                if (sec_id_cnt == 5) begin
                    IDAM <= 0;
                    sec_id_cnt <= 0;
                    IDAM_done   <= 1;
                    IDAM_crc_ok <= crc_out == {IDAM_data[4], fdd_data};
                    if (crc_out == {IDAM_data[4], fdd_data})
                        IDAM_valid <= 1;
                end
            end

            // Přenos datového sektoru
            if (DAM_valid && DATA_counter > 0 && fdd_rx) begin
                DATA_counter <= DATA_counter - 11'd1;
                if (DATA_counter == 1) begin
                    DAM_valid <= 0;
                    crc_calc <= 0;
                    check_crc <= 2;
                end
            end

            // Zápis CRC bajtů po datech
            if (check_crc > 0 && fdd_rx) begin
                check_crc <= check_crc - 2'd1;
                DAM_crc[2 - check_crc] <= fdd_data;
            end
        end
    end

endmodule
