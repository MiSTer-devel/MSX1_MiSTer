// OCM IPL ROM
//
// Copyright (c) 2026 Molekula
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

// IPL ROM of OCM (slot 3-3): visible only before the OCM-BIOS is loaded, i.e. from
// reset until the first write to PPI port A8h (ipl_en from dev_ocm, OCM ff_ldbios_n).
module mapper_ocm_ipl (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,
    input                   ipl_en,
    output MSX::mapper_out_t out
);
    wire        cs       = block_info.typ == MAPPER_OCM_IPL && ipl_en && cpu_bus.mreq && cpu_bus.rd;
    wire [26:0] ram_addr = {11'b0, block_info.offset_ram, cpu_bus.addr[13:0]};
    wire        ram_cs   = cs && ram_addr < {2'b00, block_info.rom_size};

    assign out.ram_cs  = ram_cs;
    assign out.addr    = ram_cs ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule
