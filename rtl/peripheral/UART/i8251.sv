// Intel 8251 USART, asynchronous mode
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

// Register behaviour after openMSX I8251. The transmitter shifts a real frame on TxD,
// one bit per 1 / 16 / 64 TxC ticks (mode byte); the receiver takes whole bytes
// (rx_strobe, from a UART that already decoded the line). Synchronous mode: the mode
// and sync bytes are accepted, nothing is sent. CTS is taken as active.
module i8251 (
    input              clk,
    input              reset,
    input              addr,        // 0 data, 1 mode / command / status
    input        [7:0] din,
    input              wr,          // write pulse
    input              rd_end,      // end of a read
    output       [7:0] dout,
    input              txc_tick,    // falling edge of TxC
    output             txd,
    input              rx_strobe,
    input        [7:0] rx_data,
    input              dsr,
    output             dtr,
    output             rts,
    output             rxrdy
);

    localparam int S_TXRDY = 0, S_RXRDY = 1, S_TXEMPTY = 2, S_PE = 3, S_OE = 4, S_FE = 5;
    localparam int C_TXEN = 0, C_DTR = 1, C_RXE = 2, C_SBRK = 3, C_ER = 4, C_RTS = 5, C_IR = 6;

    typedef enum logic [1:0] { PH_MODE, PH_SYNC1, PH_SYNC2, PH_CMD } phase_t;

    phase_t     phase;
    logic [7:0] mode, command, status;
    logic [7:0] rx_buf, tx_buf;

    // transmitter: frame of start + data (+ parity) bits, then the stop time
    logic       tx_busy;
    logic [9:0] tx_shift;               // bits still to send, LSB first
    logic [3:0] tx_bits;                // bit cells left in tx_shift
    logic [6:0] tx_cnt;                 // TxC ticks left in the current cell
    logic [7:0] tx_stop;                // TxC ticks of stop time left

    wire  [6:0] rate     = mode[1:0] == 2'd3 ? 7'd64 : mode[1:0] == 2'd2 ? 7'd16 : 7'd1;
    wire  [3:0] nbits    = 4'd5 + {2'b0, mode[3:2]};
    // stop time in TxC ticks: 1, 1.5 or 2 bits (00 = invalid, taken as 1)
    wire  [7:0] stop_len = mode[7:6] == 2'd3 ? {rate, 1'b0} :
                           mode[7:6] == 2'd2 ? {1'b0, rate} + {2'b0, rate[6:1]} : {1'b0, rate};

    // bit 0 start, then the data bits LSB first, then the parity bit (if enabled)
    function automatic logic [9:0] frame(input logic [7:0] d);
        logic [7:0] m;
        logic       p;
        m = d & (8'hFF >> (2'd3 - mode[3:2]));          // data bits used
        p = ^m ^ ~mode[5];                              // even: ones made even, odd: made odd
        return {1'b0, m, 1'b0} | (mode[4] ? 10'(p) << (nbits + 4'd1) : 10'd0);
    endfunction

    logic tx_line;
    assign txd   = tx_line & ~command[C_SBRK];        // break holds TxD low
    assign dtr   = command[C_DTR];
    assign rts   = command[C_RTS];
    assign rxrdy = status[S_RXRDY];
    assign dout  = addr ? {dsr, 1'b0, status[5:0]} : rx_buf;

    wire cmd_wr = wr && addr && phase == PH_CMD && !din[C_IR];

    always_ff @(posedge clk) begin
        if (reset) begin
            phase    <= PH_MODE;
            mode     <= '0;
            command  <= '0;
            status   <= 8'(1 << S_TXRDY | 1 << S_TXEMPTY);
            rx_buf   <= '0;
            tx_buf   <= '0;
            tx_busy  <= 1'b0;
            tx_bits  <= '0;
            tx_stop  <= '0;
            tx_line  <= 1'b1;
        end else begin
            // transmitter
            if (tx_busy && txc_tick) begin
                if (tx_bits != 4'd0) begin
                    if (tx_cnt == 7'd1) begin
                        tx_cnt   <= rate;
                        tx_bits  <= tx_bits - 4'd1;
                        tx_shift <= tx_shift >> 1;
                        tx_line  <= tx_bits == 4'd1 ? 1'b1 : tx_shift[1];
                    end else
                        tx_cnt <= tx_cnt - 7'd1;
                end else if (tx_stop != 8'd1)
                    tx_stop <= tx_stop - 8'd1;
                else if (!status[S_TXRDY]) begin            // next byte waiting
                    status[S_TXRDY] <= 1'b1;
                    tx_shift <= frame(tx_buf);
                    tx_bits  <= 4'd1 + nbits + {3'b0, mode[4]};
                    tx_cnt   <= rate;
                    tx_stop  <= stop_len;
                    tx_line  <= 1'b0;
                end else begin
                    tx_busy           <= 1'b0;
                    status[S_TXEMPTY] <= 1'b1;
                end
            end

            if (wr && !addr && command[C_TXEN]) begin       // data
                if (status[S_TXEMPTY]) begin
                    status[S_TXEMPTY] <= 1'b0;
                    tx_busy  <= 1'b1;
                    tx_shift <= frame(din);
                    tx_bits  <= 4'd1 + nbits + {3'b0, mode[4]};
                    tx_cnt   <= rate;
                    tx_stop  <= stop_len;
                    tx_line  <= 1'b0;
                end else begin
                    tx_buf          <= din;
                    status[S_TXRDY] <= 1'b0;
                end
            end

            if (wr && addr) begin
                case (phase)
                    PH_MODE: begin
                        mode  <= din;
                        phase <= din[1:0] == 2'd0 ? PH_SYNC1 : PH_CMD;
                    end
                    PH_SYNC1: phase <= din[7] ? PH_CMD : PH_SYNC2;
                    PH_SYNC2: phase <= PH_CMD;
                    default: if (din[C_IR]) phase <= PH_MODE;
                endcase
            end

            if (cmd_wr) begin
                command <= din;
                if (!din[C_TXEN]) begin                     // transmitter off: abort
                    tx_busy           <= 1'b0;
                    status[S_TXRDY]   <= 1'b1;
                    status[S_TXEMPTY] <= 1'b1;
                    tx_line           <= 1'b1;
                end
                if (din[C_ER] || din[C_RXE] != command[C_RXE]) begin
                    status[S_PE] <= 1'b0;
                    status[S_OE] <= 1'b0;
                    status[S_FE] <= 1'b0;
                end
                if (!din[C_RXE]) status[S_RXRDY] <= 1'b0;
            end

            // receiver
            if (rd_end && !addr) status[S_RXRDY] <= 1'b0;
            if (rx_strobe && command[C_RXE]) begin
                if (status[S_RXRDY])
                    status[S_OE] <= 1'b1;
                else begin
                    rx_buf          <= rx_data;
                    status[S_RXRDY] <= 1'b1;
                end
            end
        end
    end

endmodule
