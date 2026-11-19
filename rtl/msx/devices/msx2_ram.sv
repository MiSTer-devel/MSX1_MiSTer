// MSX2 RAM device
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

module dev_msx2_ram (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::device_bus_t device_bus,
    input  MSX::io_device_t io_device[3],
    input                   limit_internal_mapper,
    output            [7:0] data,
    output            [7:0] data_to_mapper
);

    logic [2:0] mapper_io;
    logic [7:0] sizes[3];
    logic [7:0] data_out[0:2], data_to_mapper_ar[3];
    wire        io_en = cpu_bus.iorq && ~cpu_bus.m1;

    assign data      = data_out[0] & data_out[1] & data_out[2];
    
    always_comb begin : output_mux
        data_to_mapper = 8'hFF;
        for (int i = 0; i < MSX::N_MEM_MAPPER; i++) begin
            if (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref ) begin
                data_to_mapper = data_to_mapper_ar[i];
            end
        end        
    end

    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : msx2_ram_dev_INSTANCES
            if (i < MSX::N_MEM_MAPPER) begin : inst
                wire cs_io_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
                wire cs_enable = io_device[i].enable && cs_io_active && io_en;
                msx2_ram msx2_ram_i (
                    .clk(cpu_bus.clk),
                    .reset(cpu_bus.reset),
                    .data(cpu_bus.data),
                    .addr(cpu_bus.addr),
                    .oe(cs_enable && cpu_bus.rd),
                    .wr(cs_enable && cpu_bus.wr && cpu_bus.req),
                    .size(io_device[i].param),
                    .q(data_out[i]),
                    .data_to_mapper(data_to_mapper_ar[i]),
                    .limit_mapper(i == 0 ? limit_internal_mapper : 1'b0)
                );
            end else begin : none
                assign data_out[i]          = 8'hFF;
                assign data_to_mapper_ar[i] = 8'hFF;
            end
        end
    endgenerate

endmodule

module msx2_ram (
    input              reset,
    input              clk,
    input              oe,
    input              wr,
    input       [15:0] addr,
    input        [7:0] data,
    output       [7:0] q,
    input        [7:0] size,
    output logic [7:0] data_to_mapper,
    input              limit_mapper
);
    logic [7:0] mem_seg[0:3];

    always_ff @(posedge clk) begin
        if (reset) begin
            mem_seg[0] <= 8'd0;
            mem_seg[1] <= 8'd0;
            mem_seg[2] <= 8'd0;
            mem_seg[3] <= 8'd0;
        end else if (wr) begin
            mem_seg[addr[1:0]] <= data & (size -1'b1) & (limit_mapper ? 8'h7F : 8'hFF);
        end
    end

    assign q = oe ? (mem_seg[addr[1:0]] | (~(size -1'b1)) | (limit_mapper ? 8'h80 : 8'h00) ) : 8'hFF;
    assign data_to_mapper = mem_seg[addr[15:14]];

endmodule
