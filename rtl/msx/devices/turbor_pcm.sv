// PCM of the MSX turbo R (ports A4h / A5h)
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

// Behaviour as openMSX src/sound/MSXTurboRPCM.cc. A free-running 15.7 kHz clock (3.58 MHz / 228).
//   A4h read:  bits 1:0 = ticks since the last A4h write (wraps), other bits 0
//   A4h write: D value (sample, or compare value when recording), clears the tick count;
//              the DAC takes it only when not muted (A5h bit 1 = 1): with BUFF (bit 0) at the
//              next tick, else at once
//   A5h write: bit 0 BUFF (1 -> 0 writes the D value to the DAC at once), bit 1 MUTE (0 = all
//              sound of the machine muted), bit 2 FILT, bit 3 SEL (no effect, as openMSX),
//              bit 4 SMPL (0 -> 1 holds the input sample)
//   A5h read:  bit 7 COMP = (SMPL ? hold : input) >= D value, bits 4:0 = last A5h write
// No microphone input: the input sample is 80h (openMSX without a plugged input).
// Reset: status 0, D value 80h, hold 80h, DAC 80h, not muted until A5h is written.
module dev_turbor_pcm (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    output            [7:0] data,
    output MSX::sound_t     sound,
    output logic            mute_all            // mute every sound source of the machine
);

    localparam int TICK = MSX::CLK_CORE_HZ / 3579545 * 228;        // 6 x 228 = 1368 clk_core

    wire cs = io_device[0].enable && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire wr = cs && cpu_bus.wr && cpu_bus.req;

    logic [$clog2(TICK)-1:0] prescaler;
    wire  tick = prescaler == '0;
    logic [1:0] ticks;
    logic [7:0] status, dvalue, hold, dac, pend_val;
    logic       pend;

    wire  [7:0] sample = 8'h80;                 // input: none plugged

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            prescaler <= '0;
            ticks     <= '0;
            status    <= 8'h00;
            dvalue    <= 8'h80;
            hold      <= 8'h80;
            dac       <= 8'h80;
            pend      <= 1'b0;
            mute_all  <= 1'b0;
        end else begin
            prescaler <= tick ? ($clog2(TICK))'(TICK - 1) : prescaler - 1'b1;
            if (tick) ticks <= ticks + 2'd1;
            if (tick && pend) begin
                dac  <= pend_val;
                pend <= 1'b0;
            end
            if (wr && !cpu_bus.addr[0]) begin
                ticks  <= '0;
                dvalue <= cpu_bus.data;
                if (status[1]) begin
                    if (status[0]) begin
                        pend     <= 1'b1;
                        pend_val <= cpu_bus.data;
                    end else begin
                        dac  <= cpu_bus.data;
                        pend <= 1'b0;
                    end
                end
            end
            if (wr && cpu_bus.addr[0]) begin
                status   <= cpu_bus.data;
                mute_all <= !cpu_bus.data[1];
                if (status[0] && !cpu_bus.data[0]) begin   // BUFF 1 -> 0
                    dac  <= dvalue;
                    pend <= 1'b0;
                end
                if (!status[4] && cpu_bus.data[4]) hold <= sample;
            end
        end
    end

    wire comp = (status[4] ? hold : sample) >= dvalue;

    assign data  = cs && cpu_bus.rd ? (cpu_bus.addr[0] ? {comp, 2'b00, status[4:0]} : {6'b0, ticks}) : 8'hFF;
    assign sound = MSX::sound_t'(($signed({8'b0, dac}) - 16'sd128) <<< 7);

endmodule
