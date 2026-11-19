// Vertical frame timing of vdp18_core measured on its outputs (border shown):
// each line between two hsync edges is classified as vsync, blanking, border
// or active (white picture on a magenta backdrop), then one frame is
// run-length encoded starting at vsync.
//
// Expected, TI data manual: table 3-3 (NTSC) and section 5.5 TMS9929A
// (3 front blanking, 3 sync, 13 back blanking, 294 active + border lines);
// PAL top border 51 from MAME (VERT_DISPLAY_START_PAL = 13 + 51).
#include "Vtb_vdp_frame.h"
#include <cstdio>
#include <cstdint>
#include <string>
#include <vector>

static Vtb_vdp_frame* t;
static int fails = 0;

static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }

static void cpu_write(bool mode, uint8_t v) {
   t->mode = mode; t->cd_i = v; t->csw_n = 0;
   for (int i = 0; i < 4; i++) tick();
   t->csw_n = 1;
   for (int i = 0; i < 4; i++) tick();
}

static void set_reg(int r, uint8_t v) { cpu_write(1, v); cpu_write(1, 0x80 | r); }

static void poke(uint16_t a, uint8_t d) {
   t->poke = 1; t->poke_a = a; t->poke_d = d; tick();
   t->poke = 0;
}

// Graphic I, every cell = char 0 = solid white, backdrop magenta, no sprites.
static void setup(bool pal) {
   t->pal = pal; t->border = 1;
   t->reset_n = 0;
   for (int i = 0; i < 20; i++) tick();
   t->reset_n = 1;
   for (int i = 0; i < 20; i++) tick();
   for (int a = 0; a < 0x4000; a++) poke(a, 0);
   for (int i = 0; i < 8; i++) poke(0x0000 + i, 0xFF);   // pattern char 0
   poke(0x2000, 0xF1);                                    // colour chars 00-07
   poke(0x1B00, 0xD0);                                    // no sprites
   const uint8_t r[8] = {0x00, 0xC0, 0x06, 0x80, 0x00, 0x36, 0x07, 0x0D};
   for (int i = 0; i < 8; i++) set_reg(i, r[i]);
}

// One character per line: S vsync, B blanking, A active, R border.
static std::string lines(int n) {
   std::string s;
   bool prev_hs = true, s_, b_, a_, vis;
   s_ = b_ = a_ = vis = false;
   long guard = 0;
   while ((int)s.size() < n && ++guard < 20000000) {
      tick();
      bool hs = t->hsync_n;
      if (prev_hs && !hs) {                 // new line starts at hsync
         if (vis) s += s_ ? 'S' : b_ ? 'B' : a_ ? 'A' : 'R';
         s_ = b_ = a_ = vis = false;
      }
      prev_hs = hs;
      if (!t->ce_pix || t->hblank) continue;
      vis = true;
      if (!t->vsync_n) s_ = true;
      if (t->vblank) b_ = true;
      if (t->rgb_r == 255 && t->rgb_g == 255 && t->rgb_b == 255) a_ = true;
   }
   return s;
}

// Run lengths of one frame, starting at the first vsync line.
static std::string frame_rle(const std::string& s) {
   size_t p = s.find("S");
   while (p != std::string::npos && p > 0 && s[p - 1] == 'S') p = s.find("S", p + 1);
   size_t q = s.find("S", s.find_first_not_of('S', p));
   if (p == std::string::npos || q == std::string::npos) return "?";
   std::string out;
   for (size_t i = p; i < q;) {
      size_t j = i;
      while (j < q && s[j] == s[i]) j++;
      out += s[i] + std::to_string(j - i) + " ";
      i = j;
   }
   return out + "= " + std::to_string(q - p);
}

static void run(const char* name, bool pal, const char* expected) {
   setup(pal);
   lines(700);                              // let registers settle
   std::string got = frame_rle(lines(pal ? 700 : 600));
   bool ok = got == expected;
   printf("  %-6s %s\n         je:       %s\n         ma byt:   %s\n",
          name, ok ? "OK  " : "FAIL ", got.c_str(), expected);
   if (!ok) fails++;
}

int main(int argc, char** argv) {
   Verilated::commandArgs(argc, argv);
   setvbuf(stdout, nullptr, _IONBF, 0);
   t = new Vtb_vdp_frame;
   t->csr_n = 1; t->csw_n = 1; t->mode = 0; t->poke = 0;

   printf("=== Svisle casovani (S vsync, B zatemneni, R okraj, A obraz) ===\n");
   run("NTSC", false, "S3 B13 R27 A192 R24 B3 = 262");
   run("PAL",  true,  "S3 B13 R51 A192 R51 B3 = 313");

   printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
   delete t;
   return fails ? 1 : 0;
}
