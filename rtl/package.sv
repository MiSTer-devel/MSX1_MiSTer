typedef enum logic [3:0] {DEVICE_NONE, DEVICE_ROM } device_typ_t;
typedef enum logic {CAS_AUDIO_FILE,CAS_AUDIO_ADC} cas_audio_src_t;
typedef enum logic [1:0] {Z80, R800, UNKN1, UNKN2} cpu_t;

typedef enum logic [3:0] {CART_TYP_SCC, CART_TYP_SCC2, CART_TYP_FM_PAC, CART_TYP_MFRSD, CART_TYP_GM2, CART_TYP_FDC, CART_MEGASCC1, CART_MEGASCC2, CART_MEGA_ASCII_8, CART_MEGA_ASCII_16, MEGARAM, CART_TYP_ROM, CART_TYP_EMPTY } cart_typ_t;
typedef enum logic [4:0] {DEV_NONE, DEV_OPLL, DEV_SCC, DEV_WD2793, DEV_MSX2_RAM, DEV_LATCH_PORT, DEV_KANJI, DEV_OCM_BOOT, DEV_VDP_TMS, DEV_VDP_V99xx, DEV_RTC, DEV_PSG, DEV_PPI, DEV_RESET_STATUS, DEV_TC8566AF, DEV_OPM, DEV_YM2148, DEV_DAC } device_t;
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
                          MAPPER_UNUSED} mapper_typ_t;
typedef enum logic [3:0] {BLOCK_RAM, BLOCK_ROM, BLOCK_SRAM, BLOCK_DEVICE, BLOCK_MAPPER, BLOCK_CART, BLOCK_REF_MEM, BLOCK_REF_DEV, BLOCK_IO_DEVICE, BLOCK_EXPANDER, BLOCK_REF_SHARED_MEM} block_t;
typedef enum logic [2:0] {CONF_BLOCK, CONF_DEVICE, CONF_LAYOUT, CONF_CARTRIGE, CONF_BLOCK_FW, CONF_UNUSED5, CONF_UNUSED6, CONF_END} conf_t;
typedef enum logic [3:0] {ERR_NONE, ERR_BAD_MSX_CONF, ERR_NOT_SUPPORTED_CONF, ERR_NOT_SUPPORTED_BLOCK, ERR_BAD_MSX_FW_CONF, ERR_NOT_FW_CONF, ERR_DEVICE_MISSING, ERR_MISSING_SOURCE, ERR_NO_CRC_DB, ERR_NO_CRC_FOUND, ERR_NO_MEMORY} error_t;

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
        output  READ_DATAn
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
        input   READ_DATAn
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
    
    modport SD_mp (
        output  data_from_SD,
        input   data_to_SD,
        input   rx,
        input   tx
    );

    modport device_mp (
        input    data_from_SD,
        output   data_to_SD,
        output   rx,
        output   tx
    );
endinterface

interface flash_bus_if;
    logic [22:0] base_addr;
    logic [22:0] addr;
    logic  [7:0] data_to_flash;
    logic  [7:0] data_from_flash;
    logic        data_valid;
    logic        we;
    logic        ce;

    modport flash_mp (
        input  base_addr,
        input  addr,
        input  data_to_flash,
        output data_from_flash,
        output data_valid,
        input  we,
        input  ce
    );

    modport device_mp (
        output base_addr,
        output addr,
        output data_to_flash,
        input  data_from_flash,
        input  data_valid,
        output we,
        output ce
    );
endinterface

interface video_bus_if;
    logic  [7:0] R;
    logic  [7:0] G;
    logic  [7:0] B;
    logic        DE;
    logic        HS;
    logic        VS;
    logic        hblank;
    logic        vblank;
    logic        ce_pix;

    modport device_mp (
        output R, G, B, DE, HS, VS, hblank, vblank, ce_pix
    );
    modport display_mp (
        input R, G, B, DE, HS, VS, hblank, vblank, ce_pix
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

interface device_bus;
    logic [2:0] device_ref;
    logic       we;
    logic       en;
    logic       mode;
    logic       param;
    logic [7:0] data;
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

interface mapper_out;
    logic [26:0] addr;
    logic        rnw;
    logic        ram_cs;
    logic        sram_cs;
    logic  [7:0] data;
endinterface

interface block_info;
    logic [24:0] rom_size;
    logic [15:0] sram_size;
    logic  [1:0] offset_ram;
    logic [26:0] base_ram;
    logic [2:0]  device_ref;
    mapper_typ_t typ;
    logic        id;
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
    
    typedef struct {
        logic [15:0] AF;
        logic [15:0] BC;
        logic [15:0] DE;
        logic [15:0] HL;
        logic [15:0] AF2;
        logic [15:0] BC2;
        logic [15:0] DE2;
        logic [15:0] HL2;
        logic [15:0] IX;
        logic [15:0] IY;
        logic [15:0] PC;
        logic [15:0] SP;
    } cpu_regs_t; 

    typedef struct {
        logic           border;
        cas_audio_src_t cas_audio_src;
        logic     [7:0] ocm_dip;
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
        logic [5:0] fdd; 
    } msx_config_t;

endpackage
