// OPL4 device (MoonSound: YMF278B with 2 MB wave ROM and sample RAM)
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

// Ports as the MoonSound: C4h / C6h FM register select (array 0 / 1) and status, C5h / C7h FM
// data; 7Eh wave register select, 7Fh wave data (writes only with NEW2). Bus behaviour after
// openMSX YMF278B (doc/moonsound.md). The CPU waits while the wave part loads a header or
// accesses the sample memory.
module dev_opl4 (
    cpu_bus_if.device_mp   cpu_bus,
    input MSX::io_device_t io_device[3],
    input MSX::io_device_mem_ref_t io_memory[8],   // memory of the device: wave ROM, sample RAM behind it
    wave_bus_if.device_mp  wave_bus,
    output MSX::sound_t    sound_L,
    output MSX::sound_t    sound_R,
    output           [7:0] data,
    output                 irq,
    output                 wait_rq
);

    generate
        if (MSX::N_OPL4 == 0) begin : none
            assign sound_L = '0;
            assign sound_R = '0;
            assign data    = 8'hFF;
            assign irq     = 1'b0;
            assign wait_rq = 1'b0;
            assign wave_bus.req   = 1'b0;
            assign wave_bus.we    = 1'b0;
            assign wave_bus.addr  = '0;
            assign wave_bus.wdata = '0;
        end else begin : inst
            // delays of the status BUSY / LD bits in clk (YMF278B master clock 33.8688 MHz)
            localparam int        MCLK       = 33868800;
            localparam logic [12:0] BUSY_FM   = (56 * (MSX::CLK_CORE_HZ / 100) + MCLK / 100 - 1) / (MCLK / 100);
            localparam logic [12:0] BUSY_WAVE = (88 * (MSX::CLK_CORE_HZ / 100) + MCLK / 100 - 1) / (MCLK / 100);
            localparam logic [12:0] BUSY_MEMW = (28 * (MSX::CLK_CORE_HZ / 100) + MCLK / 100 - 1) / (MCLK / 100);
            localparam logic [12:0] BUSY_MEMR = (38 * (MSX::CLK_CORE_HZ / 100) + MCLK / 100 - 1) / (MCLK / 100);
            localparam logic [12:0] LOAD_TIME = (MSX::CLK_CORE_HZ / 1000) * 10000 / (MCLK / 1000);   // 300 us

            wire        en    = io_device[0].enable;
            wire        reset = cpu_bus.reset || ~en;
            wire        io_en = en && cpu_bus.iorq && ~cpu_bus.m1;
            wire        cs_fm   = io_en && cpu_bus.addr[7:2] == 6'b110001;     // C4h-C7h
            wire        cs_wave = io_en && cpu_bus.addr[7:1] == 7'b0111111;    // 7Eh, 7Fh

            // sample clocks from clk_core (21.47727 MHz): FM 33868800 / 684 Hz, wave 44100 Hz
            logic [23:0] fm_acc;
            logic [19:0] wv_acc;
            logic        fm_tick, wv_tick;
            always_ff @(posedge cpu_bus.clk) begin
                fm_tick <= 1'b0;
                wv_tick <= 1'b0;
                if (fm_acc >= 24'd13602271 - 24'd31360) begin fm_acc <= fm_acc + 24'd31360 - 24'd13602271; fm_tick <= 1'b1; end
                else fm_acc <= fm_acc + 24'd31360;
                if (wv_acc >= 20'd715909 - 20'd1470) begin wv_acc <= wv_acc + 20'd1470 - 20'd715909; wv_tick <= 1'b1; end
                else wv_acc <= wv_acc + 20'd1470;
                if (reset) begin fm_acc <= '0; wv_acc <= '0; end
            end

            // FM part
            logic  [8:0] fm_latch;
            logic        fm_wr;
            logic  [7:0] fm_wdata;
            wire   [7:0] fm_rdata, fm_status;
            wire         newm, new2, fm_ready, fm_valid;
            wire signed [15:0] fm_a, fm_b;
            opl3 opl3 (
                .clk(cpu_bus.clk), .reset(reset), .smp_tick(fm_tick),
                .wr(fm_wr), .wr_addr(fm_latch), .wr_data(fm_wdata),
                .rd_addr(fm_latch), .rd_data(fm_rdata),
                .status(fm_status), .newm(newm), .new2(new2), .ready(fm_ready),
                .out_a(fm_a), .out_b(fm_b), .out_valid(fm_valid)
            );

            // wave part
            logic  [7:0] wv_latch, wv_wdata;
            logic        wv_wr, wv_rd;
            wire   [7:0] wv_rdata;
            wire         wv_busy, wv_valid, wv_mem_req, wv_mem_we;
            wire   [5:0] mix_fm;
            wire  [21:0] wv_mem_addr;
            wire signed [20:0] wv_l, wv_r;
            opl4_wave wave (
                .clk(cpu_bus.clk), .reset(reset), .smp_tick(wv_tick),
                .ram_chunks(io_device[0].param[4:0]),
                .reg_wr(wv_wr), .reg_rd(wv_rd), .reg_addr(wv_latch), .reg_wdata(wv_wdata),
                .reg_rdata(wv_rdata), .busy(wv_busy), .mix_fm(mix_fm),
                .mem_req(wv_mem_req), .mem_we(wv_mem_we), .mem_addr(wv_mem_addr), .mem_wdata(wave_bus.wdata),
                .mem_ack(wave_bus.ack), .mem_rdata(wave_bus.rdata),
                .out_l(wv_l), .out_r(wv_r), .out_valid(wv_valid), .late(), .idle()
            );
            assign wave_bus.req  = wv_mem_req;
            assign wave_bus.we   = wv_mem_we;
            assign wave_bus.addr = io_memory[io_device[0].mem_ref].memory + {5'd0, wv_mem_addr};

            // bus access: taken once per access; on the wave data port only when the wave part
            // is free, the CPU waits until then
            logic        pend, p_wr;
            logic  [2:0] p_port;                    // {wave, address 1:0}
            logic  [7:0] p_data, rd_q;
            logic        status2, new2_seen;        // status bit 1 once after NEW2 was first set
            logic [12:0] busy_cnt, load_cnt;
            wire         acc     = (cs_fm || cs_wave) && (cpu_bus.rd || cpu_bus.wr) && cpu_bus.req;
            wire         a_wr    = pend ? p_wr   : cpu_bus.wr;
            wire   [2:0] a_port  = pend ? p_port : {cs_wave, cpu_bus.addr[1:0]};
            wire   [7:0] a_data  = pend ? p_data : cpu_bus.data;
            wire         a_wave  = a_port[2];
            wire         want    = acc || pend;
            wire         blocked = (a_wave && a_port[0] && wv_busy) || ~fm_ready;
            wire         go      = want && ~blocked;
            assign wait_rq = want && ~go;

            wire   [7:0] st_val  = fm_status | {6'd0, load_cnt != 13'd0 || status2, busy_cnt != 13'd0 || wv_busy};
            wire         wv_mem_reg = wv_latch >= 8'd3 && wv_latch <= 8'd6;

            always_ff @(posedge cpu_bus.clk) begin
                fm_wr <= 1'b0;
                wv_wr <= 1'b0;
                wv_rd <= 1'b0;
                if (busy_cnt != 13'd0) busy_cnt <= busy_cnt - 13'd1;
                if (load_cnt != 13'd0) load_cnt <= load_cnt - 13'd1;

                if (want && ~go && ~pend) begin
                    pend   <= 1'b1;
                    p_wr   <= cpu_bus.wr;
                    p_port <= {cs_wave, cpu_bus.addr[1:0]};
                    p_data <= cpu_bus.data;
                end
                if (go) begin
                    pend <= 1'b0;
                    if (~a_wave) begin
                        if (a_wr) begin
                            busy_cnt <= BUSY_FM;
                            if (~a_port[0]) fm_latch <= {a_port[1], a_data};
                            else begin
                                fm_wr    <= 1'b1;
                                fm_wdata <= a_data;
                                if (fm_latch == 9'h105 && a_data[1] && ~new2_seen) begin
                                    status2   <= 1'b1;
                                    new2_seen <= 1'b1;
                                end
                            end
                        end else begin
                            rd_q <= a_port[0] ? fm_rdata : st_val;
                            if (~a_port[0]) status2 <= 1'b0;
                        end
                    end else if (a_wr) begin
                        if (new2) begin                         // wave writes need NEW2
                            if (~a_port[0]) begin
                                wv_latch <= a_data;
                                busy_cnt <= BUSY_WAVE;
                            end else begin
                                wv_wr    <= 1'b1;
                                wv_wdata <= a_data;
                                busy_cnt <= wv_mem_reg ? BUSY_MEMW : BUSY_WAVE;
                                if (wv_latch >= 8'h08 && wv_latch <= 8'h1F) load_cnt <= LOAD_TIME;
                            end
                        end
                    end else begin
                        rd_q <= a_port[0] ? wv_rdata : 8'hFF;
                        if (a_port[0]) begin
                            wv_rd <= 1'b1;
                            if (wv_mem_reg) busy_cnt <= BUSY_MEMR;
                        end
                    end
                end

                if (reset) begin
                    pend <= 1'b0;
                    fm_latch <= '0; wv_latch <= '0;
                    status2 <= 1'b0; new2_seen <= 1'b0;
                    busy_cnt <= '0; load_cnt <= '0;
                end
            end

            assign data = (cs_fm || cs_wave) && cpu_bus.rd ? rd_q : 8'hFF;
            assign irq  = en && fm_status[7];

            // mix: FM operator full scale (4084) = wave sample full scale; 18 bit like the
            // DAC of the board, here with 2 bits less at the bottom
            function automatic logic signed [20:0] gain8(input logic signed [20:0] x, input logic [2:0] i);
                logic signed [22:0] x3;
                x3 = {x[20], x[20], x} + {x[20], x, 1'b0};
                case (i)
                    3'd0:    gain8 = x;
                    3'd1:    gain8 = x3[22:2];
                    3'd2:    gain8 = {x[20], x[20:1]};
                    3'd3:    gain8 = {x3[22], x3[22:3]};
                    3'd4:    gain8 = {{2{x[20]}}, x[20:2]};
                    3'd5:    gain8 = {{2{x3[22]}}, x3[22:4]};
                    3'd6:    gain8 = {{3{x[20]}}, x[20:3]};
                    default: gain8 = 21'sd0;
                endcase
            endfunction
            function automatic logic signed [17:0] sat18(input logic signed [21:0] v);
                logic signed [19:0] h;
                h = v[21:2];
                sat18 = (h[19] != h[18] || h[18] != h[17]) ? {h[19], {17{~h[19]}}} : h[17:0];
            endfunction

            logic signed [20:0] fm_l, fm_r, wvq_l, wvq_r;
            MSX::sound_t        snd_l, snd_r;
            always_ff @(posedge cpu_bus.clk) begin
                if (fm_valid) begin
                    fm_l <= gain8({{2{fm_a[15]}}, fm_a, 3'b000}, mix_fm[2:0]);
                    fm_r <= gain8({{2{fm_b[15]}}, fm_b, 3'b000}, mix_fm[5:3]);
                end
                if (wv_valid) begin wvq_l <= wv_l; wvq_r <= wv_r; end
                snd_l <= sat18({fm_l[20], fm_l} + {wvq_l[20], wvq_l});
                snd_r <= sat18({fm_r[20], fm_r} + {wvq_r[20], wvq_r});
                if (reset) begin fm_l <= '0; fm_r <= '0; wvq_l <= '0; wvq_r <= '0; snd_l <= '0; snd_r <= '0; end
            end
            assign sound_L = snd_l;
            assign sound_R = snd_r;
        end
    endgenerate

endmodule
