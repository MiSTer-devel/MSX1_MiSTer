// package
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

typedef enum logic [3:0] {DEVICE_NONE, DEVICE_ROM } device_typ_t;
typedef enum logic {CAS_AUDIO_FILE,CAS_AUDIO_ADC} cas_audio_src_t;
typedef enum logic [1:0] {Z80, R800, UNKN1, UNKN2} cpu_t;

typedef enum logic [3:0] {CART_TYP_SCC, CART_TYP_SCC2, CART_TYP_FM_PAC, CART_TYP_MFRSD, CART_TYP_GM2, CART_TYP_FDC, CART_MEGASCC1, CART_MEGASCC2, CART_MEGA_ASCII_8, CART_MEGA_ASCII_16, MEGARAM, CART_TYP_ROM, CART_TYP_EMPTY, CART_TYP_MOONSOUND } cart_typ_t;
typedef enum logic [4:0] {DEV_NONE, DEV_OPLL, DEV_SCC, DEV_WD2793, DEV_MSX2_RAM, DEV_LATCH_PORT, DEV_KANJI, DEV_OCM_BOOT, DEV_VDP_TMS, DEV_VDP_V99xx, DEV_RTC, DEV_PSG, DEV_PPI, DEV_RESET_STATUS, DEV_TC8566AF, DEV_OPM, DEV_YM2148, DEV_DAC, DEV_SYSTIMER, DEV_S1990, DEV_TURBOR_PCM, DEV_TURBOR_PAUSE, DEV_OPL4 } device_t;
typedef enum logic [5:0] {MAPPER_NONE, MAPPER_OFFSET, MAPPER_ASCII16, MAPPER_RTYPE, MAPPER_ASCII8, MAPPER_KOEI, MAPPER_WIZARDY, MAPPER_KONAMI, 
                          MAPPER_FMPAC, MAPPER_GM2, VY0010, MAPPER_KONAMI_SCC, MAPPER_MSX2, MAPPER_GENERIC16KB, MAPPER_CROSS_BLAIM, MAPPER_GENERIC8KB, 
                          MAPPER_HARRY_FOX, MAPPER_ZEMINA_80, MAPPER_ZEMINA_90, MAPPER_KONAMI_SCC_PLUS, 
                          MAPPER_MFRSD3, MAPPER_MFRSD2, MAPPER_MFRSD1, MAPPER_MFRSD0, 
                          MAPPER_NATIONAL, MAPPER_ESE_RAM, 
                          MAPPER_MEGARAM, MAPPER_MEGASCC, MAPPER_MEGAASCII8, MAPPER_MEGAASCII16,
                          MAPPER_TURBO_R_FDC,
                          MAPPER_YAMAHA_SFG,MAPPER_MIRROR,
                          MAPPER_SUPERSWANGI,
                          MAPPER_MSXWRITE,
                          MAPPER_OCM_IPL,
                          MAPPER_PANASONIC, MAPPER_PANASONIC_RAM, MAPPER_DRAM,
                          MAPPER_ASCII16X,
                          MAPPER_HIDDEN,          // no mapper module: memory of the block is not on the CPU bus (MoonSound)
                          MAPPER_NEO8, MAPPER_NEO16,
                          MAPPER_UNUSED} mapper_typ_t;
typedef enum logic [3:0] {BLOCK_RAM, BLOCK_ROM, BLOCK_SRAM, BLOCK_DEVICE, BLOCK_MAPPER, BLOCK_CART, BLOCK_REF_MEM, BLOCK_REF_DEV, BLOCK_IO_DEVICE, BLOCK_EXPANDER, BLOCK_REF_SHARED_MEM, BLOCK_FLASH} block_t;
typedef enum logic [2:0] {CONF_BLOCK, CONF_DEVICE, CONF_LAYOUT, CONF_CARTRIGE, CONF_BLOCK_FW, CONF_UNUSED5, CONF_UNUSED6, CONF_END} conf_t;
typedef enum logic [3:0] {ERR_NONE, ERR_BAD_MSX_CONF, ERR_NOT_SUPPORTED_CONF, ERR_NOT_SUPPORTED_BLOCK, ERR_BAD_MSX_FW_CONF, ERR_NOT_FW_CONF, ERR_DEVICE_MISSING, ERR_MISSING_SOURCE, ERR_NO_CRC_DB, ERR_NO_CRC_FOUND, ERR_NO_MEMORY, ERR_FDC_PRESENT, ERR_ROM_TOO_BIG} error_t;

interface cpu_regs_if();
    wire [15:0] AF;
    wire [15:0] BC;
    wire [15:0] DE;
    wire [15:0] HL;
    wire [15:0] AF2;
    wire [15:0] BC2;
    wire [15:0] DE2;
    wire [15:0] HL2;
    wire [15:0] IX;
    wire [15:0] IY;
    wire [15:0] PC;
    wire [15:0] SP;
    wire change;
endinterface

interface clock_bus_if(
    input     clk,
    input     clk_mem
);
    wire     ce_10m7_p;
    wire     ce_10m7_n;
    wire     ce_5m39_p;
    wire     ce_5m39_n;   
    wire     ce_3m58_p;
    wire     ce_3m58_n;
    wire     ce_7m16_n;   // R800 (turbo R)
    wire     ce_1m79_n;
    wire     ce_1k;
    wire     ce_10hz;

    modport generator_mp (
        input   clk,
        input   clk_mem,
        output  ce_10m7_p,
        output  ce_10m7_n,
        output  ce_5m39_p,
        output  ce_5m39_n,   
        output  ce_3m58_p,
        output  ce_3m58_n,
        output  ce_7m16_n,
        output  ce_1m79_n,
        output  ce_1k,
        output  ce_10hz
    );

    modport base_mp (
        input   clk,
        input   clk_mem,
        input   ce_10m7_p,
        input   ce_10m7_n,
        input   ce_5m39_p,
        input   ce_5m39_n,   
        input   ce_3m58_p,
        input   ce_3m58_n,
        input   ce_7m16_n,
        input   ce_1m79_n,
        input   ce_1k,
        input   ce_10hz
    );

endinterface

interface block_device_if;
   wire        rd;
   wire        wr;
   wire        ack;
   wire [31:0] lba;
   wire  [5:0] blk_cnt;
   wire  [7:0] buff_din;
   wire  [7:0] buff_dout;
   wire [13:0] buff_addr;
   wire        buff_wr;
   wire        img_mounted;
   wire [63:0] img_size;
   wire        img_readonly;

   modport hps_mp (
        input   rd,
        input   wr,
        output  ack,
        input   lba,
        input   blk_cnt,
        input   buff_din,
        output  buff_dout,
        output  buff_addr,
        output  buff_wr,
        output  img_mounted,
        output  img_size,
        output  img_readonly
   );
   modport device_mp (
        output  rd,
        output  wr,
        input   ack,
        output  lba,
        output  blk_cnt,
        output  buff_din,
        input   buff_dout,
        input   buff_addr,
        input   buff_wr,
        input   img_mounted,
        input   img_size,
        input   img_readonly
   );
endinterface


interface FDD_if();
    wire       USEL;
    wire       MOTORn;
    wire       READYn;
    wire       STEPn;
    wire       SDIRn;   
    wire       SIDEn;
    wire       INDEXn;
    wire       TRACK0n;
    wire       WPROTn;
    wire       READ_DATAn;
    wire       WRITE_GATEn;  // 0 = the controller writes; READ_DATA is silent meanwhile
    wire       WRITE_DATAn;  // flux transitions from the controller (falling edge)
    wire       MFM;          // encoding of the controller (1 MFM, 0 FM): emulation only, the drive
                             // regenerates the track from sectors (WD279x DDEN, TC8566AF MF bit)
    wire [1:0] DSKCHGn;     // per drive: 0 = disk changed since DSKCHG_ACK (turbo R FDCHG1/2)
    wire [1:0] DSKCHG_ACK;  // per drive: the controller has read the change (openMSX: read clears)

    modport FDD_mp (
        input   USEL,
        input   MOTORn,
        output  READYn,
        input   STEPn,
        input   SDIRn,
        input   SIDEn,
        output  INDEXn,
        output  TRACK0n,
        output  WPROTn,
        output  READ_DATAn,
        input   WRITE_GATEn,
        input   WRITE_DATAn,
        input   MFM,
        output  DSKCHGn,
        input   DSKCHG_ACK
    );

    modport FDC_mp (
        output  USEL,
        output  MOTORn,
        input   READYn,
        output  STEPn,
        output  SDIRn,
        output  SIDEn,
        input   INDEXn,
        input   TRACK0n,
        input   WPROTn,
        input   READ_DATAn,
        output  WRITE_GATEn,
        output  WRITE_DATAn,
        output  MFM,
        input   DSKCHGn,
        output  DSKCHG_ACK
    );

endinterface

interface cpu_bus_if(
    input       clk,
    input       reset
);
    wire        mreq;
    wire        iorq;
    wire        rd;
    wire        wr;
    wire        m1;
    wire        halt;
    wire        rfsh;
    wire [15:0] addr;
    wire  [7:0] data;
    wire        req;
    wire        int_rq;

    modport cpu_mp (
        input   clk,
        input   reset,
        output  mreq,
        output  iorq,
        output  rd,
        output  wr,
        output  m1,
        output  halt,
        output  rfsh,
        output  addr,
        output  data,
        output  req,
        output  int_rq
    );
    
    modport device_mp (
        input   clk,
        input   reset,
        input   mreq,
        input   iorq,
        input   rd,
        input   wr,
        input   m1,
        input   halt,
        input   rfsh,
        input   addr,
        input   data,
        input   req,
        input   int_rq
    );

endinterface

interface ext_sd_card_if;
    logic        rx;
    logic        tx;
    logic  [7:0] data_to_SD;
    logic  [7:0] data_from_SD;
    logic        busy;              // SPI transfer running (16 clk per byte)
    
    modport SD_mp (
        output  data_from_SD,
        output  busy,
        input   data_to_SD,
        input   rx,
        input   tx
    );

    modport device_mp (
        input    data_from_SD,
        input    busy,
        output   data_to_SD,
        output   rx,
        output   tx
    );
endinterface

interface flash_bus_if;
    logic [26:0] base_addr;     // system address = addr - base_addr (block may lie above 8 MB)
    logic [22:0] addr;          // address in the chip
    logic [22:0] area_lo;       // part of the chip backed by memory: area_lo .. area_lo + area_size - 1
    logic [23:0] area_size;
    logic        chip;          // 0 = M29W640GB (MFRSD), 1 = S29GL064S (ASCII16-X)
    logic        id;            // cartridge (slot A / B)
    logic  [7:0] data_to_flash;
    logic  [7:0] data_from_flash;
    logic        data_valid;
    logic        we;
    logic        ce;

    modport flash_mp (
        input  base_addr,
        input  addr,
        input  area_lo,
        input  area_size,
        input  chip,
        input  id,
        input  data_to_flash,
        output data_from_flash,
        output data_valid,
        input  we,
        input  ce
    );

    modport device_mp (
        output base_addr,
        output addr,
        output area_lo,
        output area_size,
        output chip,
        output id,
        output data_to_flash,
        input  data_from_flash,
        input  data_valid,
        output we,
        output ce
    );
endinterface


interface vram_bus_if;
    logic   [7:0] q_lo;
    logic   [7:0] q_hi;
    logic  [15:0] addr;
    logic   [7:0] data;
    logic         we_lo;
    logic         we_hi;

    modport device_mp (
        output addr, data, we_lo, we_hi,
        input  q_lo, q_hi
    );
    modport vram_mp (
        input  addr, data, we_lo, we_hi,
        output q_lo, q_hi
    );

endinterface

interface memory_bus_if;
    logic [26:0] addr;
    logic [7:0]  data;
    logic [7:0]  q;
    logic        rnw;
    logic        sram_cs;
    logic        ram_cs;
    logic        sdram_ready;
    logic        sdram_done;
    modport device_mp (
        output   addr,data,rnw,sram_cs,ram_cs,
        input    q,sdram_ready,sdram_done
    );
    modport ram_mp (
        input    addr,data,rnw,sram_cs,ram_cs,
        output   q,sdram_ready,sdram_done
    );
endinterface

// Sample memory of the OPL4 (MoonSound): system address, word read or byte write
interface wave_bus_if;
    logic        req;           // held until ack
    logic        we;
    logic [26:0] addr;
    logic  [7:0] wdata;
    logic        ack;           // one clk
    logic [15:0] rdata;         // bytes at the even (7:0) and odd (15:8) address of the word

    modport device_mp (
        output req, we, addr, wdata,
        input  ack, rdata
    );
    modport ram_mp (
        input  req, we, addr, wdata,
        output ack, rdata
    );
endinterface

interface sd_bus;
   logic          ack;
   logic   [13:0] buff_addr;
   logic    [7:0] buff_data;
   logic          buff_wr;
endinterface

interface sd_bus_control;
   logic         rd;
   logic         wr;
   logic  [31:0] sd_lba;
   logic   [7:0] buff_data;
endinterface

package MSX;

    // One-directional bundles (driver -> readers) between slots, mappers and devices.
    // Inactive values are neutral for the wired-AND / OR merge (*_merge below).
    typedef struct packed {
        logic [26:0] addr;      // '1 when inactive (AND)
        logic        rnw;       // 1 when inactive (AND)
        logic        ram_cs;    // OR
        logic        sram_cs;   // OR
        logic        main_cs;   // OR; addr is an offset in the main RAM (turbo R)
        logic  [7:0] data;      // FF when inactive (AND)
    } mapper_out_t;            // mapper -> mappers.sv

    typedef struct packed {
        logic [24:0] rom_size;
        logic [15:0] sram_size;
        logic  [1:0] offset_ram;
        logic [26:0] base_ram;
        logic  [2:0] device_ref;
        mapper_typ_t typ;
        logic        id;
        logic  [1:0] mapper_param;   // per block, from the pack (DRAM: first 16 KB page of the top 64 KB)
        logic [16:0] main_ram_size;  // main RAM in 8 KB blocks, 0 = none (turbo R)
        logic        dram;           // turbo R S1990: ROM read from the top 64 KB of the main RAM
    } block_info_t;            // msx_slots -> mappers, devices (active block of the access)

    typedef struct packed {
        logic  [2:0] device_ref;
        logic        we;        // OR
        logic        en;        // OR
        logic        mode;      // 1 when inactive (AND)
        logic        param;     // 1 when inactive (AND)
    } device_bus_t;            // mappers (cartridge devices) -> devices

    typedef struct packed {
        logic  [7:0] R, G, B;
        logic        DE, HS, VS, hblank, vblank, ce_pix;
    } video_t;                 // VDP -> video output; inactive VDP drives 0 (OR merge)

    typedef struct packed {
        logic        en;        // 1 = overrides the static speed from msx_config
        logic  [1:0] clock_sel; // msx_cpu encoding: 00 3.58, 01 10.7, 10 5.39 MHz
        logic  [3:0] mem_wait;  // wait states on each memory access
        logic  [3:0] io_wait;   // extra wait states on each I/O access
    } cpu_speed_t;             // devices (OCM turbo) -> msx_cpu; '0 = no override

    // Inactive (neutral) values and pairwise merge of the bundles above.
    localparam mapper_out_t MAPPER_OUT_IDLE = {27'h7FFFFFF, 1'b1, 1'b0, 1'b0, 1'b0, 8'hFF};
    localparam device_bus_t DEVICE_BUS_IDLE = {3'd0, 1'b0, 1'b0, 1'b1, 1'b1};

    function automatic mapper_out_t mapper_out_merge(input mapper_out_t a, input mapper_out_t b);
        mapper_out_t r;
        r.addr    = a.addr    & b.addr;
        r.rnw     = a.rnw     & b.rnw;
        r.ram_cs  = a.ram_cs  | b.ram_cs;
        r.sram_cs = a.sram_cs | b.sram_cs;
        r.main_cs = a.main_cs | b.main_cs;
        r.data    = a.data    & b.data;
        return r;
    endfunction

    function automatic device_bus_t device_bus_merge(input device_bus_t a, input device_bus_t b);
        device_bus_t r;
        r.device_ref = a.device_ref | b.device_ref;
        r.we         = a.we         | b.we;
        r.en         = a.en         | b.en;
        r.mode       = a.mode       & b.mode;
        r.param      = a.param      & b.param;
        return r;
    endfunction

    typedef struct {
        logic           border;
        cas_audio_src_t cas_audio_src;
        logic           tape_monitor;   // tape signal in the sound output while the motor runs
        logic     [7:0] ocm_dip;
        logic           joy_swap;       // OCM: swap joystick ports
        logic           mouse_port;     // OCM: PS/2 mouse on port 1 (0) / 2 (1)
        logic           ocm_r800;       // OCM: CPU type R800 (MULUB / MULUW)
        logic           turbor_firmware; // turbo R: firmware switch on (S1990 register 5)
        logic           osd_pause;      // OSD open and "Pause when OSD open" on
    } user_config_t;    
    
    typedef struct {
        logic       en;
        logic       wo;
        logic [7:0] init;
    } slot_expander_t; 
    
    typedef struct {
        logic  [3:0] ref_ram;
        logic  [1:0] ref_sram;
        logic  [1:0] offset_ram;
        logic  [2:0] device_ref;
        mapper_typ_t mapper;
        logic  [1:0] mapper_param;
        logic        cart_num;
        logic        external;
    } block_t;    
    
    typedef struct {
        logic [26:0] addr;
        logic [16:0] size;
        logic        ro;
    } lookup_RAM_t;
    
    typedef struct {
        logic [26:0] addr;
        logic [15:0] size;
    } lookup_SRAM_t;

    typedef struct packed {
        logic        en;
        logic  [3:0] ref_ram;   // lookup_RAM entry of the main RAM
    } main_ram_t;              // memory_upload -> msx_slots (turbo R: mapper PANASONIC_RAM)

    typedef struct {
        cart_typ_t   typ;
    } config_cart_t;

    typedef struct {
        logic [7:0] mask; 
        logic [7:0] port;
        logic [7:0] param;
        logic [2:0] mem_ref;
        logic [2:0] device_ref;
        logic       enable;
    } io_device_t;

    typedef struct {
        logic [26:0] memory;
        logic  [7:0] memory_size;
    } io_device_mem_ref_t;

    typedef struct {
        logic isConfigRegDisabled;
        logic isMemoryMapperEnabled;
        logic isDSKmodeEnabled;
        logic isPSGalsoMappedToNormalPorts;
        logic isSlotExpanderEnabled;
        logic isFlashRomBlockProtectEnabled;
        logic isFlashRomWriteEnabled;
    } mfrsd_config_t;

    typedef struct {
       logic [8:0] addr;
       logic [7:0] data;
       logic       we;
       logic       rq;
    } kb_memory_t;

    typedef struct {
        cpu_t cpu;
        logic [2:0] wait_count;
        logic [2:0] cpu_clock_sel;
        logic [5:0] fdd;        // drives shown in the OSD, a bit pair per FDC position (2*N_FDC used)
    } msx_config_t;

    // clk_core frequency in Hz (pll outclk_1). The only place it is defined.
    localparam int CLK_CORE_HZ = 21477270;

    // DDR3 areas of the OSD files, offset from 0x30000000 (ddram.sv). The HPS writes a file
    // whole at its address: the load addresses in CONF_STR (MSX1.sv) must be these.
    // Map and sizes: doc/konfigurace.md "Oblasti v DDR3".
    localparam logic [27:0] DDR3_ROM_PACK = 28'h0000000;   //  3 MB
    localparam logic [27:0] DDR3_FW_PACK  = 28'h0300000;   // 19 MB
    localparam logic [27:0] DDR3_DB       = 28'h1600000;   //  1 MB  mapper database (CRC32)
    localparam logic [27:0] DDR3_CAS      = 28'h1700000;   //  9 MB
    localparam logic [27:0] DDR3_ROM_A    = 28'h2000000;   // 16 MB
    localparam logic [27:0] DDR3_ROM_B    = 28'h3000000;   // 16 MB
    localparam logic [26:0] ROM_MAX       = 27'h1000000;   // larger ROM: ERR_ROM_TOO_BIG

    // System memory below 2^BRAM_WIDTH is BRAM in the FPGA, the rest SDRAM (system_memory).
    localparam int BRAM_WIDTH = 18;

    // ---------------------------------------------------------------- synthesized copies
    // The one place to set how many copies of a device are built (io_device keeps 3 slots
    // per type). Values = what the machine XMLs and the OSD cartridges need, see
    // doc/pocty-zarizeni.md. memory_upload stops a configuration needing more copies with
    // ERR_MISSING_SOURCE ("Device not in this core build").
    localparam int N_OPLL         = 2;      // 0..3  machine + FM-PAC, or FM-PAC in A and B
    localparam int N_OPM          = 1;      // 0..3
    localparam int N_SCC          = 2;      // 0..2
    localparam int N_PSG          = 1;      // 0..3
    localparam int N_DAC          = 2;      // 0..3  Synthesizer ROM in A and B
    localparam int N_LATCH_PORT   = 2;      // 0..3  Zemina90 ROM in A and B
    localparam int N_MEM_MAPPER   = 2;      // 0..3  machine + MFRSD in slot A
    localparam int N_RESET_STATUS = 1;      // 0..3
    localparam int N_OPL4         = 1;      // 0..1  MoonSound cartridge
    // Floppy controller positions, each with a WD2793 and an FDD unit (2 drives):
    // 0 = internal (machine XML), 1 = cartridge in slot A. With N_FDC = 1 the cartridge
    // takes position 0 and only when the machine has no FDC (ERR_FDC_PRESENT). FDC
    // cartridges go to slot A only. N_FDC = 2 also needs the S3/S4 drive items in CONF_STR.
    localparam int N_FDC          = 1;      // 1..2
    localparam int N_TC8566AF     = 1;      // 0..1, position 0 only
    // Every other device type is a single copy.

    // Sound of one device type: sum of up to 3 instances x 16 bit signed, no overflow.
    // Clipped only once, in sound_mix.
    typedef logic signed [17:0] sound_t;

    function automatic logic [2:0] cnt_mask(input int n);
        return n >= 3 ? 3'b111 : n == 2 ? 3'b011 : n == 1 ? 3'b001 : 3'b000;
    endfunction

    // Synthesized copies of a device type: bit k = io_device[type][k] has hardware
    function automatic logic [2:0] dev_slots(input device_t d);
        case (d)
            DEV_OPLL:         return cnt_mask(N_OPLL);
            DEV_OPM:          return cnt_mask(N_OPM);
            DEV_SCC:          return cnt_mask(N_SCC);
            DEV_PSG:          return cnt_mask(N_PSG);
            DEV_DAC:          return cnt_mask(N_DAC);
            DEV_LATCH_PORT:   return cnt_mask(N_LATCH_PORT);
            DEV_MSX2_RAM:     return cnt_mask(N_MEM_MAPPER);
            DEV_RESET_STATUS: return cnt_mask(N_RESET_STATUS);
            DEV_OPL4:         return cnt_mask(N_OPL4);
            DEV_WD2793:       return cnt_mask(N_FDC);
            DEV_TC8566AF:     return cnt_mask(N_TC8566AF);
            default:          return 3'b001;
        endcase
    endfunction

endpackage
