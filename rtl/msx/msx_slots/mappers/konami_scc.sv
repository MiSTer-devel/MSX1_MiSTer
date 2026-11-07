// Konami SCC/SCC+ mapper
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

module mapper_konami_scc (
   cpu_bus_if.device_mp     cpu_bus,        // Interface for CPU communication
   output MSX::mapper_out_t out,            // Mapper output, merged in mappers.sv
   input  MSX::block_info_t block_info,     // Active block (slot layout entry) 
   output MSX::device_bus_t device_out      // Cartridge device control
);

    // Control signals for memory mapping
    wire cs, mapped, sccType, sccModeRegAccess;

    // Mapper is enabled if type is KONAMI_SCC and there is a memory request (mreq)
    assign cs = (block_info.typ == MAPPER_KONAMI_SCC || block_info.typ == MAPPER_KONAMI_SCC_PLUS) && cpu_bus.mreq;
    assign sccType = block_info.typ == MAPPER_KONAMI_SCC_PLUS;

    // Address is mapped if it is between 0x4000 and 0xBFFF and within ROM size
    assign mapped = (cpu_bus.addr >= 16'h4000) && (cpu_bus.addr < 16'hC000) && (ram_addr < {2'b0, block_info.rom_size});


    assign sccModeRegAccess = {cpu_bus.addr[15:1],1'b0} == 16'hBFFE && sccType == 1'b1;

    // Bank registers for switching between memory banks
    logic [7:0] bank1[2];       // Bank 1 for address range 0x4000-0x5FFF
    logic [7:0] bank2[2];       // Bank 2 for address range 0x6000-0x7FFF
    logic [7:0] bank3[2];       // Bank 3 for address range 0x8000-0x9FFF
    logic [7:0] bank4[2];       // Bank 4 for address range 0xA000-0xBFFF
    logic [1:0] isRamSegment1;  // ramSegment 1
    logic [1:0] isRamSegment2;  // ramSegment 2
    logic [1:0] isRamSegment3;  // ramSegment 3
    logic [1:0] isRamSegment4;  // ramSegment 4
    logic [1:0] soundMode;      // sound mode for SCC+
    logic [1:0] sccEnable;      // SCC enable flag for each bank

    // Bank switching logic: On reset, set default bank values. On write, update bank values.
    always @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            // Reset bank registers and disable SCC
            bank1         <= '{'h00, 'h00}; // Default bank 1 values
            bank2         <= '{'h01, 'h01}; // Default bank 2 values
            bank3         <= '{'h02, 'h02}; // Default bank 3 values
            bank4         <= '{'h03, 'h03}; // Default bank 4 values
            isRamSegment1 <= 2'b00;         // Default ramSegment 1 values
            isRamSegment2 <= 2'b00;         // Default ramSegment 2 values
            isRamSegment3 <= 2'b00;         // Default ramSegment 3 values
            isRamSegment4 <= 2'b00;         // Default ramSegment 4 values
            soundMode     <= 2'b00;         // Default sound mode for SCC+
            sccEnable <= 2'b00;             // Disable SCC initially
        end else if (cs && cpu_bus.wr && cpu_bus.req ) begin
            // Write to the bank registers based on address ranges
            case (cpu_bus.addr[15:11])
                5'b01010:                                                                           // 5000-57FFh -> Bank 1
                    if (isRamSegment1[block_info.id] == 1'b0) bank1[block_info.id] <= cpu_bus.data;
                5'b01110:                                                                           // 7000-77FFh -> Bank 2
                    if (isRamSegment2[block_info.id] == 1'b0) bank2[block_info.id] <= cpu_bus.data;
                5'b10010: begin                                                                     // 9000-97FFh -> Bank 3
                    if (isRamSegment3[block_info.id] == 1'b0) bank3[block_info.id] <= cpu_bus.data;
                    if (sccType == 1'b0) sccEnable[block_info.id] <= (cpu_bus.data[5:0] == 6'h3F);  // Enable SCC if the data matches the specific SCC enable value (0x3F)
                end
                5'b10110:                                                                           // B000-B7FFh -> Bank 4
                    if (isRamSegment4[block_info.id] == 1'b0) bank4[block_info.id] <= cpu_bus.data;
                default: ;
            endcase
            if (sccModeRegAccess) begin
                isRamSegment1[block_info.id] <= cpu_bus.data[4] | cpu_bus.data[0];
                isRamSegment2[block_info.id] <= cpu_bus.data[4] | cpu_bus.data[1];
                isRamSegment3[block_info.id] <= cpu_bus.data[4] | (cpu_bus.data[2] & cpu_bus.data[5]);
                isRamSegment4[block_info.id] <= cpu_bus.data[4];
                soundMode[block_info.id]     <= cpu_bus.data[5];
            end
        end
    end
    
    wire area_scc_plus_mode_scc_plus = sccType == 1'b1 && soundMode[block_info.id] == 1'b1 && bank4[block_info.id][7]   == 1'b1      && cpu_bus.addr[15:8]  == 8'hB8;    //SCC+ mode SCC+
    wire area_scc_plus_mode_scc      = sccType == 1'b1 && soundMode[block_info.id] == 1'b0 && bank3[block_info.id][5:0] == 6'b111111 && cpu_bus.addr[15:11] == 5'b10011; //SCC+ mode SCC
    wire area_scc_mode               = sccType == 1'b0 && sccEnable[block_info.id]                                                   && cpu_bus.addr[15:11] == 5'b10011; //SCC
    wire scc_area                    = area_scc_plus_mode_scc_plus || area_scc_plus_mode_scc || area_scc_mode;
    
    // Bank selection logic based on the current address range
    wire [7:0] bank_base;
    wire       is_ram_segment;
    assign {bank_base, is_ram_segment} = (cpu_bus.addr[15:13] == 3'b010) ? {bank1[block_info.id], isRamSegment1[block_info.id]} :  // Bank 1 for 4000-5FFFh
                                         (cpu_bus.addr[15:13] == 3'b011) ? {bank2[block_info.id], isRamSegment2[block_info.id]} :  // Bank 2 for 6000-7FFFh
                                         (cpu_bus.addr[15:13] == 3'b100) ? {bank3[block_info.id], isRamSegment3[block_info.id]} :  // Bank 3 for 8000-9FFFh
                                                                           {bank4[block_info.id], isRamSegment4[block_info.id]} ;  // Bank 4 for A000-BFFFh

    // Generate RAM address based on bank and lower address bits
    wire [26:0] ram_addr = {6'b0, bank_base, cpu_bus.addr[12:0]};

    // Output enable signal: active only if address is mapped and not in SCC area
    wire oe = cs && mapped && ~scc_area && (is_ram_segment || sccType == 1'b0) && (cpu_bus.rd || cpu_bus.wr);

    // Output assignments to the `out` interface
    assign out.addr   = oe ? ram_addr : {27{1'b1}};   // Output address, or '1 if not enabled
    assign out.ram_cs = oe;                           // RAM chip select signal
    assign out.rnw    = ~(cpu_bus.wr && is_ram_segment && ~sccModeRegAccess);

    assign device_out.mode  = cs ? soundMode[block_info.id] : 1'b1;
    assign device_out.en    = cs && scc_area;
    assign device_out.param = cs ? sccType : 1'b1;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.data    = 8'hFF;
    assign device_out.device_ref = 3'd0;
    assign device_out.we         = 1'b0;
    assign device_out.data       = 8'hFF;

endmodule
