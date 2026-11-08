// ASCII8 mapper
//
// Copyright (c) 2024-2025 Molekula
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

module mapper_ascii8 (
    cpu_bus_if.device_mp    cpu_bus,
    output MSX::mapper_out_t out,
    input  MSX::block_info_t block_info
);

    wire cs, mapped, mode_wizardy, mode_koei, mapper_en;

    assign mapped       = ^cpu_bus.addr[15:14];

    assign mapper_en    = (block_info.typ == MAPPER_ASCII8) |
                          (block_info.typ == MAPPER_KOEI) |
                          (block_info.typ == MAPPER_WIZARDY);

    assign mode_wizardy = (block_info.typ == MAPPER_WIZARDY);
    assign mode_koei    = (block_info.typ == MAPPER_KOEI);

    assign cs           = mapped & mapper_en & cpu_bus.mreq;

    logic [7:0] bank[2][4];
    logic [7:0] sramBank[2][4];
    logic [7:0] sramEnable[2];

    wire        sram_exists   = (block_info.sram_size > 0);
    wire  [7:0] sram_mask     = (block_info.sram_size[10:3] > 0) ?
                                (block_info.sram_size[10:3] - 8'd1) : 8'd0;

    wire  [7:0] sramEnableBit = mode_wizardy ? 8'h80 : block_info.rom_size[20:13];
    wire  [7:0] sramPages     = mode_koei ? 8'h34 : 8'h30;
    wire  [1:0] region        = cpu_bus.addr[12:11];
    wire  [7:0] bank_base     = bank[block_info.id][{cpu_bus.addr[15], cpu_bus.addr[13]}];
    wire  [7:0] sram_bank_base = sramBank[block_info.id][{cpu_bus.addr[15], cpu_bus.addr[13]}];

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank       <= '{'{default: '0},'{default: '0}};
            sramBank   <= '{'{default: '0},'{default: '0}};
            sramEnable <= '{default: '0};
        end else if (cs & cpu_bus.wr & (cpu_bus.addr[15:13] == 3'b011) && cpu_bus.req) begin
            if (((cpu_bus.data & sramEnableBit) != 0) && sram_exists) begin
                sramEnable[block_info.id] <= sramEnable[block_info.id] |
                                        ((8'b00000100 << region) & sramPages);
                sramBank[block_info.id][region] <= cpu_bus.data & sram_mask;
            end else begin
                sramEnable[block_info.id] <= sramEnable[block_info.id] &
                                        ~(8'b00000100 << region);
                bank[block_info.id][region] <= cpu_bus.data;
            end
        end
    end

    wire        sram_en   = |((8'b00000001 << cpu_bus.addr[15:13]) & sramEnable[block_info.id]);
    wire [26:0] sram_addr = {6'b0, sram_bank_base, cpu_bus.addr[12:0]};
    wire [26:0] ram_addr  = {6'b0, bank_base, cpu_bus.addr[12:0]};
    wire        ram_valid = (out.addr < {2'b00, block_info.rom_size});

    wire sram_cs   = cs & sram_en & (cpu_bus.rd || cpu_bus.wr);
    wire ram_cs    = cs & ram_valid & ~sram_en & cpu_bus.rd;

    assign out.sram_cs = sram_cs;
    assign out.ram_cs  = ram_cs;
    assign out.rnw     = ~(sram_cs & cpu_bus.wr);
    assign out.addr    = cs ? (sram_en ? sram_addr : ram_addr) : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.data    = 8'hFF;

endmodule
