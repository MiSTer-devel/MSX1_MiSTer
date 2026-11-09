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
// drive.
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
dev_TC8566AF #(.sysCLK(SYS)) tc (
    .cpu_bus(cpu_bus), .model(model), .twoside(1'b1), .FDD_bus(FDD_bus),
    .cs(1'b1), .data(tc_data), .data_oe_rq(tc_oe)
);

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

function automatic logic [7:0] pat(input int seed, input int lba, input int off);
    if (off == 0) return 8'(lba);
    if (off == 1) return {4'(seed), 4'(lba >> 8)};
    return 8'(lba * 31 + off * 7 + seed * 101 + (off >> 3));
endfunction

task automatic mount(input int d, input int size, input int seed);
    for (int i = 0; i < size; i++) img[d][i] = pat(seed, i / 512, i % 512);
    img_bytes[d] = size;
    img_seed[d]  = seed;
    @(negedge clk); img_size = 64'(size); img_readonly = 1'b0; img_mounted[d + 1] = 1'b1;
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
        repeat (MS) @(posedge clk);
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
task automatic wait_seek(input string what, input int pcn);
    logic [7:0] r[], s;
    longint unsigned t_end;
    t_end = cyc + 2000 * longint'(MS);
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
            return;
        end
    end
    fail({what, ": no seek end"});
endtask

// Read Data (MFM) of sectors sec..eot on cylinder c, head h of drive 0; data loop as the ROM:
// a byte while RQM and NDM, then a TC pulse after the last expected byte
task automatic read_data(input string what, input int c, input int h, input int sec, input int eot,
                         input int lba, output logic [7:0] st[]);
    logic [7:0] s, v;
    int n, bad, nbytes;
    longint unsigned t_end;
    n = 0; bad = 0; nbytes = (eot - sec + 1) * 512;
    command(what, '{8'h46, 8'(h << 2), 8'(c), 8'(h), 8'(sec), 8'h02, 8'(eot), 8'h2A, 8'hFF});
    t_end = cyc + 3000 * longint'(MS);
    while (n < nbytes && cyc < t_end) begin
        mem_rd(r_msr, s);
        if (!s[7]) continue;
        if (!s[5]) break;                               // execution phase ended
        mem_rd(r_dat, v);
        if (v !== pat(img_seed[0], lba + n / 512, n % 512)) bad++;
        n++;
    end
    mem_wr(r_ctl1, 8'h03);                              // TC
    mem_wr(r_ctl1, 8'h02);
    result(what, 7, st);
    if (n != nbytes) fail($sformatf("%s: %0d of %0d bytes (ST0 %02h ST1 %02h ST2 %02h)", what, n, nbytes, st[0], st[1], st[2]));
    if (bad) fail($sformatf("%s: %0d bytes differ (expected image %0d LBA %0d)", what, bad, img_seed[0], lba));
    if (st[0][7:6] != 2'b00 || st[1] != 8'h00 || st[2] != 8'h00)
        fail($sformatf("%s: ST0 %02h ST1 %02h ST2 %02h", what, st[0], st[1], st[2]));
    // uPD765 ID after TC on the last sector = EOT, MT = 0: C + 1, H, R = 1, N (openMSX: C, R = EOT + 1)
    if (st[0][2] != h[0] || st[3] != 8'(c + 1) || st[4] != 8'(h) || st[5] != 8'h01 || st[6] != 8'h02)
        fail($sformatf("%s: result C %0d H %0d R %0d N %0d, ST0 %02h", what, st[3], st[4], st[5], st[6], st[0]));
endtask

// ------------------------------------------------------------------ test sequence
initial begin
    logic [7:0] v, r[];
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
    wait_seek("recalibrate", 0);
    command("sense drive", '{8'h04, 8'h00});
    result("sense drive", 1, r);
    if (r[0][4] != 1'b1 || r[0][3] != 1'b1 || r[0][5] != 1'b1 || r[0][1:0] != 2'b00)
        fail($sformatf("ST3 %02h (expected track 0, two side, ready, unit 0)", r[0]));

    // --- read: T0 H0 S1, T0 H1 S9, seek to 5, T5 H0 S1-3, T5 H1 S9
    read_data("T0 H0 S1", 0, 0, 1, 1, 0, r);
    read_data("T0 H1 S9", 0, 1, 9, 9, 17, r);
    command("seek 5", '{8'h0F, 8'h00, 8'h05});
    wait_seek("seek 5", 5);
    read_data("T5 H0 S1-3", 5, 0, 1, 3, 90, r);
    read_data("T5 H1 S9", 5, 1, 9, 9, 107, r);

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

    // --- drive 1 has no disk (not ready): Sense Interrupt must report the Recalibrate end (the
    // ROM polls it). ST0 differs between models: this core 29h (SE, NR), upstream PC88_MiSTer
    // 69h (IC 01), openMSX 21h (SE only); checked: SE, US = 1, IC 00 or 01
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
                if (!r[0][5] || r[0][1:0] != 2'b01 || r[0][7])
                    fail($sformatf("recalibrate (no disk): ST0 %02h (expected SE, US 1)", r[0]));
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
    mem_rd(16'h7FF1, v);
    if (v != 8'h03) fail($sformatf("7FF1 after mount = %02h (expected 03: both changed)", v));
    mem_rd(16'h7FF1, v);
    if (v != 8'h33) fail($sformatf("7FF1 read again = %02h (expected 33)", v));
    mount(0, 737280, 2);
    mem_rd(16'h7FF1, v);
    if (v != 8'h23) fail($sformatf("7FF1 after drive 0 change = %02h (expected 23)", v));
    mem_wr(r_ctl0, 8'h14);
    command("recalibrate (turbo R)", '{8'h07, 8'h00});
    wait_seek("recalibrate (turbo R)", 0);
    read_data("turbo R T0 H0 S2", 0, 0, 2, 2, 1, r);

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
