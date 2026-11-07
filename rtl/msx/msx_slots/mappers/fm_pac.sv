// FM PAC mapper
//
// Copyright (c) 2024 Molekula
//
// All rights reserved
//
// Redistribution and use in source and synthezised forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
//   this list of conditions and the following disclaimer.
//
// * Redistributions in synthesized form must reproduce the above copyright
//   notice, this list of conditions and the following disclaimer in the
//   documentation and/or other materials provided with the distribution.
//
// * Neither the name of the author nor the names of other contributors may
//   be used to endorse or promote products derived from this software without
//   specific prior written agreement from the author.
//
// * License is granted for non-commercial use only.  A fee may not be charged
//   for redistributions as source code or in synthesized/hardware form without
//   specific prior written agreement from the author.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
// THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
// PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
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

    // Initial setup
    initial begin
        opll_wr  = 1'b0;
        enable   = '{default: 8'b0};
        bank     = '{default: 2'b0};
        magicLo  = '{default: 8'b0};
        magicHi  = '{default: 8'b0};
    end

    // Main control logic
    always @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Reset states
            enable  <= '{default: 8'b0};
            bank    <= '{default: 2'b0};
            magicLo <= '{default: 8'b0};
            magicHi <= '{default: 8'b0};
        end else begin
            opll_wr <= 1'b0;
            if (block_info.typ == MAPPER_FMPAC && cpu_bus.wr && cpu_bus.mreq && cpu_bus.req) begin
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

    // Memory addressing and control
    wire cs            = (block_info.typ == MAPPER_FMPAC) && cpu_bus.mreq;
    wire mapped        = cpu_bus.addr[15:14] == 2'b01;
    wire sramEnable    = {magicHi[block_info.id], magicLo[block_info.id]} == 16'h694D;
    wire sram_en       = sramEnable && cpu_bus.addr[13:0] < 14'h1FFE && cpu_bus.mreq && (cpu_bus.wr || cpu_bus.rd);
    wire [26:0] sram_addr = {14'b0, cpu_bus.addr[12:0]};
    wire [26:0] ram_addr  = {11'b0, bank[block_info.id], cpu_bus.addr[13:0]};

    // Mapper output signals
    assign out.sram_cs  = cs && sram_en;
    assign out.ram_cs   = cs && ~sram_en && cpu_bus.rd && mapped;
    assign out.rnw      = ~(out.sram_cs && cpu_bus.wr);
    assign out.addr     = cs ? (out.sram_cs ? sram_addr : ram_addr) : {27{1'b1}};

    assign device_out.we  = cs && opll_wr;
    assign device_out.en  = cs && enable[block_info.id][0];

    // Multiplexing output data
    assign out.data = (block_info.typ == MAPPER_FMPAC) ?
                      (cpu_bus.addr[13:0] == 14'h3FF6) ? enable[block_info.id] :
                      (cpu_bus.addr[13:0] == 14'h3FF7) ? {6'b000000, bank[block_info.id]} :
                      (cpu_bus.addr[13:0] == 14'h1FFE && sramEnable) ? magicLo[block_info.id] :
                      (cpu_bus.addr[13:0] == 14'h1FFF && sramEnable) ? magicHi[block_info.id] :
                      8'hFF : 8'hFF;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign device_out.device_ref = 3'd0;
    assign device_out.mode       = 1'b1;
    assign device_out.param      = 1'b1;
    assign device_out.data       = 8'hFF;

endmodule
