// OPLL device
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

module dev_opll (
    cpu_bus_if.device_mp   cpu_bus,
    device_bus             device_bus,
    clock_bus_if.base_mp   clock_bus,
    input MSX::io_device_t io_device[3],
    output signed [15:0]   sound
);

    assign sound = (io_device[0].enable ? sound_OPLL[0] : '0) +
                   (io_device[1].enable ? sound_OPLL[1] : '0) +
                   (io_device[2].enable ? sound_OPLL[2] : '0);

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            opll_enabled <= 3'b111;
        end else begin
            opll_enabled[0] <= io_device[0].device_ref == device_bus.device_ref ? device_bus.en : opll_enabled[0];
            opll_enabled[1] <= io_device[1].device_ref == device_bus.device_ref ? device_bus.en : opll_enabled[1];
            opll_enabled[2] <= io_device[2].device_ref == device_bus.device_ref ? device_bus.en : opll_enabled[2];
        end
    end

    wire io_en = cpu_bus.iorq && ~cpu_bus.m1;

    logic signed [15:0] sound_OPLL[0:2];
    logic [2:0] opll_enabled;
    genvar i;

    generate
        for (i = 0; i < 3; i++) begin : OPLL_INSTANCES
            if (i < MSX::N_OPLL) begin : inst
                wire cs_io_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
                wire cs_enable    = (io_device[i].enable && cs_io_active && io_en && opll_enabled[i]);
                wire cs_dev_bus   = (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref && device_bus.we);

                IKAOPLL #(.FULLY_SYNCHRONOUS(1), .FAST_RESET(1), .ALTPATCH_CONFIG_MODE(0), .USE_PIPELINED_MULTIPLIER(1)) ika_opll_opll_int (
                    .i_XIN_EMUCLK       (cpu_bus.clk),
                    .i_phiM_PCEN_n      (~clock_bus.ce_3m58_n),
                    .i_IC_n             (~cpu_bus.reset),
                    .i_ALTPATCH_EN      (1'b0),
                    .i_CS_n             (~(cs_enable || cs_dev_bus)),
                    .i_WR_n             (~(cpu_bus.wr || device_bus.we)),
                    .i_A0               (cpu_bus.addr[0]),
                    .i_D                (cpu_bus.data),
                    .i_ACC_SIGNED_MOVOL (5'sd9),
                    .i_ACC_SIGNED_ROVOL (5'sd15),
                    .o_ACC_SIGNED       (sound_OPLL[i])
                );
            end else begin : none
                assign sound_OPLL[i] = '0;
            end
        end
    endgenerate

endmodule
