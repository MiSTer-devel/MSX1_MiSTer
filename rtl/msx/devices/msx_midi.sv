// MSX-MIDI (FS-A1GT, MIDI Interface 3 cartridge)
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

// Ports (base E8h): +0 8251 data, +1 8251 command / status, +2 write: timer IRQ off,
// +4..+7 8254. Wiring after openMSX MSXMidi: 8254 CLK0 and CLK2 4 MHz, OUT0 = 8251 TxC,
// OUT2 clocks counter 1 and its rising edge sets the timer IRQ. 8251 DTR enables the
// timer IRQ, RTS the RxRDY IRQ; DSR reads the timer IRQ.
module dev_msx_midi (
    cpu_bus_if.device_mp   cpu_bus,
    input MSX::io_device_t io_device[3],       // single instance: [0]
    input                  uart_rx,            // received byte strobe
    input            [7:0] uart_rx_data,
    output           [7:0] data,
    output                 irq,
    output                 tx
);

    wire en    = io_device[0].enable;
    wire reset = cpu_bus.reset || ~en;
    wire cs    = en && cpu_bus.iorq && ~cpu_bus.m1
                 && (cpu_bus.addr[7:0] & io_device[0].mask) == io_device[0].port;
    wire wr    = cs && cpu_bus.wr && cpu_bus.req;

    // read side effects once, when the read ends
    logic       rd_q = 1'b0;
    logic [2:0] rd_port;
    always_ff @(posedge cpu_bus.clk) begin
        rd_q <= cs && cpu_bus.rd;
        if (cs && cpu_bus.rd) rd_port <= cpu_bus.addr[2:0];
    end
    wire rd_end = rd_q && !(cs && cpu_bus.rd);
    wire [2:0] port = rd_end ? rd_port : cpu_bus.addr[2:0];

    // 4 MHz for CLK0 / CLK2
    localparam int HZ = MSX::CLK_CORE_HZ;
    logic [24:0] acc = '0;
    logic        tick4m = 1'b0;
    always_ff @(posedge cpu_bus.clk) begin
        if (acc + 25'd4_000_000 >= 25'(HZ)) begin
            acc    <= acc + 25'd4_000_000 - 25'(HZ);
            tick4m <= 1'b1;
        end else begin
            acc    <= acc + 25'd4_000_000;
            tick4m <= 1'b0;
        end
    end

    // 8254
    wire [2:0] out;
    logic      out0_q = 1'b1, out2_q = 1'b1;
    always_ff @(posedge cpu_bus.clk) begin
        out0_q <= out[0];
        out2_q <= out[2];
    end
    wire [7:0] pit_q;
    i8254 pit (
        .clk(cpu_bus.clk), .reset(reset),
        .addr(port[1:0]), .din(cpu_bus.data),
        .wr(wr && port[2]), .rd_end(rd_end && port[2]), .dout(pit_q),
        .tick({tick4m, out2_q && !out[2], tick4m}),     // CLK1 = OUT2, counted on its falling edge
        .out(out)
    );

    // 8251
    wire [7:0] uart_q;
    wire       dtr, rts, rxrdy;
    logic      timer_latch;
    wire       timer_irq = timer_latch && dtr;
    i8251 usart (
        .clk(cpu_bus.clk), .reset(reset),
        .addr(port[0]), .din(cpu_bus.data),
        .wr(wr && port[2:1] == 2'd0), .rd_end(rd_end && port[2:1] == 2'd0), .dout(uart_q),
        .txc_tick(out0_q && !out[0]),
        .txd(tx),
        .rx_strobe(uart_rx), .rx_data(uart_rx_data),
        .dsr(timer_irq), .dtr(dtr), .rts(rts), .rxrdy(rxrdy)
    );

    // timer IRQ: set by OUT2 rising while enabled, cleared by a write to +2
    always_ff @(posedge cpu_bus.clk) begin
        if (reset)
            timer_latch <= 1'b0;
        else if (wr && port == 3'd2)
            timer_latch <= 1'b0;
        else if (dtr && !out2_q && out[2])
            timer_latch <= 1'b1;
    end

    assign irq  = timer_irq || (rxrdy && rts);
    assign data = cs && cpu_bus.rd ? (port[2] ? pit_q : port[1] ? 8'hFF : uart_q) : 8'hFF;

endmodule
