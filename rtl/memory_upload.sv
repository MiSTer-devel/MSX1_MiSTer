// memory_upload
//
// Copyright (c) 2023-2026 Molekula
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

module memory_upload
(
    input                       clk,
    output                      upload,
    input                       ioctl_download,
    input                [15:0] ioctl_index,
    input                [26:0] ioctl_addr,
    input                       rom_eject,
    input                       reload,
    output logic         [27:0] ddr3_addr,
    output logic                ddr3_rd,
    input                 [7:0] ddr3_dout,
    input                       ddr3_ready,
    output                      ddr3_request,
    memory_bus_if.device_mp     memory_bus,
    output MSX::kb_memory_t     kb_upload_memory,
    output MSX::slot_expander_t slot_expander[4],
    output MSX::block_t         slot_layout[64],
    output MSX::lookup_RAM_t    lookup_RAM[16],
    output MSX::lookup_SRAM_t   lookup_SRAM[4],
    output MSX::main_ram_t      main_ram,           // turbo R: block with mapper PANASONIC_RAM
    input  MSX::config_cart_t   cart_conf[2],
    output MSX::io_device_t     io_device[32][3],
    output MSX::io_device_mem_ref_t io_memory[8],
    output MSX::msx_config_t    msx_config,

    output logic                load_sram,
    output error_t              error,
    output logic                reset
);

    typedef enum logic [2:0] { size_MSX_PACK, size_FW_PACK, size_ROM_A, size_ROM_B, size_CRC } size_idx_t;

    // Parametry
    localparam DDR3_BASE_FW_ADDR = 28'h300000;
    localparam DDR3_CRC32_TABLE_ADDR = 28'h1600000;
    localparam logic [2:0] CONF_SIZE = 7;           // Conf block size for computer 8 bytes - 1 byte

    // Stavový signál, který indikuje, že jsem v režimu upload. Resetujeme core a RAM přístup pro UPLOAD
    assign upload = state != STATE_IDLE;

    // Řízení načítání dat
    logic [26:0] ioctl_size[5] = '{default: 27'd0};
    logic        load = 1'b0;

    always_ff @(posedge clk) begin
        logic ioctl_download_last;
        load <= 1'b0;
        if (~ioctl_download & ioctl_download_last) begin
            case (ioctl_index[5:0])
                6'd1: begin ioctl_size[size_MSX_PACK] <= ioctl_addr; load <= 1'b1; end  // MSX PACK
                6'd2: begin ioctl_size[size_FW_PACK] <= ioctl_addr; load <= 1'b1; end  // FW PACK
                6'd3: begin ioctl_size[size_ROM_A] <= ioctl_addr; load <= 1'b1; end  // ROM A
                6'd4: begin ioctl_size[size_ROM_B] <= ioctl_addr; load <= 1'b1; end  // ROM B
                6'd6: begin ioctl_size[size_CRC] <= ioctl_addr; end                // Další případy
                default: ;
            endcase
        end

        // Vynulování velikostí ROM při vysunutí
        if (rom_eject) begin
            ioctl_size[size_ROM_A] <= 27'd0;
            ioctl_size[size_ROM_B] <= 27'd0;
            load <= 1'b1;
        end

        // Obnovovací signál pro načtení
        if (reload) load <= 1'b1;

        ioctl_download_last <= ioctl_download;
    end

    // Pomocník pro vyplňování RAM
    typedef enum logic [2:0] {
        PATTERN_DDR,
        PATTERN_FF,
        PATTERN_ZERO,
        PATTERN_03,
        PATTERN_04,
        PATTERN_05
    } pattern_t;

    wire [8:0] fill_poss = 9'(ram_addr - lookup_RAM[ref_ram].addr);

    // Vstupní data RAM jsou vybírána podle vzoru
    assign memory_bus.data    = (pattern == PATTERN_DDR)  ? ddr3_dout :
                     (pattern == PATTERN_FF)   ? 8'hFF     :
                     (pattern == PATTERN_ZERO) ? 8'h00     :
                     (pattern == PATTERN_03)   ? ((fill_poss[8]) ? ((fill_poss[1]) ? 8'hff : 8'h00) : ((fill_poss[1]) ? 8'h00 : 8'hff)) :
                     (pattern == PATTERN_04)   ? ((fill_poss[8]) ? ((fill_poss[0]) ? 8'h00 : 8'hff) : ((fill_poss[0]) ? 8'hff : 8'h00)) :
                     (pattern == PATTERN_05)   ? ((fill_poss[7]) ? 8'hff : 8'h00) : 8'hFF;
    assign memory_bus.addr    = ram_addr;
    assign memory_bus.ram_cs  = ram_ce;
    assign memory_bus.rnw     = '0;
    assign memory_bus.sram_cs = '0;

    // Definice stavového automatu
    typedef enum logic [3:0] {
        STATE_IDLE,
        STATE_CLEAN,
        STATE_READ_ADRFILL_FW_ROM,
        STATE_READ_CONF,
        STATE_CHECK_FW_CONF,
        STATE_CHECK_CONF,
        STATE_LOAD_CONF,
        STATE_PROCESS_BLOCK,
        STATE_FILL_RAM,
        STATE_SET_LAYOUT,
        STATE_SEARCH_CRC32_INIT,
        STATE_SEARCH_CRC32,
        STATE_GET_FW_ADDR,
        STATE_LOAD_KBD_LAYOUT,
        STATE_STOP,
        STATE_RESET
    } state_t;

    state_t state = STATE_IDLE;
    state_t next_state = STATE_IDLE;
    pattern_t pattern;
    logic [26:0] ram_addr;
    logic  [7:0] conf[8];
    // A free io_device slot exists for the device of the current CONF_DEVICE record,
    // within the number of synthesized copies (MSX::dev_copies)
    wire dev_slot_free = (~io_device[device_t'(conf[1])][0].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd0) ||
                         (~io_device[device_t'(conf[1])][1].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd1) ||
                         (~io_device[device_t'(conf[1])][2].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd2);
    logic  [3:0] ref_ram;
    logic        crc_en;
    logic        ram_ce;

    always_ff @(posedge clk) begin
        logic [24:0] data_size;
        logic [7:0]  temp[8];
        logic [5:0]  block_num;
        logic [2:0]  head_addr, read_cnt;
        logic [27:0] save_addr, save_addr2;
        logic        ref_add, ref_sram_add, fw_space, ref_dev_block, ref_dev_mem, set_offset, fix_offset;
        logic [1:0]  slot, subslot, block, size, offset, ref_sram, mapper_param;
        logic [15:0] rom_fw_table;
        logic  [2:0] io_ref_mem, io_ref_mapper;
        logic        cart_id;
        mapper_typ_t mapper;
        device_t device;

        MSX::io_device_t temp_io_device;
        device_t    last_device;
        logic [1:0] last_device_num;
        logic [2:0] current_io_ref_mapper;

        if (load) begin
            state <= STATE_CLEAN;
            $display("DO STATE_CLEAN");
        end

        // Automatické inkrementace pro DDR3, RAM a klávesnici
        if (ddr3_ready && ddr3_rd) begin
            ddr3_addr <= ddr3_addr + 1'b1;
            ddr3_rd   <= '0;
        end

        ram_ce <= '0;
        if (ram_ce) ram_addr <= ram_addr + 1'd1;

        kb_upload_memory.we  <= '0;
        if (kb_upload_memory.we) kb_upload_memory.addr <= kb_upload_memory.addr + 1'd1;

        if (ddr3_ready && ~ddr3_rd) begin
            case(state)
                STATE_IDLE: begin
                    block_num           <= '0;
                    ddr3_request        <= '0;
                    ref_add             <= '0;
                    ref_sram_add        <= '0;
                    ref_sram            <= '0;
                    ref_ram             <= '0;
                    ram_addr            <= '0;
                    crc_en              <= '0;
                    fw_space            <= '0;
                    save_addr           <= '0;
                    save_addr2          <= '0;
                    kb_upload_memory.rq <= '0;
                    ref_dev_block       <= '0;
                    ref_dev_mem         <= '0;
                    set_offset          <= '0;
                    fix_offset          <= '0;
                    load_sram           <= '0;
                    reset               <= '0;
                end
                STATE_RESET: begin
                    reset      <= '1;
                    state      <= STATE_IDLE;
                end
                STATE_CLEAN: begin
                    error <= ERR_NONE;
                    reset <= '1;
                    ddr3_request <= '1;
                    slot_layout[block_num].mapper     <= MAPPER_NONE;
                    slot_layout[block_num].ref_ram    <= '0;
                    slot_layout[block_num].offset_ram <= block_num[1:0];
                    slot_layout[block_num].cart_num   <= '0;
                    slot_layout[block_num].ref_sram   <= '0;
                    slot_layout[block_num].external   <= '0;
                    slot_layout[block_num].device_ref <= '0;
                    slot_layout[block_num].mapper_param <= '0;
                    lookup_SRAM[block_num[1:0]].size  <= '0;
                    main_ram.en                       <= '0;
                    slot_expander[block_num & 3].en   <= '0;
                    slot_expander[block_num & 3].wo   <= '1;
                    slot_expander[block_num & 3].init <= '0;

                    io_device[block_num[4:0]][0].enable     <= '0;
                    io_device[block_num[4:0]][0].port       <= '1;
                    io_device[block_num[4:0]][0].mask       <= '0;
                    io_device[block_num[4:0]][0].param      <= '0;
                    io_device[block_num[4:0]][0].mem_ref    <= '0;
                    io_device[block_num[4:0]][0].device_ref <= '0;

                    io_device[block_num[4:0]][1].enable     <= '0;
                    io_device[block_num[4:0]][1].port       <= '1;
                    io_device[block_num[4:0]][1].mask       <= '0;
                    io_device[block_num[4:0]][1].param      <= '0;
                    io_device[block_num[4:0]][1].mem_ref    <= '0;
                    io_device[block_num[4:0]][1].device_ref <= '0;

                    io_device[block_num[4:0]][2].enable     <= '0;
                    io_device[block_num[4:0]][2].port       <= '1;
                    io_device[block_num[4:0]][2].mask       <= '0;
                    io_device[block_num[4:0]][2].param      <= '0;
                    io_device[block_num[4:0]][2].mem_ref    <= '0;
                    io_device[block_num[4:0]][2].device_ref <= '0;

                    io_memory[block_num[2:0]].memory        <= '0;
                    io_memory[block_num[2:0]].memory_size   <= '0;

                    block_num                               <= block_num + 1'd1;
                    if (block_num == 63) begin
                        state      <= STATE_READ_CONF;
                        next_state <= STATE_CHECK_CONF;
                        block_num  <= '0;
                        ddr3_addr  <= '0;
                        ddr3_rd    <= '1;
                        head_addr  <= '0;
                        ram_addr   <= '0;
                        io_ref_mem <= '0;
                        io_ref_mapper <= 1;
                        read_cnt   <= CONF_SIZE;
                        msx_config.cpu           <= Z80;
                        msx_config.wait_count    <= 3'd1;
                        msx_config.cpu_clock_sel <= '0;
                        msx_config.fdd           <= '0;
                        if (ioctl_size[size_FW_PACK] > 0) begin
                            state      <= STATE_READ_CONF;
                            next_state <= STATE_CHECK_FW_CONF;
                            ddr3_addr  <= DDR3_BASE_FW_ADDR;
                            fw_space   <= '1;                           // Čtení firmware oblasti
                        end
                    end
                end
                STATE_READ_CONF: begin                                  // Přečte požadovaný počet bytů do konfigurace
                    if (fw_space ? ioctl_size[size_FW_PACK] > 27'(ddr3_addr - DDR3_BASE_FW_ADDR) : ioctl_size[size_MSX_PACK] > ddr3_addr[26:0]) begin  // Kontrola konce dat
                        conf[head_addr] <= ddr3_dout;
                        ddr3_rd         <= '1;
                        if (head_addr == read_cnt) begin
                            state     <= next_state;
                            head_addr <= '0;
                        end else begin
                            head_addr <= head_addr + 1'b1;
                        end
                    end else begin

                        state     <= STATE_RESET;
                        load_sram <= '1;
                        reset     <= '0;
                        $display("CONFIG LOAD END %t", $time);
                    end
                    kb_upload_memory.rq <= '0;
                end
                STATE_CHECK_FW_CONF: begin
                    if ({conf[0], conf[1], conf[2]} == {"M", "s", "X"}) begin
                        fw_space     <= '0;
                        state        <= STATE_READ_CONF;
                        next_state   <= STATE_CHECK_CONF;
                        rom_fw_table <= {conf[5], conf[4]};
                        ddr3_addr    <= '0;
                        ddr3_rd      <= '1;
                    end else begin
                        error <= ERR_BAD_MSX_FW_CONF;
                        state <= STATE_IDLE;
                    end
                end
                STATE_CHECK_CONF: begin
                    if ({conf[0], conf[1], conf[2]} == {"M", "S", "x"}) begin
                        state                    <= STATE_READ_CONF;
                        next_state               <= STATE_LOAD_CONF;
                        ddr3_request             <= '1;
                        msx_config.cpu           <= cpu_t'(conf[3][7:6]);
                        msx_config.wait_count    <= conf[3][5:3];
                        msx_config.cpu_clock_sel <= conf[3][2:0];
                    end else begin
                        error <= ERR_BAD_MSX_CONF;
                        state <= STATE_IDLE;
                    end
                end
                STATE_LOAD_CONF: begin
                    case(conf_t'(conf[0]))
                        CONF_BLOCK:  begin
                            $display("  BLOCK FW state %d", fw_space);
                            state   <= STATE_PROCESS_BLOCK;
                            slot    <= fw_space ? slot | conf[1][7:6] : conf[1][7:6];
                            subslot <= conf[1][5:4];
                            block   <= conf[1][3:2];
                            size    <= conf[1][1:0];
                            current_io_ref_mapper <= slot_layout[{fw_space ? slot | conf[1][7:6] : conf[1][7:6], conf[1][5:4], conf[1][3:2]}].device_ref;
                        end
                        CONF_LAYOUT:  begin
                            $display("  LOAD KBD LAYOUT");
                            kb_upload_memory.addr <= '0;
                            kb_upload_memory.rq   <= '1;
                            state                 <= STATE_LOAD_KBD_LAYOUT;
                        end
                        CONF_DEVICE:  begin
                            if (~io_device[device_t'(conf[1])][0].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd0) begin
                                $display("LOAD IO_DEVICE[%x][%x] port:%x mask %x param %x size %x addr: %x (DDR addr %x)",
                                        device_t'(conf[1]), 4'd0, conf[2], conf[3], conf[4], {3'b0, conf[5], 14'd0}, ram_addr, ddr3_addr);
                                io_device[device_t'(conf[1])][0].enable    <= 1'b1;
                                io_device[device_t'(conf[1])][0].port      <= conf[2];
                                io_device[device_t'(conf[1])][0].mask      <= conf[3];
                                io_device[device_t'(conf[1])][0].param     <= conf[4];
                                if (conf[5] != 0) begin
                                    io_device[device_t'(conf[1])][0].mem_ref <= io_ref_mem;
                                    io_ref_mem <= io_ref_mem + 3'd1;
                                end

                            end else if (~io_device[device_t'(conf[1])][1].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd1) begin
                                $display("LOAD IO_DEVICE[%x][%x] port:%x mask %x param %x size %x addr: %x (DDR addr %x)",
                                        device_t'(conf[1]), 4'd1, conf[2], conf[3], conf[4], {3'b0, conf[5], 14'd0}, ram_addr, ddr3_addr);
                                io_device[device_t'(conf[1])][1].enable    <= 1'b1;
                                io_device[device_t'(conf[1])][1].port      <= conf[2];
                                io_device[device_t'(conf[1])][1].mask      <= conf[3];
                                io_device[device_t'(conf[1])][1].param     <= conf[4];
                                if (conf[5] != 0) begin
                                    io_device[device_t'(conf[1])][1].mem_ref <= io_ref_mem;
                                    io_ref_mem <= io_ref_mem + 3'd1;
                                end

                            end else if (~io_device[device_t'(conf[1])][2].enable && MSX::dev_copies(device_t'(conf[1])) > 2'd2) begin
                                $display("LOAD IO_DEVICE[%x][%x] port:%x mask %x param %x size %x addr: %x (DDR addr %x)",
                                        device_t'(conf[1]), 4'd2, conf[2], conf[3], conf[4], {3'b0, conf[5], 14'd0}, ram_addr, ddr3_addr);
                                io_device[device_t'(conf[1])][2].enable    <= 1'b1;
                                io_device[device_t'(conf[1])][2].port      <= conf[2];
                                io_device[device_t'(conf[1])][2].mask      <= conf[3];
                                io_device[device_t'(conf[1])][2].param     <= conf[4];
                                if (conf[5] != 0) begin
                                    io_device[device_t'(conf[1])][2].mem_ref <= io_ref_mem;
                                    io_ref_mem <= io_ref_mem + 3'd1;
                                end

                            end else begin
                                $display("LOAD IO_DEVICE FAILED ID:%x port:%x mask %x param %x size %x addr: %x (DDR addr %x)",
                                        conf[1], conf[2], conf[3], conf[4], {3'b0, conf[5], 14'd0}, ram_addr, ddr3_addr);
                                error <= ERR_MISSING_SOURCE;
                                state <= STATE_IDLE;
                            end

                            if (conf[6][7] && dev_slot_free) begin                        // memory = window into an existing block
                                $display("  LOAD IO_DEVICE SHARED io_ref_mem :%x block %x offset %x size %x", io_ref_mem, conf[6][5:0], conf[7], conf[5]);
                                io_memory[io_ref_mem].memory      <= lookup_RAM[slot_layout[conf[6][5:0]].ref_ram].addr + {5'b0, conf[7], 14'd0};
                                io_memory[io_ref_mem].memory_size <= conf[5];
                                state                             <= STATE_READ_CONF;
                                next_state                        <= STATE_LOAD_CONF;
                            end else if (conf[5] != 0 && dev_slot_free) begin             // a slot was allocated above
                                $display("  LOAD IO_DEVICE FILL ROM io_ref_mem :%x memory addr:%x size: %x", io_ref_mem, ram_addr, {3'b0, conf[5], 14'd0});
                                io_memory[io_ref_mem].memory      <= ram_addr;
                                io_memory[io_ref_mem].memory_size <= conf[5];
                                data_size                         <= {3'b0, conf[5], 14'd0};
                                pattern                           <= PATTERN_DDR;
                                state                             <= STATE_FILL_RAM;
                                next_state                        <= STATE_READ_CONF;
                            end else begin
                                state      <= STATE_READ_CONF;
                                next_state <= STATE_LOAD_CONF;
                            end
                        end
                        CONF_END: begin
                            ddr3_addr  <= save_addr;
                            ddr3_rd    <= '1;
                            fw_space   <= '0;
                            read_cnt   <= CONF_SIZE;
                            state      <= STATE_READ_CONF;
                            next_state <= STATE_LOAD_CONF;
                        end
                    default: begin
                        error <= ERR_NOT_SUPPORTED_CONF;
                        state <= STATE_IDLE;
                    end
                    endcase
                end
                STATE_PROCESS_BLOCK: begin
                    mapper        <= MAPPER_NONE;
                    mapper_param  <= '0;
                    device        <= DEV_NONE;
                    ref_dev_block <= '0;
                    ref_dev_mem   <= '0;
                    next_state    <= STATE_READ_CONF;
                    case(block_t'(conf[2]))
                        BLOCK_REF_SHARED_MEM: begin
                            //conf 3 source_block
                            //conf 4 offset
                            //conf 5 size
                            //conf 6 bit 0 ro

                            $display("BLOCK SHARED MEMORY source(%d/%d/%d) source reference: %d base RAM %x - ref_RAM:%x addr:%x size %d "
                                                                                      , conf[3][5:4]
                                                                                      , conf[3][3:2]
                                                                                      , conf[3][1:0]
                                                                                      , slot_layout[conf[3][5:0]].ref_ram
                                                                                      , lookup_RAM[slot_layout[conf[3][5:0]].ref_ram].addr
                                                                                      , ref_ram
                                                                                      , lookup_RAM[slot_layout[conf[3][5:0]].ref_ram].addr + {4'b0000, conf[4] == 8'd0, conf[4],14'd0}
                                                                                      , {conf[5] == 8'd0, conf[5],14'd0});

                            lookup_RAM[ref_ram].addr <= lookup_RAM[slot_layout[conf[3][5:0]].ref_ram].addr + {4'b0000, conf[4] == 8'd0, conf[4],14'd0};      // Copy reference + offset
                            lookup_RAM[ref_ram].size <= {8'd0, conf[5],1'b0};                                                                                // Uložíme velikost RAM
                            lookup_RAM[ref_ram].ro   <= conf[6][0];                                                                                          // Vypneme ochranu paměti RAM

                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            state                    <= STATE_SET_LAYOUT;
                        end
                        BLOCK_RAM: begin
                            $display("BLOCK RAM ref_RAM:%x addr:%x size %d ", ref_ram, ram_addr, {conf[3] == 8'd0, conf[3],14'd0});
                            lookup_RAM[ref_ram].addr <= ram_addr;                  // Uložíme adresu RAM
                            lookup_RAM[ref_ram].size <= {8'd0, conf[3],1'b0};      // Uložíme velikost RAM
                            lookup_RAM[ref_ram].ro   <= '0;                        // Vypneme ochranu paměti RAM
                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            data_size                <= {2'b0, conf[3] == 8'd0, conf[3],14'd0};     // Velikost nahrávaných dat
                            pattern                  <= pattern_t'(conf[4]);
                            state                    <= STATE_FILL_RAM;
                        end
                        BLOCK_SRAM: begin
                            // TODO: Určení reference
                            // 0 - ROM
                            // 1 - Extension A
                            // 2 - Extension B
                            // 3 - Computer CMOS
                            next_state <= STATE_LOAD_CONF;   // Defaultně neděláme nic
                            state <= STATE_READ_CONF;

                            if (fw_space) begin   // Zatím umíme pouze CART SRAM
                                if ((ref_sram == 2'd0 && lookup_SRAM[ref_sram].size == '0) || ref_sram != 2'd0) begin  // Jedná se o ROM SRAM?
                                    $display("BLOCK SRAM ref_SRAM:%x addr:%x size %d", ref_sram, ram_addr, {conf[3],10'd0});
                                    lookup_SRAM[ref_sram].addr <= ram_addr;               // Uložíme adresu RAM
                                    lookup_SRAM[ref_sram].size <= {8'd0, conf[3]};        // Uložíme velikost RAM
                                    ref_sram_add               <= '1;                     // Signalizujeme potřebu přiřadit SRAM
                                    data_size                  <= {7'b0, conf[3],10'd0};  // Velikost nahrávaných dat
                                    pattern                    <= PATTERN_FF;
                                    next_state                 <= STATE_READ_CONF;
                                    state                      <= STATE_FILL_RAM;
                                end
                            end
                        end
                        BLOCK_ROM: begin
                            lookup_RAM[ref_ram].addr <= ram_addr;                  // Uložíme adresu ROM
                            lookup_RAM[ref_ram].ro   <= '1;                        // Uložíme ochranu paměti ROM
                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            pattern                  <= PATTERN_DDR;
                            if (fw_space) begin                                    // Pokud se  bude jednat o ROM z FW musíme dle indexu najít adresu v DDR
                                $display("BLOCK FW ROM ID: %x ref_RAM:%x addr:%x size %d ", conf[3], ref_ram, ram_addr, {conf[4],conf[5],14'd0});
                                lookup_RAM[ref_ram].size <= {conf[4],conf[5],1'b0};              // Uložíme velikost ROM
                                data_size                <= {conf[4][2:0],conf[5],14'd0};
                                save_addr2               <= ddr3_addr - 1'b1;                    // Uložíme adresu pokračování -1 kvůli prefetch
                                ddr3_addr                <= DDR3_BASE_FW_ADDR + {12'b0, rom_fw_table} + {18'b0, conf[3],2'b00};
                                ddr3_rd                  <= '1;
                                state                    <= STATE_READ_CONF;                     // Jdeme přečíst ROM ADDR
                                next_state               <= STATE_READ_ADRFILL_FW_ROM;           // Pokračujeme nastavením ROM
                            end else begin
                                $display("BLOCK ROM ref_RAM:%x addr:%x size %d ", ref_ram, ram_addr, {conf[3],14'd0});
                                lookup_RAM[ref_ram].size <= {8'd0, conf[3],1'b0};    // Uložíme velikost ROM
                                data_size                <= {3'b0, conf[3],14'd0};   // Velikost nahrávaných dat
                                state                    <= STATE_FILL_RAM;
                            end
                        end
                        BLOCK_CART: begin
                            next_state <= STATE_LOAD_CONF;                          // Defaultně neděláme nic
                            state      <= STATE_READ_CONF;
                            $display("BLOCK CART ID:%d CONF:%x", conf[3][0], cart_conf[conf[3][0]].typ);
                            cart_id    <= conf[3][0];
                            if (cart_conf[conf[3][0]].typ == CART_TYP_ROM) begin
                                if (ioctl_size[conf[3][0] ? size_ROM_B : size_ROM_A] > '0) begin
                                    $display("BLOCK CART %d LOAD START ref: %d addr:%x size:%x - %x", conf[3][0], ref_ram, ram_addr, ioctl_size[conf[3][0] ? size_ROM_B : size_ROM_A], ioctl_size[conf[3][0] ? size_ROM_B : size_ROM_A][26:14]);
                                    lookup_RAM[ref_ram].addr <= ram_addr;                                                   // Uložíme adresu ROM
                                    lookup_RAM[ref_ram].size <= {3'b0, ioctl_size[conf[3][0] ? size_ROM_B : size_ROM_A][26:13]};        // Uložíme velikost ROM
                                    lookup_RAM[ref_ram].ro   <= '1;                                                         // Uložíme ochranu paměti ROM
                                    state                    <= STATE_FILL_RAM;                                             // Načítáme ROM
                                    next_state               <= STATE_SEARCH_CRC32_INIT;                                    // Po nahrání budeme hledat CRC
                                    save_addr                <= ddr3_addr - 1'b1;                                           // Uchováme adresu -1 kvůli již načtenému prefetch bajtu
                                    ddr3_addr                <= conf[3][0] ? 28'h1100000 : 28'hC00000;                      // Adresa ROM v DDR
                                    data_size                <= ioctl_size[conf[3][0] ? size_ROM_B : size_ROM_A][24:0];                 // Velikost ROM
                                    ddr3_rd                  <= '1;                                                         // Prefetch
                                    ref_add                  <= '1;                                                         // Ukládáme referenci
                                    crc_en                   <= '1;                                                         // Počítáme CRC
                                    pattern                  <= PATTERN_DDR;                                                // Ukládáme z ROM
                                    ref_sram                 <= 2'd0;
                                end
                            end else begin                                                                // Neni ROM jdeme do FW
                                if (ioctl_size[size_FW_PACK] > '0) begin                                  // Máme FW?
                                    save_addr  <= ddr3_addr - 1'b1;                                       // Uchováme adresu -1 kvůli již načtenému prefetch bajtu
                                    ddr3_addr  <= 28'h300010 + {22'b0, cart_conf[conf[3][0]].typ,2'b00};  // FW Area + ID zařízení
                                    ddr3_rd    <= '1;                                                     // Preferch
                                    read_cnt   <= 4;
                                    fw_space   <= '1;
                                    ref_sram   <= conf[3][0] ? 2'd2 : 2'd1;                               // Kam patří případná SRAM
                                    state      <= STATE_READ_CONF;                                        // Zahájíme LOAD
                                    next_state <= STATE_GET_FW_ADDR;
                                    $display("%t BLOCK CART LOAD FW FROM DDR ADDR %x", $time(), 28'h300010 + {22'b0, cart_conf[conf[3][0]].typ,2'b00});
                                end else begin
                                    error <= ERR_NOT_FW_CONF;                                             // FW není k dispozici
                                    state <= STATE_IDLE;
                                end
                            end
                        end
                        BLOCK_MAPPER: begin
                            $display("BLOCK MAPPER %d offset enable %d offset %d set_offset %d fix_offset %d param %d", conf[3], conf[4][7], conf[4][1:0],conf[4][7],conf[4][6],conf[4][3:2]);
                            mapper     <= mapper_typ_t'(conf[3]);
                            offset     <= conf[4][1:0];
                            mapper_param <= conf[4][3:2];
                            set_offset <= conf[4][7];
                            fix_offset <= conf[4][6];
                            state      <= STATE_SET_LAYOUT;
                        end
                        BLOCK_DEVICE: begin
                            state  <= STATE_SET_LAYOUT;
                            device <= device_t'(conf[3]);
                            last_device <= device_t'(conf[3]);
                            if (device_t'(conf[3]) == DEV_TC8566AF || device_t'(conf[3]) == DEV_WD2793) begin       //FIXED DEVICE position ID
                                temp_io_device            = io_device[device_t'(conf[3])][fw_space ? {1'b0, cart_id} : 2'd2];
                                temp_io_device.enable     = 1'b1;
                                temp_io_device.param      = conf[4];
                                temp_io_device.device_ref = current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                io_device[device_t'(conf[3])][fw_space ? {1'b0, cart_id} : 2'd2] <= temp_io_device;
                                io_ref_mapper                                       <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                current_io_ref_mapper                               <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                last_device_num                                     <= fw_space ? {1'b0, cart_id} : 2'd2;
                                $display("BLOCK IO_DEVICE[%x] IS FIXED pos:%x reference %d", device_t'(conf[3]), fw_space ? {1'b0, cart_id} : 2'd2, current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper );
                                $display("BLOCK IO_DEVICE[%x][%x] enable: 1 param:%x", device_t'(conf[3]), fw_space ? {1'b0, cart_id} : 2'd2, conf[4]);
                            end else begin
                                if (~io_device[device_t'(conf[3])][0].enable) begin
                                    $display("BLOCK IO_DEVICE[%x][0] enable: 1 param:%x reference: %d", device_t'(conf[3]), conf[4], current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper);
                                    temp_io_device                    = io_device[device_t'(conf[3])][0];
                                    temp_io_device.enable             = 1'b1;
                                    temp_io_device.param              = conf[4];
                                    temp_io_device.device_ref         = current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    io_ref_mapper                    <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                    current_io_ref_mapper            <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    last_device_num                  <= 0;
                                    io_device[device_t'(conf[3])][0] <= temp_io_device;
                                end else if (~io_device[device_t'(conf[3])][1].enable) begin
                                    $display("BLOCK IO_DEVICE[%x][1] enable: 1 param:%x reference: %d", device_t'(conf[3]), conf[4], current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper);
                                    temp_io_device                    = io_device[device_t'(conf[3])][1];
                                    temp_io_device.enable             = 1'b1;
                                    temp_io_device.param              = conf[4];
                                    temp_io_device.device_ref         = current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    io_ref_mapper                    <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                    current_io_ref_mapper            <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    last_device_num                  <= 1;
                                    io_device[device_t'(conf[3])][1] <= temp_io_device;
                                end else if (~io_device[device_t'(conf[3])][2].enable) begin
                                    $display("BLOCK IO_DEVICE[%x][2] enable: 1 param:%x reference: %d", device_t'(conf[3]), conf[4], current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper);
                                    temp_io_device                    = io_device[device_t'(conf[3])][2];
                                    temp_io_device.enable             = 1'b1;
                                    temp_io_device.param              = conf[4];
                                    temp_io_device.device_ref         = current_io_ref_mapper == '0 ? io_ref_mapper     : current_io_ref_mapper;
                                    io_ref_mapper                    <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                    current_io_ref_mapper            <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    last_device_num                  <= 2;
                                    io_device[device_t'(conf[3])][2] <= temp_io_device;
                                end else begin
                                    error                            <= ERR_DEVICE_MISSING;                  // DEVICE JIZ NENI K DISPOZICI
                                    state                            <= STATE_IDLE;
                                    $display("DEVICE %x JIZ NENI K DISPOZICI", device_t'(conf[3]));
                                    device                           <= DEV_NONE;
                                    last_device                      <= DEV_NONE;
                                end
                            end
                        end
                        BLOCK_IO_DEVICE: begin
                            $display("BLOCK IO_DEVICE ref:%d port:%x mask %x param %x (%d/%d/%d)",
                                    slot_layout[{slot, subslot, block}].device_ref,
                                    conf[3], conf[4], conf[5], slot, subslot, block);

                            temp_io_device = io_device[last_device][last_device_num];
                            temp_io_device.port  = conf[3];
                            temp_io_device.mask  = conf[4];
                            temp_io_device.param = conf[5];
                            io_device[last_device][last_device_num] <= temp_io_device;
                            last_device <= DEV_NONE;

                            state      <= STATE_READ_CONF;
                            next_state <= STATE_LOAD_CONF;
                        end
                        BLOCK_REF_DEV: begin
                            $display("BLOCK_REF_DEV ref to block:%x", conf[3][1:0]);
                            state         <= STATE_SET_LAYOUT;
                            ref_dev_block <= 1'b1;
                        end
                        BLOCK_REF_MEM: begin
                            $display("BLOCK_REF_MEM ref to block:%x", conf[3][1:0]);
                            state       <= STATE_SET_LAYOUT;
                            ref_dev_mem <= 1'b1;
                        end
                        BLOCK_EXPANDER: begin
                            $display("BLOCK_EXPANDER slot: %d enabled: %d wo: %d init:%x", slot, conf[3][0], conf[3][1], conf[4]);
                            slot_expander[slot].en <=   conf[3][0];
                            slot_expander[slot].wo <=   conf[3][1];
                            slot_expander[slot].init <= conf[4];
                            next_state             <= STATE_LOAD_CONF;
                            state                  <= STATE_READ_CONF;
                        end
                        default: begin
                            $display("BLOCK UNKNOWN");
                            error <= ERR_NOT_SUPPORTED_BLOCK;
                            state <= STATE_IDLE;
                        end
                    endcase
                end
                STATE_READ_ADRFILL_FW_ROM:begin
                    ddr3_addr  <= DDR3_BASE_FW_ADDR + {conf[3][3:0],conf[2],conf[1],conf[0]};
                    ddr3_rd    <= '1;
                    next_state <= STATE_READ_CONF;
                    state      <= STATE_FILL_RAM;
                end
                STATE_FILL_RAM: begin
                    if (memory_bus.sdram_ready && ~ram_ce) begin             // RAM je připravená
                        data_size <= data_size - 25'd1;                      // Snížíme velikost dat
                        ram_ce    <= 1'b1;
                    end
                    if (pattern == PATTERN_DDR && ram_ce) ddr3_rd <= 1'b1;   // Připrav další byte z DDR, pokud je vzor DDR
                    if (data_size == 25'd0) state <= STATE_SET_LAYOUT;       // Poslední byte
                end
                STATE_SET_LAYOUT: begin
                    if (size == 2'b00) begin                                 // Kontrola, zda jsme na konci
                        if (ref_add) begin
                            ref_ram    <= ref_ram + 1'd1;                    // Zvýšíme referenci o 1
                        end
                        if (save_addr2 != '0) begin                          // Pokud jsme jeli v ROM FW uložíme
                            ddr3_addr  <= save_addr2;
                            save_addr2 <= '0;
                            ddr3_rd    <= '1;
                        end
                        ref_add      <= '0;
                        ref_sram_add <= '0;
                        set_offset   <= '0;
                        fix_offset   <= '0;
                        mapper       <= MAPPER_NONE;
                        mapper_param <= '0;
                        state        <= next_state;
                        next_state   <= STATE_LOAD_CONF;
                    end

                    block  <= block + 2'b01;                 // Další blok
                    size   <= size - 2'b01;                  // Snížíme počet
                    if (!fix_offset)
                        offset <= offset + 2'b01;

                    if (ref_add) begin
                        slot_layout[{slot, subslot, block}].ref_ram    <= ref_ram;
                        $display("BLOCK slot:%x subslot:%x block:%x < reference:%x ", slot, subslot, block, ref_ram );
                    end

                    if (set_offset) begin
                        slot_layout[{slot, subslot, block}].offset_ram <= offset;
                        $display("BLOCK slot:%x subslot:%x block:%x < offset:%x ", slot, subslot, block, offset );
                    end

                    if (mapper != MAPPER_NONE) begin
                        slot_layout[{slot, subslot, block}].mapper     <= mapper;
                        slot_layout[{slot, subslot, block}].mapper_param <= mapper_param;
                        if (mapper == MAPPER_PANASONIC_RAM) begin   // the RAM of this block (set by its RAM entry)
                            main_ram.en      <= 1'b1;
                            main_ram.ref_ram <= slot_layout[{slot, subslot, block}].ref_ram;
                            $display("BLOCK slot:%x subslot:%x block:%x = main RAM ref:%x", slot, subslot, block, slot_layout[{slot, subslot, block}].ref_ram);
                        end
                        $display("BLOCK slot:%x subslot:%x block:%x < mapper:%x", slot, subslot, block, mapper );
                    end

                    if (conf_t'(conf[0]) == CONF_BLOCK && block_t'(conf[2]) == BLOCK_CART)  begin
                        slot_layout[{slot, subslot, block}].cart_num   <= conf[3][0];
                        $display("BLOCK slot:%x subslot:%x block:%x < cart_num:%x", slot, subslot, block, conf[3][0] );
                    end

                    if (ref_sram_add)  begin
                        slot_layout[{slot, subslot, block}].ref_sram   <= ref_sram;
                        $display("BLOCK slot:%x subslot:%x block:%x < ref_sram:%x", slot, subslot, block, ref_sram );
                    end

                    if (device != DEV_NONE) begin
                        slot_layout[{slot, subslot, block}].device_ref <= current_io_ref_mapper;
                        $display("BLOCK slot:%x subslot:%x block:%x < device REF:%d ", slot, subslot, block, current_io_ref_mapper);
                    end

                    if (ref_dev_block) begin
                        slot_layout[{slot, subslot, block}].device_ref <= slot_layout[{slot, subslot, conf[3][1:0]}].device_ref;
                        $display("BLOCK slot:%x subslot:%x block:%x < device ref:%d ", slot, subslot, block, slot_layout[{slot, subslot, conf[3][1:0]}].device_ref );
                        ref_dev_block <= '0;
                    end

                    if (ref_dev_mem) begin
                        slot_layout[{slot, subslot, block}].ref_ram    <= slot_layout[{slot, subslot, conf[3][1:0]}].ref_ram;
                        slot_layout[{slot, subslot, block}].mapper     <= slot_layout[{slot, subslot, conf[3][1:0]}].mapper;
                        slot_layout[{slot, subslot, block}].mapper_param <= slot_layout[{slot, subslot, conf[3][1:0]}].mapper_param;
                        slot_layout[{slot, subslot, block}].offset_ram <= slot_layout[{slot, subslot, conf[3][1:0]}].offset_ram;
                        $display("BLOCK slot:%x subslot:%x block:%x < reference:%x ", slot, subslot, block, slot_layout[{slot, subslot, conf[3][1:0]}].ref_ram);
                        $display("BLOCK slot:%x subslot:%x block:%x < offset:%x ", slot, subslot, block, slot_layout[{slot, subslot, conf[3][1:0]}].offset_ram);
                        $display("BLOCK slot:%x subslot:%x block:%x < mapper:%x ", slot, subslot, block, slot_layout[{slot, subslot, conf[3][1:0]}].mapper);
                        ref_dev_mem <= '0;
                    end

                    if (device == DEV_TC8566AF || device == DEV_WD2793) begin
                        temp_io_device = io_device[device][last_device_num];
                        if (fw_space) begin
                            if (cart_id) begin
                                msx_config.fdd[3:2] <= conf[4][3:2];
                                temp_io_device.param[7:6] = 2'd1;
                                $display("Change FDD layout. Slot %d: %x ", cart_id, conf[4][3:2]);
                            end else begin
                                msx_config.fdd[1:0] <= conf[4][3:2];
                                temp_io_device.param[7:6] = 2'd0;
                                $display("Change FDD layout. Internal: %x) ", conf[4][3:2]);
                            end
                        end else begin
                            msx_config.fdd[5:4] <= conf[4][3:2];
                            temp_io_device.param[7:6] = 2'd2;
                            $display("Change FDD layout. Internal: %x) ", conf[4][3:2]);
                        end
                        io_device[device][last_device_num] <= temp_io_device;
                    end
                end
                STATE_SEARCH_CRC32_INIT: begin
                    if (ioctl_size[size_CRC] == 0) begin
                        $display("NO CRC32 DB");
                        ddr3_addr <= save_addr;
                        ddr3_rd   <= '1;
                        error     <= ERR_NO_CRC_DB;
                        state     <= STATE_STOP;
                    end else begin
                        state     <= STATE_SEARCH_CRC32;
                        ddr3_addr <= DDR3_CRC32_TABLE_ADDR;                     // Adresa CRC32 tabulky
                        ddr3_rd   <= 1'b1;                                      // Prefetch
                        crc_en    <= 1'b0;                                      // Zastavení počítání CRC32
                    end
                end
                STATE_SEARCH_CRC32: begin
                    temp[ddr3_addr[2:0]] = ddr3_dout;
                    if (ddr3_addr[2:0] == 3'd0 && rom_crc32 == {temp[4], temp[3], temp[2], temp[1]}) begin
                        $display("FIND CRC32: %x mapper:%x sram:%x", rom_crc32, temp[5], temp[6]);       // CRC32 nalezeno
                        if (ioctl_size[size_FW_PACK] > '0) begin                                                    // Máme FW?
                            ddr3_addr  <= 28'h300010 + {18'b0, temp[5], 2'b00};
                            ddr3_rd    <= '1;
                            read_cnt   <= 4;
                            fw_space   <= '1;
                            state      <= STATE_READ_CONF;
                            next_state <= STATE_GET_FW_ADDR;
                        end else begin
                            error <= ERR_NOT_FW_CONF;
                            state <= STATE_IDLE;
                        end
                    end else begin
                        if ((ddr3_addr - DDR3_CRC32_TABLE_ADDR) == {1'b0, ioctl_size[size_CRC]}) begin
                            $display("NOT FIND CRC32: %x", rom_crc32);
                            // TODO: Nastav linear mapper a pokračuj.
                            ddr3_addr <= save_addr;
                            ddr3_rd   <= '1;
                            error     <= ERR_NO_CRC_FOUND;
                            state     <= STATE_STOP;
                        end else begin
                            ddr3_rd <= 1'b1;
                        end                                                                                                // Další data z DDR
                    end
                end
                STATE_GET_FW_ADDR: begin
                    ddr3_addr  <= {4'b0, 4'h3, conf[2][3:0], conf[1], conf[0]};
                    ddr3_rd    <= '1;
                    read_cnt   <= 5;
                    state      <= STATE_READ_CONF;
                    next_state <= STATE_LOAD_CONF;
                    $display("CART_CONFIG DDR ADDR %x", {4'b0, 4'h3, conf[2][3:0], conf[1], conf[0]});
                end
                STATE_LOAD_KBD_LAYOUT: begin
                    if (~kb_upload_memory.we) begin
                        ddr3_rd               <= 1'b1;
                        kb_upload_memory.we   <= 1'b1;
                        kb_upload_memory.data <= ddr3_dout;
                        if (kb_upload_memory.addr == 9'h1FF) begin
                            state <= STATE_READ_CONF;
                        end
                    end
                end
                default: ;
            endcase
        end
    end

    wire [31:0] rom_crc32;
    CRC_32 CRC_32
    (
        .clk(clk),
        .en(crc_en),
        .we(ram_ce),
        .crc_in(ddr3_dout),
        .crc_out(rom_crc32)
    );

endmodule
