// virtual FDC device
//
// Copyright (c) 2025 Molekula
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

module dev_FDC #(parameter sysCLK)
(
   cpu_bus_if.device_mp    cpu_bus,
   input  MSX::device_bus_t device_bus,
   input MSX::io_device_t  io_device[32][3],
   FDD_if.FDC_mp           FDD_bus[3],
   output            [7:0] data,
   output                  data_oe_rq
);

   assign data = wd2793_data[0] & wd2793_data[1] & wd2793_data[2]; //& TC8566AF_data;
   assign data_oe_rq = wd2793_oe_rq[0] | wd2793_oe_rq[1] | wd2793_oe_rq[2]; //| TC8566AF_data_oe_rq;

   logic [7:0] wd2793_data[3];
   logic       wd2793_oe_rq[3];
   genvar i;
   generate
      for (i = 0; i < 3; i++) begin : FDC_INSTANCES
         if (i < MSX::N_WD2793) begin : inst
            wire cs_dev                = (io_device[DEV_WD2793][i].device_ref == device_bus.device_ref && io_device[DEV_WD2793][i].enable);
            wire [1:0] model           = io_device[DEV_WD2793][i].param[1:0];
            wire [1:0] floppy_drive_en = io_device[DEV_WD2793][i].param[3:2];
            dev_WD2793 #(.sysCLK(sysCLK)) WD2793 (
               .cpu_bus(cpu_bus),
               .model(model),
               .floppy_drive_en(floppy_drive_en),
               .FDD_bus(FDD_bus[i]),
               .cs(cs_dev),
               .data(wd2793_data[i]),
               .data_oe_rq(wd2793_oe_rq[i])
            );
         end else begin : none
            assign wd2793_data[i]       = 8'hFF;
            assign wd2793_oe_rq[i]      = 1'b0;
            assign FDD_bus[i].USEL      = 1'b0;     // idle drive interface
            assign FDD_bus[i].MOTORn    = 1'b1;
            assign FDD_bus[i].STEPn     = 1'b1;
            assign FDD_bus[i].SDIRn     = 1'b1;
            assign FDD_bus[i].SIDEn     = 1'b1;
            assign FDD_bus[i].DSKCHG_ACK = 2'b00;
         end
      end
   endgenerate

   /*
    wire [7:0] TC8566AF_data;
    wire TC8566AF_data_oe_rq;
    dev_TC8566AF TC8566AF (
        .cpu_bus(cpu_bus),
        .clock_bus(clock_bus),
        .device_bus(device_bus),
        .io_device(io_device[DEV_TC8566AF]),
        .sd_bus(sd_bus),
        .sd_bus_control(sd_bus_control),
        .image_info(image_info),
        .data(TC8566AF_data),
        .data_oe_rq(TC8566AF_data_oe_rq)
    );
*/
endmodule
