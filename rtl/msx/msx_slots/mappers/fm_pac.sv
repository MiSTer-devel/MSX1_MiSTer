// FM PAC mapper
//
// Copyright (c) 2024 Molekula
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

module mapper_fm_pac (
    cpu_bus_if.device_mp    cpu_bus,       // Interface for CPU communication
    input  MSX::block_info_t block_info,    // Active block (slot layout entry)
    output MSX::mapper_out_t out,           // Mapper output, merged in mappers.sv
    output MSX::device_bus_t device_out     // Cartridge device control
);

    // Internal logic variables
    logic [7:0] enable[2];             // Enable registers for mapper
    logic [1:0] bank[2];               // Bank registers for mapper
    logic [7:0] magicLo[2];            // Lower half of magic value for SRAM
    logic [7:0] magicHi[2];            // Upper half of magic value for SRAM
    logic       opll_wr;               // OPLL write signal
    wire        mapped = cpu_bus.addr[15:14] == 2'b01;   // window 4000-7FFF

    // Initial setup
    initial begin
        opll_wr  = 1'b0;
        enable   = '{default: 8'b0};
        bank     = '{default: 2'b0};
        magicLo  = '{default: 8'b0};
        magicHi  = '{default: 8'b0};
    end

    // Main control logic
    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Reset states
            enable  <= '{default: 8'b0};
            bank    <= '{default: 2'b0};
            magicLo <= '{default: 8'b0};
            magicHi <= '{default: 8'b0};
        end else begin
            opll_wr <= 1'b0;
            if (block_info.typ == MAPPER_FMPAC && cpu_bus.wr && cpu_bus.mreq && cpu_bus.req && mapped) begin
                case (cpu_bus.addr[13:0])
                    14'h1FFE:
                        if (~enable[block_info.id][4])
                            magicLo[block_info.id] <= cpu_bus.data;
                    14'h1FFF:
                        if (~enable[block_info.id][4])
                            magicHi[block_info.id] <= cpu_bus.data;
                    14'h3FF4, 14'h3FF5:
                        opll_wr <= 1'b1;
                    14'h3FF6: begin
                        enable[block_info.id] <= cpu_bus.data & 8'h11;
                        if (cpu_bus.data[4]) begin
                            magicLo[block_info.id] <= 8'b0;
                            magicHi[block_info.id] <= 8'b0;
                        end
                    end
                    14'h3FF7:
                        bank[block_info.id] <= cpu_bus.data[1:0];
                    default: ; // No action
                endcase
            end
        end
    end

    // Memory addressing and control. Everything is in the window 4000-7FFF (openMSX fmpac.xml).
    // With the SRAM on: SRAM below 5FFE, 5FFE / 5FFF the magic, the rest FF (MSXFmPac::readMem).
    // Register reads give the register alone, no ROM byte (the CPU data is an AND of all sources).
    wire cs            = (block_info.typ == MAPPER_FMPAC) && cpu_bus.mreq && mapped;
    wire sramEnable    = {magicHi[block_info.id], magicLo[block_info.id]} == 16'h694D;
    wire sram_en       = sramEnable && cpu_bus.addr[13:0] < 14'h1FFE && cpu_bus.mreq && (cpu_bus.wr || cpu_bus.rd);
    wire reg_rd        = cpu_bus.addr[13:0] == 14'h3FF6 || cpu_bus.addr[13:0] == 14'h3FF7;
    wire [26:0] sram_addr = {14'b0, cpu_bus.addr[12:0]};
    wire [26:0] ram_addr  = {11'b0, bank[block_info.id], cpu_bus.addr[13:0]};

    // Mapper output signals
    assign out.sram_cs  = cs && sram_en;
    assign out.main_cs  = 1'b0;
    assign out.ram_cs   = cs && ~sramEnable && ~reg_rd && cpu_bus.rd;
    assign out.rnw      = ~(out.sram_cs && cpu_bus.wr);
    assign out.addr     = cs ? (out.sram_cs ? sram_addr : ram_addr) : {27{1'b1}};

    // any access to the block (all pages) keeps the OPLL port enable up to date (dev_opll)
    wire cs_block = (block_info.typ == MAPPER_FMPAC) && cpu_bus.mreq;
    assign device_out.we  = cs_block && opll_wr;
    assign device_out.en  = cs_block && enable[block_info.id][0];

    // Multiplexing output data
    assign out.data = cs ?
                      (cpu_bus.addr[13:0] == 14'h3FF6) ? enable[block_info.id] :
                      (cpu_bus.addr[13:0] == 14'h3FF7) ? {6'b000000, bank[block_info.id]} :
                      (cpu_bus.addr[13:0] == 14'h1FFE && sramEnable) ? magicLo[block_info.id] :
                      (cpu_bus.addr[13:0] == 14'h1FFF && sramEnable) ? magicHi[block_info.id] :
                      8'hFF : 8'hFF;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign device_out.device_ref = 3'd0;
    assign device_out.mode       = 1'b1;
    assign device_out.param      = 1'b1;

endmodule
