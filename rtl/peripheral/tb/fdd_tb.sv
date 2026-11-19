// Floppy drive unit (fdd) read path, driven by the real controller: dev_WD2793 (Philips
// glue) + wd279x, blockDevMux and a model of the HPS block transfer serving DSK images.
// Images hold a pattern that identifies image (seed) and LBA in every sector.
//
// Checked: sector LBA for 720K / 360K / 640K images and both sides, multi-sector read,
// disk change, slow SD (no stale track data), a transfer of another virtual disk does not
// touch the track buffer, second drive, track beyond the image,
// unformatted 2nd side of a single-sided disk, index only with motor, IAM C2 C2 C2 FC,
// FM cell rate; new configuration: single-sided drive, TRACK0 needs motor (Philips);
// disk change: Philips 7FFDh bit 2 per selected drive, cleared by the read, DSKCHGn per drive;
// READY without the motor (openMSX), motor keeps running motor_off_ms, a seek with 6 ms steps
// loads only the target track (head settle).
// Write path (a second unit on VD 3, 4 driven directly, the controller side is the MFM
// modulator of the modem library): write sector into the buffer and the image, neighbours
// intact, bad CRC rejected and the track reloaded, write protected image ignores the gate,
// format of a track (IDs of the stream choose the slots), write followed by a step with a slow
// HPS still reaches the written track, READ DATA silent while the gate is open.
// WD2793 writes (drive A): Write Sector A0h into the image and read back, deleted mark A1h,
// multi-sector B0h ended by D0h, Lost Data when DRQ is not serviced (write and read), write
// protected disk (status bit 6, nothing taken), head load flag of type I (h).
// WD2793 type III: Read Address C0h (6 bytes with the CRC of the disk, sector register), Write
// Track F0h with the MSX-DOS layout (9 sectors of E5 in the image), Read Track E0h (the ID of
// sector 1 in the raw bytes), Write Track Lost Data before the index and on a protected disk.
// FM through the WD2793 (density = FM): read, write, Read Address, back to MFM.
// WD2795/7 (bare wd279x with WD279_57 on VD 5, 6, SSO wired to SIDE): U selects the side for a
// read and for Read Address, L = 0 makes N = 2 a 1024 byte sector.
//
// Run: wsl.exe -- bash rtl/peripheral/tb/run_fdd.sh          (OLD=<git rev>: old FDD code)
module fdd_tb;

localparam int SYS   = 21477270;
localparam int MS    = SYS / 1000;
localparam int VDNUM = 7;

logic clk = 0, reset = 1;
always #1 clk = ~clk;
longint unsigned cyc = 0;
always @(posedge clk) cyc <= cyc + 1;

int errors = 0;
task automatic fail(input string msg);
    errors++;
    $display("FAIL %s", msg);
endtask

// ------------------------------------------------------------------ CPU bus + controller
cpu_bus_if cpu_bus(clk, reset);
logic [15:0] addr = '0;
logic  [7:0] dbo  = '0;
logic        mreq = 0, rd = 0, wr = 0, req = 0;
assign cpu_bus.addr = addr;  assign cpu_bus.data = dbo;
assign cpu_bus.mreq = mreq;  assign cpu_bus.iorq = 1'b0;  assign cpu_bus.m1 = 1'b0;
assign cpu_bus.rd   = rd;    assign cpu_bus.wr   = wr;    assign cpu_bus.req = req;

FDD_if     FDD_bus();
wire [7:0] wd_data;
wire       wd_oe;
logic      tb_density = 1'b0;                           // XML density: 0 MFM, 1 FM (DDEN)
dev_WD2793 #(.sysCLK(SYS)) wd (
    .cpu_bus(cpu_bus), .model(2'd0), .floppy_drive_en(2'b11), .FDD_bus(FDD_bus),
`ifndef NO_DENSITY
    .density(tb_density),
`endif
    .cs(1'b1), .data(wd_data), .data_oe_rq(wd_oe)
);
`ifdef NO_DENSITY
assign FDD_bus.MFM = 1'b1;                              // the old glue does not drive it
`endif

task automatic mem_wr(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; dbo = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (3) @(negedge clk); mreq = 0; wr = 0;
    repeat (2) @(negedge clk);
endtask

task automatic mem_rd(input logic [15:0] a, output logic [7:0] d);
    @(negedge clk); addr = a; mreq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (2) @(negedge clk);
    d = wd_data;
    mreq = 0; rd = 0;
    repeat (2) @(negedge clk);
endtask

// ------------------------------------------------------------------ block devices + HPS model
MSX::msx_config_t msx_config;
wire [31:0] sd_lba[VDNUM];
wire  [5:0] sd_blk_cnt[VDNUM];
wire [VDNUM-1:0] sd_rd, sd_wr;
logic [VDNUM-1:0] sd_ack = '0;
logic [13:0] sd_buff_addr = '0;
logic  [7:0] sd_buff_dout = '0;
wire   [7:0] sd_buff_din[VDNUM];
logic        sd_buff_wr = 0;
logic [VDNUM-1:0] img_mounted = '0;
logic [63:0] img_size = '0;
logic        img_readonly = 0;

block_device_if block_device_FDD[6]();
block_device_if block_device_SD();

blockDevMux #(.VDNUM(VDNUM)) mux (
    .clk(clk), .reset(reset), .msx_config(msx_config),
    .sd_lba(sd_lba), .sd_blk_cnt(sd_blk_cnt), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
    .sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din),
    .sd_buff_wr(sd_buff_wr), .img_mounted(img_mounted), .img_size(img_size),
    .img_readonly(img_readonly), .block_device_FDD(block_device_FDD), .block_device_SD(block_device_SD)
);

assign block_device_SD.rd = 1'b0;  assign block_device_SD.wr = 1'b0;  assign block_device_SD.lba = '0;
assign block_device_SD.blk_cnt = '0;  assign block_device_SD.buff_din = '0;

logic [1:0] drive_ds   = 2'b11;     // drives are double sided
logic       need_motor = 1'b0;      // TRACK0 / WPROT without motor (National style)
logic [15:0] motor_off_ms = 16'd0;  // motor run-on after switch off (Sony 4000)

`ifdef OLD
fdd #(.sysCLK(SYS), .SECTORS(9), .SECTOR_SIZE(512), .TRACKS(80), .ID("FDDT")) dut (
    .clk(clk), .reset(reset), .FDD_bus(FDD_bus), .block_device(block_device_FDD[0:1]),
    .speed(2'b00), .mfm(2'b11), .sides(2'b11), .sectors('{9,9}), .sector_size('{2,2}), .density('{0,0})
);
`else
fdd #(.sysCLK(SYS), .ID("FDDT")) dut (
    .clk(clk), .reset(reset), .FDD_bus(FDD_bus), .block_device(block_device_FDD[0:1]),
    .drive_ds(drive_ds), .need_motor(need_motor)
`ifndef NO_MOTOR_OFF
    , .motor_off_ms(motor_off_ms)
`endif
);
`endif

// Disk images of the drives (VD 1, 2 of the controller unit, VD 3, 4 of the write unit, VD 5, 6
// of the WD2795 unit)
logic [7:0] img[6][737280];
int         img_bytes[6] = '{default: 0};
int         img_seed[6]  = '{default: 0};
int         hps_lat      = MS;      // HPS answer latency
int         loads[6]     = '{default: 0};
int         stores[6]    = '{default: 0};

function automatic logic [7:0] pat(input int seed, input int lba, input int off);
    if (off == 0) return 8'(lba);
    if (off == 1) return {4'(seed), 4'(lba >> 8)};
    return 8'(lba * 31 + off * 7 + seed * 101 + (off >> 3));
endfunction

task automatic mount(input int d, input int size, input int seed, input bit ro = 0);
    for (int i = 0; i < size; i++) img[d][i] = pat(seed, i / 512, i % 512);
    img_bytes[d] = size;
    img_seed[d]  = seed;
    @(negedge clk); img_size = 64'(size); img_readonly = ro; img_mounted[d + 1] = 1'b1;
    @(negedge clk); img_mounted = '0;
endtask

initial forever begin                                   // HPS: one request at a time
    int n;
    @(posedge clk);
    n = 0;
    for (int k = 1; k <= 6; k++) if (n == 0 && (sd_rd[k] || sd_wr[k])) n = k;
    if (n != 0) begin
        int d, lba, cnt;
        bit is_wr;
        d     = n - 1;
        is_wr = sd_wr[n];
        lba   = int'(sd_lba[n]);
        cnt   = (int'(sd_blk_cnt[n]) + 1) * 512;
        repeat (hps_lat) @(posedge clk);
        sd_ack[n] <= 1'b1;
        for (int i = 0; i < cnt; i++) begin
            int a = lba * 512 + i;
            if (is_wr) begin                            // registered buffer: address, 2 clocks, data
                @(posedge clk); sd_buff_addr <= 14'(i);
                @(posedge clk); @(posedge clk);
                if (a < img_bytes[d]) img[d][a] = sd_buff_din[n];
            end else begin
                @(posedge clk);
                sd_buff_addr <= 14'(i);
                sd_buff_dout <= a < img_bytes[d] ? img[d][a] : 8'hFF;
                sd_buff_wr   <= 1'b1;
                @(posedge clk);
                sd_buff_wr   <= 1'b0;
            end
        end
        @(posedge clk); sd_ack[n] <= 1'b0;
        if (is_wr) stores[d]++; else loads[d]++;
    end
end

// Transfer of another virtual disk (VD 0 = SD card): buff_wr is shared by all of them
task automatic other_vd_transfer();
    @(posedge clk); sd_ack[0] <= 1'b1;
    for (int i = 0; i < 16384; i++) begin
        @(posedge clk); sd_buff_addr <= 14'(i); sd_buff_dout <= 8'hE5; sd_buff_wr <= 1'b1;
        @(posedge clk); sd_buff_wr <= 1'b0;
    end
    @(posedge clk); sd_ack[0] <= 1'b0;
endtask

// ------------------------------------------------------------------ WD2793 helpers (Philips: 7FF8-7FFF)
// Motor on: wait for the spin-up (3 ms in fdd; a disk ROM waits much longer)
task automatic select_drive(input bit drv, input bit side, input bit motor);
    mem_wr(16'h7FFD, {motor, 6'b0, drv});
    mem_wr(16'h7FFC, {7'b0, side});
    if (motor) repeat (5 * MS) @(negedge clk);
endtask

// 7FFDh read with drive select sel (bits 1:0): bit 2 = 0 iff the disk changed (read clears it)
task automatic dskchg(input string what, input logic [1:0] sel, input bit exp_changed);
    logic [7:0] v;
    mem_wr(16'h7FFD, {6'b0, sel});
    mem_rd(16'h7FFD, v);
    if (v[2] !== !exp_changed || v[1:0] !== sel)
        fail($sformatf("%s: 7FFD = %02h, expected bit 2 = %0d", what, v, !exp_changed));
endtask

task automatic wait_intrq(input int ms, output bit ok);
    logic [7:0] s;
    longint unsigned t_end = cyc + longint'(ms) * MS;
    ok = 0;
    while (cyc < t_end) begin
        mem_rd(16'h7FFF, s);
        if (!s[6]) begin ok = 1; return; end
    end
endtask

task automatic type1(input string what, input logic [7:0] cmd);
    bit ok;
    mem_wr(16'h7FF8, cmd);
    wait_intrq(2000, ok);
    if (!ok) fail({what, ": no INTRQ"});
endtask

task automatic seek(input int trk);
    mem_wr(16'h7FFB, 8'(trk));
    type1($sformatf("seek %0d", trk), 8'h10);
endtask

// Read sector(s): command 80h (or 90h multi, ended by D0h after n sectors); returns status
task automatic read_cmd(input int trk, input int sec, input int nsec, output logic [7:0] st,
                        output logic [7:0] data[$]);
    logic [7:0] s, b;
    longint unsigned t_end = cyc + longint'(1500) * MS;
    data = {};
    mem_wr(16'h7FF9, 8'(trk));
    mem_wr(16'h7FFA, 8'(sec));
    mem_wr(16'h7FF8, nsec > 1 ? 8'h90 : 8'h80);
    forever begin
        mem_rd(16'h7FFF, s);
        if (!s[7]) begin mem_rd(16'h7FFB, b); data.push_back(b); end
        if (nsec > 1 && data.size() == nsec * 512) begin
            mem_wr(16'h7FF8, 8'hD0);                    // end of a multi-sector read
            break;
        end
        if (!s[6]) break;
        if (cyc > t_end) begin fail($sformatf("read T%0d S%0d: timeout", trk, sec)); break; end
    end
    mem_rd(16'h7FF8, st);
endtask

// Type III: C0h Read Address and E0h Read Track collect the bytes, F0h Write Track feeds fmt[]
// (gap 4E past fmt_len) until the controller ends at the index. A timeout recovers with D0h.
task automatic type3_cmd(input logic [7:0] cmd, input logic [7:0] fmt[8192], input int fmt_len,
                         output logic [7:0] st, output logic [7:0] data[$], output int n);
    logic [7:0] s, b;
    longint unsigned t_end = cyc + longint'(600) * MS;
    n = 0; data = {};
    mem_wr(16'h7FF8, cmd);
    forever begin
        mem_rd(16'h7FFF, s);
        if (!s[7]) begin                                        // DRQ
            if (cmd[4]) begin mem_wr(16'h7FFB, n < fmt_len ? fmt[n] : 8'h4E); n++; end
            else begin mem_rd(16'h7FFB, b); data.push_back(b); end
        end
        if (!s[6]) break;                                       // INTRQ
        if (cyc > t_end) begin
            fail($sformatf("type III %02h: timeout (%0d bytes)", cmd, cmd[4] ? n : data.size()));
            mem_wr(16'h7FF8, 8'hD0);
            break;
        end
    end
    repeat (10) @(negedge clk);
    mem_rd(16'h7FF8, st);
endtask

// Write Track bytes of a standard MFM track (MSX-DOS FORMAT): IAM, then per sector the ID and a
// data field of 'fill'; the controller writes F5 as A1, F6 as C2 and F7 as the CRC
task automatic build_format(input int cyl, input int spt_f, input logic [7:0] fill,
                            output logic [7:0] fmt[8192], output int len);
    int k = 0;
    repeat (80) begin fmt[k] = 8'h4E; k++; end
    repeat (12) begin fmt[k] = 8'h00; k++; end
    repeat (3)  begin fmt[k] = 8'hF6; k++; end
    fmt[k] = 8'hFC; k++;
    repeat (50) begin fmt[k] = 8'h4E; k++; end
    for (int s = 1; s <= spt_f; s++) begin
        repeat (12) begin fmt[k] = 8'h00; k++; end
        repeat (3)  begin fmt[k] = 8'hF5; k++; end
        fmt[k] = 8'hFE; k++; fmt[k] = 8'(cyl); k++; fmt[k] = 8'h00; k++; fmt[k] = 8'(s); k++; fmt[k] = 8'h02; k++;
        fmt[k] = 8'hF7; k++;
        repeat (22) begin fmt[k] = 8'h4E; k++; end
        repeat (12) begin fmt[k] = 8'h00; k++; end
        repeat (3)  begin fmt[k] = 8'hF5; k++; end
        fmt[k] = 8'hFB; k++;
        repeat (512) begin fmt[k] = fill; k++; end
        fmt[k] = 8'hF7; k++;
        repeat (84) begin fmt[k] = 8'h4E; k++; end
    end
    len = k;
endtask

// Read one sector and compare with image d, LBA lba (the image array holds the writes too)
task automatic read_ok(input string what, input int trk, input int sec, input int d, input int lba,
                       input int nsec = 1);
    logic [7:0] st;
    logic [7:0] data[$];
    int bad = 0;
    read_cmd(trk, sec, nsec, st, data);
    if (nsec == 1 && (st & 8'h9C) != 0) begin fail($sformatf("%s: status %02h", what, st)); return; end
    if (data.size() != nsec * 512) begin
        fail($sformatf("%s: %0d bytes (status %02h)", what, data.size(), st)); return;
    end
    foreach (data[i]) if (data[i] !== img[d][lba * 512 + i]) bad++;
    if (bad) fail($sformatf("%s: %0d bytes differ, got image %0d LBA %0d (expected image %0d LBA %0d)",
                            what, bad, data[1][7:4], {data[1][3:0], data[0]}, img_seed[d], lba));
endtask

// Read one sector with a CPU that polls only every 40 us (a byte is 32 us): Lost Data
task automatic read_slow(input int trk, input int sec, output logic [7:0] st);
    logic [7:0] s, b;
    longint unsigned t_end = cyc + longint'(1500) * MS;
    mem_wr(16'h7FF9, 8'(trk));
    mem_wr(16'h7FFA, 8'(sec));
    mem_wr(16'h7FF8, 8'h80);
    forever begin
        repeat (40 * (SYS / 1_000_000)) @(negedge clk);
        mem_rd(16'h7FFF, s);
        if (!s[7]) mem_rd(16'h7FFB, b);
        if (!s[6]) break;
        if (cyc > t_end) begin fail($sformatf("slow read T%0d S%0d: timeout", trk, sec)); break; end
    end
    mem_rd(16'h7FF8, st);
endtask

// Write sector(s): A0h (B0h multi, ended by D0h at the DRQ for the sector after the last one;
// +1 deleted data mark). feed = 0 leaves DRQ unserviced. Returns the status and the bytes taken.
task automatic write_cmd(input int trk, input int sec, input int nsec, input logic [7:0] data[1024],
                         input bit deleted, input bit feed, output logic [7:0] st, output int n);
    logic [7:0] s;
    longint unsigned t_end = cyc + longint'(600) * MS;
    n = 0;
    mem_wr(16'h7FF9, 8'(trk));
    mem_wr(16'h7FFA, 8'(sec));
    mem_wr(16'h7FF8, 8'hA0 | (nsec > 1 ? 8'h10 : 8'h00) | (deleted ? 8'h01 : 8'h00));
    forever begin
        mem_rd(16'h7FFF, s);
        if (!s[7]) begin                                        // DRQ
            if (n == nsec * 512) begin mem_wr(16'h7FF8, 8'hD0); break; end
            if (feed) begin mem_wr(16'h7FFB, data[n]); n++; end
        end
        if (!s[6]) break;                                       // INTRQ
        if (cyc > t_end) begin
            fail($sformatf("write T%0d S%0d: timeout (%0d bytes taken)", trk, sec, n));
            mem_wr(16'h7FF8, 8'hD0);                            // recover the controller
            break;
        end
    end
    repeat (10) @(negedge clk);
    mem_rd(16'h7FF8, st);
endtask

task automatic read_rnf(input string what, input int trk, input int sec);
    logic [7:0] st;
    logic [7:0] data[$];
    read_cmd(trk, sec, 1, st, data);
    if (!st[4] || data.size() != 0)
        fail($sformatf("%s: expected record not found, status %02h, %0d bytes", what, st, data.size()));
endtask

task automatic read_not_ready(input string what, input int trk, input int sec);
    logic [7:0] st;
    logic [7:0] data[$];
    read_cmd(trk, sec, 1, st, data);
    if (!st[7] || data.size() != 0)
        fail($sformatf("%s: expected not ready, status %02h, %0d bytes", what, st, data.size()));
endtask

// ------------------------------------------------------------------ monitors
int index_edges = 0;
logic index_q = 1;
always @(posedge clk) begin
    index_q <= FDD_bus.INDEXn;
    if (index_q && !FDD_bus.INDEXn) index_edges++;
end

// Bytes after the index mark, decoded by an independent MFM demodulator
wire [7:0] rx_dat;
wire       rx_ed, rx_c2, rx_a1;
`ifdef MODEM_OLD
wd279x_mfmdem iam_dem (
`else
mfmdem iam_dem (
`endif
    .clk(clk), .rstn(~reset), .init(1'b0), .brk(1'b0), .datin(FDD_bus.READ_DATAn),
    .bitlen(32'(SYS / 500_000)), .RXDAT(rx_dat), .RXED(rx_ed), .DetMA1(rx_a1), .DetMC2(rx_c2),
    .broken(), .curlen()
);
logic [8:0] iam_seq[$];                                 // {mark, byte}
bit         iam_capture = 0;
always @(posedge clk) begin
    if (index_q && !FDD_bus.INDEXn && iam_seq.size() == 0) iam_capture <= 1;
    if (iam_capture && rx_ed) begin
        if (rx_c2 || iam_seq.size() > 0) iam_seq.push_back({rx_c2, rx_dat});
        if (iam_seq.size() >= 6) iam_capture <= 0;
    end
end

// ------------------------------------------------------------------ write path: a unit driven directly (VD 3, 4)
// The controller side is the MFM modulator of the modem library at the cell rate of the drive,
// fed byte by byte as a WD279x / TC8566AF does it (sync, marks, data, CRC).
`ifndef OLD
FDD_if  wr_bus();
logic   tb_wgn = 1'b1, tb_stepn = 1'b1, tb_sdirn = 1'b1;
assign wr_bus.USEL  = 1'b0;     assign wr_bus.MOTORn = 1'b0;  assign wr_bus.STEPn = tb_stepn;
assign wr_bus.SDIRn = tb_sdirn; assign wr_bus.SIDEn  = 1'b1;  assign wr_bus.DSKCHG_ACK = 2'b00;
assign wr_bus.WRITE_GATEn = tb_wgn; assign wr_bus.MFM = 1'b1;
fdd #(.sysCLK(SYS), .ID("FDDW")) wr_dut (
    .clk(clk), .reset(reset), .FDD_bus(wr_bus), .block_device(block_device_FDD[2:3]),
    .drive_ds(2'b11), .need_motor(1'b0)
`ifndef NO_MOTOR_OFF
    , .motor_off_ms(16'd0)
`endif
);

logic       tb_cell;
clockEnabler #(.clkFreq(SYS), .targetFreq(500000)) tb_cell_en (.clk(clk), .en(tb_cell));
logic [7:0] tb_txdat = '0;
logic       tb_txwr = 0, tb_txa1 = 0, tb_txc2 = 0;
wire        tb_txemp, tb_bit;
mfmmod tb_mod (
    .txdat(tb_txdat), .txwr(tb_txwr), .txma1(tb_txa1), .txmc2(tb_txc2), .brk(1'b0),
    .txemp(tb_txemp), .txend(), .bitout(tb_bit), .writeen(), .sft(tb_cell), .clk(clk), .rstn(~reset)
);
assign wr_bus.WRITE_DATAn = ~tb_bit;

logic [15:0] tb_crc;
task automatic tb_byte(input logic [7:0] b, input bit a1 = 0, input bit c2 = 0);
    while (!tb_txemp) @(negedge clk);
    tb_txdat = b; tb_txwr = !(a1 || c2); tb_txa1 = a1; tb_txc2 = c2;
    @(negedge clk);
    tb_txwr = 0; tb_txa1 = 0; tb_txc2 = 0;
    tb_crc = FDC::crc16(tb_crc, b);
endtask

task automatic tb_bytes(input logic [7:0] b, input int n);
    repeat (n) tb_byte(b);
endtask

task automatic tb_crc_bytes(input bit bad = 0);
    logic [15:0] c = bad ? ~tb_crc : tb_crc;
    tb_byte(c[15:8]); tb_byte(c[7:0]);
endtask

task automatic tb_mark(input logic [7:0] m);              // A1 A1 A1 + mark, CRC from FFFF over them
    tb_crc = 16'hFFFF;
    repeat (3) tb_byte(8'hA1, 1);
    tb_byte(m);
endtask

task automatic tb_gate_close();
    while (!tb_txemp) @(negedge clk);
    repeat (2 * 16 * (SYS / 500_000)) @(negedge clk);     // the last byte leaves the modulator
    tb_wgn = 1'b1;
endtask

// Write sector: the gate opens where a WD279x opens it, after GAP2 of the slot (its SYNC2)
task automatic tb_write_sector(input int sec, input logic [7:0] data[512], input bit bad_crc = 0);
    while (!(wr_dut.FDD_transmit.field == wr_dut.FDD_transmit.F_SYNC2 && wr_dut.FDD_transmit.sector == 4'(sec - 1)))
        @(negedge clk);
    tb_wgn = 1'b0;
    tb_bytes(8'h00, 12);
    tb_mark(8'hFB);
    foreach (data[i]) tb_byte(data[i]);
    tb_crc_bytes(bad_crc);
    tb_byte(8'h4E);
    tb_gate_close();
endtask

// Write track as a WD279x Write Track (F0): index to index, IAM, then the ID and data field of
// every sector (the IDs choose the slots)
task automatic tb_format(input int spt_f, input logic [7:0] fill, input int cyl);
    while (!wr_bus.INDEXn) @(negedge clk);
    while (wr_bus.INDEXn)  @(negedge clk);
    tb_wgn = 1'b0;
    tb_bytes(8'h4E, 80); tb_bytes(8'h00, 12);
    repeat (3) tb_byte(8'hC2, 0, 1); tb_byte(8'hFC);
    tb_bytes(8'h4E, 50);
    for (int s = 1; s <= spt_f; s++) begin
        tb_bytes(8'h00, 12); tb_mark(8'hFE);
        tb_byte(8'(cyl)); tb_byte(8'h00); tb_byte(8'(s)); tb_byte(8'h02); tb_crc_bytes();
        tb_bytes(8'h4E, 22); tb_bytes(8'h00, 12); tb_mark(8'hFB);
        tb_bytes(fill, 512); tb_crc_bytes();
        tb_bytes(8'h4E, 84);
    end
    do tb_byte(8'h4E); while (wr_bus.INDEXn);
    @(negedge clk); tb_wgn = 1'b1;
endtask

task automatic tb_step(input bit in);
    tb_sdirn = in;
    @(negedge clk); tb_stepn = 1'b0;
    repeat (4) @(negedge clk); tb_stepn = 1'b1;
    repeat (6 * MS) @(negedge clk);
endtask

task automatic wait_stores(input string what, input int d, input int n, input int ms);
    longint unsigned t_end = cyc + longint'(ms) * MS;
    while (stores[d] < n && cyc < t_end) @(negedge clk);
    if (stores[d] < n) fail($sformatf("%s: %0d sectors stored (expected %0d)", what, stores[d], n));
endtask

task automatic check_img(input string what, input int d, input int lba, input logic [7:0] data[512]);
    int bad = 0;
    for (int i = 0; i < 512; i++) if (img[d][lba * 512 + i] !== data[i]) bad++;
    if (bad) fail($sformatf("%s: %0d bytes of image %0d LBA %0d differ", what, bad, d, lba));
endtask

int rd_during_wg = 0;
always @(posedge clk) if (!wr_bus.WRITE_GATEn && !wr_bus.READ_DATAn) rd_during_wg++;

// ------------------------------------------------------------------ WD2795/7: bare wd279x, SSO selects the side (VD 5, 6)
FDD_if      u57_bus();
logic       u57_csn = 1'b1, u57_ren = 1'b1, u57_wen = 1'b1;
logic [1:0] u57_a   = '0;
logic [7:0] u57_din = '0;
wire  [7:0] u57_dout;
wire        u57_drq, u57_intrq, u57_sso, u57_wg, u57_wd;
wd279x #(.WD279_57(1), .sysCLK(SYS)) wd57 (
    .clk(clk), .MRn(~reset), .CSn(u57_csn), .REn(u57_ren), .WEn(u57_wen), .A(u57_a), .DIN(u57_din), .DOUT(u57_dout),
    .DRQ(u57_drq), .INTRQ(u57_intrq),
    .STEPn(u57_bus.STEPn), .SDIRn(u57_bus.SDIRn), .INDEXn(u57_bus.INDEXn), .TRK00n(u57_bus.TRACK0n),
    .READYn(u57_bus.READYn), .WPROTn(u57_bus.WPROTn), .HLD(), .SSO(u57_sso), .RAWRDn(u57_bus.READ_DATAn),
    .DDENn(1'b0), .WG(u57_wg), .WD(u57_wd)
);
assign u57_bus.USEL = 1'b0;          assign u57_bus.MOTORn = 1'b0;       assign u57_bus.SIDEn = ~u57_sso;
assign u57_bus.WRITE_GATEn = ~u57_wg; assign u57_bus.WRITE_DATAn = ~u57_wd; assign u57_bus.MFM = 1'b1;
assign u57_bus.DSKCHG_ACK = 2'b00;
fdd #(.sysCLK(SYS), .ID("FDD5")) u57_dut (
    .clk(clk), .reset(reset), .FDD_bus(u57_bus), .block_device(block_device_FDD[4:5]),
    .drive_ds(2'b11), .need_motor(1'b0)
`ifndef NO_MOTOR_OFF
    , .motor_off_ms(16'd0)
`endif
);

task automatic u57_wr(input logic [1:0] a, input logic [7:0] d);
    @(negedge clk); u57_a = a; u57_din = d; u57_csn = 1'b0;
    @(negedge clk); u57_wen = 1'b0;
    repeat (3) @(negedge clk); u57_wen = 1'b1; u57_csn = 1'b1;
    repeat (2) @(negedge clk);
endtask

task automatic u57_rd(input logic [1:0] a, output logic [7:0] d);
    @(negedge clk); u57_a = a; u57_csn = 1'b0;
    @(negedge clk); u57_ren = 1'b0;
    repeat (2) @(negedge clk); d = u57_dout; u57_ren = 1'b1; u57_csn = 1'b1;
    repeat (2) @(negedge clk);
endtask

// Command; data bytes taken while DRQ, until INTRQ. Returns the status and the bytes.
task automatic u57_cmd(input logic [7:0] cmd, output logic [7:0] st, output logic [7:0] data[$]);
    logic [7:0] b;
    longint unsigned t_end = cyc + longint'(1500) * MS;
    data = {};
    u57_wr(2'd0, cmd);
    forever begin
        if (u57_drq) begin u57_rd(2'd3, b); data.push_back(b); end
        if (u57_intrq) break;
        if (cyc > t_end) begin fail($sformatf("WD2795 command %02h: timeout", cmd)); u57_wr(2'd0, 8'hD0); break; end
        @(negedge clk);
    end
    u57_rd(2'd0, st);
endtask

task automatic u57_check(input string what, input logic [7:0] data[$], input int lba, input logic [7:0] st);
    int bad = 0;
    if (data.size() != 512 || (st & 8'h9C) != 0) begin
        fail($sformatf("%s: %0d bytes, status %02h", what, data.size(), st));
        return;
    end
    foreach (data[i]) if (data[i] !== img[4][lba * 512 + i]) bad++;
    if (bad) fail($sformatf("%s: %0d bytes differ (expected LBA %0d)", what, bad, lba));
endtask
`endif

// ------------------------------------------------------------------ cell rate monitor (drive A while measure_cells)
longint unsigned fm_last = 0, fm_min = '1;
logic fm_q = 1;
bit   measure_cells = 0;
always @(posedge clk) begin
    fm_q <= FDD_bus.READ_DATAn;
    if (measure_cells && fm_q && !FDD_bus.READ_DATAn) begin
        if (fm_last != 0 && cyc - fm_last < fm_min) fm_min <= cyc - fm_last;
        fm_last <= cyc;
    end
end

// ------------------------------------------------------------------ test sequence
initial begin
    logic [7:0] st;
    int e0;
    msx_config.wait_count    = '0;
    msx_config.cpu_clock_sel = '0;
    msx_config.fdd           = 6'b111111;                         // VD 1, 2 WD2793; VD 3, 4 write unit; VD 5, 6 WD2795
    repeat (10) @(negedge clk);
    reset = 0;
    repeat (10) @(negedge clk);
    mount(0, 737280, 1);                                // drive A: 720K
    mount(1, 368640, 2);                                // drive B: 360K (single sided disk)

    // --- disk change: both drives changed after power on / mount, the read clears it per drive
    if (FDD_bus.DSKCHGn !== 2'b00) fail($sformatf("DSKCHGn after mount = %b, expected 00", FDD_bus.DSKCHGn));
    dskchg("drive A after mount", 2'b00, 1);
    dskchg("drive A read again", 2'b00, 0);
    if (FDD_bus.DSKCHGn !== 2'b01) fail($sformatf("DSKCHGn {B,A} after A read = %b, expected 01", FDD_bus.DSKCHGn));
    dskchg("drive B after mount", 2'b01, 1);
    dskchg("drive B read again", 2'b01, 0);
    dskchg("drive A select 10", 2'b10, 0);
    dskchg("no drive", 2'b11, 0);
    mount(0, 737280, 1);                                // new disk in drive A only
    if (FDD_bus.DSKCHGn !== 2'b10) fail($sformatf("DSKCHGn {B,A} after remount A = %b, expected 10", FDD_bus.DSKCHGn));
    dskchg("drive B after remount A", 2'b01, 0);
    dskchg("drive A after remount A", 2'b10, 1);
    dskchg("drive A after the read", 2'b00, 0);

    // --- drive A, 720K; type I status bit 5 = head loaded follows h (before any type II command)
    select_drive(0, 0, 1);
    type1("restore", 8'h00);
    mem_rd(16'h7FF8, st);
    if (!st[2]) fail($sformatf("restore: no TRACK00 in status %02h", st));
    if (st[5])  fail($sformatf("restore h = 0: head loaded, status %02h", st));
    type1("restore h", 8'h08);
    mem_rd(16'h7FF8, st);
    if (!st[5]) fail($sformatf("restore h = 1: head not loaded, status %02h", st));
    read_ok("720K T0 S1", 0, 1, 0, 0);
    seek(5);
    select_drive(0, 1, 1);
    read_ok("720K T5 side 1 S9", 5, 9, 0, (5 * 2 + 1) * 9 + 8);
    seek(2);
    select_drive(0, 0, 1);
    read_ok("720K T2 S1-S9 multi", 2, 1, 0, 2 * 18, 9);
    other_vd_transfer();
    read_ok("T2 S5 after a transfer of another VD", 2, 5, 0, 2 * 18 + 4);

    // --- IAM C2 C2 C2 FC then gap 4E (decoded after an index pulse; the demodulator may
    //     lock only on the 2nd C2)
    begin
        int k = 0;
        while (k < iam_seq.size() && iam_seq[k] == 9'h1C2) k++;
        if (iam_seq.size() < 6 || k < 2 || iam_seq[k] != 9'h0FC || iam_seq[k + 1] != 9'h04E)
            fail($sformatf("IAM: %p (expected C2 marks, FC, 4E)", iam_seq));
    end

    // --- disk change at the same head position
    mount(0, 737280, 3);
    repeat (2 * MS) @(negedge clk);
    read_ok("disk change T2 S1", 2, 1, 0, 2 * 18);

    // --- slow SD answer (longer than a rotation): no sector of the old track after a step
    hps_lat = 150 * MS;
    seek(10);
    read_ok("slow SD T10 S3", 10, 3, 0, 10 * 18 + 2);
    hps_lat = MS;

    // --- track beyond the image (80 tracks: 0-79)
    seek(80);
    read_rnf("720K T80 (beyond image)", 80, 1);
    type1("restore", 8'h00);

    // --- 640K image (8 sectors per track)
    mount(0, 655360, 4);
    seek(1);
    select_drive(0, 1, 1);
    read_ok("640K T1 side 1 S8", 1, 8, 0, (1 * 2 + 1) * 8 + 7);
    read_rnf("640K T1 side 1 S9", 1, 9);

    // --- drive B, 360K single sided disk
    select_drive(1, 0, 1);
    type1("restore B", 8'h00);
    seek(3);
    read_ok("drive B 360K T3 S4", 3, 4, 1, 3 * 9 + 3);
    select_drive(1, 1, 1);
    read_rnf("drive B 360K side 1 (unformatted)", 3, 1);

    // --- index pulses only while the motor runs
    select_drive(0, 0, 0);
    repeat (5 * MS) @(negedge clk);
    e0 = index_edges;
    repeat (450 * MS) @(negedge clk);
    if (index_edges != e0) fail($sformatf("index with motor off: %0d pulses", index_edges - e0));
    select_drive(0, 0, 1);
    e0 = index_edges;
    repeat (450 * MS) @(negedge clk);
    if (index_edges - e0 < 2 || index_edges - e0 > 3)
        fail($sformatf("index with motor on: %0d pulses in 450 ms", index_edges - e0));

`ifndef OLD
    // --- single sided drive: side 1 is not ready (openMSX RealDrive::isDiskInserted)
    mount(0, 737280, 5);
    drive_ds = 2'b10;
    select_drive(0, 0, 1);
    type1("restore SS", 8'h00);
    read_ok("SS drive side 0 T0 S2", 0, 2, 0, 1);
    select_drive(0, 1, 1);
    read_not_ready("SS drive side 1", 0, 1);
    drive_ds = 2'b11;

    // --- TRACK0 needs the motor (Philips style), not without need_motor (National)
    select_drive(0, 0, 0);
    repeat (MS) @(negedge clk);
    if (FDD_bus.TRACK0n !== 1'b0) fail("National: TRACK0 with motor off");
    need_motor = 1'b1;
    repeat (10) @(negedge clk);
    if (FDD_bus.TRACK0n !== 1'b1) fail("Philips: TRACK0 active with motor off");
    select_drive(0, 0, 1);
    repeat (5 * MS) @(negedge clk);
    if (FDD_bus.TRACK0n !== 1'b0) fail("Philips: no TRACK0 with motor on");
    need_motor = 1'b0;

    // --- READY only from the disk (openMSX WD2793::isReady), also with the motor off
    select_drive(0, 0, 0);
    repeat (MS) @(negedge clk);
    if (FDD_bus.READYn !== 1'b0) fail("READY with disk in, motor off");

    // --- seek with 6 ms steps over the whole disk: only the target track is loaded
    select_drive(0, 0, 1);
    type1("restore before the long seek", 8'h00);
    repeat (20 * MS) @(negedge clk);
    e0 = loads[0];
    seek(79);
    read_ok("720K T79 S1 after a long seek", 79, 1, 0, 79 * 2 * 9);
    if (loads[0] - e0 > 2) fail($sformatf("long seek: %0d track loads (expected 1)", loads[0] - e0));

    // --- the motor keeps running motor_off_ms after it is switched off (Sony: 4000)
    motor_off_ms = 16'd50;
    select_drive(0, 0, 1);
    select_drive(0, 0, 0);
    repeat (30 * MS) @(negedge clk);
    if (dut.motor_run[0] !== 1'b1) fail("motor stopped before motor_off_ms");
    repeat (30 * MS) @(negedge clk);
    if (dut.motor_run[0] !== 1'b0) fail("motor runs after motor_off_ms");
    motor_off_ms = 16'd0;

    // --- ejected disk (size 0): not ready
    mount(1, 0, 6);
    select_drive(1, 0, 1);
    read_not_ready("drive B ejected", 0, 1);

    // ================================================================ write path (unit on VD 3, 4)
    begin
        logic [7:0] wdata[512], e5[512];
        int s0, l0;
        foreach (wdata[i]) wdata[i] = 8'(i * 3 + 11);
        foreach (e5[i])    e5[i]    = 8'hE5;
        mount(2, 737280, 7);
        repeat (25 * MS) @(negedge clk);                // spin up, settle, track load
        if (!wr_dut.track_ready) fail("write unit: track 0 not loaded");

        // --- write sector: into the buffer, then one sector flushed to the image; neighbours intact
        s0 = stores[2];
        tb_write_sector(3, wdata);
        wait_stores("write T0 S3", 2, s0 + 1, 50);
        check_img("write T0 S3", 2, 2, wdata);
        if (img[2][1 * 512] !== pat(7, 1, 0) || img[2][3 * 512] !== pat(7, 3, 0)) fail("write T0 S3: a neighbour sector changed");

        // --- bad CRC: nothing stored, the track is reloaded from the image
        s0 = stores[2]; l0 = loads[2];
        tb_write_sector(5, wdata, 1);
        repeat (40 * MS) @(negedge clk);
        if (stores[2] != s0) fail("bad CRC: sector stored");
        if (loads[2] != l0 + 1) fail($sformatf("bad CRC: %0d track loads (expected 1)", loads[2] - l0));
        if (wr_dut.FDD_buffer.track_dpram.mem[4 * 512 + 7] !== pat(7, 4, 7)) fail("bad CRC: buffer not restored");

        // --- write protected image: the gate is ignored
        mount(2, 737280, 8, 1);
        repeat (25 * MS) @(negedge clk);
        s0 = stores[2];
        tb_write_sector(2, wdata);
        repeat (40 * MS) @(negedge clk);
        if (stores[2] != s0) fail("write protected: sector stored");
        if (wr_dut.FDD_buffer.track_dpram.mem[1 * 512 + 3] !== pat(8, 1, 3)) fail("write protected: buffer changed");

        // --- format track 1: the IDs of the stream choose the slots, 9 sectors of E5
        mount(2, 737280, 9);
        tb_step(1);
        repeat (25 * MS) @(negedge clk);
        s0 = stores[2];
        tb_format(9, 8'hE5, 1);
        wait_stores("format T1", 2, s0 + 9, 300);
        for (int s = 0; s < 9; s++) check_img($sformatf("format T1 S%0d", s + 1), 2, 18 + s, e5);
        if (img[2][17 * 512] !== pat(9, 17, 0) || img[2][27 * 512] !== pat(9, 27, 0)) fail("format T1: another track changed");

        // --- write, then a step before the flush (slow HPS): the flush goes to the written track
        hps_lat = 150 * MS;
        s0 = stores[2];
        tb_write_sector(1, wdata);
        tb_step(1);
        wait_stores("write T1 S1 then step", 2, s0 + 1, 400);
        hps_lat = MS;
        check_img("write T1 S1 then step", 2, 18, wdata);
        repeat (200 * MS) @(negedge clk);
        if (!wr_dut.track_ready) fail("write then step: track 2 not loaded after the flush");

        if (rd_during_wg != 0) fail($sformatf("READ DATA while the gate is open: %0d pulses", rd_during_wg));
    end

    // ================================================================ WD2793 writes (drive A)
    begin
        logic [7:0] w1[512], w2[512], w3[512];                  // sector contents to compare
        logic [7:0] b1[1024], b2[1024], b23[1024];              // bytes given to the controller
        logic [7:0] st;
        int s0, n;
        foreach (w1[i])  w1[i]  = 8'(i * 7 + 3);
        foreach (w2[i])  w2[i]  = 8'(i * 5 + 1);
        foreach (w3[i])  w3[i]  = 8'(255 - i);
        foreach (b1[i])  b1[i]  = i < 512 ? w1[i] : 8'h00;
        foreach (b2[i])  b2[i]  = i < 512 ? w2[i] : 8'h00;
        foreach (b23[i]) b23[i] = i < 512 ? w2[i] : w3[i - 512];
        mount(0, 737280, 10);
        select_drive(0, 0, 1);
        type1("restore for the writes", 8'h00);
        seek(2);
        repeat (20 * MS) @(negedge clk);

        // --- Write Sector T2 S3: status, image, read back, neighbour intact
        s0 = stores[0];
        write_cmd(2, 3, 1, b1, 0, 1, st, n);
        if (n != 512 || (st & 8'hFC) != 0) fail($sformatf("write T2 S3: %0d bytes taken, status %02h", n, st));
        if (n == 512) begin
            wait_stores("write T2 S3", 0, s0 + 1, 50);
            check_img("write T2 S3", 0, 2 * 18 + 2, w1);
            read_ok("read back T2 S3", 2, 3, 0, 2 * 18 + 2);
            read_ok("neighbour T2 S4", 2, 4, 0, 2 * 18 + 3);

            // --- deleted data mark (A1h): the data land, the DSK image keeps no mark
            s0 = stores[0];
            write_cmd(2, 5, 1, b2, 1, 1, st, n);
            if (n != 512 || (st & 8'hFC) != 0) fail($sformatf("write deleted T2 S5: %0d bytes taken, status %02h", n, st));
            wait_stores("write deleted T2 S5", 0, s0 + 1, 50);
            check_img("write deleted T2 S5", 0, 2 * 18 + 4, w2);

            // --- multi-sector write B0h: T2 S7 and S8, D0h at the DRQ of S9
            s0 = stores[0];
            write_cmd(2, 7, 2, b23, 0, 1, st, n);
            if (n != 1024 || st[0]) fail($sformatf("multi write T2 S7-S8: %0d bytes taken, status %02h", n, st));
            wait_stores("multi write T2 S7-S8", 0, s0 + 2, 100);
            check_img("multi write T2 S7", 0, 2 * 18 + 6, w2);
            check_img("multi write T2 S8", 0, 2 * 18 + 7, w3);
            read_ok("read back T2 S7-S9 multi", 2, 7, 0, 2 * 18 + 6, 3);

            // --- Lost Data: DRQ not serviced within 11 byte times, no write
            s0 = stores[0];
            write_cmd(2, 1, 1, b1, 0, 0, st, n);
            if (!st[2] || st[0] || n != 0) fail($sformatf("lost data on write: status %02h, %0d bytes (expected bit 2)", st, n));
            repeat (30 * MS) @(negedge clk);
            if (stores[0] != s0) fail("lost data on write: sector stored");
            read_ok("lost data on write: T2 S1 unchanged", 2, 1, 0, 2 * 18);

            // --- Lost Data on a read: the CPU polls slower than the bytes come
            read_slow(2, 2, st);
            if (!st[2] || st[0]) fail($sformatf("lost data on read: status %02h (expected bit 2)", st));

            // --- write protected disk: status bit 6, no DRQ, nothing written
            mount(0, 737280, 11, 1);
            repeat (25 * MS) @(negedge clk);
            s0 = stores[0];
            write_cmd(2, 3, 1, b1, 0, 1, st, n);
            if (!st[6] || n != 0) fail($sformatf("write protected: status %02h, %0d bytes taken (expected bit 6, none)", st, n));
            repeat (30 * MS) @(negedge clk);
            if (stores[0] != s0) fail("write protected: sector stored");
            read_ok("write protected: T2 S3 unchanged", 2, 3, 0, 2 * 18 + 2);
        end else
            $display("WD2793 write: no write path, the remaining write checks are skipped");
    end

    // ================================================================ WD2793 type III (drive A, track 3)
    begin
        logic [7:0] fmt[8192], e5[512], st, data[$];
        logic [15:0] c;
        int len, n, s0;
        foreach (e5[i]) e5[i] = 8'hE5;
        mount(0, 737280, 12);
        select_drive(0, 0, 1);
        type1("restore for type III", 8'h00);
        seek(3);
        repeat (20 * MS) @(negedge clk);

        // --- Read Address C0h: the next ID (C H R N CRC CRC), sector register = track
        type3_cmd(8'hC0, fmt, 0, st, data, n);
        if (data.size() != 6 || (st & 8'hFC) != 0)
            fail($sformatf("read address: %0d bytes, status %02h", data.size(), st));
        else begin
            c = FDC::crc16(FDC::CRC_A1x3, 8'hFE);
            for (int k = 0; k < 4; k++) c = FDC::crc16(c, data[k]);
            if (data[0] != 8'd3 || data[1] != 8'd0 || data[2] < 8'd1 || data[2] > 8'd9 || data[3] != 8'd2 || {data[4], data[5]} != c)
                fail($sformatf("read address: %p (expected 03 00 1-9 02 and the CRC %04h)", data, c));
            mem_rd(16'h7FFA, st);
            if (st != 8'd3) fail($sformatf("read address: sector register %02h (expected the track, 03)", st));
        end
        if (data.size() == 6) begin
            // --- Write Track F0h with the MSX-DOS layout: 9 sectors of E5 land in the image
            build_format(3, 9, 8'hE5, fmt, len);
            s0 = stores[0];
            type3_cmd(8'hF0, fmt, len, st, data, n);
            if ((st & 8'hFC) != 0 || n < len) fail($sformatf("write track T3: status %02h, %0d bytes taken (layout %0d)", st, n, len));
            $display("write track T3: %0d bytes taken (layout %0d)", n, len);
            wait_stores("write track T3", 0, s0 + 9, 300);
            for (int k = 0; k < 9; k++) check_img($sformatf("write track T3 S%0d", k + 1), 0, 3 * 18 + k, e5);
            read_ok("read T3 S5 after the format", 3, 5, 0, 3 * 18 + 4);
            if (img[0][(3 * 18 - 1) * 512] !== pat(12, 3 * 18 - 1, 0) || img[0][(3 * 18 + 9) * 512] !== pat(12, 3 * 18 + 9, 0))
                fail("write track T3: another track changed");

            // --- Read Track E0h: the raw bytes from index to index hold the ID of sector 1
            type3_cmd(8'hE0, fmt, 0, st, data, n);
            begin
                bit found = 0;
                for (int k = 0; k + 4 < data.size(); k++)
                    if (data[k] == 8'hFE && data[k + 1] == 8'd3 && data[k + 2] == 8'd0 && data[k + 3] == 8'd1 && data[k + 4] == 8'd2) found = 1;
                $display("read track T3: %0d bytes, ID of sector 1 %s", data.size(), found ? "found" : "missing");
                if (data.size() < 5500 || !found || (st & 8'hFC) != 0)
                    fail($sformatf("read track T3: %0d bytes, ID of sector 1 %s, status %02h", data.size(), found ? "found" : "missing", st));
            end

            // --- Write Track with DRQ not serviced before the index: Lost Data, nothing written
            s0 = stores[0];
            mem_wr(16'h7FF8, 8'hF0);
            begin
                bit ok;
                wait_intrq(600, ok);
                if (!ok) fail("write track lost data: no INTRQ");
            end
            mem_rd(16'h7FF8, st);
            if (!st[2] || st[0]) fail($sformatf("write track lost data: status %02h (expected bit 2)", st));
            repeat (30 * MS) @(negedge clk);
            if (stores[0] != s0) fail("write track lost data: sector stored");

            // --- write protected disk: F0h ends with status bit 6, no DRQ
            mount(0, 737280, 13, 1);
            repeat (25 * MS) @(negedge clk);
            s0 = stores[0];
            type3_cmd(8'hF0, fmt, len, st, data, n);
            if (!st[6] || n != 0) fail($sformatf("write track protected: status %02h, %0d bytes taken (expected bit 6, none)", st, n));
            repeat (30 * MS) @(negedge clk);
            if (stores[0] != s0) fail("write track protected: sector stored");
        end else
            $display("WD2793 type III: no Read Address, the remaining type III checks are skipped");
    end

`ifndef NO_DENSITY
    // ================================================================ FM: the drive follows DDEN of the controller
    begin
        logic [7:0] w1[512], b1[1024], fmt[8192], st, data[$];
        logic [15:0] c;
        int s0, n;
        foreach (w1[i]) w1[i] = 8'(i * 11 + 5);
        foreach (b1[i]) b1[i] = i < 512 ? w1[i] : 8'h00;
        mount(0, 737280, 14);
        tb_density = 1'b1;
        select_drive(0, 0, 1);
        type1("restore FM", 8'h00);
        seek(1);
        repeat (20 * MS) @(negedge clk);

        // --- read in FM: only possible when the drive transmits FM (the FM demodulator of the
        //     controller cannot decode MFM); the shortest transition interval is 4 us in both
        if (FDD_bus.MFM !== 1'b0) fail("FDD_if.MFM not 0 with density = FM");
        fm_last = 0; fm_min = '1; measure_cells = 1;
        read_ok("FM read T1 S2", 1, 2, 0, 1 * 18 + 1);
        measure_cells = 0;
        if (fm_min < longint'(SYS / 250_000) - 4)
            fail($sformatf("FM: transitions %0d clk apart (at least %0d expected)", fm_min, SYS / 250_000));

        // --- write in FM, into the image and back
        s0 = stores[0];
        write_cmd(1, 4, 1, b1, 0, 1, st, n);
        if (n != 512 || (st & 8'hFC) != 0) fail($sformatf("FM write T1 S4: %0d bytes taken, status %02h", n, st));
        wait_stores("FM write T1 S4", 0, s0 + 1, 50);
        check_img("FM write T1 S4", 0, 1 * 18 + 3, w1);
        read_ok("FM read back T1 S4", 1, 4, 0, 1 * 18 + 3);

        // --- Read Address in FM: the CRC starts at the mark (no A1)
        type3_cmd(8'hC0, fmt, 0, st, data, n);
        if (data.size() != 6 || (st & 8'hFC) != 0)
            fail($sformatf("FM read address: %0d bytes, status %02h", data.size(), st));
        else begin
            c = FDC::crc16(FDC::CRC_INIT, 8'hFE);
            for (int k = 0; k < 4; k++) c = FDC::crc16(c, data[k]);
            if (data[0] != 8'd1 || data[1] != 8'd0 || data[3] != 8'd2 || {data[4], data[5]} != c)
                fail($sformatf("FM read address: %p (expected 01 00 R 02 and the CRC %04h)", data, c));
        end

        // --- back to MFM: the same track reads again
        tb_density = 1'b0;
        repeat (10) @(negedge clk);
        if (FDD_bus.MFM !== 1'b1) fail("FDD_if.MFM not 1 with density = MFM");
        read_ok("MFM again T1 S4", 1, 4, 0, 1 * 18 + 3);
    end
`endif

    // ================================================================ WD2795/7: SSO from U, sector length from L
    begin
        logic [7:0] st, data[$];
        mount(4, 737280, 15);
        repeat (25 * MS) @(negedge clk);                // the motor runs from the start: spin up, track 0
        u57_cmd(8'h00, st, data);                       // restore
        if (st[0] || !st[2]) fail($sformatf("WD2795 restore: status %02h", st));
        if (u57_sso !== 1'b0) fail("WD2795: SSO not 0 after reset and a type I command");

        // --- Read Sector with U = 1, L = 1 (8Ah): side 1 through SSO, 512 bytes; sector 2 of
        //     track 0 side 1 is LBA 10
        u57_wr(2'd2, 8'd2);
        u57_cmd(8'h8A, st, data);
        if (u57_sso !== 1'b1) fail("WD2795: SSO not 1 after a read with U = 1");
        u57_check("WD2795 read U = 1 (side 1)", data, 10, st);

        // --- Read Address with U = 1 (C2h) keeps side 1 (the side 1 track is loaded; right after a
        //     side switch the drive reloads the track and a truncated ID would come with a CRC error)
        u57_cmd(8'hC2, st, data);
        if (u57_sso !== 1'b1 || data.size() != 6 || data[1] !== 8'd1 || (st & 8'h9C) != 0)
            fail($sformatf("WD2795 read address U = 1: SSO %b, %0d bytes, side byte %0d, status %02h", u57_sso, data.size(), data.size() > 1 ? int'(data[1]) : -1, st));

        // --- U = 0 (88h): side 0, LBA 1 (Read Address left the track number in the sector register)
        u57_wr(2'd2, 8'd2);
        u57_cmd(8'h88, st, data);
        if (u57_sso !== 1'b0) fail("WD2795: SSO not 0 after a read with U = 0");
        u57_check("WD2795 read U = 0 (side 0)", data, 1, st);

        // --- L = 0 (80h) with N = 2 in the ID: the controller counts 1024 bytes through the next
        //     sector's marks (the chip does not look for marks inside a data field), the CRC fails
        u57_wr(2'd2, 8'd2);
        u57_cmd(8'h80, st, data);
        if (data.size() != 1024 || !st[3])
            fail($sformatf("WD2795 read L = 0: %0d bytes, status %02h (expected 1024 and a CRC error)", data.size(), st));
    end
`endif

    $display("track loads: A %0d, B %0d, W %0d; stores A %0d, W %0d", loads[0], loads[1], loads[2], stores[0], stores[2]);
    if (errors == 0) $display("PASS fdd_tb");
    else             $display("FAILED fdd_tb: %0d errors", errors);
    $finish;
end

endmodule
