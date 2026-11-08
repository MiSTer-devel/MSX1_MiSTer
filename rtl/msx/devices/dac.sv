// DAC device
//
// Copyright (c) 2025 Molekula
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
        for (int i = 0; i < 3; i++)
            if (io_device[i].enable) sound += scale(audio_dac[i]);
    end

    assign cs = cpu_bus.addr[15:14] == 2'b01 && ~cpu_bus.addr[4] && cpu_bus.mreq && cpu_bus.wr && cpu_bus.req;

    genvar i;
    generate for (i=0; i<3; i++) begin : g_dac
        always_ff @(posedge cpu_bus.clk) begin
            if (cpu_bus.reset) 
                audio_dac[i] <= '0;
            else if (cs && io_device[i].enable && io_device[i].device_ref == block_info.device_ref)
                audio_dac[i] <= cpu_bus.data;
        end
    end endgenerate   

endmodule
