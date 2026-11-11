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
    input                 [5:0] layout_id,          // msx_slots: {slot, subslot, page}
    output MSX::block_t         active_block,       // slot layout of the block layout_id
    output MSX::lookup_RAM_t    active_RAM,         // memory of that block
    output MSX::lookup_RAM_t    main_RAM,           // memory of main_ram.ref_ram (turbo R)
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
    localparam DDR3_BASE_FW_ADDR = MSX::DDR3_FW_PACK;
    localparam DDR3_CRC32_TABLE_ADDR = MSX::DDR3_DB;
    localparam logic [2:0] CONF_SIZE = 7;           // Conf block size for computer 8 bytes - 1 byte

    // Stavový signál, který indikuje, že jsem v režimu upload. Resetujeme core a RAM přístup pro UPLOAD
    assign upload = state != STATE_IDLE || restart;

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

    logic [8:0] fill_base;                                  // ram_addr[8:0] at the start of a BLOCK_RAM fill
    wire  [8:0] fill_poss = ram_addr[8:0] - fill_base;

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
    logic   restart = 1'b0;         // a load request waits for STATE_IDLE to start the upload
    // The machine's own FDC wins over an FDC cartridge on the same position: the load starts
    // again with cartridge A left out (fdc_cart_off, until the next load request).
    logic   fdc_cart_off  = 1'b0;
    logic   fdc_cart_used = 1'b0;   // the FDC of this load came from the cartridge
    state_t next_state = STATE_IDLE;
    pattern_t pattern;
    logic [26:0] ram_addr;
    logic  [7:0] conf[8];
    // io_device is written per field and only its enable bits are read back, so entries and
    // fields that no device uses are removed by the synthesis. Enable bits of the three
    // copies of the device type of the current record:
    wire  [4:0] dev_rd_t = (state == STATE_PROCESS_BLOCK) ? conf[3][4:0] : conf[1][4:0];
    wire  [2:0] dev_en   = {io_device[dev_rd_t][2].enable, io_device[dev_rd_t][1].enable, io_device[dev_rd_t][0].enable};
    // free copies of that type among the synthesized ones (MSX::dev_slots)
    wire  [2:0] dev_ok   = MSX::dev_slots(device_t'(dev_rd_t));
    wire  [2:0] dev_free = ~dev_en & dev_ok;
    wire        dev_slot_free = |dev_free;
    logic  [3:0] ref_ram;
    logic        crc_en;
    logic        ram_ce;
    logic        cart_id;
    logic        fw_space;
    logic        fw_mem;            // the cartridge configuration being read has allocated memory
    logic  [1:0] slot, subslot, block;
    // FDC (WD2793 / TC8566AF) position: 0 internal, 1 cartridge in slot A (with N_FDC = 1 the
    // cartridge shares position 0). One FDC per position, whichever type.
    wire  [1:0] fdc_pos  = (fw_space && MSX::N_FDC > 1) ? 2'd1 : 2'd0;
    wire        fdc_busy = io_device[DEV_WD2793][fdc_pos].enable || io_device[DEV_TC8566AF][fdc_pos].enable;

    // io_device write command, registered (applied one clock after the step that makes it;
    // the enable bits are next read several steps later)
    logic        dev_clr_q = 1'b0;
    logic  [6:0] dev_we_q  = '0;
    logic  [4:0] dev_wt_q;
    logic  [1:0] dev_wk_q;
    logic  [7:0] dev_port_q, dev_mask_q, dev_param_q;
    logic  [2:0] dev_mref_q, dev_dref_q;
    genvar       gt, gk;

    // Slot layout (64 x 20 b) and RAM lookup (16 x 45 b) are kept in LUT RAM (MLAB) instead of
    // registers: one write port, asynchronous read, one copy per reader (msx_slots, the
    // state machine). Written only during the upload, when the core is in reset.
    typedef struct packed {
        logic  [3:0] ref_ram;
        logic  [1:0] ref_sram;
        logic  [1:0] offset_ram;
        logic  [2:0] device_ref;
        logic  [5:0] mapper;
        logic  [1:0] mapper_param;
        logic        cart_num;
    } lay_t;
    typedef struct packed {
        logic [26:0] addr;
        logic [16:0] size;
        logic        ro;
    } ram_t;

    (* ramstyle = "MLAB, no_rw_check" *) logic [19:0] lay_slots [64];   // read by msx_slots
    (* ramstyle = "MLAB, no_rw_check" *) logic [19:0] lay_fsm0  [64];   // state machine, block being handled
    (* ramstyle = "MLAB, no_rw_check" *) logic [19:0] lay_fsm1  [64];   // state machine, referenced block
    (* ramstyle = "MLAB, no_rw_check" *) logic [44:0] ram_slots [16];   // read by msx_slots
    (* ramstyle = "MLAB, no_rw_check" *) logic [44:0] ram_main  [16];   // main RAM (turbo R)
    (* ramstyle = "MLAB, no_rw_check" *) logic [44:0] ram_fsm   [16];   // state machine

    // state machine read ports
    logic [5:0] lay_ra0;
    always_comb begin
        case (state)
            STATE_SET_LAYOUT:    lay_ra0 = {slot, subslot, block};          // block being written
            STATE_PROCESS_BLOCK: lay_ra0 = (block_t'(conf[2]) == BLOCK_FLASH || block_t'(conf[2]) == BLOCK_DEVICE)
                                           ? {slot, subslot, block}         // memory of the block
                                           : conf[3][5:0];                  // source of a shared memory
            default:             lay_ra0 = conf_t'(conf[0]) == CONF_DEVICE ? conf[6][5:0] :
                                           {fw_space ? slot | conf[1][7:6] : conf[1][7:6], conf[1][5:4], conf[1][3:2]};
        endcase
    end
    lay_t lay_q0, lay_q1, lay_qs;
    ram_t ram_q, ram_qs, ram_qm;
    assign lay_q0 = lay_t'(lay_fsm0[lay_ra0]);
    assign lay_q1 = lay_t'(lay_fsm1[{slot, subslot, conf[3][1:0]}]);
    assign ram_q  = ram_t'(ram_fsm[lay_q0.ref_ram]);

    // msx_slots read port
    assign lay_qs = lay_t'(lay_slots[layout_id]);
    assign ram_qs = ram_t'(ram_slots[lay_qs.ref_ram]);
    assign ram_qm = ram_t'(ram_main[main_ram.ref_ram]);
    assign active_block.ref_ram      = lay_qs.ref_ram;
    assign active_block.ref_sram     = lay_qs.ref_sram;
    assign active_block.offset_ram   = lay_qs.offset_ram;
    assign active_block.device_ref   = lay_qs.device_ref;
    assign active_block.mapper       = mapper_typ_t'(lay_qs.mapper);
    assign active_block.mapper_param = lay_qs.mapper_param;
    assign active_block.cart_num     = lay_qs.cart_num;
    assign active_block.external     = 1'b0;
    assign active_RAM.addr = ram_qs.addr;
    assign active_RAM.size = ram_qs.size;
    assign active_RAM.ro   = ram_qs.ro;
    assign main_RAM.addr   = ram_qm.addr;
    assign main_RAM.size   = ram_qm.size;
    assign main_RAM.ro     = ram_qm.ro;

    // Cartridge ROM without a database entry (or without a database): plain ROM, read linearly,
    // placed by its MSX header (bytes 0-3 and 4000h-4003h, captured while the ROM streams in,
    // as the CRC). FW pack configurations 0x0000 / 0x4000 / 0x8000 of cart_device.json.
    localparam logic [7:0] FW_PLAIN_0000 = 8'd20, FW_PLAIN_4000 = 8'd21, FW_PLAIN_8000 = 8'd22;
    logic [16:0] hdr_cnt;
    logic  [7:0] hdr0[4], hdr4[4];      // file offsets 0 and 4000h: 'A' 'B' INIT
    always_ff @(posedge clk) begin
        if (!crc_en) hdr_cnt <= '0;
        else if (ram_ce) begin
            if (hdr_cnt < 17'h1FFFF) hdr_cnt <= hdr_cnt + 1'd1;
            if (hdr_cnt[16:2] == 15'h0000) hdr0[hdr_cnt[1:0]] <= ddr3_dout;
            if (hdr_cnt[16:2] == 15'h1000) hdr4[hdr_cnt[1:0]] <= ddr3_dout;
        end
    end
    // ROM size of a cartridge slot; selecting the value, not the index (Quartus 10027)
    wire  [26:0] rom_size_a = ioctl_size[size_ROM_A];
    wire  [26:0] rom_size_b = ioctl_size[size_ROM_B];
    wire  [26:0] cart_size  = cart_id ? rom_size_b : rom_size_a;
    wire  [26:0] conf_rom_size = conf[3][0] ? rom_size_b : rom_size_a;   // BLOCK_CART record
    wire         ab0       = hdr0[0] == 8'h41 && hdr0[1] == 8'h42;
    wire         ab4       = cart_size > 27'h4000 && hdr4[0] == 8'h41 && hdr4[1] == 8'h42;
    wire         plain_ok  = cart_size <= 27'h10000;             // more needs a mapper
    // 'AB' at 0: INIT page 2 -> 8000h, page 0 -> 0000h, else 4000h; 'AB' only at 4000h (48 / 64 kB
    // ROM from 0000h) -> 0000h; no header -> 4000h
    wire   [7:0] plain_id  = ab0 ? (hdr0[3][7:6] == 2'd2 ? FW_PLAIN_8000 :
                                    hdr0[3][7:6] == 2'd0 && {hdr0[3], hdr0[2]} != 16'h0000 ? FW_PLAIN_0000 : FW_PLAIN_4000) :
                             ab4 ? FW_PLAIN_0000 : FW_PLAIN_4000;

    always_ff @(posedge clk) begin
        logic [24:0] data_size;
        logic [7:0]  temp[8];
        logic [5:0]  block_num;
        logic [2:0]  head_addr, read_cnt;
        logic [27:0] save_addr, save_addr2;
        logic        ref_add, ref_sram_add, ref_dev_block, ref_dev_mem, set_offset, fix_offset;
        logic [1:0]  size, offset, ref_sram, mapper_param;
        logic [15:0] rom_fw_table;
        logic  [2:0] io_ref_mem, io_ref_mapper;
        mapper_typ_t mapper;
        device_t device;

        // Writes of this step into the tables and io_device: blocking temporaries with a
        // default, applied at the end of the block
        logic        lay_we, ram_we;
        logic  [5:0] lay_wa;
        logic  [3:0] ram_wa;
        logic [26:0] flash_used, flash_size;
        lay_t        lay_d;
        ram_t        ram_d;
        logic        dev_clr, dev_we_en, dev_we_port, dev_we_mask, dev_we_plo, dev_we_phi, dev_we_mref, dev_we_dref;
        logic  [4:0] dev_wt;
        logic  [1:0] dev_wk;
        logic  [7:0] dev_port, dev_mask, dev_param;
        logic  [2:0] dev_dref;
        device_t    last_device;
        logic [1:0] last_device_num;
        logic [2:0] current_io_ref_mapper;

        lay_we      = 1'b0;
        lay_wa      = {slot, subslot, block};
        lay_d       = lay_q0;
        ram_we      = 1'b0;
        ram_wa      = ref_ram;
        ram_d       = '0;
        flash_used  = ram_addr - ram_q.addr;                // BLOCK_FLASH: loaded part of its memory
        flash_size  = {conf[3][4:0], conf[4], 14'd0};
        dev_clr     = 1'b0;
        dev_we_en   = 1'b0;
        dev_we_port = 1'b0;
        dev_we_mask = 1'b0;
        dev_we_plo  = 1'b0;
        dev_we_phi  = 1'b0;
        dev_we_mref = 1'b0;
        dev_we_dref = 1'b0;
        dev_wt      = conf[3][4:0];
        dev_wk      = 2'd0;
        dev_port    = conf[3];
        dev_mask    = conf[4];
        dev_param   = conf[4];
        dev_dref    = current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;

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
                    ddr3_request        <= restart;
                    fdc_cart_used       <= '0;
                    ref_add             <= '0;
                    ref_sram_add        <= '0;
                    ref_sram            <= '0;
                    ref_ram             <= '0;
                    ram_addr            <= '0;
                    crc_en              <= '0;
                    fw_space            <= '0;
                    fw_mem              <= '0;
                    save_addr           <= '0;
                    save_addr2          <= '0;
                    kb_upload_memory.rq <= '0;
                    ref_dev_block       <= '0;
                    ref_dev_mem         <= '0;
                    set_offset          <= '0;
                    fix_offset          <= '0;
                    load_sram           <= '0;
                    if (restart) begin                      // start the upload; the core stays in reset
                        restart         <= 1'b0;
                        state           <= STATE_CLEAN;
                        $display("DO STATE_CLEAN");
                    end else begin
                        reset           <= '0;
                    end
                end
                STATE_RESET: begin
                    reset      <= '1;
                    state      <= STATE_IDLE;
                end
                STATE_CLEAN: begin
                    error <= ERR_NONE;
                    reset <= '1;
                    ddr3_request <= '1;
                    lay_we            = 1'b1;               // layout default: no mapper, offset = page
                    lay_wa            = block_num;
                    lay_d             = '0;
                    lay_d.offset_ram  = block_num[1:0];
                    lookup_SRAM[block_num[1:0]].size  <= '0;
                    main_ram.en                       <= '0;
                    slot_expander[block_num & 3].en   <= '0;
                    slot_expander[block_num & 3].wo   <= '1;
                    slot_expander[block_num & 3].init <= '0;

                    dev_clr = 1'b1;                         // all io_device entries to their default

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
                        // XML cpu_frequency 0 3.58, 1 5.39, 2 10.7 MHz -> msx_cpu clock_sel (01 10.7, 10 5.39)
                        msx_config.cpu_clock_sel <= {conf[3][2], conf[3][0], conf[3][1]};
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
                            current_io_ref_mapper <= lay_q0.device_ref;
                        end
                        CONF_LAYOUT:  begin
                            $display("  LOAD KBD LAYOUT");
                            kb_upload_memory.addr <= '0;
                            kb_upload_memory.rq   <= '1;
                            state                 <= STATE_LOAD_KBD_LAYOUT;
                        end
                        CONF_DEVICE:  begin
                            if (dev_slot_free) begin
                                dev_wt      = conf[1][4:0];
                                dev_wk      = dev_free[0] ? 2'd0 : dev_free[1] ? 2'd1 : 2'd2;
                                $display("LOAD IO_DEVICE[%x][%x] port:%x mask %x param %x size %x addr: %x (DDR addr %x)",
                                        device_t'(conf[1]), dev_wk, conf[2], conf[3], conf[4], {3'b0, conf[5], 14'd0}, ram_addr, ddr3_addr);
                                dev_we_en   = 1'b1;
                                dev_we_port = 1'b1;
                                dev_we_mask = 1'b1;
                                dev_we_plo  = 1'b1;
                                dev_we_phi  = 1'b1;
                                dev_port    = conf[2];
                                dev_mask    = conf[3];
                                dev_param   = conf[4];
                                if (conf[5] != 0) begin
                                    dev_we_mref = 1'b1;                     // mem_ref <= io_ref_mem
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
                                io_memory[io_ref_mem].memory      <= ram_q.addr + {5'b0, conf[7], 14'd0};
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
                            end else if (dev_slot_free) begin                             // no copy left: stays stopped
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
                                     , conf[3][5:4], conf[3][3:2], conf[3][1:0], lay_q0.ref_ram, ram_q.addr, ref_ram
                                     , ram_q.addr + {4'b0000, conf[4] == 8'd0, conf[4],14'd0}, {conf[5] == 8'd0, conf[5],14'd0});

                            ram_we                   = 1'b1;                       // copy of the reference + offset
                            ram_d.addr               = ram_q.addr + {4'b0000, conf[4] == 8'd0, conf[4],14'd0};
                            ram_d.size               = {8'd0, conf[5],1'b0};
                            ram_d.ro                 = conf[6][0];

                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            state                    <= STATE_SET_LAYOUT;
                        end
                        BLOCK_RAM: begin
                            $display("BLOCK RAM ref_RAM:%x addr:%x size %d ", ref_ram, ram_addr, {conf[3] == 8'd0, conf[3],14'd0});
                            ram_we                   = 1'b1;
                            ram_d.addr               = ram_addr;
                            ram_d.size               = {8'd0, conf[3],1'b0};
                            ram_d.ro                 = 1'b0;
                            fill_base                <= ram_addr[8:0];
                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            data_size                <= {2'b0, conf[3] == 8'd0, conf[3],14'd0};     // Velikost nahrávaných dat
                            pattern                  <= pattern_t'(conf[4]);
                            state                    <= STATE_FILL_RAM;
                        end
                        BLOCK_SRAM: begin
                            // lookup_SRAM entry: 0 - none (default of every block), 1 - cartridge
                            // slot A, 2 - slot B (ROM or FW pack), 3 - computer CMOS (not yet)
                            next_state <= STATE_LOAD_CONF;   // Defaultně neděláme nic
                            state <= STATE_READ_CONF;

                            if (fw_space) begin   // Zatím umíme pouze CART SRAM
                                if (ref_sram != 2'd0) begin
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
                            ram_we                   = 1'b1;
                            ram_d.addr               = ram_addr;
                            ram_d.ro                 = 1'b1;
                            mapper                   <= MAPPER_OFFSET;
                            offset                   <= '0;                        // Offset posunu RAM
                            set_offset               <= '1;                        // Nastav offset
                            ref_add                  <= '1;                        // Bude potřeba zvednout referenci
                            pattern                  <= PATTERN_DDR;
                            if (fw_space) begin                                    // Pokud se  bude jednat o ROM z FW musíme dle indexu najít adresu v DDR
                                fw_mem                   <= 1'b1;
                                $display("BLOCK FW ROM ID: %x ref_RAM:%x addr:%x size %d ", conf[3], ref_ram, ram_addr, {conf[4],conf[5],14'd0});
                                ram_d.size               = {conf[4],conf[5],1'b0};
                                data_size                <= {conf[4][2:0],conf[5],14'd0};
                                save_addr2               <= ddr3_addr - 1'b1;                    // Uložíme adresu pokračování -1 kvůli prefetch
                                ddr3_addr                <= DDR3_BASE_FW_ADDR + {12'b0, rom_fw_table} + {18'b0, conf[3],2'b00};
                                ddr3_rd                  <= '1;
                                state                    <= STATE_READ_CONF;                     // Jdeme přečíst ROM ADDR
                                next_state               <= STATE_READ_ADRFILL_FW_ROM;           // Pokračujeme nastavením ROM
                            end else begin
                                $display("BLOCK ROM ref_RAM:%x addr:%x size %d ", ref_ram, ram_addr, {conf[3],14'd0});
                                ram_d.size               = {8'd0, conf[3],1'b0};
                                data_size                <= {3'b0, conf[3],14'd0};   // Velikost nahrávaných dat
                                state                    <= STATE_FILL_RAM;
                            end
                        end
                        BLOCK_FLASH: begin
                            // The memory of the block is a flash chip of conf[3..4] x 16 kB: what
                            // was loaded stays at its start, the rest is erased. Only for the
                            // memory allocated last (a cartridge ROM), which is extended in place.
                            state      <= STATE_READ_CONF;
                            next_state <= STATE_LOAD_CONF;
                            if (ram_q.size == {3'd0, flash_used[26:13]} && flash_used < flash_size) begin
                                $display("BLOCK FLASH ref_RAM:%x addr:%x size %x, %x loaded", lay_q0.ref_ram, ram_q.addr, flash_size, flash_used);
                                ram_we      = 1'b1;
                                ram_wa      = lay_q0.ref_ram;
                                ram_d.addr  = ram_q.addr;
                                ram_d.size  = {conf[3], conf[4], 1'b0};
                                ram_d.ro    = ram_q.ro;
                                data_size   <= 25'(flash_size - flash_used);
                                pattern     <= PATTERN_FF;
                                state       <= STATE_FILL_RAM;
                                next_state  <= STATE_READ_CONF;
                            end
                        end
                        BLOCK_CART: begin
                            next_state <= STATE_LOAD_CONF;                          // Defaultně neděláme nic
                            state      <= STATE_READ_CONF;
                            $display("BLOCK CART ID:%d CONF:%x", conf[3][0], cart_conf[conf[3][0]].typ);
                            cart_id    <= conf[3][0];
                            fw_mem     <= 1'b0;
                            if (fdc_cart_off && !conf[3][0]) begin
                                $display("BLOCK CART 0 LEFT OUT: the machine has its own FDC");
                            end else if (cart_conf[conf[3][0]].typ == CART_TYP_ROM) begin
                                if (conf_rom_size > MSX::ROM_MAX) begin
                                    $display("BLOCK CART %d: ROM over the DDR3 area of its slot", conf[3][0]);
                                    error <= ERR_ROM_TOO_BIG;
                                    state <= STATE_STOP;
                                end else if (conf_rom_size > '0) begin
                                    $display("BLOCK CART %d LOAD START ref: %d addr:%x size:%x - %x", conf[3][0], ref_ram, ram_addr, conf_rom_size, conf_rom_size[26:14]);
                                    ram_we                   = 1'b1;
                                    ram_d.addr               = ram_addr;
                                    ram_d.size               = {3'b0, conf_rom_size[26:13]};
                                    ram_d.ro                 = 1'b1;
                                    state                    <= STATE_FILL_RAM;                                             // Načítáme ROM
                                    next_state               <= STATE_SEARCH_CRC32_INIT;                                    // Po nahrání budeme hledat CRC
                                    save_addr                <= ddr3_addr - 1'b1;                                           // Uchováme adresu -1 kvůli již načtenému prefetch bajtu
                                    ddr3_addr                <= conf[3][0] ? MSX::DDR3_ROM_B : MSX::DDR3_ROM_A;             // Adresa ROM v DDR
                                    data_size                <= conf_rom_size[24:0];                 // Velikost ROM
                                    ddr3_rd                  <= '1;                                                         // Prefetch
                                    ref_add                  <= '1;                                                         // Ukládáme referenci
                                    crc_en                   <= '1;                                                         // Počítáme CRC
                                    pattern                  <= PATTERN_DDR;                                                // Ukládáme z ROM
                                    ref_sram                 <= conf[3][0] ? 2'd2 : 2'd1;                                   // SRAM of its slot (entry 0 = none)
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
                            if (device_t'(conf[3]) == DEV_TC8566AF || device_t'(conf[3]) == DEV_WD2793) begin       // FDC: fixed position
                                if ((fw_space && cart_id) || !dev_ok[fdc_pos]) begin  // slot B, or not built at this position
                                    error       <= ERR_MISSING_SOURCE;
                                    state       <= STATE_IDLE;
                                    device      <= DEV_NONE;
                                    last_device <= DEV_NONE;
                                    $display("FDC %x NOT IN THIS BUILD (cartridge %0d, position %0d)", device_t'(conf[3]), fw_space ? cart_id + 1 : 0, fdc_pos);
                                end else if (fdc_busy && (fw_space || fdc_cart_used) && !fdc_cart_off) begin
                                    restart      <= 1'b1;                            // machine FDC + FDC cartridge:
                                    state        <= STATE_IDLE;                      // again without the cartridge
                                    fdc_cart_off <= 1'b1;
                                    device       <= DEV_NONE;
                                    last_device  <= DEV_NONE;
                                    $display("FDC %x: POSITION %0d HAS AN FDC, LOAD AGAIN WITHOUT CARTRIDGE A", device_t'(conf[3]), fdc_pos);
                                end else if (fdc_busy) begin                         // one FDC per position
                                    error       <= ERR_FDC_PRESENT;
                                    state       <= STATE_IDLE;
                                    device      <= DEV_NONE;
                                    last_device <= DEV_NONE;
                                    $display("FDC %x: POSITION %0d ALREADY HAS AN FDC", device_t'(conf[3]), fdc_pos);
                                end else begin
                                    dev_wk                = fdc_pos;
                                    dev_we_en             = 1'b1;
                                    dev_we_plo            = 1'b1;
                                    dev_we_phi            = 1'b1;
                                    dev_we_dref           = 1'b1;
                                    io_ref_mapper         <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                    current_io_ref_mapper <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                    last_device_num       <= fdc_pos;
                                    if (fw_space) fdc_cart_used <= 1'b1;
                                    $display("BLOCK IO_DEVICE[%x][%x] FDC enable: 1 param:%x reference %d", device_t'(conf[3]), fdc_pos, conf[4], current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper);
                                end
                            end else if (dev_slot_free) begin                       // first free synthesized copy
                                dev_wk                = dev_free[0] ? 2'd0 : dev_free[1] ? 2'd1 : 2'd2;
                                dev_we_en             = 1'b1;
                                dev_we_plo            = 1'b1;
                                dev_we_phi            = 1'b1;
                                dev_we_dref           = 1'b1;
                                io_ref_mapper         <= current_io_ref_mapper == '0 ? io_ref_mapper + 3'd1 : io_ref_mapper;
                                current_io_ref_mapper <= current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper;
                                last_device_num       <= dev_wk;
                                $display("BLOCK IO_DEVICE[%x][%x] enable: 1 param:%x reference: %d", device_t'(conf[3]), dev_wk, conf[4], current_io_ref_mapper == '0 ? io_ref_mapper : current_io_ref_mapper);
                                if (conf[5][0] && ~fw_mem) begin            // its ROM is not in the FW pack (MoonSound: yrw801.rom)
                                    dev_we_en   = 1'b0;
                                    dev_we_plo  = 1'b0;
                                    dev_we_phi  = 1'b0;
                                    dev_we_dref = 1'b0;
                                    error       <= ERR_NOT_FW_CONF;
                                    state       <= STATE_IDLE;
                                    device      <= DEV_NONE;
                                    last_device <= DEV_NONE;
                                    $display("DEVICE %x: NO MEMORY IN ITS BLOCK", device_t'(conf[3]));
                                end else if (conf[5][0]) begin              // the device uses the memory of its block (OPL4)
                                    dev_we_mref                       = 1'b1;
                                    io_memory[io_ref_mem].memory      <= ram_q.addr;
                                    io_memory[io_ref_mem].memory_size <= ram_q.size[8:1];
                                    io_ref_mem                        <= io_ref_mem + 3'd1;
                                    $display("  DEVICE MEMORY io_ref_mem:%x addr:%x size:%x", io_ref_mem, ram_q.addr, ram_q.size);
                                end
                            end else begin
                                error                 <= ERR_MISSING_SOURCE;                  // no synthesized copy left
                                state                 <= STATE_IDLE;
                                $display("DEVICE %x: NO COPY LEFT IN THIS BUILD", device_t'(conf[3]));
                                device                <= DEV_NONE;
                                last_device           <= DEV_NONE;
                            end
                        end
                        BLOCK_IO_DEVICE: begin
                            $display("BLOCK IO_DEVICE port:%x mask %x param %x (%d/%d/%d)", conf[3], conf[4], conf[5], slot, subslot, block);

                            dev_wt      = last_device;
                            dev_wk      = last_device_num;
                            dev_we_port = 1'b1;
                            dev_we_mask = 1'b1;
                            dev_we_plo  = 1'b1;
                            dev_we_phi  = 1'b1;
                            dev_port    = conf[3];
                            dev_mask    = conf[4];
                            dev_param   = conf[5];
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

                    lay_we = 1'b1;                          // read-modify-write of the block {slot, subslot, block}

                    if (ref_add) begin
                        lay_d.ref_ram = ref_ram;
                        $display("BLOCK slot:%x subslot:%x block:%x < reference:%x ", slot, subslot, block, ref_ram );
                    end

                    if (set_offset) begin
                        lay_d.offset_ram = offset;
                        $display("BLOCK slot:%x subslot:%x block:%x < offset:%x ", slot, subslot, block, offset );
                    end

                    if (mapper != MAPPER_NONE) begin
                        lay_d.mapper       = mapper;
                        lay_d.mapper_param = mapper_param;
                        if (mapper == MAPPER_PANASONIC_RAM) begin   // the RAM of this block (set by its RAM entry)
                            main_ram.en      <= 1'b1;
                            main_ram.ref_ram <= lay_q0.ref_ram;
                            $display("BLOCK slot:%x subslot:%x block:%x = main RAM ref:%x", slot, subslot, block, lay_q0.ref_ram);
                        end
                        $display("BLOCK slot:%x subslot:%x block:%x < mapper:%x", slot, subslot, block, mapper );
                    end

                    if (conf_t'(conf[0]) == CONF_BLOCK && block_t'(conf[2]) == BLOCK_CART)  begin
                        lay_d.cart_num = conf[3][0];
                        $display("BLOCK slot:%x subslot:%x block:%x < cart_num:%x", slot, subslot, block, conf[3][0] );
                    end

                    if (ref_sram_add)  begin
                        lay_d.ref_sram = ref_sram;
                        $display("BLOCK slot:%x subslot:%x block:%x < ref_sram:%x", slot, subslot, block, ref_sram );
                    end

                    if (device != DEV_NONE) begin
                        lay_d.device_ref = current_io_ref_mapper;
                        $display("BLOCK slot:%x subslot:%x block:%x < device REF:%d ", slot, subslot, block, current_io_ref_mapper);
                    end

                    if (ref_dev_block) begin
                        lay_d.device_ref = lay_q1.device_ref;
                        $display("BLOCK slot:%x subslot:%x block:%x < device ref:%d ", slot, subslot, block, lay_q1.device_ref );
                        ref_dev_block <= '0;
                    end

                    if (ref_dev_mem) begin
                        lay_d.ref_ram      = lay_q1.ref_ram;
                        lay_d.mapper       = lay_q1.mapper;
                        lay_d.mapper_param = lay_q1.mapper_param;
                        lay_d.offset_ram   = lay_q1.offset_ram;
                        $display("BLOCK slot:%x subslot:%x block:%x < reference:%x ", slot, subslot, block, lay_q1.ref_ram);
                        $display("BLOCK slot:%x subslot:%x block:%x < offset:%x ", slot, subslot, block, lay_q1.offset_ram);
                        $display("BLOCK slot:%x subslot:%x block:%x < mapper:%x ", slot, subslot, block, lay_q1.mapper);
                        ref_dev_mem <= '0;
                    end

                    if (device == DEV_TC8566AF || device == DEV_WD2793) begin  // drive pair of the controller
                        dev_wt     = device;
                        dev_wk     = last_device_num;
                        dev_we_phi = 1'b1;
                        dev_param[7:6] = fw_space ? 2'd0 : 2'd2;           // placement: cartridge A / internal
                        if (last_device_num[0]) msx_config.fdd[3:2] <= conf[4][3:2];
                        else                    msx_config.fdd[1:0] <= conf[4][3:2];
                        $display("Change FDD layout. Position %0d (%s): %x", last_device_num, fw_space ? "cartridge A" : "internal", conf[4][3:2]);
                    end
                end
                STATE_SEARCH_CRC32_INIT: begin
                    if (ioctl_size[size_CRC] == 0) begin
                        crc_en <= 1'b0;
                        if (plain_ok && ioctl_size[size_FW_PACK] > '0) begin
                            $display("NO CRC32 DB: plain ROM, FW conf %0d", plain_id);
                            ddr3_addr  <= 28'h300010 + {18'b0, plain_id, 2'b00};
                            ddr3_rd    <= '1;
                            read_cnt   <= 4;
                            fw_space   <= '1;
                            state      <= STATE_READ_CONF;
                            next_state <= STATE_GET_FW_ADDR;
                        end else begin
                            $display("NO CRC32 DB");
                            ddr3_addr <= save_addr;
                            ddr3_rd   <= '1;
                            error     <= plain_ok ? ERR_NOT_FW_CONF : ERR_NO_CRC_DB;
                            state     <= STATE_STOP;
                        end
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
                            if (plain_ok && ioctl_size[size_FW_PACK] > '0) begin                    // plain ROM
                                $display("NOT FIND CRC32: %x, plain ROM, FW conf %0d", rom_crc32, plain_id);
                                ddr3_addr  <= 28'h300010 + {18'b0, plain_id, 2'b00};
                                ddr3_rd    <= '1;
                                read_cnt   <= 4;
                                fw_space   <= '1;
                                state      <= STATE_READ_CONF;
                                next_state <= STATE_GET_FW_ADDR;
                            end else begin
                                $display("NOT FIND CRC32: %x", rom_crc32);
                                ddr3_addr <= save_addr;
                                ddr3_rd   <= '1;
                                error     <= plain_ok ? ERR_NOT_FW_CONF : ERR_NO_CRC_FOUND;
                                state     <= STATE_STOP;
                            end
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

        // A load request ends whatever is running and starts over through STATE_IDLE, which
        // takes all working registers to their start values. After the state machine, so that
        // it wins over the transition of this step.
        if (load) begin
            restart      <= 1'b1;
            state        <= STATE_IDLE;
            fdc_cart_off <= 1'b0;
        end

        // table and io_device writes of this step
        if (lay_we) begin
            lay_slots[lay_wa] <= lay_d;
            lay_fsm0[lay_wa]  <= lay_d;
            lay_fsm1[lay_wa]  <= lay_d;
        end
        if (ram_we) begin
            ram_slots[ram_wa] <= ram_d;
            ram_main[ram_wa]  <= ram_d;
            ram_fsm[ram_wa]   <= ram_d;
        end
        // io_device command of this step, applied one clock later by the registers below
        dev_clr_q   <= dev_clr;
        dev_we_q    <= {dev_we_dref, dev_we_mref, dev_we_phi, dev_we_plo, dev_we_mask, dev_we_port, dev_we_en};
        dev_wt_q    <= dev_wt;
        dev_wk_q    <= dev_wk;
        dev_port_q  <= dev_port;
        dev_mask_q  <= dev_mask;
        dev_param_q <= dev_param;
        dev_mref_q  <= io_ref_mem;
        dev_dref_q  <= dev_dref;
    end

    // io_device registers: common clear, one entry written per command, per field. Nothing
    // but the enable bits is read back, so the synthesis keeps only what the devices use.
    generate
        for (gt = 0; gt < 32; gt++) begin : g_dev
            for (gk = 0; gk < 3; gk++) begin : g_copy
                wire sel = dev_wt_q == gt && dev_wk_q == gk;
                always @(posedge clk) begin
                    if (dev_clr_q) begin
                        io_device[gt][gk].enable     <= '0;
                        io_device[gt][gk].port       <= '1;
                        io_device[gt][gk].mask       <= '0;
                        io_device[gt][gk].param      <= '0;
                        io_device[gt][gk].mem_ref    <= '0;
                        io_device[gt][gk].device_ref <= '0;
                    end else if (sel) begin
                        if (dev_we_q[0]) io_device[gt][gk].enable     <= 1'b1;
                        if (dev_we_q[1]) io_device[gt][gk].port       <= dev_port_q;
                        if (dev_we_q[2]) io_device[gt][gk].mask       <= dev_mask_q;
                        if (dev_we_q[3]) io_device[gt][gk].param[5:0] <= dev_param_q[5:0];
                        if (dev_we_q[4]) io_device[gt][gk].param[7:6] <= dev_param_q[7:6];
                        if (dev_we_q[5]) io_device[gt][gk].mem_ref    <= dev_mref_q;
                        if (dev_we_q[6]) io_device[gt][gk].device_ref <= dev_dref_q;
                    end
                end
            end
        end
    endgenerate

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
