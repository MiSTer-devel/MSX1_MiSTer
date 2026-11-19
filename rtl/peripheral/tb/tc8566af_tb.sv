// TC8566AF controller (dev_TC8566AF + tc8566af core) with the floppy drive unit (fdd),
// blockDevMux and a model of the HPS block transfer serving DSK images. The CPU side follows
// the Panasonic FS-A1F disk ROM: control 0 = 14h, Specify 03 DF 09 (non-DMA), Recalibrate /
// Seek with Sense Interrupt, Sense Drive Status, Read Data 46h with a data loop on the main
// status register (RQM, NDM) and a TC pulse (control 1: 03h, 02h), then the 7 result bytes.
// Images hold a pattern that identifies image (seed) and LBA in every sector (as fdd_tb).
//
// Checked: recalibrate / seek / ST0 / PCN, ST3 (track 0, two side, ready), sector data and
// all 7 result bytes on both sides and after a seek, multi-sector read, Read ID, a missing
// sector (ST1 ND), Recalibrate / Seek on a drive without a disk (Sense Interrupt reports the
// end), turbo R registers (7FF4 / 7FF5, 7FF1 disk change with read clear), the
// register window constants (7FF0, 7FFC-7FFF, unused FFh, page 2 mirror), motor of the selected
// drive. Fixes of PC88_MiSTer: step time (16 - SRT) x 2 ms without settling, recalibrate at most
// 77 steps, read at EOT without TC (IC 01, EN, C H R kept), result phase of a read 93 us after
// the end, head load / unload (HLT, HUT; probe of the core, not with PREV).
// Write Data 45h: the sector reaches the image through the drive and reads back, a write
// protected image ends with ST1 NW (not with PREV).
//
// PREV=<rev>: core and glue of that revision (shows which checks the old core fails).
//
// Run: wsl.exe -- bash rtl/peripheral/tb/run_tc.sh        (OLD_GLUE=1: bugs of the TurboFDC2 glue)
module tc8566af_tb;

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

FDD_if      FDD_bus();
wire  [7:0] tc_data;
wire        tc_oe;
logic [1:0] model = 2'd2;               // 7FF8 registers (MSX2, FS-A1F)
MSX::block_info_t blk = '0;                             // block of the controller: ROM size
initial blk.rom_size = 25'h4000;                        // FS-A1F: 16 KB disk ROM, one bank
dev_TC8566AF #(.sysCLK(SYS)) tc (
    .cpu_bus(cpu_bus),
`ifndef PREV_CORE
    .block_info(blk),
`endif
    .model(model), .twoside(1'b1), .FDD_bus(FDD_bus),
    .cs(1'b1), .data(tc_data), .data_oe_rq(tc_oe)
);
`ifdef PREV_CORE
assign FDD_bus.WRITE_GATEn = 1'b1;                      // the old glue does not drive the write signals
assign FDD_bus.WRITE_DATAn = 1'b1;
assign FDD_bus.MFM         = 1'b1;
`endif

// CPU accesses at least 4 us apart (Z80 LD A,(nn) at 3.58 MHz is 3.6 us): the MSR is only
// valid some cycles after a data byte was taken
localparam int GAP = 4 * SYS / 1_000_000;
task automatic mem_wr(input logic [15:0] a, input logic [7:0] d);
    @(negedge clk); addr = a; dbo = d; mreq = 1; wr = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (3) @(negedge clk); mreq = 0; wr = 0;
    repeat (GAP) @(negedge clk);
endtask

task automatic mem_rd(input logic [15:0] a, output logic [7:0] d);
    @(negedge clk); addr = a; mreq = 1; rd = 1; req = 1;
    @(negedge clk); req = 0;
    repeat (2) @(negedge clk);
    d = tc_oe ? tc_data : 8'hEE;                       // EE: the device does not answer
    mreq = 0; rd = 0;
    repeat (GAP) @(negedge clk);
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

// Drive unit as msx_system configures it for a TC8566AF (openMSX: no connectionstyle -> the
// signals need the motor)
fdd #(.sysCLK(SYS), .ID("FDDT")) drive (
    .clk(clk), .reset(reset), .FDD_bus(FDD_bus), .block_device(block_device_FDD[0:1]),
    .drive_ds(2'b11), .need_motor(1'b1), .motor_off_ms(16'd0)
);

logic [7:0] img[2][737280];
int         img_bytes[2] = '{0, 0};
int         img_seed[2]  = '{0, 0};
int         stores[2]    = '{0, 0};

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
    if (sd_rd[1] || sd_rd[2] || sd_wr[1] || sd_wr[2]) begin
        int n, d, lba, cnt;
        bit is_wr;
        n     = (sd_rd[1] || sd_wr[1]) ? 1 : 2;
        d     = n - 1;
        is_wr = sd_wr[n];
        lba   = int'(sd_lba[n]);
        cnt   = (int'(sd_blk_cnt[n]) + 1) * 512;
        repeat (MS) @(posedge clk);
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
        if (is_wr) stores[d]++;
    end
end

// ------------------------------------------------------------------ FDC access as the disk ROM
logic [15:0] r_ctl0 = 16'h7FF8, r_ctl1 = 16'h7FF9, r_msr = 16'h7FFA, r_dat = 16'h7FFB;

task automatic use_turbo_r_regs(input bit on);
    model  = on ? 2'd1 : 2'd2;
    r_ctl0 = on ? 16'h7FF2 : 16'h7FF8;
    r_ctl1 = on ? 16'h7FF3 : 16'h7FF9;
    r_msr  = on ? 16'h7FF4 : 16'h7FFA;
    r_dat  = on ? 16'h7FF5 : 16'h7FFB;
endtask

// Wait for RQM with the given DIO (0: CPU -> FDC, 1: FDC -> CPU)
task automatic wait_rqm(input bit dio, input string what, output bit ok);
    logic [7:0] s;
    longint unsigned t_end;
    t_end = cyc + 50 * longint'(MS);
    ok = 0;
    while (cyc < t_end) begin
        mem_rd(r_msr, s);
        if (s[7] && s[6] == dio) begin ok = 1; return; end
    end
    fail($sformatf("%s: no RQM with DIO %0d (MSR %02h)", what, dio, s));
endtask

task automatic command(input string what, input logic [7:0] b[]);
    bit ok;
    foreach (b[i]) begin
        wait_rqm(1'b0, $sformatf("%s byte %0d", what, i), ok);
        if (!ok) return;
        mem_wr(r_dat, b[i]);
    end
endtask

// Result phase as the disk ROM: read while RQM and DIO = 1; n bytes expected
task automatic result(input string what, input int n, output logic [7:0] r[]);
    logic [7:0] s, q[$], m[$];
    longint unsigned t_end;
    q.delete(); m.delete();                             // (Verilator keeps queues between calls)
    t_end = cyc + 1000 * longint'(MS);                   // a missing sector ends after 2 index pulses
    while (cyc < t_end && q.size() < 16) begin
        mem_rd(r_msr, s);
        if (m.size() == 0 || m[$] != s) m.push_back(s);
        if (!s[7]) continue;
        if (!s[6]) break;
        mem_rd(r_dat, s);
        q.push_back(s);
    end
    r = new[n];
    foreach (r[i]) r[i] = i < q.size() ? q[i] : 8'hXX;
    if (q.size() != n) fail($sformatf("%s: %0d result bytes %p (expected %0d), MSR %p", what, q.size(), q, n, m));
endtask

// Result bytes while DIO = 1, any count (Sense Interrupt: 80h alone when nothing is pending)
task automatic result_any(output logic [7:0] r[]);
    logic [7:0] s, q[$];
    longint unsigned t_end;
    q.delete();
    t_end = cyc + 50 * longint'(MS);
    while (cyc < t_end && q.size() < 16) begin
        mem_rd(r_msr, s);
        if (!s[7]) continue;
        if (!s[6]) break;
        mem_rd(r_dat, s);
        q.push_back(s);
    end
    r = new[q.size()];
    foreach (r[i]) r[i] = q[i];
endtask

// Recalibrate / Seek end: Sense Interrupt until ST0 has SE (as the disk ROM, no INT line)
task automatic wait_seek(input string what, input int pcn, output int ms);
    logic [7:0] r[], s;
    longint unsigned t0, t_end;
    t0 = cyc;
    t_end = cyc + 2000 * longint'(MS);
    ms = -1;
    while (cyc < t_end) begin
        repeat (MS) @(negedge clk);
`ifdef SEEK_TRACE
        mem_rd(r_msr, s);
        $display("%s %0d ms: MSR %02h before sense int", what, cyc / MS, s);
`endif
        command({what, " sense int"}, '{8'h08});
        result_any(r);
`ifdef SEEK_TRACE
        $display("%s %0d ms: result %p", what, cyc / MS, r);
`endif
        if (r.size() == 2 && r[0][5]) begin
            if (r[0][7:6] != 2'b00 || r[1] != 8'(pcn))
                fail($sformatf("%s: ST0 %02h PCN %0d (expected PCN %0d)", what, r[0], r[1], pcn));
            ms = int'((cyc - t0) / MS);
            return;
        end
    end
    fail({what, ": no seek end"});
endtask

// Read Data (MFM) of sectors sec..eot on cylinder c, head h of drive 0; data loop as the ROM:
// a byte while RQM and NDM, then a TC pulse after the last expected byte
int res_us;                                             // read_data: TC to result phase, us
task automatic read_data(input string what, input int c, input int h, input int sec, input int eot,
                         input int lba, output logic [7:0] st[], input bit mfm = 1);
    logic [7:0] s, v;
    int n, bad, nbytes;
    longint unsigned t_end, t_tc;
    n = 0; bad = 0; nbytes = (eot - sec + 1) * 512;
    command(what, '{mfm ? 8'h46 : 8'h06, 8'(h << 2), 8'(c), 8'(h), 8'(sec), 8'h02, 8'(eot), 8'h2A, 8'hFF});
    t_end = cyc + 3000 * longint'(MS);
    while (n < nbytes && cyc < t_end) begin
        mem_rd(r_msr, s);
        if (!s[7]) continue;
        if (!s[5]) break;                               // execution phase ended
        mem_rd(r_dat, v);
        if (v !== img[0][lba * 512 + n]) bad++;         // the image array holds the writes too
        n++;
    end
    mem_wr(r_ctl1, 8'h03);                              // TC
    t_tc = cyc;
    mem_wr(r_ctl1, 8'h02);
    do mem_rd(r_msr, s); while (s[7:6] != 2'b11 && cyc < t_tc + 10 * longint'(MS));
    res_us = int'((cyc - t_tc) * 1_000_000 / SYS);
    result(what, 7, st);
    if (n != nbytes) fail($sformatf("%s: %0d of %0d bytes (ST0 %02h ST1 %02h ST2 %02h)", what, n, nbytes, st[0], st[1], st[2]));
    if (bad) fail($sformatf("%s: %0d bytes differ (expected image %0d LBA %0d)", what, bad, img_seed[0], lba));
    if (st[0][7:6] != 2'b00 || st[1] != 8'h00 || st[2] != 8'h00)
        fail($sformatf("%s: ST0 %02h ST1 %02h ST2 %02h", what, st[0], st[1], st[2]));
    // uPD765 ID after TC on the last sector = EOT, MT = 0: C + 1, H, R = 1, N (openMSX: C, R = EOT + 1)
    if (st[0][2] != h[0] || st[3] != 8'(c + 1) || st[4] != 8'(h) || st[5] != 8'h01 || st[6] != 8'h02)
        fail($sformatf("%s: result C %0d H %0d R %0d N %0d, ST0 %02h", what, st[3], st[4], st[5], st[6], st[0]));
endtask

// Write Data (MFM) of one sector on cylinder c, head h of drive 0, data loop as the ROM: a byte
// while RQM and NDM, then a TC pulse; exp_bytes = 0 when the command is expected to refuse
task automatic write_data(input string what, input int c, input int h, input int sec,
                          input logic [7:0] data[512], output logic [7:0] st[], input int exp_bytes = 512);
    logic [7:0] s;
    int n;
    longint unsigned t_end;
    n = 0;
    command(what, '{8'h45, 8'(h << 2), 8'(c), 8'(h), 8'(sec), 8'h02, 8'(sec), 8'h2A, 8'hFF});
    t_end = cyc + 3000 * longint'(MS);
    while (n < 512 && cyc < t_end) begin
        mem_rd(r_msr, s);
        if (!s[7]) continue;
        if (!s[5] || s[6]) break;                       // execution phase ended
        mem_wr(r_dat, data[n]);
        n++;
    end
    mem_wr(r_ctl1, 8'h03);                              // TC
    mem_wr(r_ctl1, 8'h02);
    result(what, 7, st);
    if (n != exp_bytes) fail($sformatf("%s: %0d bytes taken (expected %0d; ST0 %02h ST1 %02h ST2 %02h)", what, n, exp_bytes, st[0], st[1], st[2]));
endtask

// ------------------------------------------------------------------ test sequence
initial begin
    logic [7:0] v, r[];
    int ms;
    msx_config.wait_count    = '0;
    msx_config.cpu_clock_sel = '0;
    msx_config.fdd           = 6'b000011;              // FDC unit 0: drives on VD 1, 2
    repeat (10) @(negedge clk);
    reset = 0;
    repeat (10) @(negedge clk);
    mount(0, 737280, 1);                                // drive 0: 720K

    // --- constant registers, all types
    mem_rd(16'h7FFC, v); if (v != 8'hFC) fail($sformatf("7FFC = %02h", v));
    mem_rd(16'h7FFD, v); if (v != 8'hFC) fail($sformatf("7FFD = %02h", v));
    mem_rd(16'h7FFF, v); if (v != 8'h3F) fail($sformatf("7FFF = %02h", v));
    mem_rd(16'h7FF0, v); if (v != 8'h00) fail($sformatf("7FF0 = %02h (bank)", v));
    mem_rd(16'h7FF3, v); if (v != 8'hFF) fail($sformatf("7FF3 = %02h", v));
    mem_rd(16'h7FEF, v); if (v != 8'hEE) fail($sformatf("7FEF = %02h (expected no answer, ROM)", v));
    mem_rd(16'hBFFF, v); if (v != 8'h3F) fail($sformatf("BFFF = %02h (page 2 window)", v));
    mem_wr(16'h7FF0, 8'h03);                            // one 16 KB bank: stays 0
    mem_rd(16'h7FF0, v); if (v != 8'h00) fail($sformatf("7FF0 = %02h after writing 03 (16 KB ROM)", v));

    // --- motor of the selected drive, control 0 bits 7:4
    mem_wr(r_ctl0, 8'h04);
    repeat (10) @(negedge clk);
    if (FDD_bus.MOTORn !== 1'b1) fail("motor on with control 0 = 04");
    mem_wr(r_ctl0, 8'h14);                              // motor 0, drive 0 (FS-A1F)
    repeat (10) @(negedge clk);
    if (FDD_bus.MOTORn !== 1'b0 || FDD_bus.USEL !== 1'b0) fail("drive 0 motor off with control 0 = 14");
    repeat (5 * MS) @(negedge clk);                     // spin up

    // --- Disk ROM init (FS-A1F 7742h): control 0 = 04h (motor off), Specify, Recalibrate, Sense
    // Interrupt polled back to back until the end is reported. With the motor off the drive does
    // not show TRACK0 (need_motor), so the Recalibrate ends with an error; the ROM repeats Sense
    // Interrupt until ST0 has SE (7970h), so SE must come with the error too (uPD765, openMSX).
    mem_wr(r_ctl0, 8'h04);
    command("init specify", '{8'h03, 8'hDF, 8'h09});
    command("init recalibrate", '{8'h07, 8'h00});
    begin
        longint unsigned t0 = cyc, t_end = cyc + 3000 * longint'(MS);
        bit done = 0;
        while (!done && cyc < t_end) begin
            command("init sense int", '{8'h08});
            result_any(r);
            if (r.size() == 2) begin
                done = 1;
                $display("init recalibrate (motor off): ST0 %02h PCN %0d after %0d ms", r[0], r[1], (cyc - t0) / MS);
                if (r[0] != 8'h70)                      // IC 01, SE (the ROM waits for it), EC
                    fail($sformatf("init recalibrate (motor off): ST0 %02h (expected 70h)", r[0]));
                // uPD765: at most 77 step pulses of (16 - SRT) * 2 ms = 6 ms, the error one step later
                if ((cyc - t0) / MS < 460 || (cyc - t0) / MS > 485)
                    fail($sformatf("init recalibrate (motor off): %0d ms (expected 78 x 6 ms)", (cyc - t0) / MS));
            end
        end
        if (!done) fail("init recalibrate (motor off): Sense Interrupt never reports the end (80h only)");
    end
    mem_wr(r_ctl0, 8'h14);
    repeat (5 * MS) @(negedge clk);

    // --- Specify (non-DMA), Recalibrate, Sense Drive Status
    command("specify", '{8'h03, 8'hDF, 8'h09});
`ifdef MSR_TRACE
    begin   // MSR after Sense Interrupt, every clock for 200 us
        logic [7:0] s, last = 8'hAA;
        longint unsigned t0;
        command("trace recalibrate", '{8'h07, 8'h00});
        repeat (MS) @(negedge clk);
        command("trace sense int", '{8'h08});
        for (int k = 0; k < 3; k++) begin
            t0 = cyc;
            last = 8'hAA;
            repeat (MS) begin
                @(negedge clk); addr = r_msr; mreq = 1; rd = 1; #0;
                @(posedge clk); s = tc_oe ? tc_data : 8'hFF;
                if (s != last) begin $display("MSR %02h at +%0d clk", s, cyc - t0); last = s; end
            end
            mreq = 0; rd = 0;
            mem_rd(r_dat, s);
            $display("data read %0d: %02h", k, s);
        end
        $finish;
    end
`endif
    command("recalibrate", '{8'h07, 8'h00});
    wait_seek("recalibrate", 0, ms);
    command("sense drive", '{8'h04, 8'h00});
    result("sense drive", 1, r);
    if (r[0][4] != 1'b1 || r[0][3] != 1'b1 || r[0][5] != 1'b1 || r[0][1:0] != 2'b00)
        fail($sformatf("ST3 %02h (expected track 0, two side, ready, unit 0)", r[0]));

    // --- read: T0 H0 S1, T0 H1 S9, seek to 5, T5 H0 S1-3, T5 H1 S9
    read_data("T0 H0 S1", 0, 0, 1, 1, 0, r);
    // the result phase of a read starts 93 x 1 us after the end (PC-8801FH, PC88_MiSTer fb70fdc);
    // TC comes after the last byte, the end is after the data CRC (2 bytes, 64 us)
    $display("T0 H0 S1: TC to result phase %0d us", res_us);
    if (res_us < 130 || res_us > 200) fail($sformatf("TC to result phase %0d us (expected CRC + 93 us)", res_us));
    read_data("T0 H1 S9", 0, 1, 9, 9, 17, r);
    command("seek 5", '{8'h0F, 8'h00, 8'h05});
    wait_seek("seek 5", 5, ms);
    // uPD765 step (16 - SRT) * 2 ms = 6 ms, no settling time: 5 steps 30 ms (+ Sense Interrupt poll)
    $display("seek 0 -> 5: %0d ms", ms);
    if (ms < 28 || ms > 36) fail($sformatf("seek 0 -> 5: %0d ms (expected 5 x 6 ms)", ms));
    read_data("T5 H0 S1-3", 5, 0, 1, 3, 90, r);
    read_data("T5 H1 S9", 5, 1, 9, 9, 107, r);

    // --- EOT without TC: the read ends after the EOT sector with IC 01 and EN, C H R kept
    // (uPD765; PC88_MiSTer 2620836, f2d6a8f). It used to look for R = EOT + 1 two turns (ND).
    begin
        logic [7:0] s, v;
        int n = 0;
        longint unsigned t_last;
        command("read T5 S3 no TC", '{8'h46, 8'h00, 8'h05, 8'h00, 8'h03, 8'h02, 8'h03, 8'h2A, 8'hFF});
        while (n < 512) begin
            mem_rd(r_msr, s);
            if (!s[7]) continue;
            if (!s[5]) break;
            mem_rd(r_dat, v);
            n++;
        end
        t_last = cyc;
        result("read T5 S3 no TC", 7, r);
        $display("read without TC: %0d bytes, result %p after %0d ms", n, r, (cyc - t_last) / MS);
        if (n != 512 || r[0] != 8'h40 || r[1] != 8'h80 || r[2] != 8'h00 || r[3] != 8'd5 || r[4] != 8'd0 ||
            r[5] != 8'd3 || r[6] != 8'd2)
            fail($sformatf("read without TC: %0d bytes, result %p (expected 40 80 00 05 00 03 02)", n, r));
        if ((cyc - t_last) / MS > 5) fail($sformatf("read without TC: result after %0d ms", (cyc - t_last) / MS));
    end
`ifndef PREV_CORE
    // --- head load: loaded after a read, unloaded HUT (Specify F: 15 x 32 ms) after the last one
    if (tc.fdc.hdld !== 1'b1) fail("head not loaded after a read");
    repeat (500 * MS) @(negedge clk);
    if (tc.fdc.hdld !== 1'b0) fail("head still loaded 500 ms after the last read (HUT 480 ms)");
`endif

    // --- Read ID (MFM) on T5 H0: any sector header of the track
    command("read id", '{8'h4A, 8'h00});
    result("read id", 7, r);
    if (r[0][7:6] != 2'b00 || r[3] != 8'd5 || r[4] != 8'd0 || r[5] < 8'd1 || r[5] > 8'd9 || r[6] != 8'd2)
        fail($sformatf("read id: ST0 %02h C %0d H %0d R %0d N %0d", r[0], r[3], r[4], r[5], r[6]));

    // --- sector 10 does not exist: abnormal end, ST1 ND after two index pulses
    command("read T5 S10", '{8'h46, 8'h00, 8'h05, 8'h00, 8'h0A, 8'h02, 8'h0A, 8'h2A, 8'hFF});
    result("read T5 S10", 7, r);
    if (r[0][7:6] != 2'b01 || r[1] != 8'h04)
        fail($sformatf("read T5 S10: ST0 %02h ST1 %02h ST2 %02h (expected 4x 04 xx)", r[0], r[1], r[2]));

    // --- drive 1 has no disk (not ready): Recalibrate ends at once, IC 01 + SE + NR (69h), as
    // PC88_MiSTer a9ab3e6 (PC-8801FH); openMSX gives 21h (SE only)
    mem_wr(r_ctl0, 8'h21);                              // motor 1, drive 1
    command("recalibrate (no disk)", '{8'h07, 8'h01});
    begin
        longint unsigned t_end = cyc + 2000 * longint'(MS);
        bit done = 0;
        while (!done && cyc < t_end) begin
            repeat (MS) @(negedge clk);
            command("no disk sense int", '{8'h08});
            result_any(r);
            if (r.size() == 2) begin
                done = 1;
                if (r[0] != 8'h69)
                    fail($sformatf("recalibrate (no disk): ST0 %02h (expected 69h)", r[0]));
                else $display("recalibrate (no disk): ST0 %02h after %0d ms", r[0], (cyc - (t_end - 2000 * longint'(MS))) / MS);
            end
        end
        if (!done) fail("recalibrate (no disk): Sense Interrupt never reports the end (80h only)");
    end
    command("seek 5 (no disk)", '{8'h0F, 8'h01, 8'h05});
    begin
        longint unsigned t0 = cyc, t_end = cyc + 2500 * longint'(MS);
        bit done = 0;
        while (!done && cyc < t_end) begin
            repeat (MS) @(negedge clk);
            command("no disk sense int", '{8'h08});
            result_any(r);
            if (r.size() == 2) begin
                done = 1;
                if (!r[0][5] || r[0][1:0] != 2'b01 || r[0][7])
                    fail($sformatf("seek (no disk): ST0 %02h (expected SE, US 1)", r[0]));
                else $display("seek (no disk): ST0 %02h PCN %0d after %0d ms", r[0], r[1], (cyc - t0) / MS);
            end
        end
        if (!done) fail("seek (no disk): Sense Interrupt never reports the end (80h only)");
    end
    mem_wr(r_ctl0, 8'h14);                              // back to drive 0

    // --- turbo R registers: 7FF4 / 7FF5, 7FF1 disk change (bits 4 / 5 = 0, read clears)
    use_turbo_r_regs(1);
`ifndef PREV_CORE
    // ROM bank of the turbo R disk ROM (64 KB, 4 banks): written at 7FF0 only, read back in the
    // register window of every page (openMSX TurboRFDC)
    blk.rom_size = 25'h10000;
    mem_wr(16'h7FF0, 8'h06);
    mem_rd(16'h7FF0, v); if (v != 8'h02) fail($sformatf("bank 7FF0 = %02h after writing 06 (expected 02)", v));
    mem_rd(16'hBFF0, v); if (v != 8'h02) fail($sformatf("bank BFF0 = %02h (expected 02)", v));
    mem_wr(16'hBFF0, 8'h01);
    mem_rd(16'h7FF0, v); if (v != 8'h02) fail($sformatf("bank = %02h after writing BFF0 (expected 02)", v));
    mem_wr(16'h7FF0, 8'h00);
`endif
    mem_rd(16'h7FF1, v);
    if (v != 8'h03) fail($sformatf("7FF1 after mount = %02h (expected 03: both changed)", v));
    mem_rd(16'h7FF1, v);
    if (v != 8'h33) fail($sformatf("7FF1 read again = %02h (expected 33)", v));
    mount(0, 737280, 2);
    mem_rd(16'h7FF1, v);
    if (v != 8'h23) fail($sformatf("7FF1 after drive 0 change = %02h (expected 23)", v));
    mem_wr(r_ctl0, 8'h14);
    command("recalibrate (turbo R)", '{8'h07, 8'h00});
    wait_seek("recalibrate (turbo R)", 0, ms);
    $display("recalibrate 5 -> 0: %0d ms", ms);
    if (ms < 28 || ms > 36) fail($sformatf("recalibrate 5 -> 0: %0d ms (expected 5 x 6 ms)", ms));
    read_data("turbo R T0 H0 S2", 0, 0, 2, 2, 1, r);

`ifndef PREV_CORE
    // --- write T3 H0 S4: the drive flushes the sector to the image, neighbours intact, the sector
    // reads back; a write protected image: ST0 IC 01, ST1 NW, nothing stored
    begin
        logic [7:0] wdata[512];
        int s0, bad;
        longint unsigned t_end;
        foreach (wdata[i]) wdata[i] = 8'(i * 5 + 1);
        command("seek 3", '{8'h0F, 8'h00, 8'h03});
        wait_seek("seek 3", 3, ms);
        s0 = stores[0];
        write_data("write T3 H0 S4", 3, 0, 4, wdata, r);
        if (r[0][7:6] != 2'b00 || r[1] != 8'h00 || r[2] != 8'h00)
            fail($sformatf("write T3 H0 S4: ST0 %02h ST1 %02h ST2 %02h", r[0], r[1], r[2]));
        t_end = cyc + 50 * longint'(MS);
        while (stores[0] < s0 + 1 && cyc < t_end) @(negedge clk);
        if (stores[0] != s0 + 1) fail($sformatf("write T3 H0 S4: %0d sectors stored (expected 1)", stores[0] - s0));
        bad = 0;
        for (int i = 0; i < 512; i++) if (img[0][57 * 512 + i] !== wdata[i]) bad++;
        if (bad) fail($sformatf("write T3 H0 S4: %0d bytes of the image differ", bad));
        if (img[0][56 * 512] !== pat(2, 56, 0) || img[0][58 * 512] !== pat(2, 58, 0)) fail("write T3 H0 S4: a neighbour sector changed");
        read_data("T3 H0 S4 after the write", 3, 0, 4, 4, 57, r);

        mount(0, 737280, 3, 1);
        repeat (25 * MS) @(negedge clk);
        s0 = stores[0];
        write_data("write protected", 3, 0, 4, wdata, r, 0);
        if (r[0][7:6] != 2'b01 || !r[1][1])
            fail($sformatf("write protected: ST0 %02h ST1 %02h (expected IC 01, NW)", r[0], r[1]));
        repeat (30 * MS) @(negedge clk);
        if (stores[0] != s0) fail("write protected: sector stored");

        // --- FM (MF = 0): the drive follows the controller's encoding, then MFM again
        read_data("FM T3 H0 S5", 3, 0, 5, 5, 58, r, 0);
        if (FDD_bus.MFM !== 1'b0) fail("FDD_if.MFM not 0 after an FM command");
        read_data("MFM again T3 H0 S5", 3, 0, 5, 5, 58, r, 1);
    end
`endif

    $display("tc8566af_tb done at %0d ms", cyc / MS);
    if (errors == 0) $display("PASS tc8566af_tb");
    else             $display("FAILED tc8566af_tb: %0d errors", errors);
    $finish;
end

// Watchdog
initial begin
    repeat (20000 * MS) @(posedge clk);
    fail("timeout");
    $display("FAILED tc8566af_tb: %0d errors", errors);
    $finish;
end

endmodule
