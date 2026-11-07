// Mirror mapper
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

module mapper_mirror (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out
);

    wire cs = (block_info.typ == MAPPER_MIRROR) && cpu_bus.mreq && (cpu_bus.rd || cpu_bus.wr);

    // 8 KB blocks covering rom_size[15:0] (ceil); 64 KB wraps to 0
    wire  [3:0] block_count = {1'b0, block_info.rom_size[15:13]} + 4'(|block_info.rom_size[12:0]);

    // prefix = (page + 2*offset_ram) % block_count, as constant tables indexed by
    // {offset_ram, page}: pure LUT logic (Quartus builds a divider even for % const).
    // Entry i at bits [3*i +: 3]. Generated: ((i & 7) + 2*(i >> 3)) % n.
    localparam logic [95:0] MOD2 = 96'h208208208208208208208208;
    localparam logic [95:0] MOD3 = 96'h211088442211088442211088;
    localparam logic [95:0] MOD4 = 96'h21A21A68868821A21A688688;
    localparam logic [95:0] MOD5 = 96'h6888D12234448D111A444688;
    localparam logic [95:0] MOD6 = 96'h22C688B1A22C688B1A22C688;
    localparam logic [95:0] MOD7 = 96'hD634468D11AC446B1A1AC688;
    localparam logic [95:0] MOD8 = 96'hB1A23E688FAC23EB1AFAC688;

    wire  [4:0] idx = {block_info.offset_ram, cpu_bus.addr[15:13]};

    // block_count 0 (64 KB) behaves as 8 (identity); original % 0 was undefined.
    logic [2:0]  prefix;
    always_comb begin
        case (block_count)
            4'd1:    prefix = 3'd0;
            4'd2:    prefix = MOD2[3*idx +: 3];
            4'd3:    prefix = MOD3[3*idx +: 3];
            4'd4:    prefix = MOD4[3*idx +: 3];
            4'd5:    prefix = MOD5[3*idx +: 3];
            4'd6:    prefix = MOD6[3*idx +: 3];
            4'd7:    prefix = MOD7[3*idx +: 3];
            default: prefix = MOD8[3*idx +: 3];
        endcase
    end

    logic [15:0] ram_addr;
    assign ram_addr = {prefix, cpu_bus.addr[12:0]};

    assign out.ram_cs = cs;
    assign out.addr   = cs ? {11'b0, ram_addr} : {27{1'b1}};
    assign out.rnw    = ~(cs && cpu_bus.wr);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
