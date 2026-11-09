// PSG device
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


module dev_psg (
    cpu_bus_if.device_mp   cpu_bus,
    clock_bus_if.base_mp   clock_bus,
    input MSX::io_device_t io_device[3],
    output MSX::sound_t    sound,
    input          [5:0]   joy[2],
    input         [24:0]   ps2_mouse,
    input                  mouse_en,        // mouse allowed (OCM)
    input                  mouse_port,      // 0 = port 1, 1 = port 2
    input                  tape_in,
    output           [7:0] data
);

    wire [7:0] ioA, ioB;
    wire [5:0] joy_a, joy_b, joyA, joyB;
    wire [7:0] psg_data[3], data_tmp[3];
    wire [9:0] audio_PSG[3];
    wire [7:0] psg_ioB[3];
    wire       io_en;

    // PS/2 mouse (MSX_MiSTer): takes over its port when it moves, a joystick on that port
    // gives it back. Pin 8 is the mouse strobe, not the joystick common.
    wire [5:0] mouse_data;
    logic      use_mouse = 1'b0, mouse_stb = 1'b0;
    ps2mouse mouse (
        .clk(cpu_bus.clk),
        .reset(cpu_bus.reset),
        .strobe(mouse_port ? ioB[5] : ioB[4]),
        .data(mouse_data),
        .ps2_mouse(ps2_mouse)
    );
    always_ff @(posedge cpu_bus.clk) begin
        mouse_stb <= ps2_mouse[24];
        if (cpu_bus.reset || ~mouse_en || |joy[mouse_port])
            use_mouse <= 1'b0;
        else if (mouse_stb ^ ps2_mouse[24])
            use_mouse <= 1'b1;
    end

    assign joy_a = use_mouse && ~mouse_port ? mouse_data :
                   ioB[4] ? 6'b111111 : {~joy[0][5], ~joy[0][4], ~joy[0][0], ~joy[0][1], ~joy[0][2], ~joy[0][3]};
    assign joy_b = use_mouse &&  mouse_port ? mouse_data :
                   ioB[5] ? 6'b111111 : {~joy[1][5], ~joy[1][4], ~joy[1][0], ~joy[1][1], ~joy[1][2], ~joy[1][3]};
    assign joyA  = joy_a & {ioB[0], ioB[1], 4'b1111};
    assign joyB  = joy_b & {ioB[2], ioB[3], 4'b1111};
    
    always_comb begin
        sound = '0;
        for (int i = 0; i < 3; i++)
            if (io_device[i].enable) sound += $signed({4'b0000, audio_PSG[i], 4'b0000});
    end

    assign data  = psg_data[0] & psg_data[1] & psg_data[2];
    
    assign ioB   = (io_device[0].param[0] ? psg_ioB[0]  : '1) &
                   (io_device[1].param[0] ? psg_ioB[1]  : '1) &
                   (io_device[2].param[0] ? psg_ioB[2]  : '1); 

    assign ioA   = {tape_in, 1'b0, ioB[6] ? joyB : joyA};

    assign io_en = cpu_bus.iorq && ~cpu_bus.m1;
    
    genvar i;

    generate
        for (i = 0; i < 3; i++) begin : PSG_INSTANCES
            if (i < MSX::N_PSG) begin : inst
                wire cs_io_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
                wire cs_enable = io_device[i].enable && cs_io_active && io_en;

                assign psg_data[i] = cs_enable && io_device[i].param[0] ? data_tmp[i] : '1;

                jt49_bus psg_i (
                        .rst_n(~cpu_bus.reset),
                        .clk(cpu_bus.clk),
                        .clk_en(clock_bus.ce_3m58_p),
                        .bdir(cs_enable &&  ~cpu_bus.addr[1]),
                        .bc1(cs_enable &&  ~cpu_bus.addr[0]),
                        .din(cpu_bus.data),
                        .sel(0),
                        .dout(data_tmp[i]),
                        .sound(audio_PSG[i]),
                        .A(),
                        .B(),
                        .C(),
                        .IOA_in(io_device[i].param[0] ? ioA : '1),
                        .IOA_out(),
                        .IOB_in('1),
                        .IOB_out(psg_ioB[i])
                );
            end else begin : none
                assign psg_data[i]  = 8'hFF;
                assign data_tmp[i]  = 8'hFF;
                assign audio_PSG[i] = '0;
                assign psg_ioB[i]   = 8'hFF;
            end
        end
    endgenerate

endmodule
