// VRAM address generation (vdp18_addr_mux) against the TMS9918A reference:
// https://www.unige.ch/medecine/nouspikel/ti99/tms9918a.htm
// Taken from the Sord M5 core (doc/vdp-tms9918-porovnani.md there); see doc/sordm5-opravy.md.
#include "Vtb_vdp_addr.h"
#include <cstdio>
#include <cstdint>
#include <cstdarg>

static Vtb_vdp_addr* t;
static int fails = 0;

enum { GRAPH1 = 0, GRAPH2 = 1, MULTIC = 2, TEXTM = 3 };

static void check(const char* name, bool ok, const char* fmt = "", ...) {
   char b[200] = "";
   va_list ap; va_start(ap, fmt); vsnprintf(b, sizeof b, fmt, ap); va_end(ap);
   printf("  %-56s %s %s\n", name, ok ? "OK  " : "FAIL ", b);
   if (!ok) fails++;
}

static uint32_t dut(bool pgt, int mode, int line, uint8_t vr3, uint8_t vr4, uint8_t name,
                    bool bm = false) {
   t->pgt = pgt; t->mode = mode; t->line = line & 0x1FF;
   t->bitmap = bm || mode == GRAPH2;
   t->vr3 = vr3; t->vr4 = vr4 & 7; t->chr = name;
   t->eval();
   return t->addr;
}

// Reference model. Bitmap: index = third:name:row (13 bits). Colour mask is
// (VR3 & 7F) << 6 | 3F; the pattern table uses VR4 & 03 for the thirds and
// the colour mask for everything below (the reference: "the address mask of
// the color table is used for both").
static uint32_t ref(bool pgt, int mode, int line, uint8_t vr3, uint8_t vr4, uint8_t name,
                    bool bm = false) {
   uint32_t row = line & 7;
   // Bitmap text / multicolor: table per third via VR4 & 03, name unmasked.
   if (bm && (mode == TEXTM || mode == MULTIC)) {
      uint32_t sub = mode == MULTIC ? (line >> 2) & 7 : row;
      uint32_t idx = (((line >> 6) & 3) << 11) | (name << 3) | sub;
      return ((vr4 & 4) << 11) | (idx & (((vr4 & 3) << 11) | 0x7FF));
   }
   switch (mode) {
   case GRAPH2: {
      uint32_t idx   = (((line >> 6) & 3) << 11) | (name << 3) | row;
      uint32_t cmask = ((vr3 & 0x7F) << 6) | 0x3F;
      if (!pgt) return ((vr3 & 0x80) << 6) | (idx & cmask);
      uint32_t pmask = ((vr4 & 3) << 11) | (cmask & 0x7FF);
      return ((vr4 & 4) << 11) | (idx & pmask);
   }
   case GRAPH1:
      return pgt ? ((vr4 & 7) << 11) | (name << 3) | row
                 : (vr3 << 6) | (name >> 3);
   case MULTIC:
      return ((vr4 & 7) << 11) | (name << 3) | ((line >> 2) & 7);
   default: // TEXTM
      return ((vr4 & 7) << 11) | (name << 3) | row;
   }
}

// Sweep all VR3/VR4/names over lines that cover each third and row edge.
static void sweep(const char* tag, int mode, bool pgt, int vr3_n, bool bm = false) {
   static const int lines[] = {0, 7, 63, 64, 71, 127, 128, 135, 191};
   long bad = 0, n = 0;
   char first[120] = "";
   for (int vr3 = 0; vr3 < vr3_n; vr3++)
      for (int vr4 = 0; vr4 < 8; vr4++)
         for (int line : lines)
            for (int name = 0; name < 256; name++) {
               uint32_t got = dut(pgt, mode, line, vr3, vr4, name, bm);
               uint32_t exp = ref(pgt, mode, line, vr3, vr4, name, bm);
               n++;
               if (got != exp && bad++ == 0)
                  snprintf(first, sizeof first, "(VR3=%02X VR4=%X line=%d name=%02X: %04X, má být %04X)",
                           vr3, vr4, line, name, got, exp);
            }
   check(tag, bad == 0, "%s", bad ? first : "");
   if (bad) printf("      chybných %ld z %ld\n", bad, n);
}

int main(int argc, char** argv) {
   Verilated::commandArgs(argc, argv);
   setvbuf(stdout, nullptr, _IONBF, 0);
   t = new Vtb_vdp_addr;

   printf("=== Bitmap: tabulka VR3/VR4 z reference ===\n");
   // VR3, VR4, top / middle / bottom third
   static const struct { uint8_t vr3, vr4; uint16_t a[3]; } tab[] = {
      {0x1F, 0x00, {0x0000, 0x0000, 0x0000}},
      {0x9F, 0x04, {0x2000, 0x2000, 0x2000}},
      {0x3F, 0x01, {0x0000, 0x0800, 0x0000}},
      {0xBF, 0x05, {0x2000, 0x2800, 0x2000}},
      {0x5F, 0x02, {0x0000, 0x0000, 0x1000}},
      {0xDF, 0x06, {0x2000, 0x2000, 0x3000}},
      {0x7F, 0x03, {0x0000, 0x0800, 0x1000}},
      {0xFF, 0x07, {0x2000, 0x2800, 0x3000}},
   };
   for (auto& r : tab) {
      char tag[80];
      for (int pgt = 0; pgt < 2; pgt++) {
         uint32_t g[3];
         for (int th = 0; th < 3; th++) g[th] = dut(pgt, GRAPH2, th * 64, r.vr3, r.vr4, 0);
         snprintf(tag, sizeof tag, "VR3=%02X VR4=%02X %s: %04X/%04X/%04X", r.vr3, r.vr4,
                  pgt ? "vzory" : "barvy", r.a[0], r.a[1], r.a[2]);
         check(tag, g[0] == r.a[0] && g[1] == r.a[1] && g[2] == r.a[2],
               "(je %04X/%04X/%04X)", g[0], g[1], g[2]);
      }
   }

   printf("\n=== Bitmap: seskupení znaků podle VR3 >1F ===\n");
   // VR3=0F: characters 80-FF repeat 00-7F; n and n^10 stay distinct.
   for (int pgt = 0; pgt < 2; pgt++) {
      const char* tb = pgt ? "vzory" : "barvy";
      char tag[80];
      snprintf(tag, sizeof tag, "VR3=0F %s: znak 00 = 80", tb);
      check(tag, dut(pgt, GRAPH2, 0, 0x0F, 3, 0x00) == dut(pgt, GRAPH2, 0, 0x0F, 3, 0x80));
      snprintf(tag, sizeof tag, "VR3=0F %s: znak 00 != 10", tb);
      check(tag, dut(pgt, GRAPH2, 0, 0x0F, 3, 0x00) != dut(pgt, GRAPH2, 0, 0x0F, 3, 0x10));
      snprintf(tag, sizeof tag, "VR3=03 %s: znak 00 = 20 = 40 = E0", tb);
      uint32_t a = dut(pgt, GRAPH2, 0, 0x03, 3, 0x00);
      check(tag, a == dut(pgt, GRAPH2, 0, 0x03, 3, 0x20) &&
                 a == dut(pgt, GRAPH2, 0, 0x03, 3, 0x40) &&
                 a == dut(pgt, GRAPH2, 0, 0x03, 3, 0xE0));
      snprintf(tag, sizeof tag, "VR3=03 %s: znaky 00-1F jsou různé", tb);
      bool distinct = true;
      for (int n = 1; n < 32; n++)
         if (dut(pgt, GRAPH2, 0, 0x03, 3, n) == a) distinct = false;
      check(tag, distinct);
   }

   printf("\n=== Úplné porovnání s referencí ===\n");
   sweep("Bitmap, barvy (VR3 00-FF, VR4 0-7)", GRAPH2, false, 256);
   sweep("Bitmap, vzory (VR3 00-FF, VR4 0-7)", GRAPH2, true, 256);
   sweep("Graphic I, barvy", GRAPH1, false, 256);
   sweep("Graphic I, vzory", GRAPH1, true, 1);
   sweep("Multicolor, vzory", MULTIC, true, 1);
   sweep("Text, vzory", TEXTM, true, 1);
   sweep("Bitmap text, vzory (VR3 00-FF)", TEXTM, true, 256, true);
   sweep("Bitmap multicolor, vzory (VR3 00-FF)", MULTIC, true, 256, true);

   printf("\n%s (%d errors)\n", fails ? "FAIL" : "PASS", fails);
   delete t;
   return fails ? 1 : 0;
}
