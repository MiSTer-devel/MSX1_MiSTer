// WD2793 device
//
// Copyright (c) 2024-2025 Molekula
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

module dev_WD2793 #(parameter sysCLK)
(
   cpu_bus_if.device_mp    cpu_bus,
   input             [1:0] model,
   input             [1:0] floppy_drive_en,
   FDD_if.FDC_mp           FDD_bus,
   input                   cs,
   output            [7:0] data,
   output                  data_oe_rq
);

typedef enum logic [1:0] {DRIVE_NONE, DRIVE_A, DRIVE_B} drive_t;

logic [7:0] philips_sideReg, philips_driveReg;

// model (XML style): 0 Philips, 1 National, 2 Sony (Philips registers, openMSX PhilipsFDC)
wire area_philips   = (cpu_bus.addr[13:3] == 11'b11111111111) && (model == 2'h0 || model == 2'h2);
wire area_national  = (cpu_bus.addr[13:7] ==  7'b1111111) && model == 2'h1;
wire area_device    = area_philips || area_national;
wire device_cs      = cs && area_device && cpu_bus.mreq;

wire wdcs           = device_cs && cpu_bus.addr[2] == 0;

logic motor, side;
drive_t drive;


assign FDD_bus.USEL   = drive == DRIVE_B;
assign FDD_bus.MOTORn = ~(motor && drive != DRIVE_NONE);       // no drive selected: no motor, not ready
assign FDD_bus.SIDEn  = ~side;

// Philips 7FFDh bit 2 = 0 iff the disk of the selected drive changed (openMSX PhilipsFDC; read
// by the Sony disk ROMs, the Philips ROMs ignore it). The read clears it: acknowledged at the
// end of the read cycle, after the CPU took the value.
wire       dskchg_n  = drive == DRIVE_NONE ? 1'b1 : FDD_bus.DSKCHGn[drive == DRIVE_B];
wire       rd_7ffd   = cpu_bus.rd && device_cs && area_philips && cpu_bus.addr[2:0] == 3'd5;
logic       rd_7ffd_q = 1'b0;
logic [1:0] ack_mask  = 2'b00;                  // drive read: A 01, B 10, none 00
always_ff @(posedge cpu_bus.clk) begin
   rd_7ffd_q <= rd_7ffd;
   if (rd_7ffd) ack_mask <= {drive == DRIVE_B, drive == DRIVE_A};
end
assign FDD_bus.DSKCHG_ACK = rd_7ffd_q && !rd_7ffd ? ack_mask : 2'b00;

//wire [1:0] dbg_status = {drq, intrq};

always_ff @(posedge cpu_bus.clk) begin
   if (cpu_bus.reset) begin
      philips_sideReg  <= 8'd0;
      philips_driveReg <= 8'd0;
      drive <= DRIVE_A;
      side  <= 0;
      motor <= 0;
   end else begin
      if (cpu_bus.wr && cpu_bus.req && cs) begin
         if (area_philips) begin
            if (cpu_bus.addr[2:0] == 3'd4) begin
               philips_sideReg  <= cpu_bus.data;
               side             <= cpu_bus.data[0];
               //$display("WRITE DEV SIDEREG  %X  (%d,%d) %t", cpu_bus.data, dbg_status[0], dbg_status[1], $time);
            end
            if (cpu_bus.addr[2:0] == 3'd5) begin 
               philips_driveReg <= cpu_bus.data;
               motor              <=cpu_bus.data[7];
               //$display("WRITE DEV DRIVEREG %X  (%d,%d) %t", cpu_bus.data, dbg_status[0], dbg_status[1], $time);
               case(cpu_bus.data[1:0])
                  0, 2: drive <= DRIVE_A;
                  1:    drive <= DRIVE_B;
                  3:    drive <= DRIVE_NONE;
               endcase
            end
         end else begin
            if (area_national) begin
               if (cpu_bus.addr[2] == 1) begin
                  case(cpu_bus.data[1:0])
                     1:       drive <= DRIVE_A;
                     2:       drive <= DRIVE_B;
                     default: drive <= DRIVE_NONE;
                  endcase
               side  <= cpu_bus.data[2];
               motor <= cpu_bus.data[3];
               end
            end
         end
      end
   end
end

always_comb begin
   data = 8'hFF;
   data_oe_rq = 0;
  
   if (cpu_bus.rd && device_cs) begin
      if (cpu_bus.addr[2] == 0) begin
         data = d_from_wd17;
         data_oe_rq = 1;
      end else begin
         if (area_philips) begin
            case(cpu_bus.addr[1:0])
               0: begin data = philips_sideReg; data_oe_rq = 1; end
               1: begin data = {philips_driveReg[7:3], dskchg_n, philips_driveReg[1:0]}; data_oe_rq = 1; end
               2: ;
               3: begin data = {~drq, ~intrq, 6'b111111}; data_oe_rq = 1; end
            endcase
         end else begin
            if (area_national) begin
               data = {intrq, ~drq, 6'b111111};
               data_oe_rq = 1;
            end
         end
      end
   end
end

logic [15:0] crc;
//logic fdc_we;
//assign fdc_we = data_oe_rq && wdcs && drq;

wire [7:0] d_from_wd17;
wire drq, intrq;
wd279x #(.WD279_57(0),.sysCLK(sysCLK)) wd2793_i
(
   .clk(cpu_bus.clk),
   .MRn(~cpu_bus.reset),
   .CSn(~wdcs),
   .REn(~cpu_bus.rd),
   .WEn(~cpu_bus.wr),
   .A(cpu_bus.addr[1:0]),
   .DIN(cpu_bus.data),
   .DOUT(d_from_wd17),
   .DRQ(drq),
   .INTRQ(intrq),
   
   //FDD
   .STEPn(FDD_bus.STEPn),
   .SDIRn(FDD_bus.SDIRn),
   .INDEXn(FDD_bus.INDEXn),
   .TRK00n(FDD_bus.TRACK0n),
   .READYn(FDD_bus.READYn),
   .WPROTn(FDD_bus.WPROTn),
   .RAWRDn(FDD_bus.READ_DATAn),
   .DDENn(1'b0),              //TODO      Režim FM/MFM
   .SSO()                 //Pouze WD2795/7
);

endmodule
