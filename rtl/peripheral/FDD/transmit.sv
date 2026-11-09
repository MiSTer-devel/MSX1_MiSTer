// transmit
//
// Copyright (c) 2025-2026 Molekula
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

// Flux stream of one formatted IBM track, regenerated every rotation from the track buffer:
// index gap, IAM, then per sector the ID field and the data field with CRC. MFM or FM as the
// controller asks (mfm); the gaps and marks follow the IBM layout of that encoding.
// A sector (and the IAM) is recorded only while 'valid' (the buffer holds this track);
// otherwise it reads as gap without address marks, so a controller never gets stale data.
module transmit
(
    input  logic        clk,
    input  logic        reset,
    input  logic        index,          // start of a rotation (1 clk)
    input  logic        cell_en,        // MFM bit cell enable (2 cells per data bit)
    input  logic        mfm,            // 1 MFM, 0 FM (half the data rate)
    input  logic  [4:0] spt,            // sectors per track (512 B each)
    input  logic  [6:0] cyl,            // ID field C
    input  logic        hd,             // ID field H
    input  logic        valid,
    output logic [12:0] buffer_addr,
    input  logic  [7:0] buffer_q,
    output logic        flux,           // 1 clk pulse per flux transition
    output logic  [3:0] sector_out      // sector slot under the head (0 based); a write lands here
);

    typedef enum logic [4:0] {
        F_GAP4A, F_SYNC0, F_IAM_M, F_IAM, F_GAP1,
        F_SYNC1, F_IDAM_M, F_IDAM, F_ID, F_ICRC, F_GAP2,
        F_SYNC2, F_DAM_M, F_DAM, F_DATA, F_DCRC, F_GAP3,
        F_GAP4B
    } field_t;

    wire [7:0] gap = mfm ? 8'h4E : 8'hFF;

    function automatic logic [9:0] field_len(input field_t f, input logic m);
        case (f)
            F_GAP4A:                     return m ? 10'd80 : 10'd40;
            F_SYNC0, F_SYNC1, F_SYNC2:   return m ? 10'd12 : 10'd6;
            F_IAM_M, F_IDAM_M, F_DAM_M:  return 10'd3;
            F_GAP1:                      return m ? 10'd50 : 10'd26;
            F_ID:                        return 10'd4;
            F_ICRC, F_DCRC:              return 10'd2;
            F_GAP2:                      return m ? 10'd22 : 10'd11;
            F_DATA:                      return 10'd512;
            F_GAP3:                      return m ? 10'd84 : 10'd42;
            default:                     return 10'd1;      // marks; GAP4B lasts until index
        endcase
    endfunction

    function automatic field_t next_field(input field_t f, input logic last_sector, input logic m);
        case (f)
            F_GAP4A:  return F_SYNC0;
            F_SYNC0:  return m ? F_IAM_M : F_IAM;
            F_IAM_M:  return F_IAM;
            F_IAM:    return F_GAP1;
            F_GAP1:   return F_SYNC1;
            F_SYNC1:  return m ? F_IDAM_M : F_IDAM;
            F_IDAM_M: return F_IDAM;
            F_IDAM:   return F_ID;
            F_ID:     return F_ICRC;
            F_ICRC:   return F_GAP2;
            F_GAP2:   return F_SYNC2;
            F_SYNC2:  return m ? F_DAM_M : F_DAM;
            F_DAM_M:  return F_DAM;
            F_DAM:    return F_DATA;
            F_DATA:   return F_DCRC;
            F_DCRC:   return F_GAP3;
            F_GAP3:   return last_sector ? F_GAP4B : F_SYNC1;
            default:  return F_GAP4B;
        endcase
    endfunction

    field_t      field;
    logic  [9:0] cnt;
    logic  [3:0] sector;
    logic  [4:0] spt_l;
    logic        sec_ok;                // current sector is recorded
    logic [15:0] crc;
    logic  [7:0] txdat;
    typedef enum logic [2:0] {M_A1, M_C2, M_FC, M_FE, M_FB} mark_t;
    logic        txwr, txmark;
    mark_t       mark;
    logic        mfm_txemp, fm_txemp, mfm_bit, fm_bit;
    wire         txemp = mfm ? mfm_txemp : fm_txemp;

    assign buffer_addr = {sector, cnt[8:0]};
    assign sector_out  = sector;

    // byte to send now; FM marks carry their own missing clocks and start the CRC
    logic  [7:0] b;
    logic        b_mark, b_crc_init, b_crc_upd;
    mark_t       b_kind;
    wire   in_sector = field >= F_SYNC1 && field <= F_GAP3;
    wire   rec       = in_sector ? sec_ok : (field == F_IAM_M || field == F_IAM) ? valid : 1'b1;
    always_comb begin
        b = gap;
        {b_mark, b_crc_init, b_crc_upd} = '0;
        b_kind = M_A1;
        case (field)
            F_SYNC0, F_SYNC1, F_SYNC2: b = 8'h00;
            F_IAM_M:  begin b = 8'hC2; b_mark = 1'b1; b_kind = M_C2; end
            F_IAM:    begin b = 8'hFC; b_mark = !mfm; b_kind = M_FC; end
            F_IDAM_M, F_DAM_M: begin b = 8'hA1; b_mark = 1'b1; b_crc_upd = 1'b1; b_crc_init = cnt == 0; end
            F_IDAM:   begin b = 8'hFE; b_mark = !mfm; b_kind = M_FE; b_crc_upd = 1'b1; b_crc_init = !mfm; end
            F_DAM:    begin b = 8'hFB; b_mark = !mfm; b_kind = M_FB; b_crc_upd = 1'b1; b_crc_init = !mfm; end
            F_ID: begin
                b_crc_upd = 1'b1;
                case (cnt[1:0])
                    2'd0: b = {1'b0, cyl};
                    2'd1: b = {7'd0, hd};
                    2'd2: b = {3'd0, sector + 5'd1};
                    2'd3: b = 8'd2;                       // 512 B
                endcase
            end
            F_DATA:   begin b = buffer_q; b_crc_upd = 1'b1; end
            F_ICRC, F_DCRC: b = cnt[0] ? crc[7:0] : crc[15:8];
            default: ;
        endcase
        if (!rec) begin
            b = gap;
            {b_mark, b_crc_init, b_crc_upd} = '0;
        end
    end

    always_ff @(posedge clk) begin
        {txwr, txmark} <= '0;
        if (reset) begin
            field  <= F_GAP4B;
            cnt    <= '0;
            sector <= '0;
            spt_l  <= 5'd9;
            sec_ok <= 1'b0;
        end else begin
            if (!valid) sec_ok <= 1'b0;
            if (index) begin
                field  <= F_GAP4A;
                cnt    <= '0;
                sector <= '0;
                spt_l  <= spt;
            end else if (txemp) begin
                txdat  <= b;
                mark   <= b_kind;
                txmark <= b_mark;
                txwr   <= !b_mark;
                if (b_crc_upd) crc <= FDC::crc16(b_crc_init ? FDC::CRC_INIT : crc, b);
                if (field != F_GAP4B) begin
                    if (cnt == field_len(field, mfm) - 10'd1) begin
                        field <= next_field(field, {1'b0, sector} == spt_l - 5'd1, mfm);
                        cnt   <= '0;
                        if (field == F_GAP3) sector <= sector + 4'd1;
                        if (field == F_GAP1 || field == F_GAP3) sec_ok <= valid;
                    end else
                        cnt <= cnt + 10'd1;
                end
            end
        end
    end

    // Modulators of the modem library; the one not in use is held in break.
    // FM uses every 2nd cell (half the data rate of MFM on the same medium)
    logic half = 1'b0;
    always_ff @(posedge clk) if (cell_en) half <= ~half;

    mfmmod mod_mfm (
        .txdat(txdat), .txwr(txwr && mfm), .brk(!mfm),
        .txma1(txmark && mfm && mark == M_A1), .txmc2(txmark && mfm && mark == M_C2),
        .txemp(mfm_txemp), .txend(), .bitout(mfm_bit), .writeen(), .sft(cell_en),
        .clk(clk), .rstn(~reset)
    );
    fmmod mod_fm (
        .txdat(txdat), .txwr(txwr && !mfm), .txmf8(1'b0), .txmfb(txmark && !mfm && mark == M_FB),
        .txmfc(txmark && !mfm && mark == M_FC), .txmfe(txmark && !mfm && mark == M_FE),
        .brk(mfm), .sft(cell_en && half), .clk(clk), .rstn(~reset),
        .txemp(fm_txemp), .txend(), .bitout(fm_bit), .writeen()
    );
    assign flux = mfm ? mfm_bit : fm_bit;

endmodule
