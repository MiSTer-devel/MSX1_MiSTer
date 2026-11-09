// RTC device
//
// Copyright (c) 2024-2025 Molekula
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

module dev_rtc (
    cpu_bus_if.device_mp    cpu_bus,
    clock_bus_if.base_mp    clock_bus,
    input  MSX::io_device_t io_device[3],
    input            [64:0] rtc_time,
    output            [7:0] data
);

    
    wire [7:0] q;
    wire       io_en       = cpu_bus.iorq && ~cpu_bus.m1;
    wire       cs_io_match = (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire       cs_enable   = io_device[0].enable && cs_io_match && io_en;

    assign data      = cs_enable ? q : '1;

    rtc rtc_i
    (
        .clk21m(cpu_bus.clk),
        .reset(cpu_bus.reset),
        .setup(cpu_bus.reset),
        .rt(rtc_time),
        .clkena(clock_bus.ce_10hz),
        .req(cs_enable & cpu_bus.req),
        .ack(),
        .wrt(cpu_bus.wr),
        .adr(cpu_bus.addr),
        .dbi(q),
        .dbo(cpu_bus.data)
    );

endmodule

