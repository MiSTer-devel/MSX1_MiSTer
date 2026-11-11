// Konami SCC/SCC+ mapper
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
    always_ff @(posedge cpu_bus.clk) begin
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
    wire [7:0] bank_reg;
    wire       is_ram_segment;
    assign {bank_reg, is_ram_segment} = (cpu_bus.addr[15:13] == 3'b010) ? {bank1[block_info.id], isRamSegment1[block_info.id]} :  // Bank 1 for 4000-5FFFh
                                         (cpu_bus.addr[15:13] == 3'b011) ? {bank2[block_info.id], isRamSegment2[block_info.id]} :  // Bank 2 for 6000-7FFFh
                                         (cpu_bus.addr[15:13] == 3'b100) ? {bank3[block_info.id], isRamSegment3[block_info.id]} :  // Bank 3 for 8000-9FFFh
                                                                           {bank4[block_info.id], isRamSegment4[block_info.id]} ;  // Bank 4 for A000-BFFFh

    // SCC+ 128 KB: 16 blocks, higher bank numbers mirror (openMSX subtype "expanded")
    wire [7:0] bank_base = sccType ? {4'b0, bank_reg[3:0]} : bank_reg;

    // Generate RAM address based on bank and lower address bits
    wire [26:0] ram_addr = {6'b0, bank_base, cpu_bus.addr[12:0]};

    // As openMSX MSXSCCPlusCart: memory is readable in every segment, the RAM mode controls
    // writes only. A write in a RAM segment goes to the RAM, not to the SCC or a bank register.
    wire ram_wr = cpu_bus.wr && is_ram_segment && ~sccModeRegAccess;
    wire oe     = cs && mapped && ((cpu_bus.rd && ~scc_area) || ram_wr);

    // Output assignments to the `out` interface
    assign out.addr   = oe ? ram_addr : {27{1'b1}};   // Output address, or '1 if not enabled
    assign out.ram_cs = oe;                           // RAM chip select signal
    assign out.rnw    = ~ram_wr;

    assign device_out.mode  = cs ? soundMode[block_info.id] : 1'b1;
    assign device_out.en    = cs && scc_area && ~(cpu_bus.wr && is_ram_segment);
    assign device_out.param = cs ? sccType : 1'b1;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;
    assign device_out.device_ref = 3'd0;
    assign device_out.we         = 1'b0;

endmodule
