// tape (CAS player) + ddram: a CAS image in a DDR3 model is played and the cassette
// signal is decoded back (FSK 2400 Bd: "0" = one cycle, "1" = two cycles per bit;
// frame = start 0, 8 data bits LSB first, 2 stop bits 1).
// Blocks are split as openMSX does: a header may start at any byte, not only at
// a multiple of 8. Checks: silence before the first block, sync of ones before each
// block, data bytes of each block exactly as in the image, pulse widths, silence after
// the end of the file. The DDR3 model is randomly busy (Avalon waitrequest).
// Run: wsl.exe -- bash rtl/peripheral/tb/run_tape.sh [alt_tape.sv]   (DDRAM=alt_ddram.sv)
//      +cas=<file> plays a real CAS image, +blocks=<n> limits the checked blocks
//      (default: all of the synthetic image, 4 of a real one); +nosize: size 0 (unknown);
//      +nobusy: DDR3 never busy
module tape_tb;

localparam int PHASE = 560;              // clk per phase with ce_5m3 = 1 (4 phases per bit)
localparam int LAT   = 7;                // DDR3 read latency in clk

logic clk = 0, reset = 1, rewind = 1;
logic [26:0] size = '0;                  // CAS file size from the download
logic        busy_en = 1, DDRAM_BUSY = 0;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DUT + ddram
wire  [27:0] ram_a;
wire   [7:0] ram_di;
wire         ram_rd, ram_ready, cas_out;

tape dut (
    .clk(clk), .ce_5m3(1'b1), .play(1'b1), .rewind(rewind), .enable(1'b1), .size(size),
    .ram_a(ram_a), .ram_di(ram_di), .ram_rd(ram_rd),
    .buff_mem_ready(ram_ready), .cas_out(cas_out)
);

logic  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
logic [28:0] DDRAM_ADDR;
logic [63:0] DDRAM_DOUT, DDRAM_DIN;
logic        DDRAM_DOUT_READY = 0, DDRAM_RD, DDRAM_WE;

ddram ddr (
    .reset(reset), .DDRAM_CLK(clk), .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .addr(ram_a), .dout(ram_di), .din(8'h00), .we(1'b0), .rd(ram_rd), .ready(ram_ready),
    .dout64()
);

// ------------------------------------------------------------------ CAS image
localparam logic [27:0] BASE = MSX::DDR3_CAS;
byte unsigned sig[8] = '{8'h1F, 8'hA6, 8'hDE, 8'hBA, 8'hCC, 8'h13, 8'h7D, 8'h74};
byte unsigned image[$];
byte unsigned exp_data[$];               // expected bytes of all blocks, concatenated
int           exp_start[$], exp_len[$];  // per block: offset in exp_data, length
int           nb_check;                  // blocks to check

task automatic put_header();
    foreach (sig[i]) image.push_back(sig[i]);
endtask

task automatic put(input byte unsigned b);
    image.push_back(b);
endtask

function automatic bit header_at(input int p);
    if (p + 8 > image.size()) return 0;
    for (int i = 0; i < 8; i++) if (image[p + i] != sig[i]) return 0;
    return 1;
endfunction

// Synthetic image: aligned blocks first, then headers at offsets 5 and 6 mod 8,
// data with a 7-byte prefix of the header, a stray byte before a header.
task automatic build_synthetic();
    string name = "GAME  ";
    put_header();                                                   // @0
    for (int i = 0; i < 10; i++) put(8'hD3);
    for (int i = 0; i < 6; i++)  put(name[i]);
    put_header();                                                   // @24
    for (int i = 0; i < 13; i++) put(8'(i * 37 + 5));               // no padding
    put_header();                                                   // @45
    for (int i = 0; i < 7; i++)  put(sig[i]);                       // almost a header
    put(8'h00); put(8'h55);
    put_header();                                                   // @62
    for (int i = 0; i < 5; i++)  put(8'(8'hA0 + i));
    put(8'h1F);                                                     // stray byte, then a header
    put_header();                                                   // @76
    for (int i = 0; i < 4; i++)  put(8'(8'hC0 + i));
endtask

// Split into blocks at every header, wherever it starts (openMSX CasImage)
task automatic split_blocks();
    int p = 0;
    while (p < image.size() && !header_at(p)) p++;
    while (p < image.size()) begin
        p += 8;
        exp_start.push_back(exp_data.size());
        while (p < image.size() && !header_at(p)) begin exp_data.push_back(image[p]); p++; end
        exp_len.push_back(exp_data.size() - exp_start[$]);
    end
endtask

initial begin
    string fname;
    int    fd, c, nb = 1000;
    if ($value$plusargs("cas=%s", fname)) begin
        nb = 4;
        fd = $fopen(fname, "rb");
        if (fd == 0) begin $display("FAIL cannot open %s", fname); $finish; end
        while ((c = $fgetc(fd)) != -1) image.push_back(8'(c));
        $fclose(fd);
    end else
        build_synthetic();
    split_blocks();
    if (!$test$plusargs("nosize")) size = 27'(image.size());
    if ($test$plusargs("nobusy")) busy_en = 0;
    nb_check = exp_len.size();
    void'($value$plusargs("blocks=%d", nb));
    if (nb_check > nb) nb_check = nb;
    $write("image %0d bytes, %0d blocks:", image.size(), exp_len.size());
    foreach (exp_len[i]) $write(" %0d", exp_len[i]);
    $display("");
end

// DDR3 model: one 64-bit word per read, after LAT clk; outside the image 00.
// Busy at random (also while a read is in flight); a read is taken only when not busy.
logic [28:0] rd_addr;
int          rd_wait = -1;
always_ff @(posedge clk) begin
    DDRAM_DOUT_READY <= 1'b0;
    DDRAM_BUSY <= busy_en && $urandom_range(3) == 0;
    if (DDRAM_RD && !DDRAM_BUSY) begin rd_addr <= DDRAM_ADDR; rd_wait <= LAT; end
    else if (rd_wait > 0) rd_wait <= rd_wait - 1;
    else if (rd_wait == 0) begin
        for (int b = 0; b < 8; b++) begin
            int ofs = int'({rd_addr[24:0], 3'(b)}) - int'(BASE);
            DDRAM_DOUT[8*b +: 8] <= (ofs >= 0 && ofs < image.size()) ? image[ofs] : 8'h00;
        end
        DDRAM_DOUT_READY <= 1'b1;
        rd_wait <= -1;
    end
end

// ------------------------------------------------------------------ decoder
int errors = 0;
int t = 0, t_rise = 0, t_edge = 0;
int first_rise = -1;
logic out_q = 0;
int half_ones = 0;                       // short high pulses (half of a "1")
int ones_run = 0;                        // consecutive "1" bits
byte unsigned got_data[$];               // decoded bytes of all blocks
int  got_start[$], max_run[$];           // per decoded block
int  fbit = -1;                          // -1 idle, 0..8 data, 9..10 stop
logic [7:0] fbyte;

function automatic int got_len(input int k);
    return (k + 1 < got_start.size() ? got_start[k + 1] : got_data.size()) - got_start[k];
endfunction

task automatic bit_in(input logic b);
    ones_run = b ? ones_run + 1 : 0;
    // long run of ones outside a frame = sync of the next block
    if (ones_run == 50 && fbit < 0 && (got_start.size() == 0 || got_len(got_start.size() - 1) > 0)) begin
        got_start.push_back(got_data.size());
        max_run.push_back(0);
    end
    if (got_start.size() == 0) return;
    if (ones_run > max_run[$]) max_run[$] = ones_run;
    if (fbit < 0) begin
        if (!b) fbit = 0;                // start bit
    end else if (fbit < 8) begin
        fbyte[fbit] = b; fbit++;
    end else begin
        if (!b) begin errors++; if (errors <= 10) $display("FAIL stop bit 0 (block %0d, byte %0d)", got_start.size() - 1, got_len(got_start.size() - 1)); end
        if (fbit == 9) begin got_data.push_back(fbyte); fbit = -1; end
        else fbit++;
    end
endtask

always_ff @(posedge clk) begin
    t <= t + 1;
    out_q <= cas_out;
    if (cas_out != out_q) t_edge <= t;
    if (cas_out && !out_q) begin
        if (first_rise < 0) first_rise <= t;
        t_rise <= t;
    end
    if (!cas_out && out_q) begin
        int w = t - t_rise;
        if (w == PHASE) begin
            half_ones++;
            if (half_ones == 2) begin bit_in(1'b1); half_ones = 0; end
        end else if (w == 2 * PHASE) begin
            if (half_ones != 0) begin errors++; if (errors <= 10) $display("FAIL lone half of a 1 at t=%0d", t); end
            half_ones = 0;
            bit_in(1'b0);
        end else begin
            errors++; if (errors <= 10) $display("FAIL pulse width %0d clk at t=%0d (expected %0d or %0d)", w, t, PHASE, 2 * PHASE);
        end
    end
end

// ------------------------------------------------------------------ run
initial begin
    longint limit;
    int last;
    bit at_eof;
    repeat (10) @(posedge clk);
    reset = 0;
    repeat (10) @(posedge clk);
    rewind = 0;
    // time for silence, syncs and data of the checked blocks, plus a margin
    limit = 2_000_000;
    for (int k = 0; k < nb_check; k++) limit += longint'(16_000 + 11 * exp_len[k]) * 4 * PHASE;
    last = nb_check - 1;
    // wait until the last checked block has its data, then 20 bytes more (next sync,
    // or silence at the end of the file)
    while (!(got_start.size() > nb_check ||
             (got_start.size() == nb_check && got_len(last) >= exp_len[last])) && t < limit)
        @(posedge clk);
    repeat (20 * 11 * 4 * PHASE) @(posedge clk);
    at_eof = nb_check == exp_len.size() && size != 0;
    if (at_eof && t - t_edge < 10 * 11 * 4 * PHASE) begin
        errors++; $display("FAIL signal goes on after the end of the file (last edge %0d clk ago)", t - t_edge);
    end

    if (first_rise < 900 * PHASE) begin
        errors++; $display("FAIL no silence before the first block: first edge at %0d clk", first_rise);
    end
    for (int k = 0; k < nb_check; k++) begin
        int n;
        if (k >= got_start.size()) begin
            errors++; $display("FAIL block %0d: no sync (decoded %0d blocks)", k, got_start.size());
            continue;
        end
        n = got_len(k);
        if (max_run[k] < 8000) begin errors++; $display("FAIL block %0d: sync only %0d ones", k, max_run[k]); end
        // a block ends where the next sync or the file ends; without size the last one goes on
        if ((k < nb_check - 1 || nb_check < exp_len.size() || size != 0) ? n != exp_len[k] : n < exp_len[k]) begin
            errors++; $display("FAIL block %0d: %0d bytes, expected %0d", k, n, exp_len[k]);
        end
        for (int i = 0, e = 0; i < exp_len[k] && i < n; i++)
            if (got_data[got_start[k] + i] !== exp_data[exp_start[k] + i]) begin
                errors++; e++;
                if (e <= 4) $display("FAIL block %0d byte %0d: %02h expected %02h", k, i,
                                     got_data[got_start[k] + i], exp_data[exp_start[k] + i]);
            end
    end
    $write("silence %0d phases, %0d blocks decoded (sync / bytes):", first_rise / PHASE, got_start.size());
    for (int k = 0; k < got_start.size(); k++) $write(" %0d/%0d", max_run[k], got_len(k));
    $display("");
    if (errors == 0) $display("PASS tape_tb");
    else             $display("FAILED tape_tb: %0d errors", errors);
    $finish;
end

endmodule
