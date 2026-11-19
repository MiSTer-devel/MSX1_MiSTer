// S1985 MSX-Engine: switched I/O device ID FEh
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

// As openMSX src/MSXS1985.cc. Ports 40h-4Fh (io_device mask F0h, port 40h):
//   40h  write: device select (every switched device latches it); read ~ID = 01h when selected
//   41h  write: backup RAM address (4 bits)
//   42h  read / write: backup RAM data (16 bytes, battery backed)
//   46h  write: colour register (the previous value moves to the second one)
//   47h  write: pattern; read: colour by pattern bit 7, the pattern rotates left after the read
// Other ports read FFh. The backup RAM is not saved; it is FFh at power-on and after a pack
// load (sram_init). Not done: the mapper read-back of the S1985 (5 bits, base 80h).
module dev_s1985 (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],       // single instance: [0]
    input                   sram_init,          // backup RAM to FFh (pack load)
    output            [7:0] data
);

    localparam logic [7:0] ID = 8'hFE;

    wire en = io_device[0].enable;
    wire cs = en && cpu_bus.iorq && ~cpu_bus.m1
              && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire wr = cs && cpu_bus.wr && cpu_bus.req;

    logic [7:0] select;
    wire        active = select == ID;

    // read side effect once, when the read ends
    logic       rd_q = 1'b0;
    logic [3:0] rd_port;
    always_ff @(posedge cpu_bus.clk) begin
        rd_q <= cs && cpu_bus.rd && active;
        if (cs && cpu_bus.rd) rd_port <= cpu_bus.addr[3:0];
    end
    wire rd_end = rd_q && !(cs && cpu_bus.rd);

    logic [7:0] color1, color2, pattern;
    logic [3:0] address;
    logic [7:0] sram [16];
    initial for (int i = 0; i < 16; i++) sram[i] = 8'hFF;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            select  <= 8'h00;
            color1  <= 8'h00;
            color2  <= 8'h00;
            pattern <= 8'h00;
            address <= 4'd0;
        end else begin
            if (wr && cpu_bus.addr[3:0] == 4'd0)
                select <= cpu_bus.data;
            if (wr && active) begin
                case (cpu_bus.addr[3:0])
                    4'd1: address <= cpu_bus.data[3:0];
                    4'd6: begin color2 <= color1; color1 <= cpu_bus.data; end
                    4'd7: pattern <= cpu_bus.data;
                    default: ;
                endcase
            end
            if (rd_end && rd_port == 4'd7)
                pattern <= {pattern[6:0], pattern[7]};
        end
        if (sram_init)
            for (int i = 0; i < 16; i++) sram[i] <= 8'hFF;
        else if (wr && active && cpu_bus.addr[3:0] == 4'd2)
            sram[address] <= cpu_bus.data;
    end

    logic [7:0] reg_data;
    always_comb begin
        case (cpu_bus.addr[3:0])
            4'd0:    reg_data = ~ID;
            4'd2:    reg_data = sram[address];
            4'd7:    reg_data = pattern[7] ? color2 : color1;
            default: reg_data = 8'hFF;
        endcase
    end

    assign data = cs && cpu_bus.rd && active ? reg_data : 8'hFF;

endmodule
