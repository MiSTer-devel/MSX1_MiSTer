// Simple UART RX
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

module uart_rx #(parameter sysCLK)
(
    input              clk,
    input              reset,
    input              rx,
    input [31:0]       uart_speed,
    output logic       data_rx,
    output logic       framing_err,
    output logic [7:0] data
);


// Bit period = baudrate cycles (counter runs 1..baudrate), so no "- 1".
// Only speeds offered by CONF_STR; anything else falls back to 115200.
function automatic [13:0] baud_calc(input [31:0] spd);
    unique case (spd[15:0])
      16'd31250 : baud_calc = 14'(sysCLK / 31250);
      default   : baud_calc = 14'(sysCLK / 115200);
    endcase
endfunction

typedef enum logic [1:0] { UART_IDLE, UART_DATA, UART_STOP } uart_state_t;

logic        clk_en;
logic        rx_s, old_rx_s;
logic        clk_rx;
logic  [3:0] rx_reg;
logic  [2:0] data_count;
logic  [7:0] tmp_data;
logic [13:0] counter, baudrate_q;
uart_state_t state;

always_ff @(posedge clk) begin
    if (reset) begin
        baudrate_q <= baud_calc(32'd115200);
    end else if (state == UART_IDLE) begin
        baudrate_q <= baud_calc(uart_speed);
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        rx_reg <= 4'b1111;
        rx_s   <= 1'b1;
    end else begin
        rx_reg <= {rx_reg[2:0], rx};
        if (rx_reg == 4'b0000)      rx_s <= 1'b0;
        else if (rx_reg == 4'b1111) rx_s <= 1'b1;
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        clk_rx  <= 1'b0;
        counter <= 14'd1;
    end else begin
        if (state == UART_IDLE && old_rx_s && ~rx_s)
            counter <= {1'b0, baudrate_q[13:1]};

        if (clk_en) begin
            if (counter == baudrate_q) begin
                clk_rx  <= 1'b1;
                counter <= 14'd1;
            end else begin
                clk_rx  <= 1'b0;
                counter <= counter + 14'd1;
            end
        end else begin
            clk_rx  <= 1'b0;
            counter <= {1'b0, baudrate_q[13:1]};
        end
    end
end

always_ff @(posedge clk) begin
    if (reset) begin
        clk_en   <= 1'b0;
        old_rx_s <= 1'b1;
    end else begin
        if (state == UART_IDLE &&  old_rx_s && ~rx_s)
            clk_en <= 1'b1;

        if (state == UART_STOP && clk_rx)
            clk_en <= 1'b0;

        if (state == UART_IDLE && ~old_rx_s && rx_s)
            clk_en <= 1'b0;

        old_rx_s <= rx_s;
    end
end

always_ff @(posedge clk) begin
    data_rx <= 0;
    if (reset) begin
        state   <= UART_IDLE;
        data     <= '0;
        tmp_data <= '0;
    end else begin
        if (clk_rx) begin
            case(state)
                UART_IDLE: begin
                    if (~rx_s) begin
                        data_count <= '1;
                        state      <= UART_DATA;
                    end
                end
                UART_DATA: begin
                    tmp_data <= {rx_s, tmp_data[7:1]};
                    if (data_count == 0) begin
                        state      <= UART_STOP;
                        data_count <= '1;
                    end else begin
                        data_count <= data_count - 3'd1;
                    end
                end
                UART_STOP: begin
                    framing_err <= ~rx_s;
                    state       <= UART_IDLE;
                    data_rx     <= 1;
                    data        <= tmp_data;
                end
                default:;
            endcase
        end
    end
end

endmodule
