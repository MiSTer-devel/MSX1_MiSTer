// virtual FDC device
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

// One floppy controller per FDC position (MSX::N_FDC; 0 internal, 1 cartridge in slot A),
// position i drives FDD unit i. The TC8566AF (MSX::N_TC8566AF) sits at position 0 and takes
// the unit over when enabled.
module dev_FDC #(parameter sysCLK)
(
   cpu_bus_if.device_mp    cpu_bus,
   input  MSX::device_bus_t device_bus,
   input  MSX::block_info_t block_info,
   input MSX::io_device_t  io_device[32][3],
   FDD_if.FDC_mp           FDD_bus[MSX::N_FDC],
   output            [7:0] data,
   output                  data_oe_rq
);

   logic [7:0] fdc_data[MSX::N_FDC];
   logic       fdc_oe_rq[MSX::N_FDC];

   // N_FDC is 1 or 2
   assign data       = fdc_data[0] & fdc_data[MSX::N_FDC-1];
   assign data_oe_rq = fdc_oe_rq[0] | fdc_oe_rq[MSX::N_FDC-1];

   genvar i;
   generate
      for (i = 0; i < MSX::N_FDC; i++) begin : FDC_INSTANCES
         FDD_if wd_bus();
         FDD_if tc_bus();
         wire [7:0] wd_data, tc_data;
         wire       wd_oe_rq, tc_oe_rq, tc_enable;

         begin : wd
            wire cs_dev                = (io_device[DEV_WD2793][i].device_ref == device_bus.device_ref && io_device[DEV_WD2793][i].enable);
            wire [1:0] model           = io_device[DEV_WD2793][i].param[1:0];
            wire [1:0] floppy_drive_en = io_device[DEV_WD2793][i].param[3:2];
            dev_WD2793 #(.sysCLK(sysCLK)) WD2793 (
               .cpu_bus(cpu_bus),
               .model(model),
               .floppy_drive_en(floppy_drive_en),
               .density(io_device[DEV_WD2793][i].param[5]),
               .FDD_bus(wd_bus),
               .cs(cs_dev),
               .data(wd_data),
               .data_oe_rq(wd_oe_rq)
            );
         end

         if (i == 0 && MSX::N_TC8566AF > 0) begin : tc
            wire cs_dev = (io_device[DEV_TC8566AF][i].device_ref == device_bus.device_ref && io_device[DEV_TC8566AF][i].enable);
            dev_TC8566AF #(.sysCLK(sysCLK)) TC8566AF (
               .cpu_bus(cpu_bus),
               .block_info(block_info),
               .model(io_device[DEV_TC8566AF][i].param[1:0]),
               .twoside(!io_device[DEV_TC8566AF][i].param[4]),
               .FDD_bus(tc_bus),
               .cs(cs_dev),
               .data(tc_data),
               .data_oe_rq(tc_oe_rq)
            );
            assign tc_enable = io_device[DEV_TC8566AF][i].enable;
         end else begin : no_tc
            assign tc_data   = 8'hFF;
            assign tc_oe_rq  = 1'b0;
            assign tc_enable = 1'b0;
            fdc_if_idle idle (.FDC_bus(tc_bus));
         end

         fdd_if_mux mux (.sel(tc_enable), .fdc0(wd_bus), .fdc1(tc_bus), .fdd(FDD_bus[i]));
         assign fdc_data[i]  = wd_data & tc_data;
         assign fdc_oe_rq[i] = wd_oe_rq | tc_oe_rq;
      end
   endgenerate

endmodule

// No controller: drive interface idle
module fdc_if_idle (FDD_if.FDC_mp FDC_bus);
   assign FDC_bus.USEL       = 1'b0;
   assign FDC_bus.MOTORn     = 1'b1;
   assign FDC_bus.STEPn      = 1'b1;
   assign FDC_bus.SDIRn      = 1'b1;
   assign FDC_bus.SIDEn      = 1'b1;
   assign FDC_bus.WRITE_GATEn = 1'b1;
   assign FDC_bus.WRITE_DATAn = 1'b1;
   assign FDC_bus.MFM        = 1'b1;
   assign FDC_bus.DSKCHG_ACK = 2'b00;
endmodule

// Two controllers on one FDD unit: sel picks the one driving it, both see the drive signals
module fdd_if_mux (
   input          sel,
   FDD_if.FDD_mp  fdc0,
   FDD_if.FDD_mp  fdc1,
   FDD_if.FDC_mp  fdd
);
   assign fdd.USEL       = sel ? fdc1.USEL       : fdc0.USEL;
   assign fdd.MOTORn     = sel ? fdc1.MOTORn     : fdc0.MOTORn;
   assign fdd.STEPn      = sel ? fdc1.STEPn      : fdc0.STEPn;
   assign fdd.SDIRn      = sel ? fdc1.SDIRn      : fdc0.SDIRn;
   assign fdd.SIDEn      = sel ? fdc1.SIDEn      : fdc0.SIDEn;
   assign fdd.WRITE_GATEn = sel ? fdc1.WRITE_GATEn : fdc0.WRITE_GATEn;
   assign fdd.WRITE_DATAn = sel ? fdc1.WRITE_DATAn : fdc0.WRITE_DATAn;
   assign fdd.MFM        = sel ? fdc1.MFM        : fdc0.MFM;
   assign fdd.DSKCHG_ACK = sel ? fdc1.DSKCHG_ACK : fdc0.DSKCHG_ACK;

   assign fdc0.READYn     = fdd.READYn;
   assign fdc0.INDEXn     = fdd.INDEXn;
   assign fdc0.TRACK0n    = fdd.TRACK0n;
   assign fdc0.WPROTn     = fdd.WPROTn;
   assign fdc0.READ_DATAn = fdd.READ_DATAn;
   assign fdc0.DSKCHGn    = fdd.DSKCHGn;
   assign fdc1.READYn     = fdd.READYn;
   assign fdc1.INDEXn     = fdd.INDEXn;
   assign fdc1.TRACK0n    = fdd.TRACK0n;
   assign fdc1.WPROTn     = fdd.WPROTn;
   assign fdc1.READ_DATAn = fdd.READ_DATAn;
   assign fdc1.DSKCHGn    = fdd.DSKCHGn;
endmodule
