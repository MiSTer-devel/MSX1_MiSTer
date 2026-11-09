// OPLL device
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

module dev_opll (
    cpu_bus_if.device_mp   cpu_bus,
    input  MSX::device_bus_t device_bus,
    clock_bus_if.base_mp   clock_bus,
    input MSX::io_device_t io_device[3],
    input                  enawait,         // CPU faster than 3.58 MHz (OCM turbo): wait while the OPLL is busy
    output                 wait_rq,         // CPU wait request
    output MSX::sound_t    sound
);

    logic signed [15:0] sound_OPLL[0:2];
    logic [2:0] opll_enabled;
    logic [2:0] io_wait;

    assign wait_rq = |io_wait;

    always_comb begin
        sound = '0;
        for (int i = 0; i < 3; i++)
            if (io_device[i].enable) sound += sound_OPLL[i];
    end

    // I/O of an OPLL in a block (FM-PAC, device_ref != 0) follows the block's enable (7FF6h bit 0).
    // An OPLL of the machine (device_ref 0, e.g. OCM) stays enabled: device_ref 0 is also the idle bus.
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            opll_enabled <= 3'b111;
        end else begin
            for (int k = 0; k < 3; k++)
                if (io_device[k].device_ref != 3'd0 && io_device[k].device_ref == device_bus.device_ref)
                    opll_enabled[k] <= device_bus.en;
        end
    end

    wire io_en = cpu_bus.iorq && ~cpu_bus.m1;

    genvar i;

    generate
        for (i = 0; i < 3; i++) begin : OPLL_INSTANCES
            if (i < MSX::N_OPLL) begin : inst
                wire cs_io_active = (cpu_bus.addr[7:0] & io_device[i].mask) == io_device[i].port;
                wire cs_io_wr     = (io_device[i].enable && cs_io_active && io_en && opll_enabled[i] && cpu_bus.wr);
                wire cs_dev_bus   = (io_device[i].enable && io_device[i].device_ref == device_bus.device_ref && device_bus.we);

                // I/O write taken once per access when the OPLL is not busy (else the CPU waits),
                // then held for IKAOPLL 12 clk (two 3.58 MHz enables) regardless of the CPU strobe.
                // Busy with enawait as the YM2413 (IKAOPLL is cycle exact): address 12, data 84
                // cycles of 3.58 MHz + 2 margin (OCM eseopll: 4 / 72, too short here); else 12 clk.
                logic       pend, a0_q;
                logic [7:0] d_q;
                logic [9:0] busy;
                logic [3:0] strobe;
                wire        want = (cs_io_wr && cpu_bus.req) || pend;
                wire        go   = want && busy == 10'd0;
                wire        io_wr = strobe != 4'd0;
                assign io_wait[i] = want && ~go;

                always_ff @(posedge cpu_bus.clk) begin
                    if (cpu_bus.reset) begin
                        pend   <= 1'b0;
                        busy   <= 10'd0;
                        strobe <= 4'd0;
                    end else begin
                        if (busy != 10'd0)  busy   <= busy - 10'd1;
                        if (strobe != 4'd0) strobe <= strobe - 4'd1;
                        if (go) begin
                            pend   <= 1'b0;
                            a0_q   <= cpu_bus.addr[0];
                            d_q    <= cpu_bus.data;
                            strobe <= 4'd12;
                            busy   <= ~enawait ? 10'd12 : cpu_bus.addr[0] ? 10'd516 : 10'd84;
                        end else if (want)
                            pend   <= 1'b1;
                    end
                end

                IKAOPLL #(.FULLY_SYNCHRONOUS(1), .FAST_RESET(1), .ALTPATCH_CONFIG_MODE(0), .USE_PIPELINED_MULTIPLIER(1)) ika_opll_opll_int (
                    .i_XIN_EMUCLK       (cpu_bus.clk),
                    .i_phiM_PCEN_n      (~clock_bus.ce_3m58_n),
                    .i_IC_n             (~cpu_bus.reset),
                    .i_ALTPATCH_EN      (1'b0),
                    .i_CS_n             (~(io_wr || cs_dev_bus)),
                    .i_WR_n             (~(io_wr || device_bus.we)),
                    .i_A0               (io_wr ? a0_q : cpu_bus.addr[0]),
                    .i_D                (io_wr ? d_q  : cpu_bus.data),
                    .i_ACC_SIGNED_MOVOL (5'sd9),
                    .i_ACC_SIGNED_ROVOL (5'sd15),
                    .o_ACC_SIGNED       (sound_OPLL[i])
                );
            end else begin : none
                assign sound_OPLL[i] = '0;
                assign io_wait[i]    = 1'b0;
            end
        end
    endgenerate

endmodule
