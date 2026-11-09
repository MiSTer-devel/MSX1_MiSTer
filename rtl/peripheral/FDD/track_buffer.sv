// track_buffer
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

// Track buffer: keeps the sectors of the track under the head (drive, cylinder, head) and
// reloads them from the drive's image (HPS block device) when the head moves to another
// track or the image is (re)mounted. One transfer at a time. 'ready' only when the buffer
// holds that track.
// Writes: the controller's bytes land in the buffer (port B); a complete sector (wr_done) is
// marked dirty and flushed to the image one sector per transfer. A new track is loaded only
// after the flushes, so a write followed by a step still reaches the image. A broken write
// (wr_bad) reloads the track; a changed image drops the pending writes.
module track_buffer #(parameter ID = 0)
(
    input  logic        clk,
    input  logic        reset,
    block_device_if.device_mp block_device[2],
    input  logic        want,           // a recorded track is under the head
    input  logic        drive,
    input  logic  [6:0] track,
    input  logic        head,
    input  logic        disk_ds,        // image geometry of the selected drive
    input  logic  [4:0] spt,
    input  logic  [1:0] changed,        // image of drive i (re)mounted (1 clk)
    input  logic [12:0] buffer_addr,
    output logic  [7:0] buffer_q,
    output logic        ready,
    input  logic        wr_en,          // byte of the controller into the buffer
    input  logic [12:0] wr_addr,
    input  logic  [7:0] wr_data,
    input  logic  [3:0] wr_sector,
    input  logic        wr_done,        // sector wr_sector complete (1 clk): flush it
    input  logic        wr_bad          // broken write (1 clk): reload the track
);
    logic  [6:0] buf_track;
    logic        buf_drive, buf_head;
    logic        buf_valid, stale, busy, acked, flushing;
    logic  [1:0] rd, wr;
    logic [12:0] buf_lba;               // first sector of the buffered track in the image
    logic [31:0] rq_lba;
    logic  [5:0] rq_cnt;
    logic [15:0] dirty;                 // written sectors not yet in the image
    logic  [3:0] flush_sector;

    wire  ack   = buf_drive ? block_device[1].ack : block_device[0].ack;
    wire  match = buf_valid && !stale && {buf_drive, buf_track, buf_head} == {drive, track, head};
    assign ready = want && match;

    wire  [7:0] trk_side = disk_ds ? {track, head} : {1'b0, track};     // track * sides + head
    wire [12:0] lba      = {5'd0, trk_side} * {8'd0, spt};

    logic [3:0] first_dirty;
    always_comb begin
        first_dirty = 4'd0;
        for (int s = 15; s >= 0; s--) if (dirty[s]) first_dirty = 4'(s);
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            buf_valid <= 1'b0;
            stale     <= 1'b0;
            busy      <= 1'b0;
            acked     <= 1'b0;
            flushing  <= 1'b0;
            rd        <= '0;
            wr        <= '0;
            dirty     <= '0;
        end else begin
            if (!busy) begin
                if (dirty != '0) begin                  // cleared now: a write meanwhile sets it again
                    flushing           <= 1'b1;
                    flush_sector       <= first_dirty;
                    dirty[first_dirty] <= 1'b0;
                    busy               <= 1'b1;
                    acked              <= 1'b0;
                    wr[buf_drive]      <= 1'b1;
                    rq_lba             <= {19'd0, buf_lba + {9'd0, first_dirty}};
                    rq_cnt             <= 6'd0;
                end else if (want && !match) begin
                    {buf_drive, buf_track, buf_head} <= {drive, track, head};
                    buf_lba   <= lba;
                    buf_valid <= 1'b0;
                    stale     <= 1'b0;
                    busy      <= 1'b1;
                    acked     <= 1'b0;
                    rd[drive] <= 1'b1;
                    rq_lba    <= {19'd0, lba};
                    rq_cnt    <= {1'b0, spt - 5'd1};
                end
            end else begin
                if (ack) begin
                    acked <= 1'b1;
                    rd    <= '0;
                    wr    <= '0;
                end else if (acked) begin               // transfer finished
                    busy     <= 1'b0;
                    flushing <= 1'b0;
                    if (!flushing) buf_valid <= 1'b1;
                end
            end
            if (wr_done && match)   dirty[wr_sector] <= 1'b1;
            if (wr_bad)             stale <= 1'b1;      // reload after the pending flushes
            if (changed[buf_drive]) begin               // also during a load: reload after it
                stale <= 1'b1;
                dirty <= '0;
            end
        end
    end

    assign block_device[0].rd      = rd[0];
    assign block_device[1].rd      = rd[1];
    assign block_device[0].wr      = wr[0];
    assign block_device[1].wr      = wr[1];
    assign block_device[0].lba     = rq_lba;
    assign block_device[1].lba     = rq_lba;
    assign block_device[0].blk_cnt = rq_cnt;
    assign block_device[1].blk_cnt = rq_cnt;

    // HPS side, port A: a load writes the sectors (buff_wr is shared by all virtual disks, only
    // the transfer acknowledged for this drive may write), a flush reads the dirty sector.
    wire [13:0] sd_addr = buf_drive ? block_device[1].buff_addr : block_device[0].buff_addr;
    wire  [7:0] sd_data = buf_drive ? block_device[1].buff_dout : block_device[0].buff_dout;
    wire        sd_wr   = !flushing && (buf_drive ? block_device[1].buff_wr && block_device[1].ack
                                                  : block_device[0].buff_wr && block_device[0].ack);
    wire [12:0] addr_a  = flushing ? {flush_sector, sd_addr[8:0]} : sd_addr[12:0];
    wire  [7:0] q_a;
    assign block_device[0].buff_din = q_a;
    assign block_device[1].buff_din = q_a;

    dpram #(.addr_width(13), .mem_name(ID)) track_dpram (
        .clock(clk),
        .address_a(addr_a),
        .data_a(sd_data),
        .wren_a(sd_wr),
        .q_a(q_a),
        .address_b(wr_en ? wr_addr : buffer_addr),
        .wren_b(wr_en),
        .data_b(wr_data),
        .q_b(buffer_q)
    );

endmodule
