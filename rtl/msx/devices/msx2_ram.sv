// MSX2 RAM device
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

module dev_msx2_ram (
    cpu_bus_if.device_mp    cpu_bus,
    device_bus              device_bus,
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
        for (int i = 0; i < 3; i++) begin
            if (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref ) begin
                data_to_mapper = data_to_mapper_ar[i];
            end
        end        
    end

    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : msx2_ram_dev_INSTANCES
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
