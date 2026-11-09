// TC8566AF device
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
//

// Memory mapped TC8566AF floppy controller of the Panasonic MSX2 / 2+ and MSX turbo R machines,
// registers as openMSX TurboRFDC in the 3FF0-3FFF window of every page of the block (XML ioRegs):
//   7FF8 (MSX2):    write 8 control 0, 9 control 1, B data; read A status (MSR), B data
//   7FF2 (turbo R): write 2 control 0, 3 control 1, 5 data; read 4 status, 5 data,
//                   1 = 33h with bit 4 / 5 = 0 when the disk of drive 0 / 1 changed (read clears)
//   both types:     read 0 ROM bank, C FCh, D FCh, E FFh, F 3Fh, rest FFh
// The ROM bank (turbo R disk ROM, 16 KB banks) is written at 7FF0 exactly and masked by the ROM
// size of the block; mapper_turbor_fdc maps it, this copy only reads it back (openMSX).
// Control 0: bits 1:0 drive select, bits 7:4 motor of drive 0..3 (bit 2 reset not used, as
// openMSX). Control 1: bit 0 TC (terminal count, ends a read / write).
// The FDD unit has drives 0 and 1; drives 2 and 3 are not connected.
module dev_TC8566AF #(parameter sysCLK)
(
   cpu_bus_if.device_mp    cpu_bus,
   input  MSX::block_info_t block_info,    // ROM size of the block: bank mask
   input             [1:0] model,       // ioRegs: 0 both, 1 7FF2 (turbo R), 2 7FF8 (MSX2)
   input                   twoside,     // double sided drives (ST3 TS)
   FDD_if.FDC_mp           FDD_bus,
   input                   cs,
   output logic      [7:0] data,
   output logic            data_oe_rq
);

   wire        dev_cs  = cs && cpu_bus.mreq && cpu_bus.addr[13:4] == 10'h3FF;
   wire        r7ff2   = model != 2'd2;
   wire        r7ff8   = model != 2'd1;
   wire  [3:0] a       = cpu_bus.addr[3:0];
   wire        fdc_reg = (r7ff2 && (a == 4'h4 || a == 4'h5)) || (r7ff8 && (a == 4'hA || a == 4'hB));
   wire        wr_req  = dev_cs && cpu_bus.wr && cpu_bus.req;

   logic [7:0] ctl0, bank;
   logic       tc;
   wire  [7:0] bank_mask = 8'(block_info.rom_size[22:14] - 1'b1);
   always_ff @(posedge cpu_bus.clk) begin
      if (cpu_bus.reset) begin
         ctl0 <= 8'h00;
         tc   <= 1'b0;
         bank <= 8'h00;
      end else begin
         if (wr_req && ((r7ff2 && a == 4'h2) || (r7ff8 && a == 4'h8))) ctl0 <= cpu_bus.data;
         if (wr_req && ((r7ff2 && a == 4'h3) || (r7ff8 && a == 4'h9))) tc   <= cpu_bus.data[0];
         if (wr_req && cpu_bus.addr == 16'h7FF0)                       bank <= cpu_bus.data & bank_mask;
      end
   end

   wire [7:0] fdc_dout;
   always_comb begin
      data       = 8'hFF;
      data_oe_rq = 1'b0;
      if (dev_cs && cpu_bus.rd) begin
         data_oe_rq = 1'b1;
         if (fdc_reg)                  data = fdc_dout;
         else if (r7ff2 && a == 4'h1)  data = {2'b00, FDD_bus.DSKCHGn, 4'b0011};
         else if (a == 4'h0)           data = bank;
         else if (a == 4'hC)           data = 8'hFC;
         else if (a == 4'hD)           data = 8'hFC;
         else if (a == 4'hF)           data = 8'h3F;
      end
   end

   // 7FF1 read clears the disk change of both drives (openMSX readMem), at the end of the read
   wire  rd_7ff1   = dev_cs && cpu_bus.rd && r7ff2 && a == 4'h1;
   logic rd_7ff1_q = 1'b0;
   always_ff @(posedge cpu_bus.clk) rd_7ff1_q <= rd_7ff1;
   assign FDD_bus.DSKCHG_ACK = {2{rd_7ff1_q && !rd_7ff1}};

   wire [1:0] sel = ctl0[1:0];
   assign FDD_bus.USEL   = sel[0];
   assign FDD_bus.MOTORn = !(!sel[1] && ctl0[{2'b10, sel[0]}]);   // bit 4 / 5

   // 0.5 ms enable for the seek timing and the not ready detection
   localparam int HMS = sysCLK / 2000;
   logic [$clog2(HMS)-1:0] hms_cnt = '0;
   always_ff @(posedge cpu_bus.clk) hms_cnt <= hms_cnt == ($clog2(HMS))'(HMS - 1) ? '0 : hms_cnt + 1'b1;
   wire hmssft = hms_cnt == '0;

   // Bit cell of 250 kbit/s media as the drive makes it (fdd: 500 kHz enable); for the writes
   // also in 1/256 clocks: 4 us FM, 2 us MFM (sftfrac)
   localparam int BITLEN = 2 * (sysCLK / 500_000);
   localparam int CELLF  = (sysCLK / 1000) * 1024 / 1000;
   localparam int CELLM  = CELLF / 2;

   wire sdir, side, core_mfm;
   assign FDD_bus.SDIRn = !sdir;              // core: 0 = step in; fdd: SDIRn 1 = in
   assign FDD_bus.SIDEn = side;               // core: side = ~HD
   assign FDD_bus.MFM   = core_mfm;           // MF bit of the command

   tc8566af #(.sysclk(sysCLK / 1_000_000), .fracin(1)) fdc (
      .RDn(!(dev_cs && cpu_bus.rd && fdc_reg)),
      .WRn(!(dev_cs && cpu_bus.wr && fdc_reg)),
      .CSn(!(dev_cs && fdc_reg)),
      .A0(a[0]),
      .WDAT(cpu_bus.data),
      .RDAT(fdc_dout),
      .DATOE(),
      .DACKn(1'b1),
      .DRQ(),
      .TC(tc),
      .INTn(),
      .INTEV(),
      .WAITIN(1'b0),
      .WREN(FDD_bus.WRITE_GATEn),       // core: active low (pin 24 / 22)
      .WRBIT(FDD_bus.WRITE_DATAn),
      .RDBIT(FDD_bus.READ_DATAn),
      .STEP(FDD_bus.STEPn),
      .SDIR(sdir),
      .WPRT(FDD_bus.WPROTn),
      .track0(FDD_bus.TRACK0n),
      .index(FDD_bus.INDEXn),
      .side(side),
      .usel(),
      .READY(FDD_bus.READYn),
      .readyv({4{FDD_bus.READYn}}),     // drives selected by control 0, not by US
      .TWOSIDE({4{twoside}}),
      .int0(7'(BITLEN)),
      .int1(7'(BITLEN)),
      .int2(7'(BITLEN)),
      .int3(7'(BITLEN)),
      .intf0(15'(CELLF)), .intf1(15'(CELLF)), .intf2(15'(CELLF)), .intf3(15'(CELLF)),
      .intm0(15'(CELLM)), .intm1(15'(CELLM)), .intm2(15'(CELLM)), .intm3(15'(CELLM)),
      .td0(1'b1),
      .td1(1'b1),
      .td2(1'b1),
      .td3(1'b1),
      .hmssft(hmssft),
      .busy(),
      .mfm(core_mfm),
      .sclk(cpu_bus.clk),
      .fclk(cpu_bus.clk),
      .rstn(!cpu_bus.reset)
   );

endmodule
