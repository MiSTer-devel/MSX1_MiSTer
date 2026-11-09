// Whole-frame test of vdp18_core: random VRAM, registers written through the
// CPU port, one captured frame compared with a reference renderer that follows
// the TMS9918A reference (Nouspikel), same model as tools/vdptest/render.py of the Sord M5 core.
// Sprites are switched off (Y = D0 at the start of the attribute table).
#include "Vtb_vdp_frame.h"
#include <cstdio>
#include <cstdint>
#include <cstdarg>
#include <vector>

static Vtb_vdp_frame* t;
static int fails = 0;
static uint8_t vram[0x4000];

static const uint8_t PAL[16][3] = {   // full_rgb_table_c (MAME)
   {0, 0, 0}, {0, 0, 0}, {33, 200, 66}, {94, 220, 120},
   {84, 85, 237}, {125, 118, 252}, {212, 82, 77}, {66, 235, 245},
   {252, 85, 84}, {255, 121, 120}, {212, 193, 84}, {230, 206, 128},
   {33, 176, 59}, {201, 91, 186}, {204, 204, 204}, {255, 255, 255},
};

static uint32_t rgb(int c) { return (PAL[c][0] << 16) | (PAL[c][1] << 8) | PAL[c][2]; }

static void check(const char* name, bool ok, const char* fmt = "", ...) {
   char b[200] = "";
   va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
   printf("  %-44s %s %s\n", name, ok ? "OK  " : "FAIL ", b);
   if (!ok) fails++;
}

static void tick() { t->clk = 1; t->eval(); t->clk = 0; t->eval(); }

static void cpu_write(bool mode, uint8_t v) {
   t->mode = mode; t->cd_i = v; t->csw_n = 0;
   for (int i = 0; i < 4; i++) tick();
   t->csw_n = 1;
   for (int i = 0; i < 4; i++) tick();
}

static void set_reg(int r, uint8_t v) { cpu_write(1, v); cpu_write(1, 0x80 | r); }

static void poke(uint16_t a, uint8_t d) {
   vram[a] = d;
   t->poke = 1; t->poke_a = a; t->poke_d = d; tick();
   t->poke = 0;
}

struct Img { int w = 0, h = 0; std::vector<uint32_t> px; };

// Active area of the next complete frame (DE = !hblank && !vblank).
static Img grab() {
   Img im;
   long guard = 0;
   while (!t->vblank) { tick(); if (++guard > 3000000) return im; }
   while (t->vblank)  { tick(); if (++guard > 3000000) return im; }
   std::vector<uint32_t> line;
   while (true) {
      tick();
      if (!t->ce_pix) continue;
      if (t->vblank) break;
      if (!t->hblank) {
         line.push_back((t->rgb_r << 16) | (t->rgb_g << 8) | t->rgb_b);
      } else if (!line.empty()) {
         if (im.w == 0) im.w = (int)line.size();
         if ((int)line.size() != im.w) im.w = -1;      // ragged lines
         im.px.insert(im.px.end(), line.begin(), line.end());
         im.h++;
         line.clear();
      }
   }
   return im;
}

// Reference renderer, mode decode and addressing as in render.py.
static Img ref_frame(const uint8_t r[8]) {
   bool m1 = r[1] & 0x10, m2 = r[1] & 0x08, m3 = r[0] & 0x02;
   int nt = (r[2] & 15) << 10, fg7 = r[7] >> 4, bg7 = r[7] & 15, bd = r[7] & 15;
   Img im;
   auto col = [&](int c) { return rgb(c ? c : bd); };

   if (m1) {                                         // text, bitmap text, illegal
      im.w = 240; im.h = 192;
      for (int y = 0; y < 192; y++)
         for (int c = 0; c < 40; c++) {
            int bits;
            if (m2) bits = 0xF0;
            else {
               int name = vram[nt + (y >> 3) * 40 + c], ln = y & 7;
               int a;
               if (m3) {
                  int raw = ((y >> 6) << 11) | (name << 3) | ln;
                  a = ((r[4] & 4) << 11) | (raw & (((r[4] & 3) << 11) | 0x7FF));
               } else a = ((r[4] & 7) << 11) | (name << 3) | ln;
               bits = vram[a];
            }
            for (int b = 0; b < 6; b++)
               im.px.push_back(col(bits & (0x80 >> b) ? fg7 : bg7));
         }
      return im;
   }

   im.w = 256; im.h = 192;
   for (int y = 0; y < 192; y++)
      for (int c = 0; c < 32; c++) {
         int name = vram[nt + (y >> 3) * 32 + c], ln = y & 7;
         if (m2) {                                   // multicolor, bitmap multicolor
            int sub = (((y >> 3) & 3) << 1) | (ln >> 2), a;
            if (m3) {
               int raw = ((y >> 6) << 11) | (name << 3) | sub;
               a = ((r[4] & 4) << 11) | (raw & (((r[4] & 3) << 11) | 0x7FF));
            } else a = ((r[4] & 7) << 11) | (name << 3) | sub;
            int v = vram[a];
            for (int b = 0; b < 8; b++) im.px.push_back(col(b < 4 ? v >> 4 : v & 15));
            continue;
         }
         int bits, v;
         if (m3) {                                   // Graphic II
            int raw = ((y >> 6) << 11) | (name << 3) | ln;
            int cm = ((r[3] & 0x7F) << 6) | 0x3F;
            int pm = ((r[4] & 3) << 11) | (cm & 0x7FF);
            bits = vram[((r[4] & 4) << 11) | (raw & pm)];
            v    = vram[((r[3] & 0x80) << 6) | (raw & cm)];
         } else {                                    // Graphic I
            bits = vram[((r[4] & 7) << 11) | (name << 3) | ln];
            v    = vram[(r[3] << 6) | (name >> 3)];
         }
         for (int b = 0; b < 8; b++)
            im.px.push_back(col(bits & (0x80 >> b) ? v >> 4 : v & 15));
      }
   return im;
}

static void save_ppm(const char* path, const Img& im) {
   if (im.w <= 0 || im.h <= 0) return;
   FILE* f = fopen(path, "wb");
   if (!f) return;
   fprintf(f, "P6\n%d %d\n255\n", im.w, im.h);
   for (uint32_t p : im.px) { fputc(p >> 16, f); fputc(p >> 8, f); fputc(p, f); }
   fclose(f);
}

static uint32_t rng = 12345;
static uint8_t rnd() { rng = rng * 1103515245u + 12345u; return rng >> 16; }

static void scene(const char* name, const uint8_t r[8], uint16_t sat) {
   for (int a = 0; a < 0x4000; a++) poke(a, rnd());
   poke(sat, 0xD0);                                  // no sprites
   for (int i = 0; i < 8; i++) set_reg(i, r[i]);
   grab();                                           // let registers settle
   Img got = grab(), exp = ref_frame(r);

   bool ok;
   if (got.w != exp.w || got.h != exp.h) {
      ok = false;
      check(name, false, "(rozmer %dx%d, ma byt %dx%d)", got.w, got.h, exp.w, exp.h);
   } else {
      long bad = 0, first = -1;
      for (size_t i = 0; i < exp.px.size(); i++)
         if (got.px[i] != exp.px[i] && bad++ == 0) first = (long)i;
      ok = bad == 0;
      if (bad)
         check(name, false, "(%ld px, prvni x=%ld y=%ld)", bad, first % exp.w, first / exp.w);
      else
         check(name, true);
   }
   if (!ok) {
      char p[80];
      snprintf(p, sizeof p, "%s_got.ppm", name); save_ppm(p, got);
      snprintf(p, sizeof p, "%s_exp.ppm", name); save_ppm(p, exp);
   }
}

int main(int argc, char** argv) {
   Verilated::commandArgs(argc, argv);
   setvbuf(stdout, nullptr, _IONBF, 0);
   t = new Vtb_vdp_frame;
   t->csr_n = 1; t->csw_n = 1; t->mode = 0; t->poke = 0;
   t->border = 0; t->pal = 0;
   t->reset_n = 0;
   for (int i = 0; i < 20; i++) tick();
   t->reset_n = 1;
   for (int i = 0; i < 20; i++) tick();

   // R1 always has 16K (80h) and display on (40h).
   struct { const char* name; uint8_t r[8]; uint16_t sat; } sc[] = {
      {"g1",            {0x00, 0xC0, 0x06, 0x80, 0x00, 0x36, 0x07, 0xF4}, 0x1B00},
      {"g2_ff_03",      {0x02, 0xC0, 0x0E, 0xFF, 0x03, 0x76, 0x03, 0xF1}, 0x3B00},
      {"g2_3f_01",      {0x02, 0xC0, 0x0E, 0x3F, 0x01, 0x76, 0x03, 0xF1}, 0x3B00},
      {"g2_8f_03",      {0x02, 0xC0, 0x0E, 0x8F, 0x03, 0x76, 0x03, 0xF1}, 0x3B00},
      {"multicolor",    {0x00, 0xC8, 0x06, 0x00, 0x00, 0x36, 0x07, 0xF4}, 0x1B00},
      {"text",          {0x00, 0xD0, 0x06, 0x00, 0x00, 0x36, 0x07, 0xF4}, 0x1B00},
      {"btext_ff_03",   {0x02, 0xD0, 0x0E, 0xFF, 0x03, 0x76, 0x03, 0xF4}, 0x3B00},
      {"btext_80_01",   {0x02, 0xD0, 0x0E, 0x80, 0x01, 0x76, 0x03, 0xF4}, 0x3B00},
      {"btext_80_06",   {0x02, 0xD0, 0x0E, 0x80, 0x06, 0x76, 0x03, 0x1F}, 0x3B00},
      {"bmc_ff_03",     {0x02, 0xC8, 0x0E, 0xFF, 0x03, 0x76, 0x03, 0xF1}, 0x3B00},
      {"bmc_00_05",     {0x02, 0xC8, 0x0E, 0x00, 0x05, 0x76, 0x03, 0xF1}, 0x3B00},
      {"illegal_m1m2",  {0x00, 0xD8, 0x06, 0x00, 0x00, 0x36, 0x07, 0xF4}, 0x1B00},
      {"illegal_m1m2m3",{0x02, 0xD8, 0x0E, 0xFF, 0x03, 0x76, 0x03, 0x2A}, 0x3B00},
   };

   printf("=== Snimek proti referenci (standardni rezimy = regrese) ===\n");
   for (auto& s : sc) scene(s.name, s.r, s.sat);

   printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
   delete t;
   return fails ? 1 : 0;
}
