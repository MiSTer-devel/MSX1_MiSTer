// virtual FDC device
//
// Copyright (c) 2025 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

module dev_FDC #(parameter sysCLK)
(
   cpu_bus_if.device_mp    cpu_bus,
   device_bus              device_bus,
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
