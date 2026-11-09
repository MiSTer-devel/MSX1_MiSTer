// S1990 MSX-ENGINE registers of the MSX turbo R
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
//

// Behaviour as openMSX src/MSXS1990.cc. E4h: register select (read back), E5h: register.
//   reg 5   read: firmware switch, 40h on / 00h off
//   reg 6   read / write: CPU status, bit 5 1 = Z80 / 0 = R800, bit 6 1 = ROM / 0 = DRAM mode
//   reg 13, 14, 15 read: 03h, 2Fh, 8Bh (openMSX: fixed, "TODO")
//   other registers read FFh, writes other than reg 6 are ignored
// Reset: select 0, CPU status 60h (Z80, ROM). The CPU switch takes effect after the OUT.
// The time stamp (timer E6h / E7h) is dev_systimer.
module dev_s1990 (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    input                   firmware_sw,        // firmware switch (FS-A1GT case switch)
    output            [7:0] data,
    output                  r800,               // CPU status bit 5 = 0
    output                  dram                // CPU status bit 6 = 0
);

    wire cs = io_device[0].enable && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;

    logic [7:0] select;
    logic [1:0] cpu_status;                     // bits 6:5

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            select     <= 8'h00;
            cpu_status <= 2'b11;
        end else if (cs && cpu_bus.wr && cpu_bus.req) begin
            if (!cpu_bus.addr[0])
                select <= cpu_bus.data;
            else if (select == 8'd6)
                cpu_status <= cpu_bus.data[6:5];
        end
    end

    logic [7:0] reg_data;
    always_comb begin
        case (select)
            8'd5:    reg_data = firmware_sw ? 8'h40 : 8'h00;
            8'd6:    reg_data = {1'b0, cpu_status, 5'b0};
            8'd13:   reg_data = 8'h03;
            8'd14:   reg_data = 8'h2F;
            8'd15:   reg_data = 8'h8B;
            default: reg_data = 8'hFF;
        endcase
    end

    assign data = cs && cpu_bus.rd ? (cpu_bus.addr[0] ? reg_data : select) : 8'hFF;
    assign r800 = !cpu_status[0];
    assign dram = !cpu_status[1];

endmodule
