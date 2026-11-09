// FDC package
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

// Shared by the drive (transmit, receive) and the controllers: the CRC of the IBM floppy
// formats (CRC-CCITT, x^16 + x^12 + x^5 + 1, MSB first, preset FFFF).
package FDC;

    localparam logic [15:0] CRC_INIT  = 16'hFFFF;
    localparam logic [15:0] CRC_A1x3  = 16'hCDB4;   // after the three MFM A1 marks of a field

    function automatic logic [15:0] crc16(input logic [15:0] c, input logic [7:0] d);
        logic [15:0] r;
        r = c ^ {d, 8'h00};
        for (int i = 0; i < 8; i++) r = r[15] ? {r[14:0], 1'b0} ^ 16'h1021 : {r[14:0], 1'b0};
        return r;
    endfunction

endpackage
