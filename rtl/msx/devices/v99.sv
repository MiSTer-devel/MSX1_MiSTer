// V99 device
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

module dev_v99 (
    cpu_bus_if.device_mp    cpu_bus,
    clock_bus_if.base_mp    clock_bus,
    output MSX::video_t     video_bus,
    vram_bus_if.device_mp   vram_bus,
    input  MSX::io_device_t io_device[3],
    output            [7:0] data,
    output                  interrupt,
    input                   border
);

    wire  [7:0] q;
    wire  [5:0] R, G, B;
    wire        interrupt_n, hblank, vblank, DE, VideoHS_n, VideoVS_n;
    wire        DLClk, DHClk;  
    wire        vram_we;
    wire  [7:0] vram_data;
    wire [16:0] vramm_addr;

    wire io_en       = cpu_bus.iorq && ~cpu_bus.m1;
    wire cs_io_match = (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire cs_enable   = io_device[0].enable && cs_io_match && io_en;
    
    assign video_bus.R      = io_device[0].enable ? {R,R[5:4]}                         : '0;
    assign video_bus.G      = io_device[0].enable ? {G,G[5:4]}                         : '0;
    assign video_bus.B      = io_device[0].enable ? {B,B[5:4]}                         : '0;
    assign video_bus.HS     = io_device[0].enable ? ~VideoHS_n                                 : '0;
    assign video_bus.VS     = io_device[0].enable ? ~VideoVS_n                                 : '0;
    assign video_bus.DE     = io_device[0].enable ? DE                                 : '0;
    assign video_bus.hblank = io_device[0].enable ? hblank_cor                         : '0;
    assign video_bus.vblank = io_device[0].enable ? vblank                             : '0;
    assign video_bus.ce_pix = io_device[0].enable ? ~DHClk                             : '0;

    assign vram_bus.addr    = io_device[0].enable ? vramm_addr[15:0]                   : '1;
    assign vram_bus.data    = io_device[0].enable ? vram_data                          : '1;
    assign vram_bus.we_lo   = io_device[0].enable ? ~vram_we & DLClk & ~vramm_addr[16] : '0;
    assign vram_bus.we_hi   = io_device[0].enable ? ~vram_we & DLClk &  vramm_addr[16] : '0;

    assign interrupt        = io_device[0].enable ? ~interrupt_n                       : '0;

    assign data             = cs_enable           ? q                                  : '1;
    

    logic hblank_cor;
    always_ff @(posedge cpu_bus.clk) begin
        if (hblank)
            hblank_cor <= 1'b1;
        else 
            if (DHClk & DLClk)
                hblank_cor <= 1'b0;
    end

    VDP VDP_i 
    (
        .CLK21M(cpu_bus.clk),
        .RESET(cpu_bus.reset),
        .REQ(cs_enable && cpu_bus.req),
        .ACK(),
        .WRT(cpu_bus.wr),
        .ADR(cpu_bus.addr),
        .DBI(q),
        .DBO(cpu_bus.data),
        .INT_N(interrupt_n),
        .PRAMOE_N(),
        .PRAMWE_N(vram_we),
        .PRAMADR(vramm_addr),
        .PRAMDBI({vram_bus.q_hi, vram_bus.q_lo}),
        .PRAMDBO(vram_data),
        .VDPSPEEDMODE(0), //TODO
        .CENTERYJK_R25_N(0), //TODO
        .PVIDEOR(R),
        .PVIDEOG(G),
        .PVIDEOB(B),
        .PVIDEODE(DE),
        .HBLANK(hblank),
        .VBLANK(vblank),
        .PVIDEOHS_N(VideoHS_n),
        .PVIDEOVS_N(VideoVS_n),
        .PVIDEOCS_N(),
        .PVIDEODHCLK(DHClk),
        .PVIDEODLCLK(DLClk),
        .NTSC_PAL_TYPE('1), //TODO
        .FORCED_V_MODE('0), //TODO
        .BORDER(border),
        .VDP_ID(io_device[0].param[4:0])
    );

endmodule
