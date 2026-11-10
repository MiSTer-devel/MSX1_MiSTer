// DAC device
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


module dev_dac (
    cpu_bus_if.device_mp   cpu_bus,
    clock_bus_if.base_mp   clock_bus,
    input  MSX::block_info_t block_info,
    input MSX::io_device_t io_device[3],
    output MSX::sound_t    sound
);

function automatic signed [15:0] scale(input logic [7:0] v);
    return ($signed({8'b0, v}) - 16'sd128) <<< 7; 
endfunction

    logic [7:0] audio_dac[3];
    logic cs;

    always_comb begin
        sound = '0;
        for (int i = 0; i < MSX::N_DAC; i++)
            if (io_device[i].enable) sound += scale(audio_dac[i]);
    end

    assign cs = cpu_bus.addr[15:14] == 2'b01 && ~cpu_bus.addr[4] && cpu_bus.mreq && cpu_bus.wr && cpu_bus.req;

    genvar i;
    generate for (i=0; i<MSX::N_DAC; i++) begin : g_dac
        always_ff @(posedge cpu_bus.clk) begin
            if (cpu_bus.reset) 
                audio_dac[i] <= '0;
            else if (cs && io_device[i].enable && io_device[i].device_ref == block_info.device_ref)
                audio_dac[i] <= cpu_bus.data;
        end
    end endgenerate   

endmodule
