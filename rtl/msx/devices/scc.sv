// SCC device
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

module dev_scc (
    cpu_bus_if.device_mp   cpu_bus,
    clock_bus_if.base_mp   clock_bus,
    input  MSX::device_bus_t device_bus,
    input MSX::io_device_t io_device[3],
    output MSX::sound_t    sound,
    output           [7:0] data
);

    wire signed [14:0] sound_SCC[0:1];
    wire [7:0] data_SCC[2];
    logic [1:0] scc_mode;
    logic [1:0] scc_plus;

    always_comb begin
        sound = '0;
        for (int i = 0; i < 2; i++)
            if (io_device[i].enable) sound += sound_SCC[i];
    end

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            scc_mode    <= 2'b00;
            scc_plus    <= 2'b00;
        end else begin
            scc_mode[0] <= io_device[0].device_ref == device_bus.device_ref ? device_bus.mode : scc_mode[0];
            scc_mode[1] <= io_device[1].device_ref == device_bus.device_ref ? device_bus.mode : scc_mode[1];
            scc_plus[0] <= io_device[0].device_ref == device_bus.device_ref ? device_bus.param : scc_plus[0];
            scc_plus[1] <= io_device[1].device_ref == device_bus.device_ref ? device_bus.param : scc_plus[1];
        end
    end

    assign data = cpu_bus.rd ? data_SCC[0] & data_SCC[1] : 8'hFF;

    genvar i;
    generate
        for (i = 0; i < 2; i++) begin : SCC_INSTANCES
            if (i < MSX::N_SCC) begin : inst
                wire cs_dev_bus   = (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref && device_bus.en);
                scc_wave SCC_i (
                    .clk(cpu_bus.clk),
                    .clkena(clock_bus.ce_3m58_n),
                    .reset(cpu_bus.reset),
                    .req(cs_dev_bus && (cpu_bus.rd || cpu_bus.wr)),
                    .ack(),
                    .wrt(cpu_bus.wr && cpu_bus.req),
                    .adr(cpu_bus.addr[7:0]),
                    .dbo(cpu_bus.data),
                    .dbi(data_SCC[i]),
                    .wave(sound_SCC[i]),
                    .sccPlusChip(scc_plus[i]),
                    .sccPlusMode(scc_mode[i])
                );
            end else begin : none
                assign data_SCC[i]  = 8'hFF;
                assign sound_SCC[i] = '0;
            end
        end
    endgenerate

endmodule
