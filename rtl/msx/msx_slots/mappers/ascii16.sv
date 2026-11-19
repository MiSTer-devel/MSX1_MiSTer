// ASCII16 mapper
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

module mapper_ascii16 (
    cpu_bus_if.device_mp    cpu_bus,
    input  MSX::block_info_t block_info,
    output MSX::mapper_out_t out
);

    logic cs, mapped, sram_exists, sram_en;
    logic [26:0] sram_addr;
    logic [26:0] ram_addr;
    logic [26:0] rom_size;

    logic ram_valid, sram_cs, ram_cs;
    
    assign mapped = cpu_bus.addr[15] ^ cpu_bus.addr[14]; // 0000-3fff & c000-ffff unmaped
    assign sram_exists = (block_info.sram_size > 0);
    assign rom_size = {2'b00, block_info.rom_size};

    assign cs = ( 
            block_info.typ == MAPPER_SUPERSWANGI
         || block_info.typ == MAPPER_ASCII16
         || block_info.typ == MAPPER_RTYPE
         || block_info.typ == MAPPER_MSXWRITE
                ) && mapped && cpu_bus.mreq;
             
    
    logic [7:0] bank[2][2];
    logic [1:0] sramEnable[2];
    // 16 KB blocks, the image padded up (openMSX RomBlocks); a bank past the end wraps:
    // block < blocks ? block : block & (blocks - 1) (setRom)
    logic [11:0] nrBlocks, blockMask;
    assign nrBlocks  = {1'b0, rom_size[24:14]} + {11'd0, |rom_size[13:0]};
    assign blockMask = nrBlocks - 12'd1;

    function automatic logic [7:0] wrap(input logic [7:0] v);
        logic [11:0] m;
        m = blockMask;
        return {4'd0, v} < nrBlocks ? v : v & m[7:0];
    endfunction
    
    logic match_mapper,bank_id, sram_bank_cs;
    logic [7:0] bank_data;
    logic [7:0] bank_base;

    always_comb begin
        sram_bank_cs = 0;
        case (block_info.typ)
            MAPPER_ASCII16:  begin 
                match_mapper = (cpu_bus.addr[15:11] == 5'b01100) || (cpu_bus.addr[15:11] == 5'b01110);
                bank_data = wrap(cpu_bus.data);
                bank_id = cpu_bus.addr[12];
                bank_base = bank[block_info.id][cpu_bus.addr[15]];
                sram_bank_cs = cpu_bus.data == 8'h10 && sram_exists;
            end
            MAPPER_RTYPE:    begin 
                // openMSX RomRType: page 2 switched by a write to 4000-7FFF, page 1 fixed at 17h
                match_mapper = (cpu_bus.addr[15:14] == 2'b01);
                bank_data = wrap(cpu_bus.data & (cpu_bus.data[4] ? 8'h17 : 8'h1F));
                bank_id = 1'b1;
                bank_base = cpu_bus.addr[15] ? bank[block_info.id][1] : wrap(8'h17);
            end
            MAPPER_MSXWRITE: begin 
                match_mapper = (cpu_bus.addr[15:11] == 5'b01100) || (cpu_bus.addr[15:11] == 5'b01110) || (cpu_bus.addr == 16'h6FFF) || (cpu_bus.addr == 16'h7FFF);
                bank_data = wrap(cpu_bus.data);
                bank_id = cpu_bus.addr[12];
                bank_base = bank[block_info.id][cpu_bus.addr[15]];
            end
            MAPPER_SUPERSWANGI: begin 
                match_mapper = (cpu_bus.addr == 16'h8000);
                bank_data = wrap({1'b0, cpu_bus.data[7:1]});
                bank_id = 1'b1;
                bank_base = bank[block_info.id][cpu_bus.addr[15]];
            end
            default:         begin 
                match_mapper = 1'b0;
                bank_id = 1'b0;
                bank_base = bank[block_info.id][cpu_bus.addr[15]];
                bank_data = cpu_bus.data;
            end
        endcase
    end

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank[0]      <= '{8'h00, 8'h00};
            bank[1]      <= '{8'h00, 8'h00};
            sramEnable   <= '{2'b00, 2'b00};
        end else if (cs && cpu_bus.wr && cpu_bus.req) begin
            if (match_mapper) begin
                if (sram_bank_cs)
                    sramEnable[block_info.id][bank_id] <= 1'b1;
                else begin
                    sramEnable[block_info.id][bank_id] <= 1'b0;
                    bank[block_info.id][bank_id] <= bank_data;
                end
            end
        end
    end

    assign sram_en   = sramEnable[block_info.id][cpu_bus.addr[15]];

    assign sram_addr = {block_info.sram_size > 16'd2 ?
                           {14'd0, cpu_bus.addr[12:0]} :
                           {16'd0, cpu_bus.addr[10:0]}};

    assign ram_addr  = {5'b0, bank_base, cpu_bus.addr[13:0]};

    assign ram_valid = (ram_addr < rom_size);

    assign sram_cs = cs && sram_en && (cpu_bus.rd || cpu_bus.wr);
    assign ram_cs  = cs && ram_valid && ~sram_en && cpu_bus.rd;

    assign out.sram_cs = sram_cs;
    assign out.main_cs = 1'b0;
    assign out.ram_cs  = ram_cs;
    assign out.rnw     = ~(sram_cs && cpu_bus.wr && cpu_bus.addr[15]);
    assign out.addr    = cs ? (sram_en ? sram_addr : ram_addr) : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.data    = 8'hFF;

endmodule
