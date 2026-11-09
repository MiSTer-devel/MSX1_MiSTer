// PPI device and Keyboard mapper
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

module dev_ppi (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::io_device_t io_device[3],
    input  MSX::kb_memory_t kb_upload_memory,
    input            [10:0] ps2_key,
    output            [7:0] data,
    output            [7:0] slot_config,
    output                  tape_motor_on,
    output                  keybeep
);

    
    wire [7:0] q;
    wire [7:0] ppi_out_a, ppi_out_c;
    wire       io_en       = cpu_bus.iorq && ~cpu_bus.m1;
    wire       cs_io_match = (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire       cs_enable   = io_device[0].enable && cs_io_match && io_en;

    assign data          = cs_enable ? q : '1;
    assign tape_motor_on = ppi_out_c[4];
    assign keybeep       = ppi_out_c[7];
    assign slot_config   = ppi_out_a;

    jt8255 PPI
    (
        .rst(cpu_bus.reset),
        .clk(cpu_bus.clk),
        .addr(cpu_bus.addr[1:0]),
        .din(cpu_bus.data),
        .dout(q),
        .rdn(~cpu_bus.rd),
        .wrn(~cpu_bus.wr),
        .csn(~cs_enable),
        .porta_din(8'h0),
        .portb_din(d_from_kb),
        .portc_din(8'h0),
        .porta_dout(ppi_out_a),
        .portb_dout(),
        .portc_dout(ppi_out_c),
        .porta_reset_default(io_device[0].param[0] ? 8'hFF : 8'h00),
        .control_reset_default(io_device[0].param[0] ? 7'h0b : 7'h1b)
    );

    //  -----------------------------------------------------------------------------
    //  -- Keyboard decoder
    //  -----------------------------------------------------------------------------
    wire [7:0] d_from_kb;
    keyboard msx_key
    (
        .reset(cpu_bus.reset),
        .clk(cpu_bus.clk),
        .ps2_key(ps2_key),
        .kb_row(ppi_out_c[3:0]),
        .kb_data(d_from_kb),
        .upload_memory(kb_upload_memory)
    );

endmodule

