// /WAIT on TV80 against the Z80 rule, from the Sord M5 core where the rule was checked with a
// logic analyzer (doc/sordm5-opravy.md, Z6). Loop: INC HL, LD A,(nn), OR A,
// JR = 35 T. /WAIT of a given length starts at every phase of the loop
// (35 T x 6 clk_sys), loss = how much later the loop gets back.
//
// Z80 rule: /WAIT is sampled on the falling CLK edge in T2 (and in each Tw);
// the cycle goes on after the first sample that sees it high.
// HW (M5): /WAIT 2.448 us = 8.76 T, loss 6.09 T on average.
//
//   tb [wait_clk] [io]   /WAIT length in clk_sys (default 53 = 8.83 T); io = loop with IN (46 T)
#include "Vtb_wait.h"
#include <verilated.h>
#include <cstdio>
#include <cstdlib>
#include <cmath>

static Vtb_wait* t;
static long clk_n = 0;
static int fails = 0;

static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); clk_n++; }

// Z80 rule: sampling points (T from the M1 fall of INC HL) = middle of T2.
// I/O cycle: only in TW* (T1 13, T2 14, TW* 15 -> 15.5), not in T2.
static bool io_mode = false;
static double z80_loss(double a, double w) {
   static const double S[8] = {1.5, 7.5, 11.5, 14.5, 17.5, 20.5, 24.5, 28.5};
   static const double SI[11] = {1.5, 7.5, 11.5, 15.5, 18.5, 22.5, 25.5, 28.5, 31.5, 35.5, 39.5};
   const double* s0 = io_mode ? SI : S;
   const int ns = io_mode ? 11 : 8;
   const double per = io_mode ? 46.0 : 35.0;
   double b = a + w;
   for (int k = 0; k < 3; k++)
      for (int i = 0; i < ns; i++) {
         double s = s0[i] + per * k;
         if (s >= a && s < b) return std::ceil(b - s);
      }
   return 0;
}

static void check(const char* name, bool ok, const char* detail = "") {
   printf("%-58s %s %s\n", name, ok ? "OK  " : "FAIL ", detail);
   if (!ok) fails++;
}

// Next M1 fall of INC HL (address 0003).
static long next_loop() {
   bool pm1 = t->m1_n;
   for (;;) {
      tick();
      if (!t->m1_n && pm1 && t->addr == 0x0003) return clk_n;
      pm1 = t->m1_n;
   }
}

int main(int argc, char** argv) {
   Verilated::commandArgs(argc, argv);
   const int W = argc > 1 ? atoi(argv[1]) : 53;
   io_mode = argc > 2 && argv[2][0] == 'i';
   const int PER = io_mode ? 46 : 35;
   t = new Vtb_wait;
   t->io_loop = io_mode;
   t->wait_n = 1; t->rst_n = 0;
   for (int i = 0; i < 60; i++) tick();
   t->rst_n = 1;
   for (int i = 0; i < 5; i++) next_loop();

   double tv_sum = 0, z_sum = 0, worst = 0;
   int n = 0, diff_n = 0;
   printf("phase(T) TV80  Z80\n");
   for (int off = 0; off < PER * 6; off++) {
      long s = next_loop();
      // /WAIT from s + off for W clk_sys
      while (clk_n < s + off) tick();
      t->wait_n = 0;
      long end = clk_n + W;
      bool pm1 = t->m1_n;
      long l = -1;
      int loops = 0;
      while (loops < 4) {
         if (clk_n == end) t->wait_n = 1;
         tick();
         if (!t->m1_n && pm1 && t->addr == 0x0003) { loops++; l = clk_n; }
         pm1 = t->m1_n;
      }
      double tv = (l - s - loops * PER * 6) / 6.0;
      // M1 falls one clk_sys after CE_p; phase in T from that fall
      double z = z80_loss((off + 1) / 6.0, W / 6.0);   // wait_n set before the edge off+1
      tv_sum += tv; z_sum += z; n++;
      if (std::fabs(tv - z) > 0.01) {
         diff_n++;
         if (std::fabs(tv - z) > worst) worst = std::fabs(tv - z);
         if (diff_n <= 80) printf("  %5.2f  %4.1f  %4.1f\n", off / 6.0, tv, z);
      }
   }
   printf("/WAIT %d clk_sys = %.2f T\n", W, W / 6.0);
   printf("average loss: TV80 %.2f T, Z80 rule %.2f T (M5 HW at 8.76 T: 6.09)\n", tv_sum / n, z_sum / n);
   char d[64]; snprintf(d, sizeof d, "(%d of %d phases, worst %.1f T)", diff_n, n, worst);
   if (io_mode) printf("loop with IN A,(30h), 46 T\n");
   check("TV80 = Z80 rule in all phases", diff_n == 0, d);
   printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
   delete t;
   return fails ? 1 : 0;
}
