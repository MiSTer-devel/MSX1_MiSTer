// Pause key and LEDs of the MSX turbo R (port A7h)
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

// Behaviour as openMSX src/MSXTurboRPause.cc.
//   read:  bit 0 = pause (the pause key toggles it), other bits 0
//   write: bit 0 pause LED, bit 1 hardware pause enable, bit 7 turbo (R800) LED
// With bit 1 set and the pause on, the machine stops (hw_pause holds the CPU); the pause LED is
// lit by bit 0 or by the hardware pause. Reset: status 0, pause off.
// The pause key is the Pause key of the PS/2 keyboard: hps_io reports its make + break sequence
// as one event 377h (pressed, extended, 77h), MiSTer sends it when the key is released.
module dev_turbor_pause (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    input            [10:0] ps2_key,            // {toggle, pressed, extended, code}
    output            [7:0] data,
    output                  hw_pause,           // stop the machine
    output                  pause_led,
    output                  turbo_led
);

    wire cs = io_device[0].enable && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;

    logic [7:0]  status;
    logic        paused;
    logic [10:0] ps2_q = '0;
    wire         pause_key = ps2_key != ps2_q && ps2_key[9:0] == 10'h377;

    always_ff @(posedge cpu_bus.clk) begin
        ps2_q <= ps2_key;
        if (cpu_bus.reset) begin
            status <= 8'h00;
            paused <= 1'b0;
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req) status <= cpu_bus.data;
            if (pause_key && io_device[0].enable) paused <= !paused;
        end
    end

    assign data      = cs && cpu_bus.rd ? {7'b0, paused} : 8'hFF;
    assign hw_pause  = status[1] && paused;
    assign pause_led = status[0] || hw_pause;
    assign turbo_led = status[7];

endmodule
