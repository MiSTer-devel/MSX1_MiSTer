// Bare wd279x (WD2793 mode, MFM) against a synthetic drive: the testbench builds every revolution
// from parameters (gap 2 per sector, IDs from the head position), so a track can leave the IBM
// layout, and a short revolution (about 17 ms) keeps the index counts fast.
//
// Checked: head load (status bit 5 of type I) held for 15 idle index pulses, then released, and
// released by a type I command with h = 0 after a read; the data mark must come within 43 bytes of
// the ID (else record not found); Verify compares the ID with the track register (Step with
// u = 0 leaves it behind); head settle (E) 30 ms with the 1 MHz clock of MSX; Read Track returns
// every byte from index to index, also after a write splice at the index (GAP4A); the 500 kHz cell enable keeps its rate.
//
// Run: wsl.exe -- bash rtl/peripheral/tb/run_wd279x.sh   (PREV=<rev>: WD279x and modem of that revision)
module wd279x_tb;

localparam int SYS = 21477270;
localparam int MS  = SYS / 1000;

logic clk = 0, reset = 1;
always #1 clk = ~clk;
longint unsigned cyc = 0;
always @(posedge clk) cyc <= cyc + 1;

int errors = 0;
task automatic fail(input string msg);
    errors++;
    $display("FAIL %s", msg);
endtask

// ------------------------------------------------------------------ controller
logic       csn = 1'b1, ren = 1'b1, wen = 1'b1;
logic [1:0] a   = '0;
logic [7:0] din = '0;
wire  [7:0] dout;
wire        drq, intrq, hld, sso, wg, wd, stepn, sdirn;
logic       indexn = 1'b1;
wire        rawrdn;
int         cyl = 0;

wd279x #(.WD279_57(0), .sysCLK(SYS)) dut (
    .clk(clk), .MRn(~reset), .CSn(csn), .REn(ren), .WEn(wen), .A(a), .DIN(din), .DOUT(dout),
    .DRQ(drq), .INTRQ(intrq), .STEPn(stepn), .SDIRn(sdirn), .INDEXn(indexn), .TRK00n(cyl != 0),
    .READYn(1'b0), .WPROTn(1'b1), .HLD(hld), .SSO(sso), .RAWRDn(rawrdn), .DDENn(1'b0), .WG(wg), .WD(wd)
);

task automatic wr(input logic [1:0] ad, input logic [7:0] d);
    @(negedge clk); a = ad; din = d; csn = 1'b0;
    @(negedge clk); wen = 1'b0;
    repeat (3) @(negedge clk); wen = 1'b1; csn = 1'b1;
    repeat (2) @(negedge clk);
endtask

task automatic rd(input logic [1:0] ad, output logic [7:0] d);
    @(negedge clk); a = ad; csn = 1'b0;
    @(negedge clk); ren = 1'b0;
    repeat (2) @(negedge clk); d = dout; ren = 1'b1; csn = 1'b1;
    repeat (2) @(negedge clk);
endtask

// Command; data bytes taken while DRQ, until INTRQ. Returns the status, the bytes and the time
// of the first DRQ after the command (clk).
task automatic cmd(input logic [7:0] c, output logic [7:0] st, output logic [7:0] data[$],
                   output longint unsigned t_drq, input int ms = 600);
    logic [7:0] b;
    longint unsigned t0 = cyc, t_end = cyc + longint'(ms) * MS;
    data = {}; t_drq = 0;
    wr(2'd0, c);
    forever begin
        if (drq) begin
            if (t_drq == 0) t_drq = cyc - t0;
            rd(2'd3, b); data.push_back(b);
        end
        if (intrq) break;
        if (cyc > t_end) begin fail($sformatf("command %02h: timeout", c)); wr(2'd0, 8'hD0); break; end
        @(negedge clk);
    end
    rd(2'd0, st);
endtask

// ------------------------------------------------------------------ drive
// Head position from the step pulses (SDIRn = 1: in); track 0 sensor
logic stepn_q = 1'b1;
always @(posedge clk) begin
    stepn_q <= stepn;
    if (stepn_q && !stepn) cyl <= sdirn ? cyl + 1 : (cyl > 0 ? cyl - 1 : 0);
end

// Track: per sector the gap 2 length (bytes of 4E between the ID CRC and the 12 sync bytes)
localparam int NSEC = 2, SECLEN = 128;
int gap2[NSEC] = '{22, 22};
int revs = 0, trk_len = 0;

typedef struct packed { logic a1, c2; logic [7:0] b; } tbyte_t;
tbyte_t trk[$];
logic [15:0] crc;

task automatic put(input logic [7:0] b, input int n = 1, input bit a1 = 0, input bit c2 = 0);
    repeat (n) begin
        trk.push_back({a1, c2, b});
        crc = FDC::crc16(crc, b);
    end
endtask

task automatic put_crc();
    logic [15:0] c = crc;
    put(c[15:8]); put(c[7:0]);
endtask

task automatic build_track();
    trk = {};
    put(8'h4E, 40); put(8'h00, 12); put(8'hC2, 3, 0, 1); put(8'hFC); put(8'h4E, 20);
    for (int s = 0; s < NSEC; s++) begin
        put(8'h00, 12);
        crc = FDC::CRC_INIT; put(8'hA1, 3, 1); put(8'hFE);
        put(8'(cyl)); put(8'h00); put(8'(s + 1)); put(8'h00); put_crc();       // N = 0: 128 bytes
        put(8'h4E, gap2[s]); put(8'h00, 12);
        crc = FDC::CRC_INIT; put(8'hA1, 3, 1); put(8'hFB);
        for (int i = 0; i < SECLEN; i++) put(8'(s * 16 + i));
        put_crc();
        put(8'h4E, 24);
    end
    put(8'h4E, 40);
endtask

// MFM modulator of the modem library at the cell rate; the index pulse covers the first 8 bytes
logic       cell_tick;
clockEnabler #(.clkFreq(SYS), .targetFreq(500000)) cell_en (.clk(clk), .en(cell_tick));
logic [7:0] txdat = '0;
logic       txwr = 0, txa1 = 0, txc2 = 0;
wire        txemp, bitout;
mfmmod mod (
    .txdat(txdat), .txwr(txwr), .txma1(txa1), .txmc2(txc2), .brk(1'b0),
    .txemp(txemp), .txend(), .bitout(bitout), .writeen(), .sft(cell_tick), .clk(clk), .rstn(~reset)
);
// Write splice at the index (where Write Track ends): flux pulses between the cells break the
// MFM pattern of the first bytes, the demodulator loses its byte sync
logic splice = 0, glitch = 0;
assign rawrdn = ~(bitout | glitch);
initial forever begin
    @(negedge clk);
    if (splice) begin
        splice = 0;
        repeat (4) begin
            while (!cell_tick) @(negedge clk);
            repeat (SYS / 1_000_000) @(negedge clk);        // half a cell
            glitch = 1; @(negedge clk); glitch = 0;
        end
    end
end

int built_cyl = 0;
initial begin
    @(negedge clk);
    while (reset) @(negedge clk);
    forever begin
        build_track();
        built_cyl = cyl;
        trk_len = trk.size();
        revs++;
        foreach (trk[i]) begin
            while (!txemp) @(negedge clk);
            if (cyl != built_cyl) begin build_track(); built_cyl = cyl; end    // the head moved
            indexn = i >= 8;
            if (i == 2) splice = 1;
            txdat = trk[i].b; txwr = !(trk[i].a1 || trk[i].c2); txa1 = trk[i].a1; txc2 = trk[i].c2;
            @(negedge clk);
            txwr = 0; txa1 = 0; txc2 = 0;
        end
    end
end

task automatic wait_revs(input int n);
    int r0 = revs;
    while (revs < r0 + n) @(negedge clk);
endtask

// ------------------------------------------------------------------ cell_tick rate monitor
int cells = 0;
always @(posedge clk) if (cell_tick) cells++;

// ------------------------------------------------------------------ test sequence
initial begin
    logic [7:0] st, data[$];
    longint unsigned t;
    int c0;
    repeat (10) @(negedge clk);
    reset = 0;
    wait_revs(2);

    // --- cell rate: 500 kHz (10 ms = 5000 cells)
    c0 = cells;
    repeat (10 * MS) @(negedge clk);
    if (cells - c0 < 4995 || cells - c0 > 5005)
        fail($sformatf("cell rate: %0d cells in 10 ms (expected 5000)", cells - c0));

    // --- head load: Restore with h = 1 loads it; held for 15 idle revolutions, then released
    cmd(8'h08, st, data, t);
    if (!st[2] || !st[5]) fail($sformatf("restore h = 1: status %02h (expected track 0, head loaded)", st));
    wait_revs(12);
    rd(2'd0, st);
    if (!st[5]) fail($sformatf("head unloaded after 12 idle revolutions, status %02h", st));
    wait_revs(5);
    rd(2'd0, st);
    if (st[5] || hld) fail($sformatf("head still loaded after 17 idle revolutions, status %02h, HLD %b", st, hld));

    // --- a read loads the head (HLD and the status after Force Interrupt); it unloads after 15 idle
    //     revolutions and at once with a type I command with h = 0
    wr(2'd2, 8'd1);
    cmd(8'h80, st, data, t);
    if (data.size() != SECLEN || (st & 8'h9C) != 0) fail($sformatf("read S1: %0d bytes, status %02h", data.size(), st));
    wr(2'd0, 8'hD0);
    rd(2'd0, st);
    if (!st[5] || !hld) fail($sformatf("after a read: status %02h (Force Interrupt), HLD %b (expected head loaded)", st, hld));
    wait_revs(17);
    rd(2'd0, st);
    if (st[5] || hld) fail($sformatf("17 idle revolutions after a read: status %02h, HLD %b (expected unloaded)", st, hld));
    cmd(8'h80, st, data, t);
    wr(2'd3, 8'd0);
    cmd(8'h10, st, data, t);                                    // seek to track 0, h = 0
    if (st[5] || hld) fail($sformatf("seek h = 0 after a read: status %02h, HLD %b (expected unloaded)", st, hld));

    // --- DAM window: the data mark (after 12 x 00, A1 A1 A1) must come within 43 bytes of the ID
    gap2 = '{27, 28};                                           // DAM is byte 43 / 44 after the ID
    wait_revs(2);
    wr(2'd2, 8'd1);
    cmd(8'h80, st, data, t);
    if (data.size() != SECLEN || (st & 8'h9C) != 0)
        fail($sformatf("DAM at byte 43: %0d bytes, status %02h (expected a read)", data.size(), st));
    wr(2'd2, 8'd2);
    cmd(8'h80, st, data, t);
    if (data.size() != 0 || !st[4])
        fail($sformatf("DAM at byte 44: %0d bytes, status %02h (expected record not found)", data.size(), st));
    gap2 = '{22, 22};
    wait_revs(2);

    // --- Verify compares the ID with the track register: Step in with u = 0 leaves it at 0
    cmd(8'h00, st, data, t);                                    // restore: track 0, register 0
    cmd(8'h44, st, data, t, 1000);                              // step in, u = 0, V: head on 1
    if (cyl != 1 || !st[4])
        fail($sformatf("step u = 0 + verify: track %0d, status %02h (expected seek error)", cyl, st));
    wr(2'd1, 8'd1);
    cmd(8'h54, st, data, t, 1000);                              // step in, u = 1, V: head and register 2
    if (cyl != 2 || (st & 8'h18) != 0)
        fail($sformatf("step u = 1 + verify: track %0d, status %02h (expected no error)", cyl, st));

    // --- head settle 30 ms (E) with the 1 MHz clock: Read Address and Read Sector
    cmd(8'hC4, st, data, t);
    if (data.size() != 6 || t < 30 * MS || t > 50 * MS)
        fail($sformatf("read address E: %0d bytes, first DRQ after %0d us (expected 30 ms + the next ID)", data.size(), t / (MS / 1000)));
    wr(2'd2, 8'd1);
    cmd(8'h84, st, data, t);
    if (data.size() != SECLEN || t < 30 * MS)
        fail($sformatf("read sector E: %0d bytes, first DRQ after %0d us (expected at least 30 ms)", data.size(), t / (MS / 1000)));

    // --- Read Track: every byte from index to index, also the gap after the splice at the index
    cmd(8'hE0, st, data, t);
    begin
        bit    found = 0;
        string fs;
        for (int k = 0; k + 4 < data.size(); k++)
            if (data[k] == 8'hFE && data[k + 1] == 8'(cyl) && data[k + 2] == 8'd0 && data[k + 3] == 8'd1) found = 1;
        fs = found ? "found" : "missing";
        $display("read track: %0d bytes (track %0d), ID of sector 1 %s", data.size(), trk_len, fs);
        if (data.size() < trk_len - 3 || data.size() > trk_len + 3 || !found || (st & 8'hFC) != 0)
            fail($sformatf("read track: %0d bytes of %0d, ID of sector 1 %s, status %02h", data.size(), trk_len, fs, st));
    end

    if (errors == 0) $display("PASS wd279x_tb");
    else             $display("FAILED wd279x_tb: %0d errors", errors);
    $finish;
end

endmodule
