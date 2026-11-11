// Mega flash ROM SD mapper
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

module mapper_mfrsd0 (
    cpu_bus_if.device_mp    cpu_bus,         // Interface for CPU communication
    input  MSX::block_info_t block_info,      // Active block (slot layout entry)
    output MSX::mapper_out_t out,             // Mapper output, merged in mappers.sv
    input MSX::mfrsd_config_t config_reg
);

    wire cs = (block_info.typ == MAPPER_MFRSD0) && cpu_bus.mreq && config_reg.isSlotExpanderEnabled;

    wire [26:0] ram_addr  = {13'b0, cpu_bus.addr[13:0]};
    
    // Output assignments
    assign out.ram_cs = cs && cpu_bus.rd;  // RAM chip select signal

    // Calculate the address by adding the offset to the base address (only if chip select is active)
    assign out.addr   = cs ? ram_addr : {27{1'b1}};

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.rnw     = 1'b1;
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule

module mapper_mfrsd1 (
    cpu_bus_if.device_mp    cpu_bus,         // Interface for CPU communication
    flash_bus_if.device_mp  flash_bus,        // Interface to emulate FLASH
    input  MSX::block_info_t block_info,      // Active block (slot layout entry)
    output MSX::mapper_out_t out,             // Mapper output, merged in mappers.sv
    output MSX::device_bus_t device_out,      // Cartridge device control
    output MSX::mfrsd_config_t config_reg,
    input             [7:0] data_to_mapper
);

    logic [7:0] mapper_reg, scc_mode;
    logic [9:0] offset_reg;

    // Expander disabled: every access to the cartridge slot (any subslot type) goes to
    // subslot 1, as openMSX MegaFlashRomSCCPlusSD::getSubSlot(). Other slots are not ours.
    wire cart_slot = block_info.typ == MAPPER_MFRSD0 || block_info.typ == MAPPER_MFRSD1 ||
                     block_info.typ == MAPPER_MFRSD2 || block_info.typ == MAPPER_MFRSD3;
    wire cs = ((block_info.typ == MAPPER_MFRSD1) || (~config_reg.isSlotExpanderEnabled && cart_slot)) && cpu_bus.mreq;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            mapper_reg   <= 8'd0;
            offset_reg   <= 10'd0;
            scc_mode     <= 8'd0;
            config_reg.isConfigRegDisabled <= 1'b0;
            config_reg.isMemoryMapperEnabled <= 1'b1;
            config_reg.isDSKmodeEnabled <= 1'b0;
            config_reg.isPSGalsoMappedToNormalPorts <= 1'b0;
            config_reg.isSlotExpanderEnabled <= 1'b1;
            config_reg.isFlashRomBlockProtectEnabled <= 1'b1;
            config_reg.isFlashRomWriteEnabled <= 1'b1;
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.req) begin
                case(cpu_bus.addr)
                    16'h7FFC: begin
                        if (~config_reg.isConfigRegDisabled) begin
                            config_reg.isConfigRegDisabled <= cpu_bus.data[7];
                            config_reg.isMemoryMapperEnabled <= ~cpu_bus.data[5];
                            config_reg.isDSKmodeEnabled <= cpu_bus.data[4];
                            config_reg.isPSGalsoMappedToNormalPorts <= cpu_bus.data[3];
                            config_reg.isSlotExpanderEnabled <= ~cpu_bus.data[2];
                            config_reg.isFlashRomBlockProtectEnabled <= cpu_bus.data[1];
                            config_reg.isFlashRomWriteEnabled <= cpu_bus.data[0];
                        end
                    end
                    16'h7FFD : begin
                        if (~mapper_reg[1]) begin
                            offset_reg[7:0] <= cpu_bus.data;
                        end
                    end
                    16'h7FFE : begin
                        if (~mapper_reg[1]) begin
                            offset_reg[9:8] <= cpu_bus.data[1:0];
                        end
                    end
                    16'h7FFF : begin
                        if (~mapper_reg[2]) begin
                            mapper_reg <= cpu_bus.data;
                        end
                    end
                    16'hBFFE,
                    16'hBFFF: begin
                        if (mapper_reg[7:5] == 3'd0) begin  //Konami-SCC
                            scc_mode <= cpu_bus.data;
                        end
                    end
                    default:;
                endcase
            end
        end
    end


    logic [7:0] bank[4], scc_banks[4];

    wire [2:0] page8kB  = cpu_bus.addr[15:13] - 3'd2;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank      <= '{8'd0,8'd1,8'd2,8'd3};
            scc_banks <= '{8'd0,8'd1,8'd2,8'd3};
        end else begin
            if (~enable_wr_scc_plus) begin                         //Pazos: when SCC registers are selected flashROM is not seen, so it does not accept commands.
                if (cs && cpu_bus.wr && cpu_bus.req) begin
                    if (~mapper_reg[1] & page8kB < 3'd4) begin
                        case(mapper_reg[7:5])
                        3'b000: begin //KONAMI-SCC
                            if (cpu_bus.addr[12:11] == 2'b10) begin
                                scc_banks[page8kB[1:0]] <= cpu_bus.data;
                                bank[page8kB[1:0]]      <= mapper_reg[0] ? cpu_bus.data & 8'h3F : cpu_bus.data;
                            end
                        end
                        3'b001: begin //Konami
                            if (~(mapper_reg[3] & (cpu_bus.addr < 16'h6000))) begin
                                if (cpu_bus.addr[15:11] == 5'b01010 /*5000-57ff*/ | cpu_bus.addr[15:13] >= 3'b011 /*6000 - ffff*/) begin
                                    bank[page8kB[1:0]] <= mapper_reg[0] ? cpu_bus.data & 8'h1F : cpu_bus.data;
                                end
                            end
                        end

                        3'b010,
                        3'b011: begin//64kB
                            bank[page8kB[1:0]] <= cpu_bus.data;
                        end

                        3'b100,
                        3'b101: begin //Ascii8
                            if (cpu_bus.addr[15:13] == 3'b011 /*6000 - 7fff*/) begin
                                bank[cpu_bus.addr[13:12]] <= cpu_bus.data;
                            end
                        end

                        3'b110,
                        3'b111: begin //Acii16
                            if (cpu_bus.addr[15:11] == 5'b01100) begin
                                bank[0] <= {cpu_bus.data[6:0],1'b0};
                                bank[1] <= {cpu_bus.data[6:0],1'b1};
                            end
                            if (cpu_bus.addr[15:11] == 5'b01110) begin
                                bank[2] <= {cpu_bus.data[6:0],1'b0};
                                bank[3] <= {cpu_bus.data[6:0],1'b1};
                            end
                        end
                        default: ;
                        endcase
                    end
                end
            end
        end
    end

    wire is_konami_scc                    = mapper_reg[7:5] == 3'b000;
    wire is_ram_segment2                  = (scc_mode[5] & scc_mode[2]) | scc_mode[4];
    wire is_ram_segment3                  = scc_mode[4];

    wire area_scc_plus_mode_scc_plus      = scc_mode[5] == 1'b1 && scc_banks[3][7]   == 1'b1      && cpu_bus.addr[15:8]  == 8'hB8;    //SCC+ mode SCC+
    wire area_scc_plus_mode_scc           = scc_mode[5] == 1'b0 && scc_banks[2][5:0] == 6'b111111 && cpu_bus.addr[15:11] == 5'b10011; //SCC+ mode SCC

    wire enable_wr_scc_plus_mode_scc_plus = area_scc_plus_mode_scc_plus && ~is_ram_segment2;
    wire enable_wr_scc_plus_mode_scc      = area_scc_plus_mode_scc      && ~is_ram_segment3;

    wire enable_wr_scc_plus               = is_konami_scc && cpu_bus.wr && (enable_wr_scc_plus_mode_scc_plus || enable_wr_scc_plus_mode_scc);
    wire enable_rd_scc_plus               = is_konami_scc && cpu_bus.rd && (area_scc_plus_mode_scc_plus || area_scc_plus_mode_scc);

    wire  [2:0] page                      = mapper_reg[7:6] == 2'b01 ? 3'(cpu_bus.addr[15:14]) : cpu_bus.addr[15:13] - 3'd2;

    wire flash_area                       = page < 3'd4;

    wire [15:0] actual_bank               = config_reg.isDSKmodeEnabled && page[1:0] == 2'b00 && bank[page[1:0]] == 8'd0 ? 16'h3FA :
                                            config_reg.isDSKmodeEnabled && page[1:0] == 2'b01 && bank[page[1:0]] == 8'd1 ? 16'h3FB :
                                                                                                                           16'(bank[page[1:0]]) + 16'(offset_reg);

    wire [29:0] ram_addr                  = mapper_reg[7:6] == 2'b01 ? {actual_bank, cpu_bus.addr[13:0]} : {1'b0, actual_bank, cpu_bus.addr[12:0]};

    wire flash_we                         = config_reg.isFlashRomWriteEnabled;
    wire flash_wr                         = ~enable_wr_scc_plus && cs && cpu_bus.wr && flash_area && flash_we;
    wire flash_rd                         = ~enable_rd_scc_plus && cs && cpu_bus.rd && flash_area;
    wire flash_ce                         = flash_rd || flash_wr;

    assign device_out.mode                = cs ? scc_mode[5] : 1'b1;
    assign device_out.en                  = cs && (enable_wr_scc_plus || enable_rd_scc_plus);
    assign device_out.param               = 1'b1;

    assign flash_bus.ce                   = flash_ce;
    assign flash_bus.we                   = flash_wr;
    assign flash_bus.data_to_flash        = flash_ce ? cpu_bus.data : '0;
    assign flash_bus.addr                 = flash_ce ? 23'h10000 + ram_addr[22:0] : '0;
    assign flash_bus.base_addr            = flash_ce ? 27'h10000 - block_info.base_ram : '0;
    assign flash_bus.area_lo              = flash_ce ? 23'h10000 : '0;
    assign flash_bus.area_size            = flash_ce ? block_info.rom_size[23:0] : '0;
    assign flash_bus.chip                 = 1'b0;
    assign flash_bus.id                   = 1'b0;

    wire ram_oe                           = flash_area && cs && ~enable_rd_scc_plus && cpu_bus.rd && ~flash_bus.data_valid;

    assign out.addr                       = ram_oe ? ram_addr[26:0] : {27{1'b1}};   // Output address, or '1 if not enabled
    assign out.ram_cs                     = ram_oe;                           // RAM chip select signal
    assign out.rnw                        = 1'b1;

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.data    = 8'hFF;   // flash read data comes from mfrsd3 (shared data_valid)
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign device_out.device_ref = 3'd0;
    assign device_out.we         = 1'b0;

endmodule

module mapper_mfrsd2 (
    cpu_bus_if.device_mp    cpu_bus,         // Interface for CPU communication
    input  MSX::block_info_t block_info,      // Active block (slot layout entry)
    output MSX::mapper_out_t out,             // Mapper output, merged in mappers.sv
    input MSX::mfrsd_config_t config_reg,
    input             [7:0] data_to_mapper
);

    wire cs = (block_info.typ == MAPPER_MFRSD2) && cpu_bus.mreq && config_reg.isMemoryMapperEnabled && config_reg.isSlotExpanderEnabled;

    // Output assignments
    assign out.ram_cs = cs && (cpu_bus.rd || cpu_bus.wr);  // RAM chip select signal

    // Calculate the address by adding the offset to the base address (only if chip select is active)
    assign out.addr = cs ? {5'b0, data_to_mapper, cpu_bus.addr[13:0]} : {27{1'b1}};

    // Generate the Read/Not Write (rnw) signal based on the chip select and write signal
    assign out.rnw = ~(cs & cpu_bus.wr);

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;
    assign out.data    = 8'hFF;

endmodule

module mapper_mfrsd3 (
    cpu_bus_if.device_mp        cpu_bus,          // Interface for CPU communication
    ext_sd_card_if.device_mp    ext_SD_card_bus,  // Interface Ext SD card
    flash_bus_if.device_mp      flash_bus,        // Interface to emulate FLASH
    output MSX::mapper_out_t out,              // Mapper output, merged in mappers.sv
    input MSX::mfrsd_config_t   config_reg,
    input  MSX::block_info_t block_info        // Active block (slot layout entry)
);

    wire cs, mapped, mapper_en, sd_card_access;

    // Mapped if address is not in the lower or upper 16KB
    assign mapped       = ^cpu_bus.addr[15:14];

    // Mapper is enabled if it is MFRSD3
    assign mapper_en    = (block_info.typ == MAPPER_MFRSD3) && cpu_bus.mreq  && config_reg.isSlotExpanderEnabled;

    // Chip select is valid if address is mapped and mapper is enabled
    assign cs           = mapped && mapper_en;

    // SD card enable and adress in area
    assign sd_card_access = bank[0][7:6] == 2'b01 && cpu_bus.addr[15:13] == 3'b010; // 4000 - 5FFF

    logic [7:0] bank[4];
    logic       selected_sd;

    always_ff @(posedge cpu_bus.clk) begin
        if (cpu_bus.reset) begin
            bank <= '{8'd0, 8'd1, 8'd0, 8'd0};
        end else begin
            if (cs && cpu_bus.wr && cpu_bus.addr[15:13] == 3'b011 && cpu_bus.req) begin // 6000 - 7fff
                bank[cpu_bus.addr[12:11]] <= cpu_bus.data;
            end
        end
    end


    always_ff @(posedge cpu_bus.clk) begin

        ext_SD_card_bus.rx <= 1'b0;
        ext_SD_card_bus.tx <= 1'b0;
        ext_SD_card_bus.data_to_SD <= '1;

        if (cpu_bus.reset) begin
            selected_sd <= 1'b0;
        end else begin
            if (sd_card_access && mapper_en && cpu_bus.req) begin           // RD/RW SD card access
                if (cpu_bus.wr) begin
                    if (cpu_bus.addr[15:11] == 5'b01011) begin // addr >= 0x5800
                        selected_sd <= cpu_bus.data[0];
                    end else begin
                        ext_SD_card_bus.tx         <= ~selected_sd & ~cpu_bus.addr[12];
                        ext_SD_card_bus.data_to_SD <= cpu_bus.data;
                    end
                end
                if (cpu_bus.rd) begin
                    ext_SD_card_bus.rx <= ~selected_sd & ~cpu_bus.addr[12];
                end
            end
        end
    end

    wire  [7:0] bank_base = bank[{cpu_bus.addr[15], cpu_bus.addr[13]}];
    wire [26:0] ram_addr  = {7'b0, bank_base[6:0], cpu_bus.addr[12:0]};
    wire ram_read     = cs && ~sd_card_access && cpu_bus.rd;

    wire flash_area       = (cpu_bus.addr[15:14] == 2'b01 || cpu_bus.addr[15:14] == 2'b10);
    wire flash_wr         = mapper_en && cpu_bus.wr && flash_area && config_reg.isFlashRomWriteEnabled;
    wire flash_ce         = ram_read || flash_wr;

    wire ram_cs       = ram_read && ~flash_bus.data_valid;

    wire sd_card_read = sd_card_access && mapper_en && cpu_bus.rd;

    assign out.ram_cs              = ram_cs;
    assign out.rnw                 = 1'b1;
    assign out.addr                = ram_cs ? ram_addr : {27{1'b1}};

    assign flash_bus.ce            = flash_ce;
    assign flash_bus.we            = flash_wr;
    assign flash_bus.data_to_flash = flash_ce ? cpu_bus.data : '0;
    assign flash_bus.addr          = flash_ce ? 23'h700000 + ram_addr[22:0] : '0;
    assign flash_bus.base_addr     = flash_ce ? 27'h700000 - block_info.base_ram : '0;
    assign flash_bus.area_lo       = flash_ce ? 23'h700000 : '0;
    assign flash_bus.area_size     = flash_ce ? block_info.rom_size[23:0] : '0;
    assign flash_bus.chip          = 1'b0;
    assign flash_bus.id            = 1'b0;

    assign out.data                = sd_card_read         ? ext_SD_card_bus.data_from_SD :
                                     flash_bus.data_valid ? flash_bus.data_from_flash    :
                                                            8'hFF                        ;




    /*
    4
    01xx 4-7
    10xx 8-B
    4000 - BFFF
    flash_we
*/
    /*
    // write to flash (first, before modifying bank regs)
	if ((0x4000 <= addr) && (addr < 0xC000)) {
		unsigned flashAddr = getFlashAddrSubSlot3(addr);
		writeToFlash(flashAddr, value, time);
	}
    */

    // outputs not used by this mapper: neutral for the merge in mappers.sv
    assign out.sram_cs = 1'b0;
    assign out.main_cs = 1'b0;

endmodule



module mapper_mfrsd (
    cpu_bus_if.device_mp        cpu_bus,          // Interface for CPU communication
    input  MSX::block_info_t block_info,       // Active block (slot layout entry)
    ext_sd_card_if.device_mp    ext_SD_card_bus,  // Interface Ext SD card
    flash_bus_if.device_mp      flash_bus,        // Interface to emulate FLASH
    output MSX::mapper_out_t out,              // Mapper output, merged in mappers.sv
    output MSX::device_bus_t device_out,
    input                 [7:0] data_to_mapper, 
    output                      slot_expander_force_en,
    output                      expander_off      // register: all of the slot is subslot 1
);

    MSX::mfrsd_config_t config_reg;
    MSX::mapper_out_t sub_out[4];      // index = MFRSD subslot
    flash_bus_if flash_bus_mfrsd1();
    flash_bus_if flash_bus_mfrsd3();

    
    wire mfrds_cs = cpu_bus.mreq && (block_info.typ == MAPPER_MFRSD0 || block_info.typ == MAPPER_MFRSD1 || block_info.typ == MAPPER_MFRSD2 || block_info.typ == MAPPER_MFRSD3);
    
    assign slot_expander_force_en = config_reg.isSlotExpanderEnabled && mfrds_cs;
    assign expander_off           = ~config_reg.isSlotExpanderEnabled;

    always_comb begin
        out = MSX::MAPPER_OUT_IDLE;
        for (int i = 0; i < 4; i++)
            out = MSX::mapper_out_merge(out, sub_out[i]);
    end

    assign flash_bus.base_addr = flash_bus_mfrsd1.base_addr
                               | flash_bus_mfrsd3.base_addr;

    assign flash_bus.addr          = flash_bus_mfrsd1.addr
                                   | flash_bus_mfrsd3.addr;

    assign flash_bus.area_lo       = flash_bus_mfrsd1.area_lo
                                   | flash_bus_mfrsd3.area_lo;

    assign flash_bus.area_size     = flash_bus_mfrsd1.area_size
                                   | flash_bus_mfrsd3.area_size;

    assign flash_bus.chip          = 1'b0;
    assign flash_bus.id            = 1'b0;

    assign flash_bus.data_to_flash = flash_bus_mfrsd1.data_to_flash
                                   | flash_bus_mfrsd3.data_to_flash;

    assign flash_bus.we            = flash_bus_mfrsd1.we
                                   | flash_bus_mfrsd3.we;

    assign flash_bus.ce            = flash_bus_mfrsd1.ce
                                   | flash_bus_mfrsd3.ce;



    assign flash_bus_mfrsd1.data_from_flash = flash_bus.data_from_flash;
    assign flash_bus_mfrsd3.data_from_flash = flash_bus.data_from_flash;

    assign flash_bus_mfrsd1.data_valid = flash_bus.data_valid;
    assign flash_bus_mfrsd3.data_valid = flash_bus.data_valid;
    //mfrsd1_device_out en, mode, param


    // Instantiate the MFRSD3 mapper
    mapper_mfrsd3  mapper_mfrsd3 (
        .cpu_bus(cpu_bus),
        .ext_SD_card_bus(ext_SD_card_bus),
        .flash_bus(flash_bus_mfrsd3),
        .block_info(block_info),
        .out(sub_out[3]),
        .config_reg(config_reg)
    );

    // Instantiate the MFRSD2 RAM mapper
    mapper_mfrsd2 mapper_mfrsd2 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(sub_out[2]),
        .config_reg(config_reg),
        .data_to_mapper(data_to_mapper)
    );

    // Instantiate the MFRSD1 RAM mapper
    mapper_mfrsd1 mapper_mfrsd1 (
        .cpu_bus(cpu_bus),
        .flash_bus(flash_bus_mfrsd1),
        .block_info(block_info),
        .out(sub_out[1]),
        .device_out(device_out),
        .config_reg(config_reg),
        .data_to_mapper(data_to_mapper)
    );

    mapper_mfrsd0 mapper_mfrsd0 (
        .cpu_bus(cpu_bus),
        .block_info(block_info),
        .out(sub_out[0]),
        .config_reg(config_reg)
    );

endmodule