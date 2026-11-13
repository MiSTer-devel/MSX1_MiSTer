// Matsushita switched I/O device (Panasonic / National / Sanyo MSX2 and MSX2+), CIEL turbo
//
// Copyright (c) 2026 Molekula
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

// Behaviour as openMSX src/MSXMatsushita.cc. Switched I/O (40h-4Fh), device ID 08h:
//   40h  write: device select; read: F7h (complement of the ID) when selected
//   41h  read:  bit 7 firmware switch (0 = on), bit 2 turbo available (0 = yes),
//               bit 0 turbo (0 = 5.37 MHz); write: bit 0 = 0 turbo on, 1 = 3.58 MHz
//   43h  write: colours (high nibble colour 2, low nibble colour 1)
//        read:  two pixels of the pattern as colours, the pattern rotates by 2 bits
//   44h  write: pattern
//   47h, 48h  write: SRAM address low / high (13 bits)
//   49h  SRAM data (2 kB, address below 800h), the address increments
// param[0] = turbo available, param[1] = SRAM present. The turbo flag is cleared only by
// a cold reset. The SRAM is not saved.
module dev_matsushita (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    input                   hard_reset,
    input                   firmware_sw,        // firmware switch (OSD)
    output            [7:0] data,
    output MSX::cpu_speed_t cpu_speed
);

    localparam logic [7:0] ID = 8'h08;

    wire en        = io_device[0].enable;
    wire has_turbo = io_device[0].param[0];
    wire has_sram  = io_device[0].param[1];
    wire cs        = en && cpu_bus.iorq && ~cpu_bus.m1
                     && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire wr        = cs && cpu_bus.wr && cpu_bus.req;

    logic  [7:0] select;
    wire         active = select == ID;

    // read side effects once, when the read ends
    logic        rd_q = 1'b0;
    logic  [3:0] rd_port;
    always_ff @(posedge cpu_bus.clk) begin
        rd_q <= cs && cpu_bus.rd && active;
        if (cs && cpu_bus.rd) rd_port <= cpu_bus.addr[3:0];
    end
    wire rd_end = rd_q && !(cs && cpu_bus.rd);

    logic        turbo = 1'b0;
    logic  [3:0] color1, color2;
    logic  [7:0] pattern;
    logic [12:0] address;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            select  <= 8'h00;
            color1  <= 4'd0;
            color2  <= 4'd0;
            pattern <= 8'h00;
            address <= 13'd0;
        end else begin
            if (wr && cpu_bus.addr[3:0] == 4'd0)
                select <= cpu_bus.data;
            if (wr && active) begin
                case (cpu_bus.addr[3:0])
                    4'd1: turbo <= ~cpu_bus.data[0];
                    4'd3: {color2, color1} <= cpu_bus.data;
                    4'd4: pattern <= cpu_bus.data;
                    4'd7: address[7:0]  <= cpu_bus.data;
                    4'd8: address[12:8] <= cpu_bus.data[4:0];
                    4'd9: address <= address + 13'd1;
                    default: ;
                endcase
            end
            if (rd_end) begin
                case (rd_port)
                    4'd3: pattern <= {pattern[5:0], pattern[7:6]};
                    4'd9: address <= address + 13'd1;
                    default: ;
                endcase
            end
        end
        if (hard_reset || ~en)
            turbo <= 1'b0;
    end

    // 2 kB SRAM
    logic [7:0] sram [0:2047];
    logic [7:0] sram_q;
    initial for (int i = 0; i < 2048; i++) sram[i] = 8'hFF;
    wire sram_sel = has_sram && address[12:11] == 2'b00;
    always_ff @(posedge cpu_bus.clk) begin
        if (wr && active && cpu_bus.addr[3:0] == 4'd9 && sram_sel)
            sram[address[10:0]] <= cpu_bus.data;
        sram_q <= sram[address[10:0]];
    end

    logic [7:0] reg_data;
    always_comb begin
        case (cpu_bus.addr[3:0])
            4'd0:    reg_data = ~ID;
            4'd1:    reg_data = {~firmware_sw, 4'b1111, ~has_turbo, 1'b1, ~turbo};
            4'd3:    reg_data = {pattern[7] ? color2 : color1, pattern[6] ? color2 : color1};
            4'd9:    reg_data = sram_sel ? sram_q : 8'hFF;
            default: reg_data = 8'hFF;
        endcase
    end

    assign data = cs && cpu_bus.rd && active ? reg_data : 8'hFF;

    wire turbo_on = en && has_turbo && turbo;
    assign cpu_speed.en          = en && has_turbo;
    assign cpu_speed.clock_sel   = turbo_on ? 2'b10 : 2'b00;
    assign cpu_speed.mem_wait    = 4'd0;
    assign cpu_speed.io_wait     = 4'd0;
    assign cpu_speed.vdp_wr_hold = en && has_turbo;
    assign cpu_speed.vdp_wr_wait = turbo_on;

endmodule

// CIEL Expert Turbo: one port, bit 7 doubles the Z80 clock (7.16 MHz); reads back the last
// value written. As openMSX src/MSXCielTurbo.cc.
module dev_ciel_turbo (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    output            [7:0] data,
    output MSX::cpu_speed_t cpu_speed
);

    wire en = io_device[0].enable;
    wire cs = en && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;

    logic [7:0] value;
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset)
            value <= 8'h00;
        else if (cs && cpu_bus.wr && cpu_bus.req)
            value <= cpu_bus.data;
    end

    assign data = cs && cpu_bus.rd ? value : 8'hFF;

    assign cpu_speed.en          = en;
    assign cpu_speed.clock_sel   = value[7] ? 2'b11 : 2'b00;
    assign cpu_speed.mem_wait    = 4'd0;
    assign cpu_speed.io_wait     = 4'd0;
    assign cpu_speed.vdp_wr_hold = 1'b0;
    assign cpu_speed.vdp_wr_wait = 1'b0;

endmodule
