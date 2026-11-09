// fdd
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

// Floppy disk drive unit: two 3.5" DD drives (300 rpm, 250 kbit/s) on one Shugart style bus
// (FDD_if), disks are DSK images of the HPS block devices block_device[0..1].
// Reads: transmit regenerates the track from the track buffer. Writes: receive decodes the
// controller's stream (WRITE GATE, WRITE DATA) into the buffer, track_buffer flushes the written
// sectors to the image. A write protected image ignores the gate; READ DATA is silent while
// the gate is open. The encoding (MFM / FM) follows the controller (FDD_if.MFM): a real drive
// only moves flux, here the track is regenerated from sectors in the encoding asked for.
//
// The disk geometry comes from the image size (openMSX Disk::detectGeometryFallback, plus
// 8 sectors per track): 720K / 640K double sided, 360K / 320K single sided, 80 tracks.
// The drive properties come from the machine definition (msx_system):
//   drive_ds      0 = single sided drive: side 1 is not ready (openMSX RealDrive::isDiskInserted)
//   need_motor    TRACK0 and WPROT only while the motor runs (openMSX signalsNeedMotorOn: Philips)
//   motor_off_ms  the motor keeps running after it is switched off (openMSX motor_off_timeout_ms)
// Index and data only while the disk turns (motor on, disk in). READY = disk in, as openMSX
// WD2793::isReady (no motor emulation there). A track is loaded after the head settle time
// (SETTLE_MS, 3.5" drive 15 ms, as the WD279x verify delay), so a seek with step rates below
// it (WD279x 6 / 12 ms) loads only the target track.
// Disk change per drive (DSKCHGn[i] = 0): set at power on and when the image of drive i is
// mounted or removed, cleared by the controller with DSKCHG_ACK[i] (openMSX DiskChanger: read
// clears). Used by the Philips glue 7FFDh bit 2 (Sony disk ROMs) and turbo R 7FF1h bits 4/5.
//
// https://map.grauw.nl/articles/low-level-disk/
module fdd #(
    parameter int   sysCLK,
    parameter       ID           = 0,
    parameter int   SETTLE_MS    = 15
)(
    input  logic              clk,
    input  logic              reset,
    FDD_if.FDD_mp             FDD_bus,
    block_device_if.device_mp block_device[2],
    input  logic        [1:0] drive_ds,
    input  logic              need_motor,
    input  logic       [15:0] motor_off_ms
);

    typedef struct packed {
        logic       present;
        logic       ds;             // double sided disk
        logic [4:0] spt;
        logic [6:0] tracks;
    } geometry_t;

    function automatic geometry_t geometry(input logic [63:0] size);
        if (size == 64'd737280)      return '{1'b1, 1'b1, 5'd9, 7'd80};
        else if (size == 64'd655360) return '{1'b1, 1'b1, 5'd8, 7'd80};
        else if (size == 64'd368640) return '{1'b1, 1'b0, 5'd9, 7'd80};
        else if (size == 64'd327680) return '{1'b1, 1'b0, 5'd8, 7'd80};
        else                         return '{1'b0, 1'b0, 5'd9, 7'd0};
    endfunction

    geometry_t geo[2];
    assign geo[0] = geometry(block_device[0].img_size);
    assign geo[1] = geometry(block_device[1].img_size);

    wire [1:0] ro      = {block_device[1].img_readonly, block_device[0].img_readonly};
    wire [1:0] changed = {block_device[1].img_mounted, block_device[0].img_mounted};   // 1 clk event

    wire       sel  = FDD_bus.USEL;
    wire       side = ~FDD_bus.SIDEn;
    geometry_t g;
    assign g = geo[sel];

    // Timing: 1 ms, MFM bit cell (500 kHz), rotation 200 ms with a 4 ms index pulse
    logic msclk, cell_en;
    clockEnabler #(.clkFreq(sysCLK), .targetFreq(1000))   FDD_MS   (.clk(clk), .en(msclk));
    clockEnabler #(.clkFreq(sysCLK), .targetFreq(500000)) FDD_CELL (.clk(clk), .en(cell_en));

    localparam int ROT       = sysCLK / 5;
    localparam int INDEX_LEN = ROT / 50;
    logic [$clog2(ROT)-1:0] angle = '0;
    always_ff @(posedge clk) angle <= angle == ($clog2(ROT))'(ROT - 1) ? '0 : angle + 1'b1;
    wire index_start = angle == '0;

    logic [1:0] motor_run;
    motor FDD_motor (
        .clk(clk), .msclk(msclk), .reset(reset), .off_ms(motor_off_ms),
        .USEL(sel), .MOTORn(FDD_bus.MOTORn), .motor_run(motor_run)
    );

    logic [6:0] head_track;
    track FDD_track (
        .clk(clk), .reset(reset),
        .USEL(sel), .STEPn(FDD_bus.STEPn), .SDIRn(FDD_bus.SDIRn), .track(head_track)
    );

    wire spin      = motor_run[sel];
    wire disk_in   = g.present && (drive_ds[sel] || !side);
    wire rotate    = disk_in && spin;
    wire recorded  = disk_in && head_track < g.tracks && (g.ds || !side);   // formatted track under the head
    wire sig_ok    = !need_motor || spin;
    wire wg        = rotate && !ro[sel] && !FDD_bus.WRITE_GATEn;            // a protected disk ignores the gate

    // Head settle: SETTLE_MS without a step of the selected drive before its track is loaded
    logic [6:0] track_q;
    logic       sel_q;
    logic [4:0] settle;
    always_ff @(posedge clk) begin
        track_q <= head_track;
        sel_q   <= sel;
        if (reset)                                      settle <= 5'd0;
        else if (head_track != track_q && sel == sel_q) settle <= 5'(SETTLE_MS);
        else if (msclk && settle != 5'd0)               settle <= settle - 5'd1;
    end

    logic [12:0] buffer_addr, wr_addr;
    logic  [7:0] buffer_q, wr_data;
    logic  [3:0] tx_sector, wr_sector;
    logic        track_ready, wr_en, wr_done, wr_bad;
    track_buffer #(.ID(ID)) FDD_buffer (
        .clk(clk), .reset(reset), .block_device(block_device),
        .want(recorded && settle == 5'd0), .drive(sel), .track(head_track), .head(side),
        .disk_ds(g.ds), .spt(g.spt), .changed(changed),
        .buffer_addr(buffer_addr), .buffer_q(buffer_q), .ready(track_ready),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_sector(wr_sector),
        .wr_done(wr_done), .wr_bad(wr_bad)
    );

    logic flux;
    transmit FDD_transmit (
        .clk(clk), .reset(reset), .index(index_start), .cell_en(cell_en), .mfm(FDD_bus.MFM),
        .spt(g.spt), .cyl(head_track), .hd(side), .valid(track_ready),
        .buffer_addr(buffer_addr), .buffer_q(buffer_q), .flux(flux), .sector_out(tx_sector)
    );

    receive #(.sysCLK(sysCLK)) FDD_receive (
        .clk(clk), .reset(reset), .wg(wg), .wd(FDD_bus.WRITE_DATAn), .mfm(FDD_bus.MFM),
        .spt(g.spt), .valid(track_ready), .tx_sector(tx_sector),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_sector(wr_sector),
        .wr_done(wr_done), .wr_bad(wr_bad)
    );

    assign FDD_bus.READYn     = !disk_in;
    assign FDD_bus.INDEXn     = !(rotate && angle < ($clog2(ROT))'(INDEX_LEN));
    assign FDD_bus.READ_DATAn = !(rotate && flux && FDD_bus.WRITE_GATEn);
    assign FDD_bus.TRACK0n    = !(sig_ok && head_track == 7'd0);
    assign FDD_bus.WPROTn     = !(sig_ok && (!g.present || ro[sel]));    // no disk reads as protected

    logic [1:0] dskchg = 2'b11;                     // power on: changed (not touched by reset)
    always_ff @(posedge clk)
        for (int d = 0; d < 2; d++)
            if (changed[d])                    dskchg[d] <= 1'b1;
            else if (FDD_bus.DSKCHG_ACK[d])    dskchg[d] <= 1'b0;
    assign FDD_bus.DSKCHGn = ~dskchg;

endmodule
