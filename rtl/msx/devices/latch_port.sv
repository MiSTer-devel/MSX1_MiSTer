// Latch port device
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

module dev_latch_port (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::device_bus_t device_bus,
    input  MSX::io_device_t io_device[3],
    output            [7:0] data_to_mapper
);

    logic [7:0] data_to_mapper_ar[0:2];
    
    always_comb begin : output_mux
        data_to_mapper = 8'hFF;
        for (int i = 0; i < MSX::N_LATCH_PORT; i++) begin
            if (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref ) begin
                data_to_mapper = data_to_mapper_ar[i];
            end
        end        
    end

    wire io_en = cpu_bus.iorq && ~cpu_bus.m1;

    genvar i;
    generate
        for (i = 0; i < MSX::N_LATCH_PORT; i++) begin : LATCH_PORT_DEV_INSTANCES
            wire cs_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
            wire cs_enable = io_device[i].enable && cs_active && io_en;

            latch_port latch_port_i (
                .clk(cpu_bus.clk),
                .reset(cpu_bus.reset),
                .data(cpu_bus.data),
                .wr(cs_enable && cpu_bus.wr && cpu_bus.req),
                .data_to_mapper(data_to_mapper_ar[i])
            );
        end
    endgenerate

endmodule

module latch_port (
    input              clk,
    input              reset,
    input        [7:0] data,
    input              wr,
    output logic [7:0] data_to_mapper
);

    always_ff @(posedge clk) begin
        if (reset) begin
            data_to_mapper <= 8'd0;
        end else if (wr) begin
            data_to_mapper <= data;
        end
    end

endmodule
