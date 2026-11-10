// TMS device
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

module dev_tms (
    cpu_bus_if.device_mp    cpu_bus,
    clock_bus_if.base_mp    clock_bus,
    output MSX::video_t     video_bus,
    vram_bus_if.device_mp   vram_bus,
    input  MSX::io_device_t io_device[3],
    output            [7:0] data,
    output                  interrupt,
    input                   border
);

    wire  [7:0] q, R, G, B;
    wire        interrupt_n, HS_n, VS_n, hblank, vblank, blank_n, ce_pix;    
    wire        vram_we;
    wire  [7:0] vram_data;
    wire [13:0] vramm_addr;

    wire io_en       = cpu_bus.iorq && ~cpu_bus.m1;
    wire cs_io_match = (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire cs_enable   = io_device[0].enable && cs_io_match && io_en;

    assign video_bus.R      = io_device[0].enable ? R                   : '0;
    assign video_bus.G      = io_device[0].enable ? G                   : '0;
    assign video_bus.B      = io_device[0].enable ? B                   : '0;
    assign video_bus.HS     = io_device[0].enable ? ~HS_n               : '0;
    assign video_bus.VS     = io_device[0].enable ? ~VS_n               : '0;
    assign video_bus.DE     = io_device[0].enable ? blank_n             : '0;
    assign video_bus.hblank = io_device[0].enable ? hblank              : '0;
    assign video_bus.vblank = io_device[0].enable ? vblank              : '0;
    assign video_bus.ce_pix = io_device[0].enable ? ce_pix              : '0;

    assign vram_bus.addr    = io_device[0].enable ? {2'b00,vramm_addr}  : '1;
    assign vram_bus.data    = io_device[0].enable ? vram_data           : '1;
    assign vram_bus.we_lo   = io_device[0].enable ? vram_we             : '0;
    assign vram_bus.we_hi   = io_device[0].enable ? '0                  : '0;

    assign interrupt        = io_device[0].enable ? ~interrupt_n        : '0;

    assign data             = cs_enable           ? q                   : '1;
    

    vdp18_core #(.compat_rgb_g(0)) tms_i
    (
        .clk_i(cpu_bus.clk),
        .clk_en_10m7_i(clock_bus.ce_10m7_p),
        .reset_n_i(~cpu_bus.reset),

        .csr_n_i(~(cs_enable && cpu_bus.rd)),
        // Level strobe like the real /CSW: vdp18_cpuio samples only on clk_en_10m7,
        // a 1-clk req pulse was seen only when its phase happened to match
        .csw_n_i(~(cs_enable && cpu_bus.wr)),
        .mode_i(cpu_bus.addr[0]),
        .cd_i(cpu_bus.data),
        .cd_o(q),
        .int_n_o(interrupt_n),
        .vram_we_o(vram_we),
        .vram_a_o(vramm_addr),
        .vram_d_o(vram_data),
        .vram_d_i(vram_bus.q_lo),
        .border_i(border),
        .rgb_r_o(R),
        .rgb_g_o(G),
        .rgb_b_o(B),
        .hsync_n_o(HS_n),
        .vsync_n_o(VS_n),
        .hblank_o(hblank),
        .vblank_o(vblank),
        .blank_n_o(blank_n),
        .is_pal_i(~io_device[0].param[0]),      // MODE: 0 = PAL, 1 = NTSC (deviceParams.json)
        .ce_pix(ce_pix)
    );

endmodule
