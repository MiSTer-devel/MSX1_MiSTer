// receive
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

// Write stream from the controller (WRITE GATE + WRITE DATA) back into sectors of the track
// buffer, MFM or FM as the controller asks (mfm). The disk image has a fixed IBM geometry, so
// only sector contents can change:
//   ID field (A1 A1 A1 FE C H R N CRC): R selects the sector slot (a format writes the IDs);
//   data field (A1 A1 A1 FB/F8, 512 B, CRC): bytes go to the slot, then wr_done when the CRC
//   is good, wr_bad when it is not or the gate closed inside (the slot holds garbage).
// Without an ID in the stream the slot is the one under the head when the gate opened (write
// sector: the controller has just read that ID). Demodulators from the shared modem library.
module receive #(parameter int sysCLK)
(
    input  logic        clk,
    input  logic        reset,
    input  logic        wg,             // writing: gate open, disk turning, not protected
    input  logic        wd,             // WRITE_DATAn
    input  logic        mfm,            // 1 MFM (2 us cells), 0 FM (4 us)
    input  logic  [4:0] spt,
    input  logic        valid,          // the buffer holds the track under the head
    input  logic  [3:0] tx_sector,      // sector slot under the head (transmit)
    output logic        wr_en,
    output logic [12:0] wr_addr,
    output logic  [7:0] wr_data,
    output logic  [3:0] wr_sector,
    output logic        wr_done,
    output logic        wr_bad
);

    // Demodulators restarted with every gate opening, the one not in use held in break
    logic wg_q;
    always_ff @(posedge clk) wg_q <= wg;
    wire  init = wg && !wg_q;

    logic [7:0] mfm_data, fm_data;
    logic       mfm_ed, fm_ed, mfm_a1, fm_fe, fm_fb, fm_f8;
    mfmdem dem_mfm (
        .clk(clk), .rstn(~reset), .init(init), .brk(!wg || !mfm), .datin(wd),
        .bitlen(32'(sysCLK / 500_000)),
        .RXDAT(mfm_data), .RXED(mfm_ed), .DetMA1(mfm_a1), .DetMC2(), .broken(), .curlen()
    );
    fmdem #(.bwidth(sysCLK / 250_000)) dem_fm (
        .clk(clk), .rstn(~reset), .init(init), .brk(!wg || mfm), .datin(wd),
        .bitlen(sysCLK / 250_000),
        .RXDAT(fm_data), .RXED(fm_ed), .DetMF8(fm_f8), .DetMFB(fm_fb), .DetMFC(), .DetMFE(fm_fe), .curlen()
    );

    wire [7:0] rx_data   = mfm ? mfm_data : fm_data;
    wire       rx_ed     = mfm ? mfm_ed : fm_ed;
    wire       a1        = mfm && mfm_a1;
    wire       mark_id   = !mfm && fm_fe;
    wire       mark_data = !mfm && (fm_fb || fm_f8);

    typedef enum logic [1:0] {R_IDLE, R_ID, R_DATA} state_t;
    state_t      state;
    logic        after_a1;              // MFM: the next byte is a mark
    logic  [9:0] cnt;
    logic [15:0] crc;
    logic        crc_hi_ok;
    logic  [7:0] id_r;
    logic        slot_ok;               // the data field has a slot in the image

    // MFM marks: a plain byte FE / FB / F8 right after A1; the CRC preset after the three A1 is
    // CDB4h whichever of them the demodulator caught. FM marks come with their missing clocks.
    wire        byte_ev  = rx_ed && !a1 && !mark_id && !mark_data;
    wire        ev_id    = mfm ? (byte_ev && after_a1 && rx_data == 8'hFE) : mark_id;
    wire        ev_data  = mfm ? (byte_ev && after_a1 && (rx_data == 8'hFB || rx_data == 8'hF8)) : mark_data;
    wire [15:0] crc_mark = FDC::crc16(mfm ? FDC::CRC_A1x3 : FDC::CRC_INIT, rx_data);

    always_ff @(posedge clk) begin
        {wr_en, wr_done, wr_bad} <= '0;
        if (reset) begin
            state    <= R_IDLE;
            after_a1 <= 1'b0;
        end else if (!wg) begin
            if (state == R_DATA && slot_ok) wr_bad <= 1'b1;    // gate closed inside the data field
            state    <= R_IDLE;
            after_a1 <= 1'b0;
        end else begin
            if (init)       wr_sector <= tx_sector;
            if (a1)         after_a1  <= 1'b1;
            else if (rx_ed) after_a1  <= 1'b0;

            case (state)
                R_IDLE:
                    if (ev_id) begin
                        state <= R_ID;
                        cnt   <= '0;
                        crc   <= crc_mark;
                    end else if (ev_data) begin
                        state   <= R_DATA;
                        cnt     <= '0;
                        crc     <= crc_mark;
                        slot_ok <= valid && {1'b0, wr_sector} < spt;
                    end
                R_ID:                                   // C H R N, CRC
                    if (byte_ev) begin
                        cnt <= cnt + 10'd1;
                        case (cnt)
                            10'd0, 10'd1, 10'd3: crc <= FDC::crc16(crc, rx_data);
                            10'd2: begin crc <= FDC::crc16(crc, rx_data); id_r <= rx_data; end
                            10'd4: crc_hi_ok <= crc[15:8] == rx_data;
                            default: begin
                                state <= R_IDLE;
                                if (crc_hi_ok && crc[7:0] == rx_data && id_r != 8'd0 && {3'd0, id_r} <= {6'd0, spt})
                                    wr_sector <= id_r[3:0] - 4'd1;
                            end
                        endcase
                    end
                R_DATA:                                 // 512 B, CRC
                    if (byte_ev) begin
                        cnt <= cnt + 10'd1;
                        if (cnt < 10'd512) begin
                            crc     <= FDC::crc16(crc, rx_data);
                            wr_en   <= slot_ok;
                            wr_addr <= {wr_sector, cnt[8:0]};
                            wr_data <= rx_data;
                        end else if (cnt == 10'd512) begin
                            crc_hi_ok <= crc[15:8] == rx_data;
                        end else begin
                            state <= R_IDLE;
                            if (slot_ok) begin
                                if (crc_hi_ok && crc[7:0] == rx_data) wr_done <= 1'b1;
                                else                                  wr_bad  <= 1'b1;
                            end
                        end
                    end
                default: state <= R_IDLE;
            endcase
        end
    end

endmodule
