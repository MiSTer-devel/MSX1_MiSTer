// YM2148 MIDI UART device
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

module dev_YM2148 #(parameter COUNT=1) (
    cpu_bus_if.device_mp   cpu_bus,
    input  MSX::device_bus_t device_bus,
    clock_bus_if.base_mp   clock_bus,
    input MSX::io_device_t io_device[3],
    input            [7:0] uart_rx_data,
    input                  uart_rx,
    output         [7:0]   data,
    output                 irq
);

    localparam STAT_TXRDY = 0;
    localparam STAT_RXRDY = 1;
    localparam STAT_OE    = 4;
    localparam STAT_FE    = 5;

    localparam CMD_TXEN   = 0;
    localparam CMD_TXIE   = 1;
    localparam CMD_RXEN   = 2;
    localparam CMD_RXIE   = 3;
    localparam CMD_ER     = 4;
    localparam CMD_IR     = 7;

    logic [7:0] irq_vector[2];
    logic [7:0] status;
    logic [7:0] cmd_reg;
    logic [7:0] rx_buffer;
    logic       rxIRQ;
    logic       txIRQ;
    logic       kbIRQ;
    logic [7:0] key_row;

    logic [5:0] key_map  [0:48] = '{6'h07, 6'h00, 6'h01, 6'h02, 6'h04, 6'h05, 6'h06, 6'h08, 6'h09, 6'h0B, 
                                    6'h0C, 6'h0D, 6'h0E, 6'h10, 6'h11, 6'h13, 6'h14, 6'h15, 6'h16, 6'h18,
                                    6'h19, 6'h1B, 6'h1C, 6'h1D, 6'h1E, 6'h20, 6'h21, 6'h23, 6'h24, 6'h25,
                                    6'h26, 6'h28, 6'h29, 6'h2B, 6'h2C, 6'h2D, 6'h2E, 6'h30, 6'h31, 6'h33, 
                                    6'h34, 6'h35, 6'h36, 6'h38, 6'h39, 6'h3B, 6'h3C, 6'h3D, 6'h3E};

    wire irq_vector_to_bus = cpu_bus.m1 && cpu_bus.iorq && cpu_bus.int_rq && io_device[0].enable;

    assign data            = irq_vector_to_bus                   ? irq_vector[irq] :
                             dev_rd && cpu_bus.addr[2:0] == 3'd2 ? io_device[0].param[0] ? 8'hFF : matrix_data : 
                             dev_rd && cpu_bus.addr[2:0] == 3'd5 ? io_device[0].param[0] ? rx_buffer : 8'hFF :
                             dev_rd && cpu_bus.addr[2:0] == 3'd6 ? status :
                                                                   8'hFF;
    assign irq             = ((rxIRQ | txIRQ) & io_device[0].param[0]) | (kbIRQ & ~io_device[0].param[0]);

    wire   dev_en = io_device[0].enable && io_device[0].device_ref == device_bus.device_ref && device_bus.we;
    wire   dev_wr = dev_en && cpu_bus.req && cpu_bus.wr;
    wire   dev_rd = dev_en && cpu_bus.rd;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            rx_buffer  <= '0;
            status     <= '0;
            rxIRQ      <= '0;
            txIRQ      <= '0;
            kbIRQ      <= '0;
            status     <= '0;
            cmd_reg    <= '0;
            irq_vector <= '{'1,'1};
        end else begin
            if (dev_wr) begin
                case(cpu_bus.addr[2:0])
                    3'd2: key_row       <= cpu_bus.data;    // Keyboard row
                    3'd3: irq_vector[1] <= cpu_bus.data;    // MIDI IRQ Vector 
                    3'd4: irq_vector[0] <= cpu_bus.data;    // EXT  IRQ Vector 
                    3'd5: begin                             // Data
                        if (cmd_reg[CMD_TXEN]) begin
                        /*
                            if (syncTrans.pendingSyncPoint()) {
                                // We're still sending the previous character, only buffer
                                // this one. Don't accept any further characters.
                                txBuffer2 = value;
                                status &= byte(~STAT_TXRDY);
                                txIRQ.reset();
                            } else {
                                // Immediately start sending this character. We're still
                                // ready to accept a next character.
                                send(value, time);
                           }*/
                           ;
                        end
                    end
                    3'd6: begin                             // Command
                        if (cpu_bus.data[CMD_IR]) begin     // RESET
                            rx_buffer  <= '0;
                            status     <= '0;
                            rxIRQ      <= '0;
                            txIRQ      <= '0;
                            kbIRQ      <= '0;
                            status     <= '0;
                        end else if (cpu_bus.data[CMD_ER]) begin
                            status[STAT_OE] <= 0;            
                            status[STAT_FE] <= 0;
                        end else begin
                            cmd_reg <= cpu_bus.data;
                            if (cpu_bus.data[CMD_RXEN]) begin
                                if (cpu_bus.data[CMD_RXIE]) begin
                                    rxIRQ          <= status[STAT_RXRDY];
                                end
                            end else begin
                                status[STAT_RXRDY] <= 0;
                                rxIRQ              <= 0;
                                kbIRQ              <= 0;
                            end

                            if (cpu_bus.data[CMD_TXEN]) begin
                                if (~cmd_reg[CMD_TXEN]) begin
                                    status[STAT_TXRDY] <= 1;
                                    txIRQ              <= cpu_bus.data[CMD_TXIE];
                                end
                            end else begin
                                status[STAT_TXRDY] <= 0;
                                txIRQ              <= 0;
                            end
                        end
                    end
                    default:;
                endcase
            end
            //UART receive
            if (cmd_reg[CMD_RXEN] && uart_rx) begin
                if (status[STAT_RXRDY]) begin
                    status[STAT_OE] <= 1;
                end else begin
                    rx_buffer <= uart_rx_data;
                    status[STAT_RXRDY] <= 1;
                    if (cmd_reg[CMD_RXIE]) begin
                        rxIRQ <= 1;
                    end
                end
            end
            //KB recive
            if (cmd_reg[CMD_RXIE] && kbIRQrq) begin
                kbIRQ <= 1;
            end
            //Reset status after read data
            if (dev_rd && cpu_bus.addr[2:0] == 3'd5) begin
                rxIRQ <= 0;
                kbIRQ <= 0;
                status[STAT_RXRDY] <= 0;
            end
        end
    end

    typedef enum logic [1:0] {
        IDLE, READ_NOTE, READ_VELOCITY
    } state_t;

    state_t     state;
    logic       status_note;
    logic [6:0] note;
    logic       kbIRQrq;
    logic [7:0] key_matrix[8];

    always_ff @(posedge cpu_bus.clk) begin
        kbIRQrq <= '0;
        if (cpu_bus.reset) begin
            state                 <= IDLE;
            status_note           <= '0;
            key_matrix            <= '{'1, '1, '1, '1, '1, '1, '1, '1};
        end else begin
            if (uart_rx) begin
                if (uart_rx_data[7]) begin
                    if (uart_rx_data[6:5] == 2'b00) begin
                        status_note <= uart_rx_data[4];
                        state       <= READ_NOTE;
                    end else begin
                        state       <= IDLE;
                    end
                end else begin
                    case(state)
                        IDLE: ;
                        READ_NOTE: begin
                            note        <= uart_rx_data[6:0];
                            state       <= READ_VELOCITY;
                        end
                        READ_VELOCITY: begin
                            state       <= READ_NOTE;
                            if (note > 8'h23 && note < 8'h55) begin
                                key_matrix[key_map[note - 8'h24][5:3]][key_map[note - 8'h24][2:0]] <= status_note && uart_rx_data != 0 ? 1'b0 : 1'b1;
                                kbIRQrq <= '1;
                            end
                        end
                        default;
                    endcase    
                end
            end
        end
    end

    logic [7:0] matrix_data;
    always_comb begin
        matrix_data = '1;
        for (int i = 7; i >= 0; i--) begin
            if (key_row[i]) matrix_data &= key_matrix[i];
        end
    end

endmodule
