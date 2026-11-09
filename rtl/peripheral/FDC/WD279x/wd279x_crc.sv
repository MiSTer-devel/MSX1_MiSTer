// WD279x FDC
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

module wd279x_crc #( 
    parameter int CRC_WIDTH = 16,
    parameter logic [CRC_WIDTH-1:0] POLYNOM = 16'h1021
)(
    input  logic                  clk,
    input  logic [7:0]            data_in,
    input  logic                  valid,
    input  logic                  we,
    output logic [CRC_WIDTH-1:0]  crc
);

    logic [CRC_WIDTH-1:0] crc_reg;
    logic last_valid;

    initial begin
        crc_reg =  {CRC_WIDTH{1'b1}};
    end

    always @(posedge clk) begin
        if (valid) begin
            if (we) begin
                crc_reg <= crc_next(crc_reg, data_in);
            end
        end else begin
            if (last_valid) begin
                crc_reg <=  {CRC_WIDTH{1'b1}};
                crc     <= crc_reg;    
            end
        end
        last_valid <= valid;
    end

    function logic [CRC_WIDTH-1:0] crc_next(logic [CRC_WIDTH-1:0] crc, logic [7:0] data);
        logic [CRC_WIDTH-1:0] new_crc;
        int i;
        
        new_crc = crc ^ ({{CRC_WIDTH-8{1'b0}}, data} << (CRC_WIDTH - 8));
        
        for (i = 0; i < 8; i = i + 1) begin
            if (new_crc[CRC_WIDTH-1]) begin
                new_crc = (new_crc << 1) ^ POLYNOM;
            end else begin
                new_crc = (new_crc << 1);
            end
        end
        
        return new_crc;
    endfunction

endmodule
