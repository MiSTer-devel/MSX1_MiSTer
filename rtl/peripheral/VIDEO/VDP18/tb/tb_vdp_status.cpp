// Status register flags of vdp18_core against the TI data manual (2.3.2, 2.3.3)
// and the Sord M5 (vdptest screen 19, 2026-09-27):
//   C  - checked while a pixel is generated, so never on the undisplayed
//        line 192 (HW: C = 0 there),
//   5S - lines 0 to 192, but only while the frame flag F is 0.
// M5 (vdptest 29, 30, 2026-09-27): no collision outside the picture on any
// side; with 5S = 0 the low bits hold the sprite where the scan stopped
// (the D0 entry, or 31), also in vertical blanking.
// Status is read through the CPU port, well inside vertical blanking.
#include "Vtb_vdp_frame.h"
#include <cstdio>
#include <cstdint>
#include <cstdarg>

static Vtb_vdp_frame* t;
static int fails = 0;

static void check(const char* name, bool ok, const char* fmt = "", ...) {
   char b[200] = "";
   va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
   printf("  %-48s %s %s\n", name, ok ? "OK  " : "FAIL ", b);
   if (!ok) fails++;
}

static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }

static void cpu_write(bool mode, uint8_t v) {
   t->mode = mode; t->cd_i = v; t->csw_n = 0;
   for (int i = 0; i < 4; i++) tick();
   t->csw_n = 1;
   for (int i = 0; i < 4; i++) tick();
}

static uint8_t status() {
   t->mode = 1; t->csr_n = 0;
   for (int i = 0; i < 4; i++) tick();
   uint8_t v = t->cd_o;
   t->csr_n = 1;
   for (int i = 0; i < 4; i++) tick();
   return v;
}

static void set_reg(int r, uint8_t v) { cpu_write(1, v); cpu_write(1, 0x80 | r); }

static void poke(uint16_t a, uint8_t d) {
   t->poke = 1; t->poke_a = a; t->poke_d = d; tick();
   t->poke = 0;
}

// Three lines after the end of the active area (line 192 already done).
static void late_vblank() {
   while (t->vblank) tick();
   while (!t->vblank) tick();
   for (int i = 0; i < 3 * 342 * 4; i++) tick();
}

static const uint16_t SAT = 0x1B00;

// sprites: {Y, X} pairs, list ends with Y = D0
static void sprites(const uint8_t (*s)[2], int n) {
   for (int i = 0; i < n; i++) {
      poke(SAT + i * 4 + 0, s[i][0]);
      poke(SAT + i * 4 + 1, s[i][1]);
      poke(SAT + i * 4 + 2, 0);
      poke(SAT + i * 4 + 3, 15);
   }
   poke(SAT + n * 4, 0xD0);
}

// sprites with pattern and colour: {Y, X, pattern, colour}
static void sprites4(const uint8_t (*s)[4], int n, bool terminate = true) {
   for (int i = 0; i < n; i++)
      for (int k = 0; k < 4; k++) poke(SAT + i * 4 + k, s[i][k]);
   if (terminate) poke(SAT + n * 4, 0xD0);
}

static uint8_t frame_status() {
   late_vblank(); status();
   late_vblank();
   return status();
}

static void setup() {
   t->border = 0; t->pal = 0;
   t->reset_n = 0;
   for (int i = 0; i < 20; i++) tick();
   t->reset_n = 1;
   for (int i = 0; i < 20; i++) tick();
   for (int a = 0; a < 0x4000; a++) poke(a, 0);
   for (int i = 0; i < 8; i++) poke(0x3800 + i, 0xFF);   // sprite pattern 0: solid
   for (int i = 0; i < 8; i++) poke(0x3810 + i, 0x0F);   // 2: right half
   for (int i = 0; i < 8; i++) poke(0x3818 + i, 0xF0);   // 3: left half
   poke(SAT, 0xD0);
   // Graphic I, 8x8 sprites, SAT 1B00h, sprite patterns 3800h
   const uint8_t r[8] = {0x00, 0xC0, 0x06, 0x80, 0x00, 0x36, 0x07, 0x01};
   for (int i = 0; i < 8; i++) set_reg(i, r[i]);
   late_vblank();
   status();
}

int main(int argc, char** argv) {
   Verilated::commandArgs(argc, argv);
   setvbuf(stdout, nullptr, _IONBF, 0);
   t = new Vtb_vdp_frame;
   t->csr_n = 1; t->csw_n = 1; t->mode = 0; t->poke = 0;
   setup();

   printf("=== Kolize (C) ===\n");
   {
      const uint8_t s[][2] = {{0x5F, 100}, {0x5F, 104}};      // overlap on line 96
      sprites(s, 2);
      late_vblank(); status();
      late_vblank();
      uint8_t st = status();
      check("prekryv na viditelnem radku 96: C=1", st & 0x20, "(status %02X)", st);
   }
   {
      const uint8_t s[][2] = {{0xBF, 100}, {0xBF, 104}};      // overlap on line 192 only
      sprites(s, 2);
      late_vblank(); status();
      late_vblank();
      uint8_t st = status();
      check("prekryv jen na radku 192: C=0 (jako HW)", !(st & 0x20), "(status %02X)", st);
   }

   {
      const uint8_t s[][4] = {{0x5F, 252, 2, 15}, {0x5F, 253, 2, 15}};   // x 257-259
      sprites4(s, 2);
      uint8_t st = frame_status();
      check("prekryv jen vpravo za pixelem 255: C=0 (HW)", !(st & 0x20), "(status %02X)", st);
   }
   {
      const uint8_t s[][4] = {{0x5F, 24, 3, 0x8F}, {0x5F, 26, 3, 0x8F}}; // EC: x -6..-5
      sprites4(s, 2);
      uint8_t st = frame_status();
      check("prekryv jen vlevo (early clock): C=0 (HW)", !(st & 0x20), "(status %02X)", st);
   }
   {
      const uint8_t s[][4] = {{0xF7, 100, 0, 15}, {0xF7, 104, 0, 15}};  // lines -8..-1
      sprites4(s, 2);
      uint8_t st = frame_status();
      check("prekryv jen nad radkem 0: C=0 (HW)", !(st & 0x20), "(status %02X)", st);
   }

   printf("\n=== Cislo spritu pri 5S=0 (HW: kde skoncilo prohledavani) ===\n");
   {
      const uint8_t one[][4] = {{0x5F, 100, 0, 15}};
      sprites4(one, 1);
      uint8_t st = frame_status();
      check("1 sprite, D0 na indexu 1: N=01", (st & 0x5F) == 0x01, "(status %02X)", st);
      const uint8_t four4[][4] = {{0x5F, 20, 0, 15}, {0x5F, 60, 0, 15},
                                  {0x5F, 100, 0, 15}, {0x5F, 140, 0, 15}};
      sprites4(four4, 4);
      st = frame_status();
      check("4 sprity na radku, D0 na indexu 4: N=04", (st & 0x5F) == 0x04, "(status %02X)", st);
      uint8_t all[32][4];
      for (int i = 0; i < 32; i++) {
         all[i][0] = (uint8_t)(8 + i * 5); all[i][1] = (uint8_t)(i * 7);
         all[i][2] = 0; all[i][3] = 15;
      }
      sprites4(all, 32, false);
      st = frame_status();
      check("32 spritu bez D0: N=1F", (st & 0x5F) == 0x1F, "(status %02X)", st);
      sprites4(one, 0);
      st = frame_status();
      check("zadny sprite (D0 na indexu 0): N=00", (st & 0x5F) == 0x00, "(status %02X)", st);
   }

   printf("\n=== Paty sprite (5S) jen pri F=0 ===\n");
   const uint8_t four[][2] = {{0x5F, 20}, {0x5F, 50}, {0x5F, 80}, {0x5F, 110}, {0x2F, 140}};
   {
      sprites(four, 5);
      late_vblank(); status();                                // F cleared
      poke(SAT + 4 * 4, 0x5F);                                // 5th sprite joins line 96
      late_vblank();
      uint8_t st = status();
      check("F smazane pred radkem 96: 5S=1, N=4",
            (st & 0x40) && (st & 0x1F) == 4, "(status %02X)", st);
   }
   {
      sprites(four, 5);
      late_vblank(); status();                                // F cleared
      late_vblank();                                          // F set, not read
      poke(SAT + 4 * 4, 0x5F);
      late_vblank();
      uint8_t st = status();
      check("F nastavene po celou dobu: 5S=0", (st & 0x80) && !(st & 0x40), "(status %02X)", st);
   }

   printf("\n=== Obrazovka 19: 5 spritu na radku 192 (Y=BF) ===\n");
   {
      const uint8_t s[][2] = {{0xBF, 100}, {0xBF, 104}, {0xBF, 20}, {0xBF, 50}, {0xBF, 150}};
      sprites(s, 5);
      late_vblank(); status();
      late_vblank();
      uint8_t st = status();
      check("C=0 (jako HW)", !(st & 0x20), "(status %02X)", st);
      printf("  info: 5S=%d N=%02X pri cteni az ve vblank (HW s tesnou smyckou: vetsinou 5S=1 N=04)\n",
             !!(st & 0x40), st & 0x1F);
   }

   printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
   delete t;
   return fails ? 1 : 0;
}
