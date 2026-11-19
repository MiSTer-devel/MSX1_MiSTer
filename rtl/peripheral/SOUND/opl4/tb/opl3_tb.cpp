// opl3.sv against Nuked OPL3 (tb/nuked): the same register writes go to both, every sample
// of channels A and B must be equal. Then the timers and the status register.
//   Vopl3 [seed [random samples]]

#include "Vopl3.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <vector>
extern "C" {
#include "opl3.h"
}

static Vopl3   *dut;
static opl3_chip ref;
static bool      newm = false;
static long      nsample = 0, nfail = 0;
static uint32_t  rng = 1;
struct wr_t { long smp; int reg, val; };
static std::vector<wr_t> hist;

static uint32_t rnd() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }

static void clk() { dut->clk = 0; dut->eval(); dut->clk = 1; dut->eval(); }

static void wr(int reg, int val, bool to_ref = true) {
    dut->wr = 1; dut->wr_addr = reg; dut->wr_data = val;
    clk();
    dut->wr = 0;
    if (to_ref) {
        int r = (!newm && reg != 0x105) ? reg & 0xFF : reg;         // OPL2 mode: one register array
        OPL3_WriteReg(&ref, r, val);
        if (r == 0x105) newm = val & 1;
        // The reference takes the note select bit into the key scale value only at the next
        // frequency write; the chip logic (and opl3.sv) uses the bit as it is.
        if (r == 0x008)
            for (int c = 0; c < 18; c++)
                ref.channel[c].ksv = ref.channel[c].block << 1 | ((ref.channel[c].f_num >> (9 - ref.nts)) & 1);
    }
    hist.push_back({nsample, reg, val});
}

static void fail(const char *what, int got, int exp) {
    if (nfail < 10) {
        printf("FAIL sample %ld %s: %d, reference %d; last writes:", nsample, what, got, exp);
        for (size_t i = hist.size() > 12 ? hist.size() - 12 : 0; i < hist.size(); i++)
            printf(" [%ld] %03X=%02X", hist[i].smp, hist[i].reg, hist[i].val);
        printf("\n");
    }
    nfail++;
}

static void sample() {
    int16_t buf[4];
    OPL3_Generate4Ch(&ref, buf);
    dut->smp_tick = 1; clk(); dut->smp_tick = 0;
    bool seen = false;
    for (int i = 0; i < 220; i++) {
        clk();
        if (dut->out_valid) {
            seen = true;
            if ((int16_t)dut->out_a != buf[0]) fail("A", (int16_t)dut->out_a, buf[0]);
            if ((int16_t)dut->out_b != buf[1]) fail("B", (int16_t)dut->out_b, buf[1]);
        }
    }
    if (!seen) fail("no out_valid", 0, 1);
    nsample++;
}

static void run(int n) { for (int i = 0; i < n; i++) sample(); }

static void start() {
    dut->reset = 1; for (int i = 0; i < 4; i++) clk();
    dut->reset = 0; for (int i = 0; i < 600; i++) clk();
    if (!dut->ready) fail("not ready", 0, 1);
    OPL3_Reset(&ref, 49716);
    newm = false;
}

// operator registers of operator op (0..17) in array a
static void op(int a, int o, int r20, int r40, int r60, int r80, int re0) {
    static const int off[18] = {0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13, 16, 17, 18, 19, 20, 21};
    int b = a << 8 | off[o];
    wr(b + 0x20, r20); wr(b + 0x40, r40); wr(b + 0x60, r60); wr(b + 0x80, r80); wr(b + 0xE0, re0);
}

static void directed() {
    start();
    run(8);
    // 2 operator tones, every waveform, FM and additive, vibrato / tremolo, feedback
    wr(0x105, 1);
    for (int w = 0; w < 8; w++) {
        op(0, 0, 0xE1, 0x10 + w, 0xF4, 0x25, w);
        op(0, 3, 0x61, 0x00, 0xF3, 0x36, 7 - w);
        wr(0x0C0, 0x30 | (w & 1) | ((w & 7) << 1));
        wr(0x0A0, 0x41 + 37 * w); wr(0x0B0, 0x20 | ((w & 7) << 2) | (w & 3));
        run(400);
        wr(0x0B0, (w & 7) << 2 | (w & 3));
        run(300);
    }
    // deep vibrato / tremolo, note select, key scaling
    wr(0x0BD, 0xC0); wr(0x008, 0x40);
    op(1, 4, 0xF2, 0xC8, 0x62, 0x74, 0);
    op(1, 7, 0xD1, 0x43, 0x83, 0x55, 1);
    wr(0x1C4, 0x2E); wr(0x1A4, 0xFF); wr(0x1B4, 0x33);
    run(3000);
    wr(0x1B4, 0x13); run(1500);
    // 4 operator channels, all four connections, in both arrays
    for (int c = 0; c < 4; c++) {
        wr(0x104, 0x3F);
        for (int a = 0; a < 2; a++) {
            op(a, 0, 0x21, 0x20, 0xF2, 0x33, 0); op(a, 3, 0x22, 0x18, 0xE3, 0x44, 1);
            op(a, 6, 0x23, 0x10, 0xD4, 0x55, 2); op(a, 9, 0x21, 0x00, 0xC5, 0x66, 3);
            wr(a << 8 | 0xC0, 0x10 | (c >> 1) | 0x06); wr(a << 8 | 0xC3, 0x20 | (c & 1));
            wr(a << 8 | 0xA0, 0x80 + 16 * c); wr(a << 8 | 0xB0, 0x2D + a);
            wr(a << 8 | 0xA3, 0x12); wr(a << 8 | 0xB3, 0x21);      // second channel: ignored
        }
        run(1200);
        wr(0x0B0, 0x0D); wr(0x1B0, 0x0E);
        run(600);
        wr(0x104, c);                                              // back to 2 operator channels
        run(100);
    }
    // rhythm: all five instruments, alone and together
    wr(0x104, 0x00);
    for (int o = 12; o < 18; o++) op(0, o, 0x01 + o, 0x05, 0xF6, 0x47, o & 3);
    wr(0x0A6, 0x20); wr(0x0B6, 0x09); wr(0x0C6, 0x38);
    wr(0x0A7, 0x80); wr(0x0B7, 0x0D); wr(0x0C7, 0x30);
    wr(0x0A8, 0x57); wr(0x0B8, 0x0A); wr(0x0C8, 0x31);
    for (int d = 0; d < 6; d++) {
        wr(0x0BD, 0x20 | (d < 5 ? 1 << d : 0x1F)); run(900);
        wr(0x0BD, 0x20); run(300);
    }
    wr(0x0BD, 0x00); run(200);
    // envelope rates: slow rates run long enough to step
    for (int r = 1; r < 16; r += 3) {
        op(0, 1, 0x00 | (r & 1) << 4, 0x00, r << 4 | r, 0x50 | r, 0);
        op(0, 4, 0x20, 0x00, r << 4 | (15 - r), 0xF0 | r, 0);
        wr(0x0C1, 0x31); wr(0x0A1, 0x99); wr(0x0B1, 0x20 | r << 1);
        run(r < 6 ? 30000 : 4000);
        wr(0x0B1, r << 1); run(r < 6 ? 8000 : 2000);
    }
}

static void random_run(int n) {
    static const int grp[10] = {0x20, 0x40, 0x60, 0x80, 0xE0, 0xA0, 0xB0, 0xC0, 0xA0, 0xB0};
    start();
    for (int i = 0; i < n; i++) {
        int k = (rnd() % 100 < 20) ? 1 + rnd() % 4 : 0;
        if (rnd() % 3000 == 0) k = 40;                             // a burst: new patch
        for (int j = 0; j < k; j++) {
            int t = rnd() % 100, reg, val = rnd() & 0xFF;
            if (t < 80) {
                int g = grp[rnd() % 10];
                reg = (rnd() & 1) << 8 | g | (g < 0xA0 || g == 0xE0 ? rnd() % 0x20 : rnd() % 0x10);
                if (g == 0x60 && (rnd() & 1)) val |= 0xC0;         // audible more often
                if (g == 0x40 && (rnd() & 1)) val &= 0xCF;
                if (g == 0xB0 && (rnd() & 3)) val |= 0x20;
            } else if (t < 84) reg = 0x0BD;
            else if (t < 87) { reg = 0x104; if (rnd() & 1) val = 0; }
            else if (t < 90) { reg = 0x105; if (rnd() % 4) val |= 1; }
            else if (t < 92) reg = 0x008;
            else reg = rnd() & 0x1FF;
            if ((reg & 0xFF) >= 2 && (reg & 0xFF) <= 4) continue;  // timers: not in the reference
            wr(reg, val);
        }
        sample();
    }
}

static int status() { return dut->status; }

// timers: period (256 - value) * 4 / * 16 samples, flags, mask and IRQ
static void timers() {
    start();
    auto wrt = [](int reg, int val) { wr(reg, val, false); };
    auto until = [](int mask, int limit) { int n = 0; while (!(status() & mask) && n < limit) { sample(); n++; } return n; };
    wrt(0x002, 0xF0); wrt(0x003, 0xFE); wrt(0x004, 0x80);
    wrt(0x004, 0x01);
    int n = until(0x40, 200);
    if (n != 64 || status() != 0xC0) fail("timer 1 period / status", n << 8 | status(), 64 << 8 | 0xC0);
    wrt(0x004, 0x80);
    if (status() != 0x00) fail("flag reset", status(), 0);
    n = until(0x40, 200);
    if (n != 64) fail("timer 1 reload", n, 64);
    wrt(0x004, 0x42);                                              // timer 1 masked and stopped, timer 2
    if (status() != 0x00) fail("masked flag dropped", status(), 0);
    n = until(0x20, 200);
    if (n != 32 || status() != 0xA0) fail("timer 2 period / status", n << 8 | status(), 32 << 8 | 0xA0);
    wrt(0x004, 0x80); wrt(0x004, 0x61);                            // both masked, timer 1 runs
    n = until(0x40, 200);
    if (n != 64 || status() != 0x40) fail("masked timer: flag without IRQ", n << 8 | status(), 64 << 8 | 0x40);
    wrt(0x004, 0x21);                                              // unmasking with the flag set
    if (status() != 0xC0) fail("IRQ after unmask", status(), 0xC0);
    wrt(0x004, 0x80); wrt(0x004, 0x00);
    wrt(0x105, 0x03);
    if (!dut->newm || !dut->new2) fail("NEW / NEW2", dut->newm << 1 | dut->new2, 3);
    // read back: value written, OPL2 mode maps array 1 to array 0
    wrt(0x0A3, 0x5A); wrt(0x1A3, 0xA5); wrt(0x105, 0x00); wrt(0x1A3, 0x3C);
    dut->rd_addr = 0x0A3; clk(); clk();
    if (dut->rd_data != 0x3C) fail("read back 0A3", dut->rd_data, 0x3C);
    dut->rd_addr = 0x1A3; clk(); clk();
    if (dut->rd_data != 0xA5) fail("read back 1A3", dut->rd_data, 0xA5);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    int seed = argc > 1 ? atoi(argv[1]) : 1;
    int n    = argc > 2 ? atoi(argv[2]) : 300000;
    dut = new Vopl3;
    dut->wr = 0; dut->smp_tick = 0; dut->rd_addr = 0;
    directed();
    printf("directed: %ld samples, %ld differences\n", nsample, nfail);
    long f0 = nfail, s0 = nsample;
    rng = seed * 2654435761u + 1;
    random_run(n);
    printf("random (seed %d): %ld samples, %ld differences\n", seed, nsample - s0, nfail - f0);
    f0 = nfail;
    timers();
    printf("timers, status, read back: %ld failures\n", nfail - f0);
    printf(nfail ? "FAILED opl3_tb: %ld\n" : "PASS opl3_tb\n", nfail);
    delete dut;
    return nfail ? 1 : 0;
}
