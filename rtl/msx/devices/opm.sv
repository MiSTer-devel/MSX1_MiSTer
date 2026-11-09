// OPM device
//
// Copyright (c) 2025 Molekula
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

module dev_opm #(parameter COUNT = MSX::N_OPM) (   // synthesized copies, io_device has 3 slots
    cpu_bus_if.device_mp   cpu_bus,
    input  MSX::device_bus_t device_bus,
    clock_bus_if.base_mp   clock_bus,
    input MSX::io_device_t io_device[3],
    output MSX::sound_t    sound_L,
    output MSX::sound_t    sound_R,
    output         [7:0]   data,
    output                 irq
);

    logic signed [15:0] sound_OPM_L[3], sound_OPM_R[3];     // only [0 .. COUNT-1] used
    logic         [7:0] jt51_data_out[3];
    logic               irq_n[3];
    MSX::sound_t sound_L_accum, sound_R_accum;
    logic [7:0] data_comb;
    logic irq_comb;
    always_comb begin
        sound_L_accum = '0;
        sound_R_accum = '0;
        data_comb     = '1;
        irq_comb      = '1;
        for (int i = 0; i < COUNT; i++) begin
            if (io_device[i].enable) begin
                sound_L_accum += sound_OPM_L[i];
                sound_R_accum += sound_OPM_R[i];
                data_comb     &= jt51_data_out[i];
                irq_comb      &= irq_n[i];
            end
        end
    end

    assign sound_L = sound_L_accum;
    assign sound_R = sound_R_accum;
    assign irq     = ~irq_comb;
    assign data    = data_comb;

    logic               io_en;
    
    assign io_en = cpu_bus.iorq && ~cpu_bus.m1;

    genvar i;
    generate
        for (i = COUNT; i < 3; i++) begin : OPM_UNUSED
            assign sound_OPM_L[i]   = '0;
            assign sound_OPM_R[i]   = '0;
            assign jt51_data_out[i] = 8'hFF;
            assign irq_n[i]         = 1'b1;
        end
        for (i = 0; i < COUNT; i++) begin : OPM_INSTANCES
            wire cs_io_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
            wire cs_io        = (io_device[i].enable && cs_io_active && io_en);
            wire cs_dev       = (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref && device_bus.en);
            wire [7:0] data_tmp;

            assign jt51_data_out[i] = (cs_io || cs_dev) && cpu_bus.rd ? data_tmp : '1;

            jt51 jt51_i (
                .rst(cpu_bus.reset),
                .clk(cpu_bus.clk),
                .cen_p1(clock_bus.ce_1m79_n),
                .cs_n(~(cs_io || cs_dev)),
                .wr_n(~(cpu_bus.wr && cpu_bus.req)),
                .a0(cpu_bus.addr[0]),
                .din(cpu_bus.data),
                .dout(data_tmp),
                .ct1(),
                .ct2(),
                .irq_n(irq_n[i]),
                .sample(),
                .left(sound_OPM_L[i]),
                .right(sound_OPM_R[i]),
                .xleft(),
                .xright()
            );
        end
    endgenerate

endmodule
