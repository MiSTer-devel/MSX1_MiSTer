// TV80a interrupt acknowledge and bus timing against the Z80 specification (Zilog).
// Taken from the Sord M5 core (doc/sordm5-opravy.md, Z1-Z5).
//
// For IM0, IM1 and IM2 the same program runs:
//   main loop OUT (10h),A / INC A / IN A,(20h) / OUT (11h),A / JR
//   the handler writes a marker into RAM (LD (HL),n / INC HL) and ends EI / RETI
// and the checks are:
//   1. at the end of the acknowledge IORQ does not rise later than M1 (Zilog peripherals
//      without a WR pin - CTC, PIO, SIO - take IORQ with RD high as a write),
//   2. the right handler runs (markers in RAM in the right order),
//   3. acknowledge length as Zilog, without jitter: IM0 (RST) 13, IM1 13, IM2 19 T
//      (M1 of 5 T with two wait states, PC pushed in 3 + 3 T, IM2 vector read 3 + 3 T),
//   4. the loop with I/O takes 49 T (11 + 4 + 11 + 11 + 12),
//   5. every OUT (11h) sends the value of the IN before,
//   6. I/O: IORQ falls together with RD (IN) and WR (OUT), as on the Z80,
//   7. NMI: response 11 T (M1 5 T without wait states + 3 + 3).
#include "Vtb_tv80.h"
#include <cstdio>
#include <cstdint>
#include <vector>

static Vtb_tv80* t;
static long clk = 0;
static int  fails = 0;

static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); ++clk; }

static void check(const char* name, bool ok, const char* detail = "") {
    printf("  %-62s %s %s\n", name, ok ? "OK  " : "FAIL", detail);
    if (!ok) fails++;
}

struct Mode {
    const char* name;
    uint8_t     im_opcode;              // second byte of ED xx
    std::vector<uint8_t> vectors;       // bus value at the acknowledge
    std::vector<uint8_t> markers;       // expected markers in RAM, in order
    int         expect_t;               // T from the acknowledge to the handler's first opcode
};

static void load_program(uint8_t im_opcode) {
    uint8_t rom[256] = {};
    auto put = [&](int a, std::initializer_list<uint8_t> b) { for (uint8_t x : b) rom[a++] = x; };
    put(0x00, {0xF3});                    // DI
    put(0x01, {0x31, 0x00, 0x81});        // LD SP,8100h
    put(0x04, {0xED, im_opcode});         // IM n
    put(0x06, {0x3E, 0x00});              // LD A,0
    put(0x08, {0xED, 0x47});              // LD I,A
    put(0x0A, {0x21, 0x00, 0x80});        // LD HL,8000h
    put(0x0D, {0xFB});                    // EI
    put(0x0E, {0xD3, 0x10});              // loop: OUT (10h),A
    put(0x10, {0x3C});                    // INC A
    put(0x11, {0xDB, 0x20});              // IN A,(20h)
    put(0x13, {0xD3, 0x11});              // OUT (11h),A
    put(0x15, {0x18, 0xF7});              // JR loop
    put(0x28, {0x36, 0xC0, 0x23, 0xFB, 0xED, 0x4D});   // IM0: RST 28h
    put(0x38, {0x36, 0xB1, 0x23, 0xFB, 0xED, 0x4D});   // IM1: RST 38h
    put(0x60, {0x70, 0x00, 0x78, 0x00, 0x80, 0x00});   // IM2 vector table
    put(0x70, {0x36, 0xA0, 0x23, 0xFB, 0xED, 0x4D});
    put(0x78, {0x36, 0xA1, 0x23, 0xFB, 0xED, 0x4D});
    put(0x80, {0x36, 0xA2, 0x23, 0xFB, 0xED, 0x4D});
    put(0x66, {0xED, 0x45});                           // NMI: RETN
    for (int a = 0; a < 256; a++) {
        t->rom_we = 1; t->rom_a = a; t->rom_d = rom[a]; tick();
    }
    t->rom_we = 0;
}

static void run_mode(const Mode& m) {
    printf("\n=== %s ===\n", m.name);
    t->int_n = 1; t->nmi_n = 1; t->vec = 0xFF; t->io_rd_val = 0x40;
    t->rst_n = 0;
    load_program(m.im_opcode);
    for (int i = 0; i < 60; i++) tick();
    t->rst_n = 1;

    const int N_INT = 24;
    int  ints_raised = 0, acks = 0;
    long next_int = 6000;

    bool p_m1 = true, p_iorq = true, p_fetch = false;
    long m1_fall = 0;

    bool in_inta = false;                 // 1. clocks with M1 high and IORQ still low
    int  tail_clk = 0, tail_worst = 0;

    long inta_start = -1;                 // 3. acknowledge length
    std::vector<int> lat;

    long last_loop = -1; bool int_since_loop = false;   // 4. loop period
    std::vector<int> loop_t;

    int  last_in = -1, out11 = 0, out11_bad = 0, ins = 0;   // 5. I/O data
    bool io_write_seen = false, io_read_seen = false; uint8_t io_port = 0, io_data = 0;

    long io_start = -1; int io_lead = 0, io_kind = 0, in_lead = 0, out_lead = 0;   // 6.

    for (long i = 0; i < 200000; i++) {
        // interrupt controller: raises INT and holds it until the acknowledge
        if (ints_raised < N_INT && t->int_n && clk >= next_int) {
            t->int_n = 0;
            t->vec = m.vectors[ints_raised % m.vectors.size()];
            ints_raised++;
        }

        tick();
        bool m1 = !t->m1_n, iorq = !t->iorq_n, wr = !t->wr_n, rd = !t->rd_n, mreq = !t->mreq_n;

        if (m1 && !p_m1) m1_fall = clk;

        if (m1 && iorq && !in_inta) {                   // acknowledge
            in_inta = true; tail_clk = 0;
            inta_start = m1_fall;
            acks++;
            t->int_n = 1;
            next_int = clk + 3000;
            int_since_loop = true;
        }
        if (in_inta) {
            if (!m1 && iorq) tail_clk++;
            if (!iorq) {
                if (tail_clk > tail_worst) tail_worst = tail_clk;
                in_inta = false;
            }
        }

        bool fetch = m1 && mreq && rd;                  // opcode fetch
        if (fetch && !p_fetch) {
            if (inta_start >= 0 && !in_inta) {
                lat.push_back((int)((m1_fall - inta_start) / 6));
                inta_start = -1;
            }
            if (t->addr == 0x000E) {
                if (last_loop >= 0 && !int_since_loop) loop_t.push_back((int)((m1_fall - last_loop) / 6));
                last_loop = m1_fall; int_since_loop = false;
            }
        }
        p_fetch = fetch;

        // 6. IORQ must fall together with RD (IN) / WR (OUT), both on the rising edge of T2
        if (!m1 && iorq && !p_iorq) { io_start = clk; io_lead = 0; io_kind = 0; }
        if (!m1 && iorq && io_start >= 0) {
            if (!rd && !wr && io_kind == 0) io_lead++;
            if (rd && io_kind == 0) { io_kind = 1; if (io_lead > in_lead) in_lead = io_lead; }
            if (wr && io_kind == 0) { io_kind = 2; if (io_lead > out_lead) out_lead = io_lead; }
        }

        if (!m1 && iorq && wr) { io_write_seen = true; io_port = t->addr & 0xFF; io_data = t->dout; }
        if (!m1 && iorq && rd) io_read_seen = true;
        if (!iorq && p_iorq) {                          // end of an I/O cycle
            if (io_write_seen && io_port == 0x11) {
                out11++;
                if (io_data != last_in) out11_bad++;
            }
            if (io_read_seen) { last_in = t->io_rd_val; ins++; t->io_rd_val = (uint8_t)(t->io_rd_val + 7); }
            io_write_seen = io_read_seen = false;
        }

        p_m1 = m1; p_iorq = iorq;
    }

    int marker_bad = 0;
    for (int k = 0; k < acks; k++) {
        t->ram_a = k; t->eval();
        if (t->ram_q != m.markers[k % m.markers.size()]) marker_bad++;
    }

    char b[128];
    snprintf(b, sizeof b, "(%d acknowledges, IORQ after M1 at most %d clk)", acks, tail_worst);
    check("1. end of acknowledge: IORQ does not rise after M1", acks > 0 && tail_worst == 0, b);
    snprintf(b, sizeof b, "(%d markers, %d wrong)", acks, marker_bad);
    check("2. the right handler runs (markers in RAM)", acks == N_INT && marker_bad == 0, b);

    int lat_min = 1 << 30, lat_max = -1;
    for (int v : lat) { if (v < lat_min) lat_min = v; if (v > lat_max) lat_max = v; }
    snprintf(b, sizeof b, "(%d..%d T, Zilog %d T, %zu acknowledges)", lat_min, lat_max, m.expect_t, lat.size());
    check("3. acknowledge length as Zilog, no jitter", !lat.empty() &&
          lat_min == m.expect_t && lat_max == m.expect_t, b);

    int lp_min = 1 << 30, lp_max = -1;
    for (int v : loop_t) { if (v < lp_min) lp_min = v; if (v > lp_max) lp_max = v; }
    snprintf(b, sizeof b, "(%d..%d T, expected 49 T, %zu loops)", lp_min, lp_max, loop_t.size());
    check("4. loop OUT/INC/IN/OUT/JR = 49 T", !loop_t.empty() && lp_min == 49 && lp_max == 49, b);

    snprintf(b, sizeof b, "(OUT %d, %d wrong, IN %d)", out11, out11_bad, ins);
    check("5. OUT (11h) sends the value of the IN before", out11 > 100 && out11_bad == 0, b);

    snprintf(b, sizeof b, "(IORQ before RD at most %d, before WR at most %d clk)", in_lead, out_lead);
    check("6. I/O: IORQ falls together with RD (IN) and WR (OUT)", ins > 100 && in_lead == 0 && out_lead == 0, b);
}

static void run_nmi() {
    printf("\n=== NMI ===\n");
    t->int_n = 1; t->nmi_n = 1; t->vec = 0xFF; t->io_rd_val = 0x40;
    t->rst_n = 0;
    load_program(0x56);                      // IM1, does not matter for NMI
    for (int i = 0; i < 60; i++) tick();
    t->rst_n = 1;

    std::vector<int> lat;
    long nmi_start = -1, m1_fall = 0, next_nmi = clk + 6000, nmi_fall = 0;
    int  nmis = 0;
    bool p_m1 = true, p_fetch = false;

    for (long i = 0; i < 120000; i++) {
        if (nmis < 12 && t->nmi_n && clk >= next_nmi) { t->nmi_n = 0; nmi_fall = clk; nmis++; }
        if (!t->nmi_n && clk >= nmi_fall + 60) { t->nmi_n = 1; next_nmi = clk + 4000; }
        tick();
        bool m1 = !t->m1_n, rd = !t->rd_n, mreq = !t->mreq_n;
        if (m1 && !p_m1) m1_fall = clk;
        p_m1 = m1;

        bool fetch = m1 && mreq && rd;
        if (fetch && !p_fetch) {
            if (t->nmicycle) nmi_start = m1_fall;            // NMI acknowledge M1
            else if (nmi_start >= 0 && t->addr == 0x0066) {
                lat.push_back((int)((m1_fall - nmi_start) / 6));
                nmi_start = -1;
            }
        }
        p_fetch = fetch;
    }

    int mn = 1 << 30, mx = -1;
    for (int v : lat) { if (v < mn) mn = v; if (v > mx) mx = v; }
    char b[128];
    snprintf(b, sizeof b, "(%d..%d T, Zilog 11 T, %zu acknowledges)", mn, mx, lat.size());
    check("7. NMI: response 11 T as Zilog", !lat.empty() && mn == 11 && mx == 11, b);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    setvbuf(stdout, nullptr, _IONBF, 0);
    t = new Vtb_tv80;
    t->clk = 0; t->eval();      // the first eval only initialises, it would miss the edge

    // IM0: the controller puts RST 28h (EF), IM1: bus FF (ignored),
    // IM2: vectors 60h/62h/64h -> handlers A0/A1/A2
    run_mode({"IM0 (vector = RST 28h)", 0x46, {0xEF},             {0xC0},             13});
    run_mode({"IM1",                    0x56, {0xFF},             {0xB1},             13});
    run_mode({"IM2",                    0x5E, {0x60, 0x62, 0x64}, {0xA0, 0xA1, 0xA2}, 19});
    run_nmi();

    printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
    delete t;
    return fails ? 1 : 0;
}
