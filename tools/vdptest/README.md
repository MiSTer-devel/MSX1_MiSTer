# VDPTEST for MSX

**English** | [Česky](README.cs.md)

Test ROMs for the VDP: TMS9918A/28A/29A (the `VDP18` core), V9938 and V9958 (the ESE VDP core).
They run on the FPGA core and in openMSX, and the results are compared. They mainly measure
**timing**:
- when the flags in the status registers are set (F, 5S, C, VR, FH, CE);
- when the interrupt arrives and how long the VDP commands take.

One page also shows interrupt bars for a visual comparison.

It is based on the test of the same name for the Sord M5 (`SordM5_MiSTer_verilog/tools/vdptest`).
The program is rewritten for MSX, though: ports 98h-9Bh, keyboard through the PPI and IM2 interrupts.

## Build

```
sh tools/vdptest/build.sh
```

| File | Contents |
|---|---|
| `vdptest.rom` | 16 kB cartridge at 4000h. **Space** = next page, **Enter** = previous page. |
| `vdptest_auto.rom` | Pages by itself (about every 0.6 s), for simulation. |
| `cmdbench.rom` | VDP command times in 14 configurations (MSX2), see the CMDBENCH chapter. |

The assembler is `pasmo.exe` 0.6.0 (copied from the Sord M5 project). The option
`--equ STARTPG=n` starts at page n+1 (for debugging one page in simulation).

**ROM rules** (the core runs it without an entry in the mapper database):
- at offset 0 an `AB` header + INIT in the 4000h-7FFFh page, which places the ROM at 4000h;
- size at most 48 kB;
- the length does not have to be aligned.

## Running

**FPGA:** in the OSD load `vdptest.rom` into slot A (Cartridge = ROM).
- The FW pack (`CART_FW_EN.msx`) must be loaded.
- The mapper database does not have to be loaded: a ROM that the core does not find in it is
  started as a plain ROM according to its header (`doc/mappery.md`, chapter "ROM in the cartridge
  slot: mapper selection").
- If a database is loaded, vdptest must not be in it, otherwise the record from the database
  would be used.
- Requires a core with commit `e5dc75c` (branch `ROM_no_db`). An older core starts only a ROM
  with a database record: CRC32 + mapper "0x4000" (21), format in `tools/CreateCRC/createDB.py`.

**openMSX** (machine chosen by VDP type):

```
openmsx -machine Philips_VG_8020 -cart vdptest.rom      # TMS9929A (PAL)
openmsx -machine Philips_NMS_8245 -cart vdptest.rom     # V9938
openmsx -machine Panasonic_FS-A1WX -cart vdptest.rom    # V9958
```

**Whole-machine simulation** (`rtl/tb/machine_boot_tb`, the pages go to the log as text):

```
wsl.exe -- bash rtl/tb/run_machine_boot.sh <machine.msx> none \
   (SIMARGS="+run_ms=20000 +fw=<CART_FW_EN.msx> +rom=tools/vdptest/vdptest_auto.rom")
```

## How the program measures

- **VDP type:** writes R#15 = 1 and reads port 99h.
  - A V99x8 then returns S#1: bit 7 (FL) stays 0, the ID is in bits 5-1 (V9938 = 0, V9958 = 2).
  - A TMS99xx has no R#15, the write ends up in R#7 (which is then overwritten) and S#0 keeps being
    read, where F is set once per frame.
  - Pages for V99x8 only are skipped on a TMS.
- **Turbo R** is switched to Z80 (BIOS `CHGCPU`) so that the loops count Z80 cycles.
- **Measured with DI** by a read loop in RAM:
  `IN A,(99h) / AND m / JR cc / INC HL / LD A,H / INC A / JP NZ`.
  On MSX (one M1 wait for every fetched opcode) it takes **56 T per iteration**. A line is 228 T,
  that is **4.07 iterations per line**.
- **The time limit** is 65 280 iterations (about 1 s); it is printed as `-----`.
- **Results** are iteration counts. The FPGA is compared with openMSX. The `MODEL` row is a
  calculation according to the openMSX model (`VDP.cc`), not a measurement. A few iterations are
  lost to overhead between two measurements.

## Pages

| # | Page | VDP | What it measures | MODEL |
|---|---|---|---|---|
| 1 | INFO | all | VDP type, MSX version byte, V99x8 ID. Frame length: iterations between two F (5x). | NTSC 1066, PAL 1274 |
| 2 | IRQ BARS | all | **Visual.** The VBLANK interrupt recolours the border for 3 lines **white**. On V99x8 the line interrupt (R#19 = 96) **yellow**. The bar starts at the moment of the interrupt plus the service latency (about 0.3 line). | White bar right below the picture. Yellow from the right edge of line 96. |
| 3 | S#2 VR | V99x8 | From F to VR = 0, duration of VR = 0, and whether F is set immediately after VR = 1. 4 lines of measurement. | NTSC 281 / 786 / 1, PAL 489 / 786 / 1 |
| 4 | LINE INTERRUPT | V99x8 | With IE1 and DI: from F to FH in S#1 for R#19 = 0, 100, 191. | NTSC 288 / 695 / 1066, PAL 496 / 903 / 1288 |
| 5 | S#1 FH | V99x8 | a) FH (R#19 = 190, IE1) read 40 lines after F; b) without IE1: from F to FH = 1, duration of FH = 1, FH read on line 110; c) IE1 enabled only after the match. | a) 1111; b) ~695 / 0-1 / 0; c) 0000 |
| 6 | 5S AND C TIMING | all | Graphic 1, sprites on line 100: from F to 5S (5 sprites side by side) and to C (2 overlapping). | about 690 |
| 7 | SPRITE COLLISION WINDOW | all | C over the whole frame (all S#0 reads summed), sprites Y = 99, 191, 209, 230 (32 sprites), 252. TMS in Graphic 1, V99x8 in SCREEN 5. | V99x8 11001 |
| 8 | VDP COMMAND TIME | V99x8 | SCREEN 5, display on, sprites off: HMMV, LMMV, YMMM, HMMM, LMMM, LINE 255x100, LINE 255x255 and HMMV with the display off. From command start to CE = 0. | - (compare with openMSX) |

**Notes on the pages:**
- **Page 4, R#19 = 191:** the match happens before F, so FH is cleared after F first and only the
  next frame is measured.
- **Page 7, Y = 191** (sprite on lines 192-199):
  - openMSX checks V99x8 sprites on line 192 too, so it reports C;
  - a TMS9929A measured on the Sord M5 does not report a collision on line 192;
  - how the V9938 behaves has not been measured.

## Results

**Simulation** of the whole machine (`machine_boot_tb`, 2026-11-10, branch `VDP_fork` = VDP fixes
from chapter 3.1 of `doc/fork-muhanpong.md`). The openMSX column: Philips NMS 8245 (V9938 PAL),
2026-11-10. The FPGA column: NMS 8245 on a MiSTer, 2026-11-10.

| Page | NMS 8245, V9938 PAL (sim.) | VG-8020, TMS (sim.) | FPGA | openMSX |
|---|---|---|---|---|
| 1 frame | 1268-1271 | 1268-1272 (after the PAL fix, before 1060-1064) | 1268-1272 | 1268-1272 |
| 3 VR | 485 / 780 / 1 | - | 484-485 / 780-781 / 1 | 485 / 780 / 1 |
| 4 FH, R#19 = 0/100/191 | 492 / 899 / 1269 | - | 491-492 / 899 / 1269 | 491-492 / 899 / 1269 |
| 5 FH | a) 1111; b) 899 / 0 / 0; c) 0000 | - | a) 1111; b) 899 / 0 / 0; c) 0000 | a) 1111; b) 899 / 0 / 0; c) 0000 |
| 6 5S / C | 890 / 894 | 686 / 691-692 | 890 / 894 | 894 / 895 |
| 7 collision | 11001 | 10001 | 11001 | 11001 |
| 8 HMMV / LMMV / YMMM / HMMM / LMMM | 4553 / 18689 / 5675 / 5579 / 21737 | - | 4553 / 18648 / 5717 / 5537 / 21737 | 4561 / 18226 / 5495 / 7715 / 21280 |
| 8 LINE 255,100 / 255,255 / HMMV off | 77 / 77 / 3262 | - | 77 / 77 / 3262 | 103 / 121 / 3996 |

**Notes:**
- **VG-8020 (PAL)** ran with the TMS in NTSC: `deviceParams.json` encodes PAL = 0, NTSC = 1 and
  `dev_tms` sent `param[0]` directly to `is_pal_i`. Fixed in `9de13dc`.
- **FPGA = simulation:** pages 1-7 agree (+-1 iteration), commands within 0.8 %.
- **V9938 FPGA vs openMSX:** pages 1, 3, 4, 5 and 7 agree.
- **5S (page 6)** arrives in ESE 4 iterations (~1 line) earlier, C 1 iteration earlier.
  - openMSX checks the sprites of the whole line at once at its end (comment in
    `SpriteChecker.hh`, `checkUntil`); ESE scans Y during the line before it and, according to the
    same comment, the chip most likely does it that way too.
  - So openMSX is not an exact reference for the 5S moment. Not measured on real HW.
- **VDP commands (page 8)**, ESE against openMSX:
  - HMMV -0.2 %, LMMV +2.5 %, YMMM +3.3 %, LMMM +2.1 %: agreement;
  - HMMM 28 % faster (7715 -> 5579);
  - HMMV with the display off 18 % faster (3996 -> 3262);
  - LINE 25-36 % faster and independent of the minor axis (openMSX 103 / 121, ESE 77 / 77).
  - The earlier conclusion "logical commands 3x slower" was wrong: it compared against numbers
    from the fork (openMSX HMMV there 722 lines, here 1120), which were measured with different
    parameters.

## CMDBENCH (V9938/V9958 command times)

`cmdbench.rom` measures eight commands (HMMV, LMMV, SRCH, YMMM, HMMM, LMMM, LINE 255x100 and
255x255) in 14 configurations:
- SCREEN 5: NTSC and PAL, 212 and 192 lines, sprites on and off, display off;
- SCREEN 6, 7 and 8 (NTSC, 212 lines, sprites on) and SCREEN 8 with sprites off.

Each command starts when VR goes to 0 (the line before the display). The result is the number of
56 T loop iterations until CE = 0, like on page 8 of vdptest. After the measurement the ROM prints
a table in 80 columns, one row per configuration. The results are also in RAM from C000h
(14 x 8 words); C0FEh = A5h means done.

**openMSX without a window** (results to a file, script `cmdbench.tcl`):

```
OPENMSX_USER_DATA=<dir with systemroms> CMDBENCH_OUT=result.txt   openmsx -machine Philips_NMS_8245 -cart cmdbench.rom -script cmdbench.tcl
```

The output of openMSX 18.0 is the reference of the test
`rtl/peripheral/VIDEO/VDP/tb/run_vdp_cmd.sh` (`cmdbench_openmsx.txt`). The model of the VDP access
slots is described in `doc/vdp-prikazy.md`.
