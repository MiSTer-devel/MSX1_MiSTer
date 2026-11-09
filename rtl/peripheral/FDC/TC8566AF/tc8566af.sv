// TC8566AF floppy controller core
//
// SystemVerilog port of rtl/FDC/FDCs.vhd of PC88_MiSTer revision 1d4de0f (2025-02-25)
// (https://github.com/MiSTer-devel/PC88_MiSTer), with the FDC fixes of PC88_MiSTer by Yoshiaki
// Okuyama up to a55ba46 (2026-11-05): end at EOT without TC, seek and Sense Interrupt results per
// drive, uPD765 step timing, head load time, result phase delay, SK / deleted data mark, long
// sectors, write bit cell in 1/256 clocks. The same FDC code is published under the GNU General
// Public License version 3 in X68000_MiSTer. Port: Molekula.
//
// SPDX-License-Identifier: GPL-3.0-only

module tc8566af #(
    parameter int   maxtrack	= 85,
	parameter int   maxbwidth	= 88,
	parameter int   maxfwidth	= 88*256,              // bit cells in 1/256 clocks
	parameter bit   fracin      = 0,                   // 1: intf* / intm* time the writes
	parameter int   rdytout     = 800,
	parameter logic preseek	    = 0,
	parameter int   sysclk		= 20
)(
    input  logic                            RDn,
	input  logic                            WRn,
	input  logic                            CSn,
	input  logic                            A0,
	input  logic                     [7:0]  WDAT,
	output logic                     [7:0]  RDAT,
	output logic                            DATOE,
	input  logic                            DACKn,
	output logic                            DRQ,
	input  logic                            TC,
	output logic                            INTn,
	output logic                            INTEV,                      // events that set INTn
	input  logic                            WAITIN,

	output logic                            WREN,                       // pin24
	output logic                            WRBIT,                      // pin22
	input  logic                            RDBIT,	                    // pin30
	output logic                            STEP,                       // pin20
	output logic                            SDIR,	                    // pin18
	input  logic                            WPRT,                       // pin28
	input  logic                            track0,                     // pin26
	input  logic                            index,                      // pin8
	output logic                            side,                       // pin32
	output logic                     [1:0]  usel,
	input  logic                            READY,	                    // pin34
	input  logic                     [3:0]  readyv,                     // per drive, 1 = not ready
	input  logic                     [3:0]  TWOSIDE,                    // per drive, ST3 TS
	
    input  logic [$clog2(maxbwidth+1)-1:0]  int0,
    input  logic [$clog2(maxbwidth+1)-1:0]  int1,
    input  logic [$clog2(maxbwidth+1)-1:0]  int2,
	input  logic [$clog2(maxbwidth+1)-1:0]  int3,
	// the same bit cells in 1/256 clocks for FM and MFM, time the writes with fracin
	input  logic [$clog2(maxfwidth+1)-1:0]  intf0, intf1, intf2, intf3,
	input  logic [$clog2(maxfwidth+1)-1:0]  intm0, intm1, intm2, intm3,
	
	input  logic                            td0,
	input  logic                            td1,
	input  logic                            td2,
	input  logic                            td3,
	
	input  logic                            hmssft,                     // 0.5msec
	
	output logic                            busy,
	output logic                            mfm,
	
	input  logic                            sclk,
	input  logic                            fclk,
	input  logic                            rstn
);


    logic               IOWR_DAT;
    logic               IORD_DAT;  
    logic               IORD_STA;
    logic               DMAWR;  
    logic               DMARD;
    logic               lIOWR_DAT;
    logic               lIORD_DAT;
    logic               CPUWR_DAT;
    logic               CPURD_DAT;
    logic               DMARDx;
    logic               DMAWRx;
    logic               lDMAWR;
    logic               lDMARD;
    logic               HD;
    logic               MF;
    logic               MT;
    logic               ND;
    logic               SK;
    logic               EXEC;
    logic               RD_CMD;
    logic               sDIOc;
    logic               DxBclr;
    logic               DxBclrd;
    logic         [1:0] SISUS;                  // drive of the Sense Interrupt result
    logic               SISclr;
    logic               SISclrd;
    logic         [6:0] HLT;                    // head load time (Specify)
    logic         [3:0] HUT;                    // head unload time (Specify)
    logic               hdld;                   // head loaded
    logic               hlrun;
    logic        [10:0] hlcnt;                  // 0..128*8 half ms
    logic        [10:0] hucnt;                  // 0..16*64 half ms
    logic               skipsect;               // SK = 1: sector with the other data mark skipped
    // seek completions waiting to be reported, oldest first
    logic         [1:0] sqdrv [4];
    logic         [3:0] sqerr;
    logic         [3:0] sqnr;
    logic         [2:0] sqcnt;
    // Sense Interrupt result per drive
    logic         [7:0] sisst0 [4];
    logic         [7:0] sispcn [4];
    logic         [3:0] sisvld;
    logic         [1:0] sisdrv;                 // drive reported next, lowest number first
    logic               sisany;
    logic         [7:0] sisPCNl;                // PCN latched with the first result byte
    logic         [1:0] sCBq;
    // result phase of a read 93 us after the end (PC-8801FH)
    localparam int      resdly = sysclk*93;
    localparam int      RW = $clog2(resdly+1);
    logic      [RW-1:0] resdcnt;
    logic               resdrd;
    logic               resdstart;
    logic               resdhold;
    logic               resdint;
    logic               end_EXECd;
    logic               end_EXECo;
    logic               INTd;
    logic               CPURD_DATf;
    logic               CPUWR_DATf;
    logic               DMARDxf;
    logic               DMAWRxf;
    logic               end_EXEC;
    logic               seek_bgn;
    logic               seek_init;
    logic               crcclr;
    logic               crcwr;
    logic               deminit;
    logic               dembreak;
    logic               TCclr;
    logic               INT;                    // interrupt start
    logic               INTs;                   // interrput at seek/re-carib.
    logic               DMARQ;                  // DMA request start
    logic               DETSECT;
    logic               setC;
    logic               incC;
    logic               resH;
    logic               setH;
    logic               setR;
    logic               incR;
    logic               resR;
    logic               setN;
    logic               setHD;
    logic               resHD;
    logic               sNR;                    // Not Ready
    logic               sOR;                    // Over Run
    logic               sND;                    // Not Data
    logic               sDE;                    // Data Error
    logic               sEN;                    // End of Cylinder
    logic               sDIOd;
    logic               sNW;                    // Not Writable
    logic               sMA;                    // Missing Address Mark
    logic               sRQM;                   
    logic               sCM;                    // Control Mark
    logic               sWC;                    // Wrong Cylinder
    logic               sDD;                    // Data error in Data field(CRC)
    logic               sMD;                    // Missing Address Mark in Data Field
    logic               sSH;                    // Scan Equal Hit
    logic               sCB;                    
    logic               fmtxwr;
    logic               mfmtxwr;
    logic               fmmf8wr;
    logic               fmmfbwr;
    logic               fmmfcwr;
    logic               fmmfewr;
    logic               mfmma1wr;
    logic               mfmmc2wr;
    logic               modbreak;
    logic               NRDSTART;
    logic               scancomp;
    logic               sHD;                    // Head Address(when interrupt)
    logic               sEC;                    // Equipment Check
    logic               sSE;                    // Seek End 
    wire                sSN = 1'b0;             // Scan Not Satisfied (never set, as FDCs.vhd)
    wire                sBC = 1'b0;             // Bad Cylinder (never set, as FDCs.vhd)
    logic               lindex;
    logic               indexb;
    logic               NOTRDY;
    logic               seekbusy;
    logic               fmmfedet;
    logic               fmmf8det;
    logic               fmmfbdet;
    logic               fmmfcdet;
    logic               fmrxed;
    logic               mfmma1det;
    logic               mfmmc2det;
    logic               mfmrxed;
    logic               crcdone;
    logic               crczero;
    logic               TCen;
    logic               fmtxemp;
    logic               mfmtxemp;
    logic               fmtxend;
    logic               mfmtxend;
    logic               crcbusy;
    logic               modsft;
    logic               sTC;
    logic               seek_busy;
    logic               wrbitex;
    logic               wrenex;
    logic               wrbits;
    logic               wrens;
    logic               mfmwren;
    logic               fmwren;
    logic               fmwrbit;
    logic               mfmwrbit;
    logic               STEP0;
    logic               STEP1;
    logic               STEP2;
    logic               STEP3;
    logic               SDIR0;
    logic               SDIR1;
    logic               SDIR2;
    logic               SDIR3;
    logic               track0b;
    logic               seek_sft0;
    logic               seek_sft1;
    logic               seek_sft2;
    logic               seek_sft3;
    logic               seek_sft; 
    logic               sEXM;
    logic               track0s;
    logic               sideb;
    logic               sDIO;

    













    logic         [1:0] US;
    logic         [1:0] lCPURD_DAT;
    logic         [1:0] lCPUWR_DAT;
    logic         [1:0] lDMARDx;
    logic         [1:0] lDMAWRx;
    logic         [1:0] sIC;                    // Interrupt Code
    logic         [1:0] sUS;                    // Unit Select(when interrupt)
    logic         [1:0] seekusel;
    logic         [1:0] uselb;

    logic         [3:0] SRT;
    logic         [3:0] seek_end;
    logic         [3:0] seek_err;
    logic         [3:0] sDxB;
    logic         [3:0] seek_busyv;
    logic         [3:0] seekpend;
    logic         [3:0] tdo;
    logic         [3:0] seek_bgnv;
    logic         [3:0] seek_initv;
    logic         [3:0] seek_errv;
    logic         [3:0] seek_endv;
    logic         [3:0] tdi;
    logic         [4:0] command;
    logic         [4:0] ecommand;
    logic         [7:0] C;
    logic         [7:0] D;
    logic         [7:0] N;
    logic         [7:0] H;
    logic         [7:0] R;
    logic         [7:0] SC;
    logic         [7:0] DTL;
    logic         [7:0] EOT;
    logic         [7:0] GPL;
    logic         [7:0] CPUWRDAT;
    logic         [7:0] RDDAT_CMD;
    logic         [7:0] rxC;
    logic         [7:0] rxR;
    logic         [7:0] rxN;
    logic         [7:0] ST0;
    logic         [7:0] ST1;
    logic         [7:0] ST2;
    logic         [7:0] ST3;
    logic         [7:0] crcin;
    logic         [7:0] cntR;
    logic         [7:0] rxH;
    logic         [7:0] txdat;
    logic         [7:0] COMPDAT;
    logic         [7:0] mPCN0;
    logic         [7:0] mPCN1;
    logic         [7:0] mPCN2;
    logic         [7:0] mPCN3;
    logic         [7:0] cPCN;
    logic         [7:0] mfmrxdat;
    logic         [7:0] fmrxdat;
    logic         [7:0] RDDAT_DAT;
    logic         [7:0] PCN0;
    logic         [7:0] PCN1;
    logic         [7:0] PCN2;
    logic         [7:0] PCN3;
    logic         [7:0] MSR;
    logic        [15:0] crcdat;


    
    
    logic         [4:0] datnum;                 // command / result byte, 0..17
    int                 nturns;
    int                 iUS;
    int                 bytecount;
    localparam int      FW = $clog2(maxfwidth+1);
    logic      [FW-1:0] sftwidth;               // write bit cell in 1/256 clocks
    int                 bitwidth;
    int                 seek_cur0;
    int                 seek_cur1;
    int                 seek_cur2;
    int                 seek_cur3;
    int                 seek_cyl0;
    int                 seek_cyl1;
    int                 seek_cyl2;
    int                 seek_cyl3;
    int                 iC0;
    int                 iC1;
    int                 iC2;
    int                 iC3;
    int                 iC;



    typedef enum logic [5:0] {
        es_idle,
		es_readychk,
		es_seek,
		es_wseek,
		es_windex,
		es_GAP0,
		es_Syncp,
		es_IM0,
		es_IM1,
		es_IM2,
		es_IM3,
		es_GAP1,
		es_Synci,
		es_IAM0,
		es_IAM1,
		es_IAM2,
		es_IAM3,
		es_C,
		es_Cw,
		es_H,
		es_Hw,
		es_R,
		es_Rw,
		es_N,
		es_Nw,
		es_CRCi0,
		es_CRCi1,
		es_CRCic,
		es_GAP2,
		es_Syncd,
		es_DAM0,
		es_DAM1,
		es_DAM2,
		es_DAM3,
		es_DATA,
		es_DATAw,
		es_DATAs,
		es_CRCd0,
		es_CRCd1,
		es_CRCdc,
		es_GAP3,
		es_GAP4,
		es_NEXT,
		es_NEXT2
    } execstate_t;

    localparam cmd_READDATA			= 5'b00110;
    localparam cmd_READDELETEDDATA	= 5'b01100;
    localparam cmd_WRITEDATA		= 5'b00101;
    localparam cmd_WRITEDELETEDDATA	= 5'b01001;
    localparam cmd_READATRACK		= 5'b00010;
    localparam cmd_READID			= 5'b01010;
    localparam cmd_FORMATATRACK		= 5'b01101;
    localparam cmd_SCANEQUAL		= 5'b10001;
    localparam cmd_SCANLOWEQUAL		= 5'b11001;
    localparam cmd_SCANHIGHEQUAL	= 5'b11101;
    localparam cmd_RECALIBRATE		= 5'b00111;
    localparam cmd_SENSEINTSTATUS	= 5'b01000;
    localparam cmd_SPECIFY			= 5'b00011;
    localparam cmd_SENSEDRIVESTATUS	= 5'b00100;
    localparam cmd_SEEK				= 5'b01111;

    localparam  WR_WIDTH	        = 200;
    localparam	nfmGap0		        = 40;
    localparam	nmfmGap0	        = 80;
    localparam	nfmSyncp	        = 6;
    localparam	nmfmSyncp	        = 12;
    localparam	nfmGap1		        = 26;
    localparam	nmfmGap1	        = 50;
    localparam	nfmSynci	        = 6;
    localparam	nmfmSynci	        = 12;
    localparam	nfmGap2		        = 11;
    localparam	nmfmGap2	        = 22;
    localparam	nfmSyncd	        = 6;
    localparam	nmfmSyncd	        = 12;

    localparam  extcount	        = (sysclk*WR_WIDTH)/1000;


    execstate_t execstate;

    assign IOWR_DAT = !CSn   &&  A0 && !WRn;
    assign IORD_DAT = !CSn   &&  A0 && !RDn;
    assign IORD_STA = !CSn   && !A0 && !RDn;
    assign DMAWR    = !DACKn &&        !WRn;
    assign DMARD    = !DACKn &&        !RDn;
    
    assign DATOE    = IORD_DAT || IORD_STA || DMARD;

    always_ff @(posedge sclk or negedge rstn) begin
        if (!rstn) begin
            lIOWR_DAT <= 1'b0;
            lIORD_DAT <= 1'b0;
            CPUWRDAT  <= '0;
            CPUWR_DAT <= 1'b0;
            CPURD_DAT <= 1'b0;
            DRQ       <= 1'b0;
        end else begin
            CPUWR_DAT <= 1'b0;
            CPURD_DAT <= 1'b0;
            DMARDx    <= 1'b0;
            DMAWRx    <= 1'b0;
            
            if (IOWR_DAT) begin
                CPUWRDAT <= WDAT;
            end else if (!IOWR_DAT && lIOWR_DAT) begin
                CPUWR_DAT <= 1'b1;
            end
            
            if (!IORD_DAT && lIORD_DAT) begin
                CPURD_DAT <= 1'b1;
            end
            
            if (DMAWR) begin
                CPUWRDAT <= WDAT;
            end else if (!DMAWR && lDMAWR) begin
                DMAWRx <= 1'b1;
            end
            
            if (!DMARD && lDMARD) begin
                DMARDx <= 1'b1;
            end
            
            if (DMARQ) begin
                DRQ <= 1'b1;
            end else if (!DACKn || IORD_DAT || IOWR_DAT) begin
                DRQ <= 1'b0;
            end
            
            lIOWR_DAT <= IOWR_DAT;
            lIORD_DAT <= IORD_DAT;
            lDMAWR    <= DMAWR;
            lDMARD    <= DMARD;
        end
    end

    always_ff @(posedge sclk or negedge rstn) begin
        if (!rstn) begin
            command    <= '0;
            C          <= '0;
            D          <= '0;
            DTL        <= '0;
            EOT        <= '0;
            GPL        <= '0;
            HD         <= 0;
            MF         <= 0;
            MT         <= 0;
            N          <= '0;
            ND         <= 0;
            H          <= '0;
            R          <= '0;
            SC         <= '0;
            SK         <= 0;
            SRT        <= '0;
            US         <= '0;
            datnum     <= 0;
            EXEC       <= 0;
            RD_CMD     <= 1;
            RDDAT_CMD  <= '0;
            sDIOc      <= 0;
            DxBclr     <= 0;
            SISclr     <= 0;
            HLT        <= '0;
            HUT        <= '0;
            SISUS      <= '0;
            sisPCNl    <= '0;
        end else begin
            EXEC    <= 0;
            DxBclr  <= 0;
            SISclr  <= 0;
            
            if (setC)
                C <= rxC;
            else if (incC)
                C <= C + 8'h01;
            
            if (setH)
                H <= 8'h01;
            else if (resH)
                H <= 8'h00;
            
            if (setR)
                R <= rxR;
            else if (incR)
                R <= R + 8'h01;
            else if (resR)
                R <= 8'h01;
            
            if (setN)
                N <= rxN;
            
            if (setHD)
                HD <= 1;
            else if (resHD)
                HD <= 0;
            
            if (datnum == 0) begin
                RDDAT_CMD <= '0;
                RD_CMD    <= 1;
                sDIOc     <= 0;
                if (CPUWR_DAT) begin
                    command <= CPUWRDAT[4:0];
                    case (CPUWRDAT[4:0])
                        cmd_READDATA,
                        cmd_READDELETEDDATA,
                        cmd_SCANEQUAL,
                        cmd_SCANLOWEQUAL,
                        cmd_SCANHIGHEQUAL: begin
                            MT <= CPUWRDAT[7];
                            MF <= CPUWRDAT[6];
                            SK <= CPUWRDAT[5];
                        end
                        cmd_WRITEDATA,
                        cmd_WRITEDELETEDDATA: begin
                            MT <= CPUWRDAT[7];
                            MF <= CPUWRDAT[6];
                        end
                        cmd_READATRACK: begin
                            MT <= 0;
                            MF <= CPUWRDAT[6];
                            SK <= 0;
                        end
                        cmd_READID:
                            MF <= CPUWRDAT[6];
                        cmd_FORMATATRACK: begin
                            MF <= CPUWRDAT[6];
                            R  <= 8'h00;
                        end
                        default: ;
                    endcase
                    datnum <= 1;
                end
            end else begin
                case (command)
                    cmd_READDATA,
                    cmd_READDELETEDDATA,
                    cmd_WRITEDATA,
                    cmd_WRITEDELETEDDATA,
                    cmd_READATRACK,
                    cmd_SCANEQUAL,
                    cmd_SCANLOWEQUAL,
                    cmd_SCANHIGHEQUAL: begin
                        case (datnum)
                            1: if (CPUWR_DAT) begin
                                US  <= CPUWRDAT[1:0];
                                HD  <= CPUWRDAT[2];
                                datnum <= datnum + 5'd1;
                            end
                            2: if (CPUWR_DAT) begin
                                C <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            3: if (CPUWR_DAT) begin
                                H <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            4: if (CPUWR_DAT) begin
                                R <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            5: if (CPUWR_DAT) begin
                                N <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            6: if (CPUWR_DAT) begin
                                EOT <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            7: if (CPUWR_DAT) begin
                                GPL <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            8: if (CPUWR_DAT) begin
                                DTL <= CPUWRDAT;
                                RD_CMD <= 0;
                                sDIOc  <= 1;
                                datnum <= datnum + 5'd1;
                            end
                            9: if (!WAITIN) begin
                                EXEC   <= 1;
                                datnum <= datnum + 5'd1;
                            end
                            10: if (end_EXECo) begin
                                RD_CMD <= 1;
                                RDDAT_CMD <= ST0;
                                datnum <= datnum + 5'd1;
                            end
                            11: if (CPURD_DAT) begin
                                RDDAT_CMD <= ST1;
                                datnum <= datnum + 5'd1;
                            end
                            12: if (CPURD_DAT) begin
                                RDDAT_CMD <= ST2;
                                datnum <= datnum + 5'd1;
                            end
                            13: if (CPURD_DAT) begin
                                RDDAT_CMD <= C;
                                datnum <= datnum + 5'd1;
                            end
                            14: if (CPURD_DAT) begin
                                RDDAT_CMD <= H;
                                datnum <= datnum + 5'd1;
                            end
                            15: if (CPURD_DAT) begin
                                RDDAT_CMD <= R;
                                datnum <= datnum + 5'd1;
                            end
                            16: if (CPURD_DAT) begin
                                RDDAT_CMD <= N;
                                datnum <= datnum + 5'd1;
                            end
                            17: if (CPURD_DAT) begin
                                RD_CMD <= 1;
                                datnum <= 0;
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    cmd_READID: begin
                        case (datnum)
                            1: begin
                                if (CPUWR_DAT) begin
                                    US <= CPUWRDAT[1:0];
                                    HD <= CPUWRDAT[2];
                                    sDIOc <= 1'b1;
                                    RD_CMD <= 1'b0;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            2: begin
                                if (!WAITIN) begin
                                    EXEC <= 1'b1;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            3: begin
                                if (end_EXECo) begin
                                    RD_CMD <= 1'b1;
                                    RDDAT_CMD <= ST0;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            4: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= ST1;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            5: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= ST2;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            6: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= C;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            7: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= H;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            8: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= R;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            9: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= N;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            10: begin
                                if (CPURD_DAT) begin
                                    RD_CMD <= 1'b1;
                                    datnum <= 0;
                                end
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    cmd_FORMATATRACK: begin
                        case (datnum)
                            1: if (CPUWR_DAT) begin
                                US <= CPUWRDAT[1:0];
                                HD <= CPUWRDAT[2];
                                datnum <= datnum + 5'd1;
                            end
                            2: if (CPUWR_DAT) begin
                                N <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            3: if (CPUWR_DAT) begin
                                SC <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            4: if (CPUWR_DAT) begin
                                GPL <= CPUWRDAT;
                                datnum <= datnum + 5'd1;
                            end
                            5: if (CPUWR_DAT) begin
                                D <= CPUWRDAT;
                                R <= 8'h01;
                                sDIOc <= 1;
                                RD_CMD <= 0;
                                datnum <= datnum + 5'd1;
                            end
                            6: if (!WAITIN) begin
                                EXEC <= 1;
                                datnum <= datnum + 5'd1;
                            end
                            7: if (end_EXECo) begin
                                RD_CMD <= 1;
                                RDDAT_CMD <= ST0;
                                datnum <= datnum + 5'd1;
                            end
                            8: if (CPURD_DAT) begin
                                RDDAT_CMD <= ST1;
                                datnum <= datnum + 5'd1;
                            end
                            9: if (CPURD_DAT) begin
                                RDDAT_CMD <= ST2;
                                datnum <= datnum + 5'd1;
                            end
                            10: if (CPURD_DAT) begin
                                RDDAT_CMD <= C;
                                datnum <= datnum + 5'd1;
                            end
                            11: if (CPURD_DAT) begin
                                RDDAT_CMD <= H;
                                datnum <= datnum + 5'd1;
                            end
                            12: if (CPURD_DAT) begin
                                RDDAT_CMD <= R;
                                datnum <= datnum + 5'd1;
                            end
                            13: if (CPURD_DAT) begin
                                RDDAT_CMD <= N;
                                datnum <= datnum + 5'd1;
                            end
                            14: if (CPURD_DAT) begin
                                RD_CMD <= 1;
                                datnum <= 0;
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    cmd_RECALIBRATE: begin
                        case (datnum)
                            1: begin
                                if (CPUWR_DAT == 1) begin
                                    US      <= CPUWRDAT[1:0];
                                    HD      <= CPUWRDAT[2];
                                    C       <= 8'h00;
                                    RD_CMD  <= 0;
                                    datnum  <= datnum + 5'd1;
                                end
                            end
                            2: begin
                                if (WAITIN == 0) begin
                                    EXEC   <= 1;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            3: begin
                                if (end_EXECo == 1) begin
                                    RD_CMD <= 1;
                                    datnum <= 0;
                                end
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    cmd_SENSEINTSTATUS: begin
                        case (datnum)
                            1: begin
                                RD_CMD <= 1;
                                sDIOc <= 1;
                                // the lowest-numbered drive with a pending result (a9ab3e6)
                                if (sisany) begin
                                    RDDAT_CMD <= sisst0[sisdrv] & 8'hFB;
                                    sisPCNl   <= sispcn[sisdrv];
                                    SISUS     <= sisdrv;
                                    datnum <= datnum + 5'd1;
                                end else begin
                                    RDDAT_CMD <= 8'h80;
                                    datnum <= 4;
                                end
                            end

                            2: begin
                                if (CPURD_DAT) begin
                                    RDDAT_CMD <= sisPCNl;
                                    datnum <= datnum + 5'd1;
                                end
                            end

                            3: begin
                                if (CPURD_DAT) begin
                                    RD_CMD <= 1;
                                    DxBclr <= 1;
                                    SISclr <= 1;
                                    datnum <= 0;
                                end
                            end

                            4: begin
                                if (CPURD_DAT) begin
                                    RD_CMD <= 1;
                                    datnum <= 0;
                                end
                            end

                            default: datnum <= 0;
                        endcase
                    end
                    cmd_SPECIFY: begin
                        case (datnum)
                            1: begin
                                if (CPUWR_DAT) begin
                                    HUT <= CPUWRDAT[3:0];
                                    SRT <= CPUWRDAT[7:4];
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            2: begin
                                if (CPUWR_DAT) begin
                                    HLT <= CPUWRDAT[7:1];
                                    ND <= CPUWRDAT[0];
                                    RD_CMD <= 1;
                                    datnum <= 0;
                                end
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    cmd_SENSEDRIVESTATUS: begin
                        case (datnum)
                            1: begin
                                if (CPUWR_DAT == 1'b1) begin
                                    US <= CPUWRDAT[1:0];
                                    HD <= CPUWRDAT[2];
                                    RD_CMD <= 1'b1;
                                    sDIOc <= 1'b1;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            2: begin
                                RDDAT_CMD <= ST3;
                                datnum <= datnum + 5'd1;
                            end
                            3: begin
                                if (CPURD_DAT == 1'b1) begin
                                    RD_CMD <= 1'b1;
                                    datnum <= 0;
                                end
                            end
                            default: begin
                                datnum <= 0;
                            end
                        endcase
                    end
                    cmd_SEEK: begin
                        case (datnum)
                            1: begin
                                if (CPUWR_DAT == 1'b1) begin
                                    US <= CPUWRDAT[1:0];
                                    HD <= CPUWRDAT[2];
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            2: begin
                                if (CPUWR_DAT == 1'b1) begin
                                    C <= CPUWRDAT;
                                    RD_CMD <= 1'b0;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            3: begin
                                if (WAITIN == 1'b0) begin
                                    EXEC <= 1'b1;
                                    datnum <= datnum + 5'd1;
                                end
                            end
                            4: begin
                                if (end_EXECo == 1'b1) begin
                                    RD_CMD <= 1'b1;
                                    datnum <= 0;
                                end
                            end
                            default: datnum <= 0;
                        endcase
                    end
                    default: begin
                        case (datnum)
                            1: begin
                                RD_CMD <= 1'b1;
                                RDDAT_CMD <= 8'h80;
                                sDIOc <= 1'b1;
                                datnum <= datnum + 5'd1;
                            end
                            2: begin
                                if (CPURD_DAT == 1'b1) begin
                                    RD_CMD <= 1'b1;
                                    datnum <= 0;
                                end
                            end
                            default: begin
                                datnum <= 0;
                            end
                        endcase
                    end
                endcase;
            end
        end
    end

    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn) begin
            lCPURD_DAT <= '0;
            lCPUWR_DAT <= '0;
            lDMARDx    <= '0;
            lDMAWRx    <= '0;
            CPURD_DATf <= 1'b0;
            CPUWR_DATf <= 1'b0;
            DMARDxf    <= 1'b0;
            DMAWRxf    <= 1'b0;
        end else begin
            CPURD_DATf <= 1'b0;
            CPUWR_DATf <= 1'b0;
            DMARDxf    <= 1'b0;
            DMAWRxf    <= 1'b0;
            
            lCPURD_DAT <= {lCPURD_DAT[0], CPURD_DAT};
            lCPUWR_DAT <= {lCPUWR_DAT[0], CPUWR_DAT};
            lDMARDx    <= {lDMARDx[0], DMARDx};
            lDMAWRx    <= {lDMAWRx[0], DMAWRx};
            
            if (lCPURD_DAT == 2'b01)
                CPURD_DATf <= 1'b1;
            if (lCPUWR_DAT == 2'b01)
                CPUWR_DATf <= 1'b1;
            if (lDMARDx == 2'b01)
                DMARDxf    <= 1'b1;
            if (lDMAWRx == 2'b01)
                DMAWRxf    <= 1'b1;
        end
    end

    // Seek completions are queued, also while a transfer runs, and moved one by one into the
    // per-drive Sense Interrupt result in the command phase (PC88_MiSTer a9ab3e6). The VHDL
    // process variables are combinational here.
    logic       seekpush, pusherr, dopop;
    logic [1:0] pushdrv;
    logic [2:0] qn_pop, qn_next;
    logic [3:0] visv;
    always_comb begin
        seekpush = 1'b0;
        pushdrv  = 2'd0;
        pusherr  = 1'b0;
        for (int i = 0; i < 4; i++) begin
            if (seek_end[i]) begin
                seekpush = 1'b1; pushdrv = 2'(i); pusherr = 1'b0;
            end else if (seek_err[i]) begin
                seekpush = 1'b1; pushdrv = 2'(i); pusherr = 1'b1;
            end
        end
        dopop   = execstate == es_idle && !sCB && sCBq == 2'b00 && sqcnt != 3'd0;
        qn_pop  = dopop ? sqcnt - 3'd1 : sqcnt;
        qn_next = seekpush && qn_pop < 3'd4 ? qn_pop + 3'd1 : qn_pop;
        visv    = sisvld;
        if (SISclr && !SISclrd) visv[SISUS] = 1'b0;
        if (dopop) visv[sqdrv[0]] = 1'b1;
    end

    // the sector just finished is the last one (EOT): R = EOT and not the first side of MT
    wire lastsect = R == EOT && (!MT || HD);

    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn) begin
            execstate <= es_idle;
            end_EXEC  <= 1'b0;
            seek_bgn  <= 1'b0;
            seek_init <= 1'b0;
            crcclr    <= 1'b0;
            crcin     <= '0;
            crcwr     <= 1'b0;
            deminit   <= 1'b0;
            dembreak  <= 1'b0;
            cntR      <= '0;
            rxC       <= '0;
            rxH       <= '0;
            rxR       <= '0;
            rxN       <= '0;
            TCclr     <= 1'b0;
            INT       <= 1'b0;
            INTs      <= 1'b0;
            DMARQ     <= 1'b0;
            DETSECT   <= 1'b0;
            setC      <= 1'b0;
            incC      <= 1'b0;
            resH      <= 1'b0;
            setH      <= 1'b0;
            setR      <= 1'b0;
            incR      <= 1'b0;
            resR      <= 1'b0;
            setN      <= 1'b0;
            setHD     <= 1'b0;
            resHD     <= 1'b0;
            sIC       <= 2'b00;
            sNR       <= 1'b0;
            sOR       <= 1'b0;
            sND       <= 1'b0;
            sDE       <= 1'b0;
            sEN       <= 1'b0;
            sDIOd     <= 1'b0;
            sNW       <= 1'b0;
            sMA       <= 1'b0;
            sRQM      <= 1'b1;
            sCM       <= 1'b0;
            sWC       <= 1'b0;
            sDD       <= 1'b0;
            sMD       <= 1'b0;
            sSH       <= 1'b0;
            txdat     <= '0;
            fmtxwr    <= 1'b0;
            mfmtxwr   <= 1'b0;
            fmmf8wr   <= 1'b0;
            fmmfbwr   <= 1'b0;
            fmmfcwr   <= 1'b0;
            fmmfewr   <= 1'b0;
            mfmma1wr  <= 1'b0;
            mfmmc2wr  <= 1'b0;
            modbreak  <= 1'b0;
            NRDSTART  <= 1'b0;
            ecommand  <= '0;
            COMPDAT   <= '0;
            scancomp  <= 1'b0;
            skipsect  <= 1'b0;
            sUS       <= 2'b00;
            for (int i = 0; i < 4; i++) begin
                sqdrv[i]  <= 2'b00;
                sisst0[i] <= '0;
                sispcn[i] <= '0;
            end
            sqerr     <= '0;
            sqnr      <= '0;
            sqcnt     <= '0;
            sisvld    <= '0;
            SISclrd   <= 1'b0;
            sCBq      <= 2'b11;
        end else begin
            end_EXEC  <= 1'b0;
            seek_bgn  <= 1'b0;
            seek_init <= 1'b0;
            crcclr    <= 1'b0;
            crcwr     <= 1'b0;
            deminit   <= 1'b0;
            dembreak  <= 1'b0;
            fmtxwr    <= 1'b0;
            mfmtxwr   <= 1'b0;
            fmmf8wr   <= 1'b0;
            fmmfbwr   <= 1'b0;
            fmmfcwr   <= 1'b0;
            fmmfewr   <= 1'b0;
            mfmma1wr  <= 1'b0;
            mfmmc2wr  <= 1'b0;
            modbreak  <= 1'b0;
            TCclr     <= 1'b0;
            INT       <= 1'b0;
            INTs      <= 1'b0;
            DMARQ     <= 1'b0;
            setC      <= 1'b0;
            incC      <= 1'b0;
            resH      <= 1'b0;
            setH      <= 1'b0;
            setR      <= 1'b0;
            incR      <= 1'b0;
            resR      <= 1'b0;
            setN      <= 1'b0;
            setHD     <= 1'b0;
            resHD     <= 1'b0;
            NRDSTART  <= 1'b0;
            sCBq      <= {sCBq[0], sCB};
            if (dopop) begin
                for (int i = 0; i < 3; i++) begin
                    sqdrv[i] <= sqdrv[i+1];
                    sqerr[i] <= sqerr[i+1];
                    sqnr[i]  <= sqnr[i+1];
                end
            end
            if (seekpush && qn_pop < 3'd4) begin
                sqdrv[qn_pop[1:0]] <= pushdrv;
                sqerr[qn_pop[1:0]] <= pusherr;
                sqnr[qn_pop[1:0]]  <= readyv[pushdrv];
            end
            sqcnt   <= qn_next;
            SISclrd <= SISclr;
            sisvld  <= visv;
            if (SISclr && !SISclrd && visv != 4'b0000) INTs <= 1'b1;   // the next pending result

            if (execstate == es_idle) begin
                sRQM <= 1'b1;
                if (dopop) begin
                    case (sqdrv[0])
                        2'b00:   sispcn[sqdrv[0]] <= mPCN0;
                        2'b01:   sispcn[sqdrv[0]] <= mPCN1;
                        2'b10:   sispcn[sqdrv[0]] <= mPCN2;
                        default: sispcn[sqdrv[0]] <= mPCN3;
                    endcase
                    // IC, SE, EC, NR at completion, HD, US; SE also on an error (uPD765), disk ROMs
                    // wait for it (FS-A1F 7970h)
                    sisst0[sqdrv[0]] <= {sqerr[0] ? 2'b01 : 2'b00, 1'b1, sqerr[0], sqnr[0], HD, sqdrv[0]};
                    INTs <= 1'b1;
                end
                if (EXEC) begin
                    sIC  <= 2'b00;
                    sNR  <= readyv[iUS];
                    sHD  <= HD;
                    sUS  <= US;
                    sOR  <= 1'b0;
                    sND  <= 1'b0;
                    sDE  <= 1'b0;
                    sEN  <= 1'b0;
                    sNW  <= 1'b0;
                    sMA  <= 1'b0;
                    sWC  <= 1'b0;
                    sDD  <= 1'b0;
                    sEN  <= 1'b0;
                    sSH  <= 1'b0;
                    sMD  <= 1'b0;
                    sRQM <= 1'b0;
                    sCM  <= 1'b0;
                    skipsect <= 1'b0;
                    TCclr    <= 1'b1;   // a TC of the previous command does not carry over (f2d6a8f)
                    DETSECT  <= 1'b0;
                    NRDSTART <= 1'b1;
                    ecommand <= command;
                    case (command)
                        cmd_READDATA, 
                        cmd_READDELETEDDATA, 
                        cmd_WRITEDATA, 
                        cmd_WRITEDELETEDDATA, 
                        cmd_READATRACK: begin
                            if (preseek) begin
                                seek_bgn  <= 1'b1;
                                execstate <= es_seek;
                            end else begin
                                crcclr    <= 1'b1;
                                deminit   <= 1'b1;
                                execstate <= es_wseek;
                            end
                            nturns <= 0;
                        end
                        cmd_READID: begin
                            crcclr    <= 1'b1;
                            deminit   <= 1'b1;
                            execstate <= es_wseek;
                            nturns    <= 0;
                        end
                        cmd_FORMATATRACK: begin
                            execstate <= es_wseek;
                            nturns    <= 0;
                            cntR      <= 8'h01;
                        end
                        cmd_SCANEQUAL, 
                        cmd_SCANLOWEQUAL, 
                        cmd_SCANHIGHEQUAL: begin
                            if (preseek) begin
                                seek_bgn  <= 1'b1;
                                execstate <= es_seek;
                            end else begin
                                execstate <= es_wseek;
                            end
                            nturns <= 0;
                        end
                        cmd_RECALIBRATE,                       // ready check first (a9ab3e6)
                        cmd_SEEK:
                            execstate <= es_readychk;
                        default: begin
                            execstate <= es_idle;
                            sRQM      <= 1'b1;
                        end
                    endcase
                end
            end else begin
                case (ecommand)
                    cmd_READDATA,
                    cmd_READDELETEDDATA,
                    cmd_READATRACK: begin
                        if (execstate != es_seek && !(execstate == es_wseek && !hdld) && lindex && ~indexb &&
                            !(execstate == es_DATA || execstate == es_DATAw || execstate == es_CRCd0 ||
                              execstate == es_CRCd1 || execstate == es_CRCdc)) begin
                            if (nturns == 0) begin
                                nturns    <= 1;
                            end else begin
                                sHD <= HD;
                                sUS <= US;
                                sIC <= 2'b01;
                                sNR <= readyv[iUS];
                                sEC <= '0;
                                sSE <= '0;
                                if (DETSECT) 
                                    sND <= '1;
                                else
                                    sMA <= '1;
                                INT <= '1;
                                end_EXEC <= '1;
                                execstate <= es_idle;
                            end
                        end else if (NOTRDY) begin
                            sHD <= HD;
                            sUS <= US;
                            sIC <= 2'b11;
                            sNR <= readyv[iUS];
                            sEC <= '0;
                            sSE <= '0;
                            sND <= '0;
                            sMA <= '0;
                            INT <= '1;
                            end_EXEC <= '1;
                            execstate <= es_idle;
                        end
                        case(execstate)
                            es_seek: begin
                                if (seek_end[iUS]) begin
                                    execstate <= es_wseek;
                                    crcclr <= 1;
                                    deminit <= 1;
                                end else if (seek_err[iUS]) begin
                                    sIC <= 2'b01;
                                    sNR <= readyv[iUS];
                                    sEC <= 1;
                                    sSE <= 0;
                                    sHD <= HD;
                                    sUS <= US;
                                    INT <= 1;
                                    execstate <= es_idle;
                                end
                            end
                            es_wseek: begin
                                if (!seekbusy && hdld) begin
                                    if (ecommand == cmd_READATRACK) begin
                                        execstate <= es_windex;
                                    end else begin
                                        execstate <= es_IAM0;
                                    end
                                end
                            end
                            es_windex: begin
                                if (lindex && !indexb) begin
                                    execstate <= es_IAM0;
                                end
                            end
                            es_IAM0: begin
                                if (!MF) begin
                                    if (fmmfedet) begin
                                        crcin <= 8'hFE;
                                        crcwr <= 1;
                                        DETSECT <= 1;
                                        execstate <= es_C;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                    end
                                end else if (mfmma1det) begin
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_IAM1;
                                end
                            end
                            es_IAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_IAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end
                            es_IAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_IAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end
                            es_IAM3: begin
                                if (mfmrxed && mfmrxdat == 8'hFE) begin
                                    crcin <= 8'hFE;
                                    crcwr <= 1;
                                    DETSECT <= 1;
                                    execstate <= es_C;
                                end else if (mfmma1det || mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end
                            es_C: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxC <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_H;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else if (mfmrxed) begin
                                    rxC <= mfmrxdat;
                                    crcin <= mfmrxdat;
                                    crcwr <= 1;
                                    execstate <= es_H;
                                end else if (mfmma1det || mfmmc2det) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end
                            es_H: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxH <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_R;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxH <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_R;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_R: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxR <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_N;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxR <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_N;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_N: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxN <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi0;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxN <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi0;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi0: begin
                                if (!MF) begin
                                    if (fmrxed == 1) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet ) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet ) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCic: begin
                                if (crcdone) begin
                                    if (crczero && rxC == C && rxH == H && rxR == R && rxN == N) begin
                                        if (rxC == C) begin
                                            sWC <= 0;
                                            nturns <= 0; // Reset IAM counter for avoiding stop between data reading
                                            execstate <= es_DAM0;
                                            crcclr <= 1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b01;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sWC <= 1;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                            execstate <= es_idle;
                                        end
                                    end else if (ecommand == cmd_READATRACK) begin
                                        sND <= 1; // Set "nodata" and continue reading as if the sector was found...
                                        rxN <= N; // Change the sector length as specified
                                        nturns <= 0; // Reset IAM counter for huge N
                                        execstate <= es_DAM0;
                                        crcclr <= 1;
                                    end else begin
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_DAM0: begin
                                if (!MF) begin
                                    if (((ecommand == cmd_READDATA || ecommand == cmd_READATRACK) && fmmf8det) ||
                                        (ecommand == cmd_READDELETEDDATA && fmmfbdet)) begin
                                        sCM <= 1;
                                    end

                                    if ((((ecommand == cmd_READDATA || ecommand == cmd_READATRACK) || !SK ) && fmmfbdet) ||
                                        ((ecommand == cmd_READDELETEDDATA || !SK) && fmmf8det)) begin
                                        crcin <= fmmf8det ? 8'hf8 : 8'hfb;
                                        crcwr <= 1;
                                        TCclr <= 1;
                                        sMD <= 0;
                                        execstate <= es_DATA;
                                    end else if ((ecommand == cmd_READDATA || ecommand == cmd_READDELETEDDATA) && SK &&
                                                 (fmmf8det || fmmfbdet)) begin
                                        // SK = 1: skip the sector, go on as if read (CM set above; f2d6a8f)
                                        dembreak <= 1;
                                        sMD <= 0;
                                        skipsect <= 1;
                                        execstate <= es_CRCdc;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet || fmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        sMD <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmma1det) begin
                                        crcin <= 8'hA1;
                                        crcwr <= 1;
                                        execstate <= es_DAM1;
                                    end else if (mfmmc2det || mfmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        sMD <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end

                                if (N == 8'h00 && DTL < 8'h80) begin
                                    bytecount <= {24'b0, DTL};
                                end else begin
                                    case (rxN)
                                        8'h00: bytecount <= 128;
                                        8'h01: bytecount <= 256;
                                        8'h02: bytecount <= 512;
                                        8'h03: bytecount <= 1024;
                                        8'h04: bytecount <= 2048;
                                        8'h05: bytecount <= 4096;
                                        8'h06: bytecount <= 8192;
                                        default: bytecount <= 16384;
                                    endcase
                                end
                            end

                            es_DAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_DAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_DAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_DAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_DAM3: begin
                                if (mfmrxed) begin
                                    if (((ecommand == cmd_READDATA || ecommand == cmd_READATRACK) && mfmrxdat == 8'hF8) ||
                                        (ecommand == cmd_READDELETEDDATA && mfmrxdat == 8'hFB)) begin
                                        sCM <= 1;
                                    end
                                end

                                if (mfmrxed && ((((ecommand == cmd_READDATA || ecommand == cmd_READATRACK) || !SK) && mfmrxdat == 8'hFB) ||
                                    ((ecommand == cmd_READDELETEDDATA || !SK ) && mfmrxdat == 8'hF8))) begin
                                    crcin <= mfmrxdat;
                                    crcwr <= 1;
                                    TCclr <= 1;
                                    sMD <= 0;
                                    execstate <= es_DATA;
                                end else if (mfmrxed && (ecommand == cmd_READDATA || ecommand == cmd_READDELETEDDATA) && SK &&
                                             (mfmrxdat == 8'hF8 || mfmrxdat == 8'hFB)) begin
                                    // SK = 1: skip the sector, go on as if read (CM set above; f2d6a8f)
                                    dembreak <= 1;
                                    sMD <= 0;
                                    skipsect <= 1;
                                    execstate <= es_CRCdc;
                                end else if (mfmma1det || mfmmc2det || mfmrxed ) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_DATA: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        if (!sOR && !TCen) begin
                                            if (!ND) begin
                                                DMARQ <= 1;
                                            end else begin
                                                sHD <= HD;
                                                sUS <= US;
                                                sIC <= 2'b00;
                                                sNR <= readyv[iUS];
                                                sEC <= 0;
                                                sSE <= 0;
                                                INT <= 1;
                                            end
                                            RDDAT_DAT <= fmrxdat;
                                            sDIOd <= 1;
                                            sRQM <= 1;
                                        end
                                        execstate <= es_DATAw;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        if (!sOR && !TCen) begin
                                            if (!ND) begin
                                                DMARQ <= 1;
                                            end else begin
                                                sHD <= HD;
                                                sUS <= US;
                                                sIC <= 2'b00;
                                                sNR <= readyv[iUS];
                                                sEC <= 0;
                                                sSE <= 0;
                                                INT <= 1;
                                            end
                                            RDDAT_DAT <= mfmrxdat;
                                            sDIOd <= 1;
                                            sRQM <= 1;
                                        end
                                        execstate <= es_DATAw;
                                    end
                                end
                            end

                            es_DATAw: begin
                                if (CPURD_DATf || DMARDxf || sOR || TCen) begin
                                    sRQM <= 0;
                                    if (bytecount > 1) begin
                                        bytecount <= bytecount - 1;
                                        execstate <= es_DATA;
                                    end else begin
                                        execstate <= es_CRCd0;
                                    end
                                end else if ((!MF && fmrxed) || (MF && mfmrxed)) begin
                                    sOR <= 1;
                                    sRQM <= 0;
                                    if (!MF) begin
                                        crcin <= fmrxdat;
                                    end else begin
                                        crcin <= mfmrxdat;
                                    end
                                    crcwr <= 1;
                                    if (bytecount > 2) begin
                                        bytecount <= bytecount - 2;
                                        execstate <= es_DATA;
                                    end else if (bytecount == 2) begin
                                        execstate <= es_CRCd0;
                                    end else begin
                                        execstate <= es_CRCd1;
                                    end
                                end
                            end

                            es_CRCd0: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCd1;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCd1;
                                    end
                                end
                            end

                            es_CRCd1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCdc;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCdc;
                                    end
                                end
                            end

                            es_CRCdc: begin
                                if (crcdone || skipsect) begin
                                    if (crczero || ecommand == cmd_READATRACK || skipsect) begin
                                        skipsect <= 0;
                                        if (R != EOT) begin
                                            incR <= 1;
                                        end else if (MT) begin
                                            if (HD == 0) begin
                                                resR <= 1;
                                                setH <= 1;
                                                setHD <= 1;
                                            end else begin
                                                resR <= 1;
                                                resH <= 1;
                                                resHD <= 1;
                                                incC <= 1;
                                            end
                                        end else begin
                                            resR <= 1;
                                            incC <= 1;
                                        end
                                        if (ecommand == cmd_READATRACK && !crczero) begin
                                            // READ A TRACK goes on after a data CRC error, DE DD reported (a55ba46)
                                            sDE <= 1;
                                            sDD <= 1;
                                        end
                                        if (sOR) begin
                                            sIC <= 2'b01;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1;
                                            execstate <= es_idle;
                                            end_EXEC <= 1;
                                        end else if (!SK && sCM && (ecommand == cmd_READDATA || ecommand == cmd_READDELETEDDATA)) begin
                                            // SK = 0: end after the sector with the other data mark, C H R kept (f2d6a8f)
                                            incR  <= 0;
                                            resR  <= 0;
                                            setH  <= 0;
                                            setHD <= 0;
                                            resH  <= 0;
                                            resHD <= 0;
                                            incC  <= 0;
                                            execstate <= es_idle;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                        end else if (TCen) begin
                                            execstate <= es_idle;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                        end else if (lastsect) begin
                                            // EOT without TC: end here, IC 01 and EN, C H R kept (PC-8801FH;
                                            // 2620836, f2d6a8f). It looked for R = EOT + 1 two turns (ND).
                                            resR <= 0;
                                            resH <= 0;
                                            incC <= 0;
                                            execstate <= es_idle;
                                            sIC <= 2'b01;
                                            sEN <= 1;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                        end else begin
                                            nturns <= 0;
                                            crcclr <= 1;
                                            execstate <= es_IAM0;
                                        end
                                    end else begin
                                        sDE <= 1;
                                        sIC <= 2'b01;
                                        sNR <= readyv[iUS];
                                        sEC <= 0;
                                        sSE <= 0;
                                        sHD <= HD;
                                        sUS <= US;
                                        sDD <= 1;
                                        INT <= 1;
                                        execstate <= es_idle;
                                        end_EXEC <= 1;
                                    end
                                end
                            end

                            default:
                                execstate <= es_idle;
                        endcase
                    end
                    cmd_WRITEDATA,
                    cmd_WRITEDELETEDDATA: begin
                        if (!WPRT) begin
                            sIC <= 2'b01;
                            sNR <= readyv[iUS];
                            sEC <= 1'b0;
                            sSE <= 1'b0;
                            sNW <= 1'b1;
                            sHD <= HD;
                            sUS <= US;
                            INT <= 1'b1;
                            end_EXEC <= 1'b1;
                            execstate <= es_idle;
                        end else if (execstate != es_seek && !(execstate == es_wseek && !hdld) && lindex && !indexb) begin
                            if (nturns == 0) begin
                                nturns <= 1;
                            end else begin
                                sHD <= HD;
                                sUS <= US;
                                INT <= 1'b1;
                                sIC <= 2'b01;
                                sNR <= readyv[iUS];
                                sEC <= 1'b0;
                                sSE <= 1'b0;
                                if (!DETSECT) begin
                                    sMA <= 1'b1;
                                end else begin
                                    sND <= 1'b1;
                                end
                                end_EXEC <= 1'b1;
                                execstate <= es_idle;
                            end
                        end else if (NOTRDY) begin
                            sHD <= HD;
                            sUS <= US;
                            sIC <= 2'b11;
                            sNR <= readyv[iUS];
                            sEC <= 1'b0;
                            sSE <= 1'b0;
                            sND <= 1'b0;
                            sMA <= 1'b0;
                            INT <= 1'b1;
                            end_EXEC <= 1'b1;
                            execstate <= es_idle;
                        end
                        case(execstate)
                            es_seek: begin
                                if (seek_end[iUS]) begin
                                    execstate <= es_wseek;
                                    crcclr <= 1;
                                    deminit <= 1;
                                end else if (seek_err[iUS]) begin
                                    sIC <= 2'b01;
                                    sNR <= readyv[iUS];
                                    sEC <= 1;
                                    sSE <= 0;
                                    sHD <= HD;
                                    sUS <= US;
                                    INT <= 1;
                                    execstate <= es_idle;
                                end
                            end

                            es_wseek: begin
                                if (!seekbusy && hdld) begin
                                    execstate <= es_IAM0;
                                end
                            end

                            es_windex: begin
                                if (lindex && !indexb) begin
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM0: begin
                                if (!MF) begin
                                    if (fmmfedet) begin
                                        crcin <= 8'hfe;
                                        crcwr <= 1;
                                        DETSECT <= 1;
                                        execstate <= es_C;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                    end
                                end else if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM1;
                                end
                            end

                            es_IAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM3: begin
                                if (mfmrxed && mfmrxdat == 8'hfe) begin
                                    crcin <= 8'hfe;
                                    crcwr <= 1;
                                    DETSECT <= 1;
                                    execstate <= es_C;
                                end else if (mfmma1det || mfmmc2det || mfmrxed ) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_C: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxC <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_H;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxC <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_H;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_H: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxH <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_R;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed == 1'b1) begin
                                        rxH <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_R;
                                    end else if (mfmma1det || mfmmc2det ) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_R: begin
                                if (!MF) begin
                                    if (fmrxed == 1'b1) begin
                                        rxR <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_N;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet ) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxR <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_N;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_N: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxN <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCi0;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxN <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCi0;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end
                        
                            es_CRCi0: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCic;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCic;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCic: begin
                                if (crcdone) begin
                                    if (crczero && rxC == C && rxH == H && rxR == R && rxN == N) begin
                                        if (rxC == C) begin
                                            execstate <= es_GAP2;
                                            if (!MF) begin
                                                bytecount <= nfmGap2 - 3;
                                            end else begin
                                                bytecount <= nmfmGap2 - 3;
                                            end
                                            nturns <= 0;  // Reset IAM counter to avoid stop between data reading
                                            crcclr <= 1;
                                            sWC <= 0;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b01;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sWC <= 1;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                            execstate <= es_idle;
                                        end
                                    end else begin
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_GAP2: begin
                                if ((!MF && fmrxed) || (MF && mfmrxed)) begin
                                    if (bytecount > 0) begin
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            bytecount <= nfmSyncd - 1;
                                            fmtxwr <= 1;
                                        end else begin
                                            bytecount <= nmfmSyncd - 1;
                                            mfmtxwr <= 1;
                                        end
                                        dembreak <= 1;
                                        execstate <= es_Syncd;
                                        crcclr <= 1;
                                    end
                                end
                            end

                            es_Syncd: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (!MF) begin
                                            if (ecommand == cmd_WRITEDELETEDDATA) begin  // Deleted
                                                fmmf8wr <= 1;
                                                crcin <= 8'hf8;
                                            end else begin
                                                fmmfbwr <= 1;
                                                crcin <= 8'hfb;
                                            end
                                            crcwr <= 1;
                                        end else begin
                                            mfmma1wr <= 1;
                                            crcin <= 8'ha1;
                                            crcwr <= 1;
                                        end
                                        execstate <= es_DAM0;
                                    end
                                end
                            end
                            
                            es_DAM0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        if (!ND) begin
                                            DMARQ <= 1'b1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                        end
                                        sRQM <= 1'b1;
                                        sDIOd <= 1'b0;
                                        TCclr <= 1'b1;
                                        execstate <= es_DATA;
                                    end else begin
                                        mfmma1wr <= 1'b1;
                                        crcin <= 8'hA1;
                                        crcwr <= 1'b1;
                                        execstate <= es_DAM1;
                                    end
                                end

                                if (N == 8'h00 && DTL < 8'h80) begin
                                    bytecount <= {24'b0, DTL};
                                end else begin
                                    case (rxN)
                                        8'h00: bytecount <= 128;
                                        8'h01: bytecount <= 256;
                                        8'h02: bytecount <= 512;
                                        8'h03: bytecount <= 1024;
                                        8'h04: bytecount <= 2048;
                                        8'h05: bytecount <= 4096;
                                        8'h06: bytecount <= 8192;
                                        default: bytecount <= 16384;
                                    endcase
                                end
                            end

                            es_DAM1: begin
                                if (mfmtxemp) begin
                                    mfmma1wr <= 1'b1;
                                    crcin <= 8'hA1;
                                    crcwr <= 1'b1;
                                    execstate <= es_DAM2;
                                end
                            end

                            es_DAM2: begin
                                if (mfmtxemp) begin
                                    if (ecommand == cmd_WRITEDELETEDDATA) begin
                                        txdat <= 8'hF8;
                                        crcin <= 8'hF8;
                                    end else begin
                                        txdat <= 8'hFB;
                                        crcin <= 8'hFB;
                                    end
                                    mfmtxwr <= 1'b1;
                                    crcwr <= 1'b1;
                                    execstate <= es_DAM3;
                                end
                            end

                            es_DAM3: begin
                                if (mfmtxemp) begin
                                    if (!ND) begin
                                        DMARQ <= 1'b1;
                                    end else begin
                                        sHD <= HD;
                                        sUS <= US;
                                        sIC <= 2'b00;
                                        sNR <= readyv[iUS];
                                        sEC <= 1'b0;
                                        sSE <= 1'b0;
                                        INT <= 1'b1;
                                    end
                                    sRQM <= 1'b1;
                                    sDIOd <= 1'b0;
                                    TCclr <= 1'b1;
                                    execstate <= es_DATA;
                                end
                            end

                            es_DATA: begin
                                if (CPUWR_DATf || DMAWRxf) begin
                                    sRQM <= 1'b0;
                                    txdat <= CPUWRDAT;
                                    crcin <= CPUWRDAT;
                                    if (!MF) begin
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        mfmtxwr <= 1'b1;
                                    end
                                    crcwr <= 1'b1;
                                    if (bytecount > 1) begin
                                        bytecount <= bytecount - 1;
                                        execstate <= es_DATAw;
                                    end else begin
                                        execstate <= es_CRCd0;
                                    end
                                end else if ((!MF && fmtxend) || (MF && mfmtxend)) begin
                                    sOR <= 1'b1;
                                    execstate <= es_DATAs;
                                end
                            end
                            es_DATAw: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!sOR && !TCen) begin
                                        if (!ND) begin
                                            DMARQ <= 1'b1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                        end
                                        sRQM <= 1'b1;
                                        sDIOd <= 1'b0;
                                        execstate <= es_DATA;
                                    end else begin
                                        execstate <= es_DATAs;
                                    end
                                end
                            end
                            es_DATAs: begin
                                sRQM <= 1'b0;
                                txdat <= 8'h00;
                                crcin <= 8'h00;
                                if (!MF) begin
                                    fmtxwr <= 1'b1;
                                end else begin
                                    mfmtxwr <= 1'b1;
                                end
                                crcwr <= 1'b1;
                                if (bytecount > 1) begin
                                    bytecount <= bytecount - 1;
                                    execstate <= es_DATAw;
                                end else begin
                                    execstate <= es_CRCd0;
                                end
                            end

                            es_CRCd0: begin
                                if (((!MF && fmtxemp) || (MF && mfmtxemp)) && !crcbusy) begin
                                    txdat <= crcdat[15:8];
                                    if (!MF) begin
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        mfmtxwr <= 1'b1;
                                    end
                                    execstate <= es_CRCd1;
                                end
                            end

                            es_CRCd1: begin
                                if (((!MF && fmtxemp) || (MF && mfmtxemp)) && !crcbusy) begin
                                    txdat <= crcdat[7:0];
                                    if (!MF) begin
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        mfmtxwr <= 1'b1;
                                    end
                                    execstate <= es_GAP3;
                                end
                            end

                            es_GAP3: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= 8'hFF;
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        txdat <= 8'h4E;
                                        mfmtxwr <= 1'b1;
                                    end
                                    execstate <= es_NEXT;
                                end
                            end

                            es_NEXT: begin
                                if ((!MF && fmtxend) || (MF && mfmtxend)) begin
                                    bytecount <= GPL * 4;
                                    execstate <= es_NEXT2;
                                end
                            end

                            es_NEXT2: begin
                                if (modsft) begin
                                    if (bytecount > 0) begin
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (R != EOT) begin
                                            incR <= 1'b1;
                                        end else if (MT) begin
                                            if (!HD) begin
                                                resR <= 1'b1;
                                                setH <= 1'b1;
                                                setHD <= 1'b1;
                                            end else begin
                                                resR <= 1'b1;
                                                resH <= 1'b1;
                                                resHD <= 1'b1;
                                                incC <= 1'b1;
                                            end
                                        end else begin
                                            resR <= 1'b1;
                                            incC <= 1'b1;
                                        end

                                        if (sOR) begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b01;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                            execstate <= es_idle;
                                            end_EXEC <= 1'b1;
                                        end else if (TCen) begin
                                            execstate <= es_idle;
                                            sIC <= 2'b00;
                                            sHD <= HD;
                                            sUS <= US;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                            end_EXEC <= 1'b1;
                                        end else if (lastsect) begin
                                            // EOT without TC: end here, IC 01 and EN, C H R kept, as the reads (e71ad21)
                                            resR <= 1'b0;
                                            resH <= 1'b0;
                                            incC <= 1'b0;
                                            execstate <= es_idle;
                                            sIC <= 2'b01;
                                            sEN <= 1'b1;
                                            sHD <= HD;
                                            sUS <= US;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                            end_EXEC <= 1'b1;
                                        end else begin
                                            nturns <= 0;
                                            crcclr <= 1'b1;
                                            execstate <= es_IAM0;
                                        end
                                    end
                                end
                            end

                            default: begin
                                execstate <= es_idle;
                                end_EXEC <= 1'b1;
                            end
                        endcase
                    end
                    cmd_READID: begin
                        if (execstate != es_seek && !(execstate == es_wseek && !hdld) && lindex && !indexb) begin
                            if (nturns == 0) begin
                                nturns <= 1;
                            end else begin
                                if (MT && !HD) begin
                                    setHD <= 1'b1;
                                end else begin
                                    sHD <= HD;
                                    sUS <= US;
                                    sIC <= 2'b01;
                                    sNR <= readyv[iUS];
                                    sEC <= 1'b0;
                                    sSE <= 1'b0;
                                    if (!DETSECT) begin
                                        sMA <= 1'b1;
                                    end else begin
                                        sND <= 1'b1;
                                    end
                                    INT <= 1'b1;
                                    end_EXEC <= 1'b1;
                                    execstate <= es_idle;
                                end
                            end
                        end else if (NOTRDY) begin
                            sHD <= HD;
                            sUS <= US;
                            sIC <= 2'b11;
                            sNR <= readyv[iUS];
                            sEC <= 1'b0;
                            sSE <= 1'b0;
                            sND <= 1'b0;
                            sMA <= 1'b0;
                            INT <= 1'b1;
                            end_EXEC <= 1'b1;
                            execstate <= es_idle;
                        end
                        case (execstate)
                            es_wseek: begin
                                if (!seekbusy && hdld) begin
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM0: begin
                                if (!MF) begin
                                    if (fmmfedet) begin
                                        crcin <= 8'hfe;
                                        crcwr <= 1'b1;
                                        DETSECT <= 1'b1;
                                        execstate <= es_C;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmrxed) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                    end
                                end else begin
                                    if (mfmma1det) begin
                                        crcin <= 8'ha1;
                                        crcwr <= 1'b1;
                                        execstate <= es_IAM1;
                                    end
                                end
                            end

                            es_IAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1'b1;
                                    execstate <= es_IAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1'b1;
                                    crcclr <= 1'b1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1'b1;
                                    execstate <= es_IAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1'b1;
                                    crcclr <= 1'b1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM3: begin
                                if (mfmrxed && mfmrxdat == 8'hfe) begin
                                    crcin <= 8'hfe;
                                    crcwr <= 1'b1;
                                    DETSECT <= 1'b1;
                                    execstate <= es_C;
                                end else if (mfmma1det || mfmmc2det || mfmrxed) begin
                                    dembreak <= 1'b1;
                                    crcclr <= 1'b1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_C: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxC <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_H;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxC <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_H;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_H: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxH <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_R;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet ) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxH <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_R;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_R: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxR <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_N;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxR <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_N;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_N: begin
                                if (!MF) begin
                                    if (fmrxed == 1'b1) begin
                                        rxN <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCi0;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxN <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCi0;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1'b1;
                                        crcclr <= 1'b1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end
                            es_CRCi0: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCic: begin
                                if (crcdone) begin
                                    if (crczero) begin
                                        execstate <= es_idle;
                                        sIC <= 2'b00;
                                        sNR <= readyv[iUS];
                                        sEC <= 0;
                                        sSE <= 0;
                                        sHD <= HD;
                                        sUS <= US;
                                        INT <= 1;
                                        setC <= 1;
                                        if (rxH == 8'h00) begin
                                            resH <= 1;
                                        end else begin
                                            setH <= 1;
                                        end
                                        setR <= 1;
                                        setN <= 1;
                                        end_EXEC <= 1;
                                        crcclr <= 1;
                                    end else begin
                                        execstate <= es_IAM0;
                                        crcclr <= 1;
                                    end
                                end
                            end

                            default: begin
                                execstate <= es_idle;
                                end_EXEC <= 1;
                            end
                        endcase
                    end
                    cmd_SCANEQUAL,
                    cmd_SCANLOWEQUAL,
                    cmd_SCANHIGHEQUAL: begin
                        if (execstate != es_seek && !(execstate == es_wseek && !hdld) && lindex && !indexb) begin
                            if (nturns == 0) begin
                                nturns <= 1;
                            end else begin
                                sHD <= HD;
                                sUS <= US;
                                sIC <= 2'b01;
                                sNR <= readyv[iUS];
                                sEC <= '0;
                                sSE <= '0;
                                if (!DETSECT) begin
                                    sMA <= '1;
                                end else begin
                                    sND <= '1;
                                end
                                INT <= '1;
                                end_EXEC <= '1;
                                execstate <= es_idle;
                            end
                        end else if (NOTRDY) begin
                            sHD <= HD;
                            sUS <= US;
                            sIC <= 2'b11;
                            sNR <= readyv[iUS];
                            sEC <= '0;
                            sSE <= '0;
                            sND <= '0;
                            sMA <= '0;
                            INT <= '1;
                            end_EXEC <= '1;
                            execstate <= es_idle;
                        end
                        case(execstate)
                            es_seek: begin
                                if (seek_end[iUS]) begin
                                    execstate <= es_wseek;
                                    crcclr <= 1;
                                    deminit <= 1;
                                end else if (seek_err[iUS]) begin
                                    sIC <= 2'b01;
                                    sNR <= readyv[iUS];
                                    sEC <= 1;
                                    sSE <= 0;
                                    sHD <= HD;
                                    sUS <= US;
                                    INT <= 1;
                                    execstate <= es_idle;
                                end
                            end

                            es_wseek: begin
                                if (!seekbusy && hdld) begin
                                    execstate <= es_IAM0;
                                end
                            end

                            es_windex: begin
                                if (lindex && !indexb) begin
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM0: begin
                                if (!MF) begin
                                    if (fmmfedet) begin
                                        crcin <= 8'hfe;
                                        crcwr <= 1;
                                        DETSECT <= 1;
                                        execstate <= es_C;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                    end
                                end else begin
                                    if (mfmma1det) begin
                                        crcin <= 8'ha1;
                                        crcwr <= 1;
                                        execstate <= es_IAM1;
                                    end
                                end
                            end

                            es_IAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_IAM3: begin
                                if (mfmrxed && mfmrxdat == 8'hfe) begin
                                    crcin <= 8'hfe;
                                    crcwr <= 1;
                                    DETSECT <= 1;
                                    execstate <= es_C;
                                end else if (mfmma1det || mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_C: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxC <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_H;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxC <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_H;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_H: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxH <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_R;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxH <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_R;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_R: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxR <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_N;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxR <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_N;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_N: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        rxN <= fmrxdat;
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi0;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        rxN <= mfmrxdat;
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi0;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi0: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        execstate <= es_CRCi1;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCi1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1;
                                        dembreak <= 1;
                                        execstate <= es_CRCic;
                                    end else if (mfmma1det || mfmmc2det) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_CRCic: begin
                                if (crcdone) begin
                                    if (crczero && rxC == C && rxH == H && rxR == R && rxN == N) begin
                                        if (rxC == C) begin
                                            sWC <= 0;
                                            nturns <= 0; // Reset IAM counter to avoid stop between data reading
                                            execstate <= es_DAM0;
                                            crcclr <= 1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b01;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            sWC <= 1;
                                            INT <= 1;
                                            end_EXEC <= 1;
                                            execstate <= es_idle;
                                        end
                                    end else begin
                                        crcclr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_DAM0: begin
                                if (!MF) begin
                                    if (fmmf8det) begin
                                        sCM <= 1;
                                    end
                                    if (fmmfbdet || fmmf8det) begin
                                        if (fmmf8det) begin
                                            crcin <= 8'hf8;
                                        end else begin
                                            crcin <= 8'hfb;
                                        end
                                        crcwr <= 1;
                                        TCclr <= 1;
                                        sMD <= 0;
                                        execstate <= es_DATA;
                                        scancomp <= 0;
                                    end else if (fmmf8det || fmmfbdet || fmmfcdet || fmmfedet || fmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        sMD <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end else begin
                                    if (mfmma1det) begin
                                        crcin <= 8'ha1;
                                        crcwr <= 1;
                                        execstate <= es_DAM1;
                                    end else if (mfmmc2det || mfmrxed) begin
                                        dembreak <= 1;
                                        crcclr <= 1;
                                        sMD <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                                
                                if (N == 8'h00 && DTL < 8'h80) begin
                                    bytecount <= {24'b0, DTL};
                                end else begin
                                    case (rxN)
                                        8'h00: bytecount <= 128;
                                        8'h01: bytecount <= 256;
                                        8'h02: bytecount <= 512;
                                        8'h03: bytecount <= 1024;
                                        8'h04: bytecount <= 2048;
                                        8'h05: bytecount <= 4096;
                                        8'h06: bytecount <= 8192;
                                        default: bytecount <= 16384;
                                    endcase
                                end
                            end

                            es_DAM1: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_DAM2;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_DAM2: begin
                                if (mfmma1det) begin
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_DAM3;
                                end else if (mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end

                            es_DAM3: begin
                                if (mfmrxed) begin
                                    if (mfmrxdat == 8'hf8) begin
                                        sCM <= 1;
                                    end
                                end

                                if (mfmrxed && (mfmrxdat == 8'hfb || mfmrxdat == 8'hf8)) begin
                                    crcin <= mfmrxdat;
                                    crcwr <= 1;
                                    TCclr <= 1;
                                    sMD <= 0;
                                    execstate <= es_DATA;
                                    scancomp <= 0;
                                end else if (mfmma1det || mfmmc2det || mfmrxed) begin
                                    dembreak <= 1;
                                    crcclr <= 1;
                                    sMD <= 1;
                                    execstate <= es_IAM0;
                                end
                            end
                            
                            es_DATA: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        if (!ND) begin
                                            DMARQ <= 1'b1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                        end
                                        COMPDAT <= fmrxdat;
                                        sDIOd <= 1'b0;
                                        sRQM <= 1'b1;
                                        execstate <= es_DATAw;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        if (!ND) begin
                                            DMARQ <= 1'b1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            INT <= 1'b1;
                                        end
                                        COMPDAT <= mfmrxdat;
                                        sDIOd <= 1'b0;
                                        sRQM <= 1'b1;
                                        execstate <= es_DATAw;
                                    end
                                end
                            end

                            es_DATAw: begin
                                if (CPUWR_DATf || DMAWRxf) begin
                                    sRQM <= 1'b0;
                                    if (CPUWRDAT == 8'hFF || CPUWRDAT == COMPDAT || scancomp) begin
                                        if (bytecount > 1) begin
                                            bytecount <= bytecount - 1;
                                            execstate <= es_DATA;
                                        end else begin
                                            execstate <= es_CRCd0;
                                        end
                                    end else if (COMPDAT < CPUWRDAT && command == cmd_SCANLOWEQUAL) begin
                                        scancomp <= 1'b1;
                                        if (bytecount > 1) begin
                                            bytecount <= bytecount - 1;
                                            execstate <= es_DATA;
                                        end else begin
                                            execstate <= es_CRCd0;
                                        end
                                    end else if (COMPDAT > CPUWRDAT && command == cmd_SCANHIGHEQUAL) begin
                                        scancomp <= 1'b1;
                                        if (bytecount > 1) begin
                                            bytecount <= bytecount - 1;
                                            execstate <= es_DATA;
                                        end else begin
                                            execstate <= es_CRCd0;
                                        end
                                    end else begin
                                        sOR <= 1'b0;
                                        sIC <= 2'b01;
                                        sNR <= readyv[iUS];
                                        sEC <= 1'b0;
                                        sSE <= 1'b0;
                                        sHD <= HD;
                                        sUS <= US;
                                        INT <= 1'b1;
                                        end_EXEC <= 1'b1;
                                        execstate <= es_idle;
                                    end
                                end else if ((!MF && fmrxed) || (MF && mfmrxed)) begin
                                    sOR <= 1'b1;
                                    sIC <= 2'b01;
                                    sNR <= readyv[iUS];
                                    sEC <= 1'b0;
                                    sSE <= 1'b0;
                                    sHD <= HD;
                                    sUS <= US;
                                    INT <= 1'b1;
                                    end_EXEC <= 1'b1;
                                    execstate <= es_idle;
                                end
                            end

                            es_CRCd0: begin
                                if (!scancomp) begin
                                    sSH <= 1'b1;
                                end else begin
                                    sSH <= 1'b0;
                                end
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCd1;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCd1;
                                    end
                                end
                            end

                            es_CRCd1: begin
                                if (!MF) begin
                                    if (fmrxed) begin
                                        crcin <= fmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCdc;
                                    end
                                end else begin
                                    if (mfmrxed) begin
                                        crcin <= mfmrxdat;
                                        crcwr <= 1'b1;
                                        execstate <= es_CRCdc;
                                    end
                                end
                            end

                            es_CRCdc: begin
                                if (crcdone) begin
                                    if (crczero) begin
                                        if (R != EOT) begin
                                            incR <= 1'b1;
                                        end else if (MT) begin
                                            if (!HD) begin
                                                resR <= 1'b1;
                                                setH <= 1'b1;
                                                setHD <= 1'b1;
                                            end else begin
                                                resR <= 1'b1;
                                                resH <= 1'b1;
                                                resHD <= 1'b1;
                                                incC <= 1'b1;
                                            end
                                        end else begin
                                            resR <= 1'b1;
                                            incC <= 1'b1;
                                        end
                                        sDE <= 1'b0;
                                        if (TCen) begin
                                            execstate <= es_idle;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1'b1;
                                            end_EXEC <= 1'b1;
                                        end else if (lastsect) begin
                                            // EOT without TC: end here with EN (2620836)
                                            execstate <= es_idle;
                                            sIC <= 2'b00;
                                            sEN <= 1'b1;
                                            sNR <= readyv[iUS];
                                            sEC <= 1'b0;
                                            sSE <= 1'b0;
                                            sHD <= HD;
                                            sUS <= US;
                                            INT <= 1'b1;
                                            end_EXEC <= 1'b1;
                                        end else begin
                                            nturns <= 0;
                                            crcclr <= 1'b1;
                                            execstate <= es_IAM0;
                                        end
                                    end else begin
                                        sDE <= 1'b1;
                                        sIC <= 2'b01;
                                        sNR <= readyv[iUS];
                                        sEC <= 1'b0;
                                        sSE <= 1'b0;
                                        sHD <= HD;
                                        sUS <= US;
                                        sDD <= 1'b1;
                                        INT <= 1'b1;
                                        execstate <= es_idle;
                                        end_EXEC <= 1'b1;
                                    end
                                end
                            end

                            default: begin
                                execstate <= es_idle;
                            end
                        endcase
                    end
                    cmd_FORMATATRACK: begin
                        if (!WPRT) begin
                            sIC <= 2'b01;
                            sNR <= readyv[iUS];
                            sEC <= 1'b0;
                            sSE <= 1'b0;
                            sNW <= 1'b1;
                            sHD <= HD;
                            sUS <= US;
                            INT <= 1'b1;
                            end_EXEC <= 1'b1;
                            execstate <= es_idle;
                        end else if (execstate != es_wseek && lindex && !indexb) begin
                            if (sOR) begin
                                modbreak <= 1'b1;
                                sHD <= HD;
                                sUS <= US;
                                sIC <= 2'b01;
                                sNR <= readyv[iUS];
                                sEC <= 1'b0;
                                sSE <= 1'b0;
                                INT <= 1'b1;
                                execstate <= es_idle;
                                end_EXEC <= 1'b1;
                            end else if (execstate != es_windex) begin
                                modbreak <= 1'b1;
                                sHD <= HD;
                                sUS <= US;
                                sIC <= 2'b00;
                                sNR <= readyv[iUS];
                                sEC <= 1'b0;
                                sSE <= 1'b0;
                                INT <= 1'b1;
                                end_EXEC <= 1'b1;
                                execstate <= es_idle;
                            end
                        end else if (NOTRDY) begin
                            sHD <= HD;
                            sUS <= US;
                            sIC <= 2'b11;
                            sNR <= readyv[iUS];
                            sEC <= 1'b0;
                            sSE <= 1'b0;
                            sND <= 1'b0;
                            sMA <= 1'b0;
                            INT <= 1'b1;
                            end_EXEC <= 1'b1;
                            execstate <= es_idle;
                        end

                        case(execstate)
                            es_wseek: begin
                                if (!seekbusy && hdld) begin
                                    execstate <= es_windex;
                                end
                            end

                            es_windex: begin
                                if (lindex && !indexb) begin
                                    if (!MF) begin
                                        bytecount <= nfmGap0 - 1;
                                        txdat <= 8'hff;
                                        fmtxwr <= 1;
                                    end else begin
                                        bytecount <= nmfmGap0 - 1;
                                        txdat <= 8'h4e;
                                        mfmtxwr <= 1;
                                    end
                                    execstate <= es_GAP0;
                                end
                            end

                            es_GAP0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        if (!MF) begin
                                            txdat <= 8'hff;
                                            fmtxwr <= 1;
                                        end else begin
                                            txdat <= 8'h4e;
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                            bytecount <= nfmSyncp;
                                        end else begin
                                            mfmtxwr <= 1;
                                            bytecount <= nmfmSyncp;
                                        end
                                        execstate <= es_Syncp;
                                    end
                                end
                            end

                            es_Syncp: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (!MF) begin
                                            fmmfcwr <= 1;
                                        end else begin
                                            mfmmc2wr <= 1;
                                        end
                                        execstate <= es_IM0;
                                    end
                                end
                            end

                            es_IM0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= 8'hff;
                                        fmtxwr <= 1;
                                        bytecount <= nfmGap1 - 1;
                                        execstate <= es_GAP1;
                                    end else begin
                                        mfmmc2wr <= 1;
                                        execstate <= es_IM1;
                                    end
                                end
                            end

                            es_IM1: begin
                                if (mfmtxemp) begin
                                    mfmmc2wr <= 1;
                                    execstate <= es_IM2;
                                end
                            end

                            es_IM2: begin
                                if (mfmtxemp) begin
                                    txdat <= 8'hfc;
                                    mfmtxwr <= 1;
                                    execstate <= es_IM3;
                                end
                            end

                            es_IM3: begin
                                if (mfmtxemp) begin
                                    txdat <= 8'h4e;
                                    mfmtxwr <= 1;
                                    bytecount <= nmfmGap1 - 1;
                                    execstate <= es_GAP1;
                                end
                            end

                            es_GAP1: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        if (!MF) begin
                                            txdat <= 8'hff;
                                            fmtxwr <= 1;
                                        end else begin
                                            txdat <= 8'h4e;
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                            bytecount <= nfmSynci - 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                            bytecount <= nmfmSynci - 1;
                                        end
                                        execstate <= es_Synci;
                                        crcclr <= 1;
                                    end
                                end
                            end

                            es_Synci: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (!MF) begin
                                            fmmfewr <= 1;
                                            crcin <= 8'hfe;
                                        end else begin
                                            mfmma1wr <= 1;
                                            crcin <= 8'ha1;
                                        end
                                        crcwr <= 1;
                                        execstate <= es_IAM0;
                                    end
                                end
                            end

                            es_IAM0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        if (!ND) begin
                                            DMARQ <= 1;
                                        end else begin
                                            sHD <= HD;
                                            sUS <= US;
                                            sIC <= 2'b00;
                                            sNR <= readyv[iUS];
                                            sEC <= 0;
                                            sSE <= 0;
                                            INT <= 1;
                                        end
                                        sRQM <= 1;
                                        sDIOd <= 0;
                                        execstate <= es_C;
                                    end else begin
                                        mfmma1wr <= 1;
                                        crcin <= 8'ha1;
                                        execstate <= es_IAM1;
                                    end
                                    crcwr <= 1;
                                end
                            end

                            es_IAM1: begin
                                if (mfmtxemp) begin
                                    mfmma1wr <= 1;
                                    crcin <= 8'ha1;
                                    crcwr <= 1;
                                    execstate <= es_IAM2;
                                end
                            end

                            es_IAM2: begin
                                if (mfmtxemp) begin
                                    txdat <= 8'hfe;
                                    crcin <= 8'hfe;
                                    mfmtxwr <= 1;
                                    crcwr <= 1;
                                    execstate <= es_IAM3;
                                end
                            end

                            es_IAM3: begin
                                if (mfmtxemp) begin
                                    if (!ND) begin
                                        DMARQ <= 1;
                                    end else begin
                                        sHD <= HD;
                                        sUS <= US;
                                        sIC <= 2'b00;
                                        sNR <= readyv[iUS];
                                        sEC <= 0;
                                        sSE <= 0;
                                        INT <= 1;
                                    end
                                    sRQM <= 1;
                                    sDIOd <= 0;
                                    execstate <= es_C;
                                end
                            end

                            es_C, 
                            es_H, 
                            es_R, 
                            es_N: begin
                                if (CPUWR_DATf || DMAWRxf) begin
                                    sRQM <= 1'b0;
                                    txdat <= CPUWRDAT;
                                    crcin <= CPUWRDAT;
                                    if (!MF) begin
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        mfmtxwr <= 1'b1;
                                    end
                                    crcwr <= 1'b1;
                                    case (execstate)
                                        es_C: execstate <= es_Cw;
                                        es_H: execstate <= es_Hw;
                                        es_R: execstate <= es_Rw;
                                        es_N: execstate <= es_Nw;
                                        default: execstate <= es_idle;
                                    endcase
                                end else if ((!MF && fmtxend) || (MF && mfmtxend)) begin
                                    sOR <= 1'b1;
                                    execstate <= es_GAP4;
                                end
                            end
                            
                            es_Cw,
                            es_Hw, 
                            es_Rw: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!ND) begin
                                        DMARQ <= 1'b1;
                                    end else begin
                                        sHD <= HD;
                                        sUS <= US;
                                        sIC <= 2'b00;
                                        sNR <= readyv[iUS];
                                        sEC <= 1'b0;
                                        sSE <= 1'b0;
                                        INT <= 1'b1;
                                    end
                                    sRQM <= 1'b1;
                                    sDIOd <= 1'b0;
                                    case (execstate)
                                        es_Cw: execstate <= es_H;
                                        es_Hw: execstate <= es_R;
                                        es_Rw: execstate <= es_N;
                                        default: execstate <= es_idle;
                                    endcase
                                end
                            end

                            es_Nw: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    txdat <= crcdat[15:8];
                                    if (!MF) begin
                                        fmtxwr <= 1'b1;
                                    end else begin
                                        mfmtxwr <= 1'b1;
                                    end
                                    execstate <= es_CRCi0;
                                end
                            end

                            es_CRCi0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    txdat <= crcdat[7:0];
                                    if (!MF) begin
                                        fmtxwr <= 1;
                                    end else begin
                                        mfmtxwr <= 1;
                                    end
                                    execstate <= es_CRCi1;
                                end
                            end

                            es_CRCi1: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= 8'hFF;
                                        fmtxwr <= 1;
                                        bytecount <= nfmGap2 - 1;
                                    end else begin
                                        txdat <= 8'h4E;
                                        mfmtxwr <= 1;
                                        bytecount <= nmfmGap2 - 1;
                                    end
                                    execstate <= es_GAP2;
                                end
                            end

                            es_GAP2: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        if (!MF) begin
                                            txdat <= 8'hFF;
                                            fmtxwr <= 1;
                                        end else begin
                                            txdat <= 8'h4E;
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                            bytecount <= nfmSyncd - 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                            bytecount <= nmfmSyncd - 1;
                                        end
                                        crcclr <= 1;
                                        execstate <= es_Syncd;
                                    end
                                end
                            end

                            es_Syncd: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 0) begin
                                        txdat <= 8'h00;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (!MF) begin
                                            fmmfbwr <= 1;
                                            crcin <= 8'hFB;
                                        end else begin
                                            mfmma1wr <= 1;
                                            crcin <= 8'hA1;
                                        end
                                        crcwr <= 1;
                                        execstate <= es_DAM0;
                                    end
                                end
                            end

                            es_DAM0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= D;
                                        crcin <= D;
                                        fmtxwr <= 1;
                                        execstate <= es_DATA;
                                    end else begin
                                        mfmma1wr <= 1;
                                        crcin <= 8'hA1;
                                        execstate <= es_DAM1;
                                    end
                                    crcwr <= 1;
                                    case (N)
                                        8'h00: bytecount <= 128;
                                        8'h01: bytecount <= 256;
                                        8'h02: bytecount <= 512;
                                        8'h03: bytecount <= 1024;
                                        8'h04: bytecount <= 2048;
                                        8'h05: bytecount <= 4096;
                                        8'h06: bytecount <= 8192;
                                        default: bytecount <= 16384;
                                    endcase
                                end
                            end

                            es_DAM1: begin
                                if (mfmtxemp) begin
                                    mfmma1wr <= 1;
                                    crcin <= 8'hA1;
                                    crcwr <= 1;
                                    execstate <= es_DAM2;
                                end
                            end

                            es_DAM2: begin
                                if (mfmtxemp) begin
                                    txdat <= 8'hFB;
                                    crcin <= 8'hFB;
                                    mfmtxwr <= 1;
                                    crcwr <= 1;
                                    execstate <= es_DAM3;
                                end
                            end

                            es_DAM3: begin
                                if (mfmtxemp) begin
                                    txdat <= D;
                                    crcin <= D;
                                    mfmtxwr <= 1;
                                    crcwr <= 1;
                                    execstate <= es_DATA;
                                end
                            end
                            
                            es_DATA: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 1) begin
                                        txdat <= D;
                                        crcin <= D;
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        crcwr <= 1;
                                        bytecount <= bytecount - 1;
                                    end else if (!crcbusy) begin
                                        txdat <= crcdat[15:8];
                                        if (!MF) begin
                                            fmtxwr <= 1;
                                        end else begin
                                            mfmtxwr <= 1;
                                        end
                                        execstate <= es_CRCd0;
                                    end
                                end
                            end

                            es_CRCd0: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    txdat <= crcdat[7:0];
                                    if (!MF) begin
                                        fmtxwr <= 1;
                                    end else begin
                                        mfmtxwr <= 1;
                                    end
                                    execstate <= es_CRCd1;
                                    crcclr <= 1;
                                end
                            end

                            es_CRCd1: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= 8'hFF;
                                        fmtxwr <= 1;
                                    end else begin
                                        txdat <= 8'h4E;
                                        mfmtxwr <= 1;
                                    end
                                    bytecount <= {24'b0, GPL} - 1;
                                    execstate <= es_GAP3;
                                end
                            end

                            es_GAP3: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (bytecount > 1) begin
                                        if (!MF) begin
                                            txdat <= 8'hFF;
                                            fmtxwr <= 1;
                                        end else begin
                                            txdat <= 8'h4E;
                                            mfmtxwr <= 1;
                                        end
                                        bytecount <= bytecount - 1;
                                    end else begin
                                        if (cntR < SC) begin
                                            txdat <= 8'h00;
                                            if (!MF) begin
                                                fmtxwr <= 1;
                                                bytecount <= nfmSynci - 1;
                                            end else begin
                                                mfmtxwr <= 1;
                                                bytecount <= nmfmSynci - 1;
                                            end
                                            cntR <= cntR + 8'd1;
                                            execstate <= es_Synci;
                                        end else begin
                                            if (!MF) begin
                                                txdat <= 8'hFF;
                                                fmtxwr <= 1;
                                            end else begin
                                                txdat <= 8'h4E;
                                                mfmtxwr <= 1;
                                            end
                                            execstate <= es_GAP4;
                                        end
                                    end
                                end
                            end

                            es_GAP4: begin
                                if ((!MF && fmtxemp) || (MF && mfmtxemp)) begin
                                    if (!MF) begin
                                        txdat <= 8'hFF;
                                        fmtxwr <= 1;
                                    end else begin
                                        txdat <= 8'h4E;
                                        mfmtxwr <= 1;
                                    end
                                end
                            end

                            default: begin
                                execstate <= es_idle;
                                end_EXEC <= 1;
                            end
                        endcase
                    end
                    cmd_RECALIBRATE,
                    cmd_SEEK: begin
                        case(execstate)
                            es_readychk: begin
                                if (!readyv[iUS]) begin
                                    case (command)
                                        cmd_RECALIBRATE: seek_init <= 1'b1;
                                        cmd_SEEK:        seek_bgn  <= 1'b1;
                                        default: ;
                                    endcase
                                    execstate <= es_seek;
                                end else begin
                                    // not ready: end at once, abnormal with SE (a9ab3e6; it waited
                                    // for NRDET and ended with IC 11 that Sense Interrupt missed)
                                    sHD   <= HD;
                                    sUS   <= US;
                                    sIC   <= 2'b01;
                                    sNR   <= readyv[iUS];
                                    sEC   <= 1'b0;
                                    sSE   <= 1'b1;
                                    sND   <= 1'b0;
                                    sMA   <= 1'b0;
                                    sisst0[US] <= {2'b01, 1'b1, 1'b0, readyv[iUS], HD, US};
                                    sispcn[US] <= cPCN;
                                    sisvld[US] <= 1'b1;
                                    INTs  <= 1'b1;
                                    end_EXEC <= 1'b1;
                                    execstate <= es_idle;
                                end
                            end

                            es_seek: begin
                                end_EXEC <= 1'b1;
                                sRQM    <= 1'b1;
                                execstate <= es_idle;
                            end

                            default: execstate <= es_idle;
                        endcase
                    end
                    default: begin
                        execstate <= es_idle;
					    end_EXEC <= '1;
                    end
                endcase
            end
            lindex <= indexb;
        end
    end

    // A FH enters the result phase of a read about 0.09 ms after its end: the end of the
    // execution and its interrupt wait resdly clocks with RQM low (fb70fdc)
    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn) begin
            resdcnt   <= '0;
            resdint   <= 1'b0;
            end_EXECd <= 1'b0;
        end else begin
            end_EXECd <= 1'b0;
            if (resdstart) begin
                resdcnt <= RW'(resdly);
                resdint <= INT;
            end else if (resdcnt == 1'b1) begin
                resdcnt   <= '0;
                end_EXECd <= 1'b1;
            end else if (resdcnt != '0) begin
                resdcnt <= resdcnt - 1'b1;
            end
        end
    end
    // only the reads were measured; the interrupt for a data byte (non-DMA) goes at once
    assign resdrd    = ecommand == cmd_READDATA || ecommand == cmd_READDELETEDDATA ||
                       ecommand == cmd_READID || ecommand == cmd_READATRACK;
    assign resdstart = end_EXEC && resdrd;
    assign end_EXECo = (end_EXEC && !resdrd) || end_EXECd;
    assign INTd      = (INT && !resdstart) || (end_EXECd && resdint);
    assign resdhold  = resdstart || resdcnt != '0 || end_EXECd;
    assign INTEV     = INTs || INTd;

    assign sisany = |sisvld;
    assign sisdrv = sisvld[0] ? 2'd0 : sisvld[1] ? 2'd1 : sisvld[2] ? 2'd2 : 2'd3;

    // Sense Interrupt reports the per-drive results (sisvld), not the interrupt line (a9ab3e6)
    always_ff @(posedge sclk or negedge rstn) begin
        if (!rstn)
            INTn <= 1'b1;
        else if (INTs || INTd)
            INTn <= 1'b0;
        else if (CPUWR_DAT || CPURD_DAT)
            INTn <= 1'b1;
    end

    always_ff @(posedge sclk or negedge rstn) begin
        if (!rstn)
            sTC <= 1'b0;
        else if (TC)
            sTC <= 1'b1;
        else if (TCen)
            sTC <= 1'b0;
    end

    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn)
            TCen <= 1'b0;
        else if (TCclr)
            TCen <= 1'b0;
        else if (sTC)
            TCen <= 1'b1;
    end

    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn) begin
            sDxB    <= '0;
            DxBclrd <= 1'b0;
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (seek_busyv[i] || seekpend[i]) begin
                    sDxB[i] <= 1'b1;
                end
            end
            DxBclrd <= DxBclr;
            if (DxBclr && !DxBclrd) begin
                sDxB[SISUS] <= 1'b0;            // only the reported drive (a9ab3e6)
            end
        end
    end

    // Head load before a read or write: HLT x 4 ms (0 = 128), unload HUT x 32 ms (0 = 16) after the
    // last read or write; the units of the uPD765 at 4 MHz = 250 kbit/s (d86e4d8, PC-8801FH)
    always_ff @(posedge fclk or negedge rstn) begin
        if (!rstn) begin
            hdld  <= 1'b0;
            hlrun <= 1'b0;
            hlcnt <= '0;
            hucnt <= '0;
        end else begin
            if (execstate == es_wseek && !hdld) begin
                if (!hlrun) begin
                    hlrun <= 1'b1;
                    hlcnt <= HLT == 7'd0 ? 11'd1024 : {1'b0, HLT, 3'b000};
                end else if (hmssft) begin
                    if (hlcnt <= 11'd1) begin
                        hdld  <= 1'b1;
                        hlrun <= 1'b0;
                    end else begin
                        hlcnt <= hlcnt - 1'b1;
                    end
                end
            end else begin
                hlrun <= 1'b0;
            end
            // SEEK and RECALIBRATE do not restart the unload time
            if (hdld && (execstate == es_idle || ecommand == cmd_SEEK || ecommand == cmd_RECALIBRATE)) begin
                if (hmssft) begin
                    if ((HUT == 4'd0 && hucnt >= 11'd1023) || (HUT != 4'd0 && hucnt >= {1'b0, HUT, 6'd0} - 11'd1)) begin
                        hdld  <= 1'b0;
                        hucnt <= '0;
                    end else begin
                        hucnt <= hucnt + 1'b1;
                    end
                end
            end else begin
                hucnt <= '0;
            end
        end
    end

    digifilter ixflt(
        .D(index),
        .Q(indexb),
        .clk(fclk),
        .rstn(rstn)
    );

    digifilter t0flt(
        .D(track0),
        .Q(track0b),
        .clk(fclk),
        .rstn(rstn)
    );

    digifilter t0flts(
        .D(track0),
        .Q(track0s),
        .clk(sclk),
        .rstn(rstn)
    );

    assign sCB = datnum == 0 ? 1'b0 : 1'b1;
    assign iUS = {30'b0, US};

    assign sDIO  = RD_CMD ? sDIOc : sDIOd;
    assign sideb = HD;
    assign side  = ~sideb;
    assign uselb = US;
    always_comb begin
        sEXM  = (execstate != es_idle || resdhold) && ND;

	    ST0   = {sIC, sSE, sEC, sNR, sHD, sUS};
	    ST1   = {sEN, 1'b0, sDE, sOR, 1'b0, sND, sNW, sMA};
	    ST2   = {1'b0, sCM, sDD, sWC, sSH, sSN, sBC, sMD};
	    // RY per drive (a9ab3e6; PC88_MiSTer f9c38d0 ties it to 1 for the PC-8801 board, not taken)
	    ST3   = {1'b0, ~WPRT, ~readyv[uselb], ~track0s, TWOSIDE[uselb], sideb, uselb};

	    MSR   = {sRQM && !resdhold, sDIO, sEXM, sCB, sDxB};
	
	    RDAT  = !DACKn ? RDDAT_DAT :
                !A0    ? MSR :
                RD_CMD ? RDDAT_CMD : RDDAT_DAT;
        
	    usel  = seekbusy ? seekusel : US;
	
	    case(US)
            2'b00: bitwidth = 32'(int0);
            2'b01: bitwidth = 32'(int1);
            2'b10: bitwidth = 32'(int2);
            2'b11: bitwidth = 32'(int3);
        endcase
    end

    sftdiv #(.width(4)) sksft (
        .sel(~SRT),
		.sftin(hmssft),
		
		.sftout(seek_sft),
		
		.clk(fclk),
		.rstn(rstn)
    );   

    assign iC  = {24'b0, $unsigned(C)};
    assign tdi = {td3, td2, td1, td0};

    seekcont seekcnt (
        .uselin(US),
		.inireq(seek_init),
		.seekreq(seek_bgn),
		.destin(iC),
		.tdi(tdi),
		
		.iniout(seek_initv),
		.seekout(seek_bgnv),
		.dest0(iC0),
		.dest1(iC1),
		.dest2(iC2),
		.dest3(iC3),
		.tdo(tdo),
		.readyin(READY),
		
		.sendin(seek_endv),
		.serrin(seek_errv),
		.sbusyin(seek_busyv),
		
		.seek_end(seek_end),
		.seek_err(seek_err),
		.readyout(),

		.seek_pend(seekpend),
		.busy(seekbusy),
		.uselout(seekusel),
		
		.clk(fclk),
		.rstn(rstn)
    );

    always_comb begin
        // 2D double steps are done by the drive, not the FDC (cb745a4)
        seek_cyl0 = iC0;
        seek_cyl1 = iC1;
        seek_cyl2 = iC2;
        seek_cyl3 = iC3;

        seek_sft0 = seekusel==2'b00 ? seek_sft : '0;
        seek_sft1 = seekusel==2'b01 ? seek_sft : '0;
        seek_sft2 = seekusel==2'b10 ? seek_sft : '0;
        seek_sft3 = seekusel==2'b11 ? seek_sft : '0;
    end

    headseek #(.maxtrack(maxtrack), .maxset(30), .initseek(0)) hds0 (
        .desttrack(seek_cyl0),
		.destset(seek_bgnv[0]),
		.setwait(0),
	
		.curtrack(seek_cur0),
	
		.reachtrack(seek_endv[0]),
		.busy(seek_busyv[0]),
	
		.track0(track0b),
		.seek(STEP0),
		.sdir(SDIR0),
	
		.init(seek_initv[0]),
		.seekerr(seek_errv[0]),
		.sft(seek_sft0),
		.clk(fclk),
		.rstn(rstn)
    );
    
    headseek #(.maxtrack(maxtrack), .maxset(30), .initseek(0)) hds1 (
        .desttrack(seek_cyl1),
		.destset(seek_bgnv[1]),
		.setwait(0),
	
		.curtrack(seek_cur1),
	
		.reachtrack(seek_endv[1]),
		.busy(seek_busyv[1]),
	
		.track0(track0b),
		.seek(STEP1),
		.sdir(SDIR1),
	
		.init(seek_initv[1]),
		.seekerr(seek_errv[1]),
		.sft(seek_sft1),
		.clk(fclk),
		.rstn(rstn)
    );
    
    headseek #(.maxtrack(maxtrack), .maxset(30), .initseek(0)) hds2 (
        .desttrack(seek_cyl2),
		.destset(seek_bgnv[2]),
		.setwait(0),
	
		.curtrack(seek_cur2),
	
		.reachtrack(seek_endv[2]),
		.busy(seek_busyv[2]),
	
		.track0(track0b),
		.seek(STEP2),
		.sdir(SDIR2),
	
		.init(seek_initv[2]),
		.seekerr(seek_errv[2]),
		.sft(seek_sft2),
		.clk(fclk),
		.rstn(rstn)
    );

    headseek #(.maxtrack(maxtrack), .maxset(30), .initseek(0)) hds3 (
        .desttrack(seek_cyl3),
		.destset(seek_bgnv[3]),
		.setwait(0),
	
		.curtrack(seek_cur3),
	
		.reachtrack(seek_endv[3]),
		.busy(seek_busyv[3]),
	
		.track0(track0b),
		.seek(STEP3),
		.sdir(SDIR3),
	
		.init(seek_initv[3]),
		.seekerr(seek_errv[3]),
		.sft(seek_sft3),
		.clk(fclk),
		.rstn(rstn)
    );

    always_comb begin
        seek_busy = seek_busyv[seekusel];
        
        case(seekusel)
            2'b00: STEP = STEP0;
            2'b01: STEP = STEP1;
            2'b10: STEP = STEP2;
            2'b11: STEP = STEP3;
        endcase

        case(seekusel)
            2'b00: SDIR = SDIR0;
            2'b01: SDIR = SDIR1;
            2'b10: SDIR = SDIR2;
            2'b11: SDIR = SDIR3;
        endcase

        PCN0 = seek_cur0[7:0];
        PCN1 = seek_cur1[7:0];
        PCN2 = seek_cur2[7:0];
        PCN3 = seek_cur3[7:0];

        mPCN0 = PCN0;
        mPCN1 = PCN1;
        mPCN2 = PCN2;
        mPCN3 = PCN3;

        case(US)
            2'b00: cPCN = mPCN0;
            2'b01: cPCN = mPCN1;
            2'b10: cPCN = mPCN2;
            2'b11: cPCN = mPCN3;
        endcase
    end

    crcgenn #(.DATWIDTH(8), .WIDTH(16)) CRCG (
        .POLY(17'b10000100000010001),
		.DATA(crcin),
		.DIR('0),
		.WRITE(crcwr),
		.BITIN('0),
		.BITWR('0),
		.CLR(crcclr),
		.CLRDAT(16'hffff),
		.CRC(crcdat),
		.BUSY(crcbusy),
		.DONE(crcdone),
		.CRCZERO(crczero),

		.clk(fclk),
		.rstn(rstn)
    );

    fmdem #(.bwidth(maxbwidth)) FMD (
        	.bitlen(bitwidth),
	
            .datin(RDBIT),

            .init(deminit),
            .brk(dembreak),

            .RXDAT(fmrxdat),
            .RXED(fmrxed),
            .DetMF8(fmmf8det),
            .DetMFB(fmmfbdet),
            .DetMFC(fmmfcdet),
            .DetMFE(fmmfedet),

            .clk(fclk),
            .rstn(rstn)
    );

    mfmdem #(.bwidth(maxbwidth/2)) MFMD (
        .bitlen(bitwidth/2),
	
        .datin(RDBIT),
        
        .init(deminit),
        .brk(dembreak),
        
        .RXDAT(mfmrxdat),
        .RXED(mfmrxed),
        .DetMA1(mfmma1det),
        .DetMC2(mfmmc2det),
        
        .clk(fclk),
        .rstn(rstn)
    );

    // write bit cell in 1/256 clocks (6a42cb2): intf* / intm* with fracin, else int* x 256
    always_comb begin
        if (fracin)
            case (US)
                2'b00:   sftwidth = MF ? intm0 : intf0;
                2'b01:   sftwidth = MF ? intm1 : intf1;
                2'b10:   sftwidth = MF ? intm2 : intf2;
                default: sftwidth = MF ? intm3 : intf3;
            endcase
        else
            sftwidth = FW'((MF ? bitwidth/2 : bitwidth) * 256);
    end

    sftfrac #(.maxlen(maxfwidth)) sgen (
        .len(sftwidth),
		.sft(modsft),
		
		.clk(fclk),
		.rstn(rstn)
    );

    fmmod FMM (
	    .txdat(txdat),
        .txwr(fmtxwr),
        .txmf8(fmmf8wr),
        .txmfb(fmmfbwr),
        .txmfc(fmmfcwr),
        .txmfe(fmmfewr),
        .brk(modbreak),
        
        .txemp(fmtxemp),
        .txend(fmtxend),
        
        .bitout(fmwrbit),
        .writeen(fmwren),
        
        .sft(modsft),
        .clk(fclk),
        .rstn(rstn)
);

    mfmmod MFMM (
        .txdat(txdat),
        .txwr(mfmtxwr),
        .txma1(mfmma1wr),
        .txmc2(mfmmc2wr),
        .brk(modbreak),

        .txemp(mfmtxemp),
        .txend(mfmtxend),

        .bitout(mfmwrbit),
        .writeen(mfmwren),

        .sft(modsft),
        .clk(fclk),
        .rstn(rstn)
    );
    
    nrdet #(.TOms(rdytout*2)) RDET (
        .start(NRDSTART),
        .RDY(!readyv[iUS]),
        .NOTRDY(NOTRDY),
        .mssft(hmssft),
        .clk(fclk),
        .rstn(rstn)
    );
     
    assign wrbits = MF ? mfmwrbit : fmwrbit;
    assign wrens  = MF ? mfmwren  : fmwren;
    
    signext wbext (
        .len(extcount),
        .signin(wrbits),
        .signout(wrbitex),
        .clk(fclk),
        .rstn(rstn)
    );

    signext weext (
        .len(extcount),
        .signin(wrens),
        .signout(wrenex),
        .clk(fclk),
        .rstn(rstn)
    );

    assign WREN  = !wrenex;
	assign WRBIT = !wrbitex;
    assign busy  = seek_busy || datnum != 0;
    assign mfm   = MF;

endmodule
