// tape (CAS player) + ddram: a CAS image in a DDR3 model is played and the cassette
// signal is decoded back (FSK 2400 Bd: "0" = one cycle, "1" = two cycles per bit;
// frame = start 0, 8 data bits LSB first, 2 stop bits 1).
// Checks: silence before the first block, sync of ones before each block, data bytes
// of each block exactly as in the image, pulse widths.
// Run: wsl.exe -- bash rtl/peripheral/tb/run_tape.sh [alt_tape.sv]
module tape_tb;

localparam int PHASE = 560;              // clk per phase with ce_5m3 = 1 (4 phases per bit)
localparam int LAT   = 7;                // DDR3 read latency in clk

logic clk = 0, reset = 1, rewind = 1;
always #1 clk = ~clk;

// ------------------------------------------------------------------ DUT + ddram
wire  [27:0] ram_a;
wire   [7:0] ram_di;
wire  [63:0] ram_di64;
wire         ram_rd, ram_ready, cas_out;

tape dut (
    .clk(clk), .ce_5m3(1'b1), .play(1'b1), .rewind(rewind), .enable(1'b1),
    .ram_a(ram_a), .ram_di(ram_di), .ram_di64(ram_di64), .ram_rd(ram_rd),
    .buff_mem_ready(ram_ready), .cas_out(cas_out)
);

logic  [7:0] DDRAM_BURSTCNT, DDRAM_BE;
logic [28:0] DDRAM_ADDR;
logic [63:0] DDRAM_DOUT, DDRAM_DIN;
logic        DDRAM_DOUT_READY = 0, DDRAM_RD, DDRAM_WE;

ddram ddr (
    .reset(reset), .DDRAM_CLK(clk), .DDRAM_BUSY(1'b0), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .addr(ram_a), .dout(ram_di), .din(8'h00), .we(1'b0), .rd(ram_rd), .ready(ram_ready),
    .dout64(ram_di64)
);

// ------------------------------------------------------------------ CAS image
localparam logic [27:0] BASE = MSX::DDR3_CAS;
byte image[$];
byte unsigned exp_block[2][$];

function automatic void put_header();
    byte sig[8] = '{8'h1F, 8'hA6, 8'hDE, 8'hBA, 8'hCC, 8'h13, 8'h7D, 8'h74};
    foreach (sig[i]) image.push_back(sig[i]);
endfunction

initial begin
    string name = "GAME  ";
    put_header();                                          // block 0: file header
    for (int i = 0; i < 10; i++) begin image.push_back(8'hD3); exp_block[0].push_back(8'hD3); end
    for (int i = 0; i < 6; i++)  begin image.push_back(name[i]); exp_block[0].push_back(name[i]); end
    put_header();                                          // block 1: 13 data bytes + 3 padding
    for (int i = 0; i < 13; i++) begin image.push_back(8'(i * 37 + 5)); exp_block[1].push_back(8'(i * 37 + 5)); end
    for (int i = 0; i < 3; i++)  begin image.push_back(8'h00); exp_block[1].push_back(8'h00); end
end

// DDR3 model: one 64-bit word per read, after LAT clk; outside the image 00
logic [28:0] rd_addr;
int          rd_wait = -1;
always_ff @(posedge clk) begin
    DDRAM_DOUT_READY <= 1'b0;
    if (DDRAM_RD) begin rd_addr <= DDRAM_ADDR; rd_wait <= LAT; end
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
int t = 0, t_rise = 0, t_fall = 0;
int first_rise = -1;
logic out_q = 0;
int half_ones = 0;                       // short high pulses (half of a "1")
int ones_run = 0;                        // consecutive "1" bits
int nblock = -1;                         // -1 before first sync
int max_run[2];
byte unsigned got[2][$];
int  fbit = -1;                          // -1 idle, 0..8 data, 9..10 stop
logic [7:0] fbyte;

task automatic bit_in(input logic b);
    ones_run = b ? ones_run + 1 : 0;
    // long run of ones outside a frame = sync of the next block
    if (ones_run == 50 && fbit < 0 && nblock < 1 && (nblock < 0 || got[nblock].size() > 0))
        nblock++;
    if (nblock >= 0 && ones_run > max_run[nblock]) max_run[nblock] = ones_run;
    if (nblock < 0) return;
    if (fbit < 0) begin
        if (!b) fbit = 0;                // start bit
    end else if (fbit < 8) begin
        fbyte[fbit] = b; fbit++;
    end else begin
        if (!b) begin errors++; if (errors <= 10) $display("FAIL stop bit 0 (block %0d, byte %0d)", nblock, got[nblock].size()); end
        if (fbit == 9) begin got[nblock].push_back(fbyte); fbit = -1; end
        else fbit++;
    end
endtask

always_ff @(posedge clk) begin
    t <= t + 1;
    out_q <= cas_out;
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
    repeat (10) @(posedge clk);
    reset = 0;
    repeat (10) @(posedge clk);
    rewind = 0;
    // wait for both blocks, block 1 data plus a margin
    while (!(nblock == 1 && got[1].size() >= exp_block[1].size() + 2) && t < 100_000_000) @(posedge clk);

    if (first_rise < 900 * PHASE) begin
        errors++; $display("FAIL no silence before the first block: first edge at %0d clk", first_rise);
    end
    for (int k = 0; k < 2; k++) begin
        int n = (k == 0) ? got[0].size() : exp_block[1].size();
        if (max_run[k] < 8000) begin errors++; $display("FAIL block %0d: sync only %0d ones", k, max_run[k]); end
        if (k == 0 && got[0].size() != exp_block[0].size()) begin
            errors++;
            $write("FAIL block 0: %0d bytes, expected %0d:", got[0].size(), exp_block[0].size());
            foreach (got[0][i]) $write(" %02h", got[0][i]);
            $display("");
        end
        for (int i = 0; i < exp_block[k].size() && i < got[k].size(); i++)
            if (got[k][i] !== exp_block[k][i]) begin
                errors++; $display("FAIL block %0d byte %0d: %02h expected %02h", k, i, got[k][i], exp_block[k][i]);
            end
        if (got[k].size() < exp_block[k].size()) begin errors++; $display("FAIL block %0d: only %0d bytes", k, got[k].size()); end
    end
    $display("silence %0d phases, sync %0d / %0d ones, bytes %0d / %0d",
             first_rise / PHASE, max_run[0], max_run[1], got[0].size(), got[1].size());
    if (errors == 0) $display("PASS tape_tb");
    else             $display("FAILED tape_tb: %0d errors", errors);
    $finish;
end

endmodule
