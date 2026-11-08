// Reset staus device
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

// Port F4 (reset status): cleared only by a cold reset, so the BIOS can tell a warm boot
// (MSX2+ skips the logo); as OCM portF4_bit7 (pColdReset).
module dev_reset_status (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],
    input                   hard_reset,     // cold reset (power-up, MiSTer menu, pack upload)
    output            [7:0] data
);

    logic [7:0] status[3];
    wire io_en = cpu_bus.iorq && ~cpu_bus.m1;
    assign data = status[0] & status[1] & status[2];

    genvar i;
    generate
        for (i = 0; i < 3; i++) begin : RESET_STATUS_DEV_INSTANCES
            wire cs_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
            wire cs_enable = io_device[i].enable && cs_active && io_en;

            reset_status latch_port_i (
                .clk(cpu_bus.clk),
                .reset(hard_reset),
                .data(cpu_bus.data),
                .wr(cs_enable && cpu_bus.wr && cpu_bus.req),
                .rd(cs_enable && cpu_bus.rd),
                .status(status[i]),
                .inverted(io_device[i].param[0])
            );
        end
    endgenerate

endmodule

module reset_status (
    input              clk,
    input              reset,
    input        [7:0] data,
    input              wr,
    input              rd,
    input              inverted,
    output       [7:0] status
);
    logic [7:0] r_status;
    // Sync reset: async reset loading a non-constant value was synthesized as latches
    always_ff @(posedge clk) begin
        if (reset) begin
            r_status <= inverted ? 8'hFF : 8'h00;
        end else if (wr) begin
            r_status <= inverted ? data | 8'h7F : (r_status & 8'h20) | (data & 8'hA0);
        end
    end

    assign status = rd ? r_status : 8'hFF;

endmodule
