// cfg_report
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

// Configuration report for the HPS (Main_MiSTer support/msx): after each configuration run of
// memory_upload the result is written into the DDR3 at MSX::DDR3_INFO, one byte per ddram write.
//   0-3   'M' 'S' 'X' 'R'
//   4     valid: written 0 first and 1 last
//   5     version (1)
//   6     generation, +1 per report
//   7     error (error_t)
//   8, 9  slot A: source (MSX::cart_src_t), FW ID
//   10,11 slot B: source, FW ID
//   12-15 CRC32 of ROM A, 16-19 CRC32 of ROM B (little endian)
// The DDR3 port is used only while memory_upload is idle (done); a new upload ends the report
// at once and the next one is written after it.
module cfg_report
(
    input                       clk,
    input                       done,           // memory_upload idle or stopped
    input                       mu_rd,          // memory_upload read not finished
    input  error_t              error,
    input  MSX::cart_report_t   cart[2],
    input                       ddr3_ready,
    output                      ddr3_request,
    output logic         [27:0] ddr3_addr,
    output logic          [7:0] ddr3_din,
    output logic                ddr3_we = 1'b0
);

    localparam logic [4:0] LEN = 5'd20;

    typedef enum logic [1:0] {IDLE, SEND, HOLD, WAIT} state_t;
    state_t     state   = IDLE;
    logic       done_q  = 1'b1;     // no report at power-up
    logic       pending = 1'b0;
    logic [7:0] gen     = '0;
    logic [4:0] step;               // 0: valid = 0, 1..LEN: byte step-1, LEN+1: valid = 1

    assign ddr3_request = state != IDLE && done;

    wire       edge_step = step == '0 || step == LEN + 5'd1;
    wire [4:0] offset    = edge_step ? 5'd4 : step - 5'd1;

    function automatic logic [7:0] report_byte(input logic [4:0] i);
        case (i)
            5'd0:    return 8'h4D;                  // 'M'
            5'd1:    return 8'h53;                  // 'S'
            5'd2:    return 8'h58;                  // 'X'
            5'd3:    return 8'h52;                  // 'R'
            5'd5:    return 8'd1;
            5'd6:    return gen;
            5'd7:    return {4'd0, error};
            5'd8:    return {5'd0, cart[0].src};
            5'd9:    return cart[0].fw;
            5'd10:   return {5'd0, cart[1].src};
            5'd11:   return cart[1].fw;
            5'd12:   return cart[0].crc[7:0];
            5'd13:   return cart[0].crc[15:8];
            5'd14:   return cart[0].crc[23:16];
            5'd15:   return cart[0].crc[31:24];
            5'd16:   return cart[1].crc[7:0];
            5'd17:   return cart[1].crc[15:8];
            5'd18:   return cart[1].crc[23:16];
            5'd19:   return cart[1].crc[31:24];
            default: return 8'd0;                   // 4: valid stays 0
        endcase
    endfunction

    always_ff @(posedge clk) begin
        done_q  <= done;
        ddr3_we <= 1'b0;
        if (done && !done_q) pending <= 1'b1;
        if (!done) state <= IDLE;
        else case (state)
            IDLE: if (pending && ddr3_ready && !mu_rd) begin
                pending <= 1'b0;
                gen     <= gen + 8'd1;
                step    <= '0;
                state   <= SEND;
            end
            SEND: if (ddr3_ready) begin
                ddr3_addr <= MSX::DDR3_INFO + {23'd0, offset};
                ddr3_din  <= edge_step ? {7'd0, step != '0} : report_byte(offset);
                ddr3_we   <= 1'b1;
                state     <= HOLD;
            end
            HOLD: state <= WAIT;                    // ddram takes the write at the end of this clk
            WAIT: if (ddr3_ready) begin
                step  <= step + 5'd1;
                state <= step == LEN + 5'd1 ? IDLE : SEND;
            end
        endcase
    end

endmodule
