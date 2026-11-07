// SCC device
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

module dev_scc (
    cpu_bus_if.device_mp   cpu_bus,
    clock_bus_if.base_mp   clock_bus,
    input  MSX::device_bus_t device_bus,
    input MSX::io_device_t io_device[3],
    output   signed [15:0] sound,
    output           [7:0] data
);

    assign sound = (io_device[0].enable ? {sound_SCC[0][14], sound_SCC[0]} : '0) +
                   (io_device[1].enable ? {sound_SCC[1][14], sound_SCC[1]} : '0);

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

    wire signed [14:0] sound_SCC[0:1];
    wire [7:0] data_SCC[2];
    logic [1:0] scc_mode;
    logic [1:0] scc_plus;

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
