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
dev_WD2793 #(.sysCLK(SYS)) wd (
    .cpu_bus(cpu_bus), .model(2'd0), .floppy_drive_en(2'b11), .FDD_bus(FDD_bus),
    .cs(1'b1), .data(wd_data), .data_oe_rq(wd_oe)
);

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
genvar gi;
generate
    for (gi = 2; gi < 6; gi++) begin : idle_bd
        assign block_device_FDD[gi].rd = 1'b0;  assign block_device_FDD[gi].wr = 1'b0;
        assign block_device_FDD[gi].lba = '0;   assign block_device_FDD[gi].blk_cnt = '0;
        assign block_device_FDD[gi].buff_din = '0;
    end
endgenerate

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

// Disk images of the two drives (VD 1, 2)
logic [7:0] img[2][737280];
int         img_bytes[2] = '{0, 0};
int         img_seed[2]  = '{0, 0};
int         hps_lat      = MS;      // HPS answer latency
int         loads[2]     = '{0, 0};

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
    @(posedge clk);
    if (sd_rd[1] || sd_rd[2]) begin
        int n, d, lba, cnt;
        n   = sd_rd[1] ? 1 : 2;
        d   = n - 1;
        lba = int'(sd_lba[n]);
        cnt = (int'(sd_blk_cnt[n]) + 1) * 512;
        repeat (hps_lat) @(posedge clk);
        sd_ack[n] <= 1'b1;
        for (int i = 0; i < cnt; i++) begin
            int a = lba * 512 + i;
            @(posedge clk);
            sd_buff_addr <= 14'(i);
            sd_buff_dout <= a < img_bytes[d] ? img[d][a] : 8'hFF;
            sd_buff_wr   <= 1'b1;
            @(posedge clk);
            sd_buff_wr   <= 1'b0;
        end
        @(posedge clk); sd_ack[n] <= 1'b0;
        loads[d]++;
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

// Read one sector and compare with image d, LBA lba
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
    foreach (data[i]) if (data[i] !== pat(img_seed[d], lba + i / 512, i % 512)) bad++;
    if (bad) fail($sformatf("%s: %0d bytes differ, got image %0d LBA %0d (expected image %0d LBA %0d)",
                            what, bad, data[1][7:4], {data[1][3:0], data[0]}, img_seed[d], lba));
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

// ------------------------------------------------------------------ FM cell rate (separate unit, no SD answers)
FDD_if          fm_bus();
block_device_if fm_bd[2]();
assign fm_bus.USEL = 1'b0;  assign fm_bus.MOTORn = 1'b0;  assign fm_bus.STEPn = 1'b1;
assign fm_bus.SDIRn = 1'b1; assign fm_bus.SIDEn  = 1'b1; assign fm_bus.DSKCHG_ACK = 2'b00;
generate
    for (gi = 0; gi < 2; gi++) begin : fm_hps
        assign fm_bd[gi].ack = 1'b0;          assign fm_bd[gi].buff_addr = '0;
        assign fm_bd[gi].buff_dout = '0;      assign fm_bd[gi].buff_wr = 1'b0;
        assign fm_bd[gi].img_size = 64'd737280;
        assign fm_bd[gi].img_readonly = 1'b0;
`ifdef OLD
        assign fm_bd[gi].img_mounted = 1'b1;  // level in the old block device semantics
`else
        assign fm_bd[gi].img_mounted = 1'b0;
`endif
    end
endgenerate
`ifdef OLD
fdd #(.sysCLK(SYS), .ID("FDDF")) fm_dut (
    .clk(clk), .reset(reset), .FDD_bus(fm_bus), .block_device(fm_bd),
    .speed(2'b00), .mfm(2'b00), .sides(2'b11), .sectors('{9,9}), .sector_size('{2,2}), .density('{0,0})
);
`else
fdd #(.sysCLK(SYS), .ID("FDDF"), .MFM(1'b0)) fm_dut (
    .clk(clk), .reset(reset), .FDD_bus(fm_bus), .block_device(fm_bd),
    .drive_ds(2'b11), .need_motor(1'b0)
`ifndef NO_MOTOR_OFF
    , .motor_off_ms(16'd0)
`endif
);
`endif
longint unsigned fm_last = 0, fm_min = '1;
logic fm_q = 1;
always @(posedge clk) begin
    fm_q <= fm_bus.READ_DATAn;
    if (fm_q && !fm_bus.READ_DATAn && !reset) begin
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
    msx_config.fdd           = 6'b000011;                         // FDC in cartridge A: drives VD 1, 2
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

    // --- drive A, 720K
    select_drive(0, 0, 1);
    type1("restore", 8'h00);
    mem_rd(16'h7FF8, st);
    if (!st[2]) fail($sformatf("restore: no TRACK00 in status %02h", st));
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

    // --- FM: one cell = 4 us at 250 kbit/s media (FF gap: a pulse every cell)
    if (fm_min < longint'(SYS / 250_000) - 4 || fm_min > longint'(SYS / 250_000) + 4)
        fail($sformatf("FM cell %0d clk (expected %0d)", fm_min, SYS / 250_000));

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
`endif

    $display("track loads: A %0d, B %0d; FM min interval %0d clk", loads[0], loads[1], fm_min);
    if (errors == 0) $display("PASS fdd_tb");
    else             $display("FAILED fdd_tb: %0d errors", errors);
    $finish;
end

endmodule
