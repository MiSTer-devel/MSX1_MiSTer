# VDPCMD as a ROM

**English** | [Česky](README.cs.md)

A cartridge ROM that runs bengalack's [vdpcmd](https://github.com/bengalack/vdpcmd) without
MSX-DOS. vdpcmd measures how many pixels the V9938/V9958 command engine handles in one frame and
compares them with values measured on real machines (column `REAL`). The tests and how to read
the results are described in the original README.

The ROM contains the original `vdpcmd.com` unchanged, so the measurement runs the same code as
under DOS.

## Build

```
sh tools/vdpcmd/build.sh
```

| File | Content |
|---|---|
| `vdpcmd.rom` | 16 kB cartridge at 4000h |
| `vdpcmd.asm` | loader and MSX-DOS environment |
| `upstream/vdpcmd.com` | the original program (bengalack/vdpcmd, commit `ddcc203`) |
| `upstream/LICENSE` | license of the original (MIT) |
| `screen.tcl`, `trace.tcl`, `mkdata.py` | result and trace from openMSX for the VDP testbench |

The assembler is `pasmo.exe` from `tools/vdptest`. The ROM starts without an entry in the
mapper database (`AB` header at offset 0, see [vdptest](../vdptest/README.md)).

## Running

Any MSX2, MSX2+ or turbo R: `vdpcmd.rom` into slot A (Cartridge = ROM). The program starts right
after boot, measures for a few seconds (the picture switches between SCREEN 8 and a blank screen)
and then prints a table in 80 columns. SPACE runs the measurement again.

On the FS-A1ST/GT the firmware switch must be off, otherwise the firmware starts instead of the
cartridge.

The measurement runs at the frequency the machine is set to (50 or 60 Hz), which also selects
the `REAL` values. On a turbo R and with the Panasonic turbo, vdpcmd switches to the Z80 at
3.5 MHz by itself.

**openMSX:**

```
openmsx -machine Philips_NMS_8245 -cart vdpcmd.rom
```

## How the ROM replaces DOS

vdpcmd expects what MSX-DOS gives it:
- RAM in all four pages, the program at 0100h, its data up to 4817h;
- a `JP` at 0038h; vdpcmd replaces the address at 0039h with its own interrupt handler (which
  stops the VDP command in the frame interrupt);
- BIOS calls through `CALSLT` (001Ch) and `RDSLT` (000Ch), the end through BDOS (0005h).

The ROM sets this up:
1. Copies its resident part to RAM at E000h; the stack is below F000h.
2. Switches pages 0 and 1 to the RAM slot of page 3 (primary and secondary slot), loads
   `vdpcmd.com` to 0100h and clears the rest of RAM up to E000h.
3. Puts a `JP` at 0038h to a handler that calls the BIOS interrupt routine, `JP`s at 000Ch and
   001Ch to `RDSLT` / `CALSLT`, and `JP`s at 0000h and 0005h to the program end.
4. `CALSLT` and `RDSLT` switch page 0 to the main BIOS, call it and switch RAM back. `CALSLT`
   handles the main BIOS only (vdpcmd calls no other slot); both return with interrupts
   disabled.
5. A BDOS call restores the slots as they were when the cartridge started, prints
   `SPACE: run again` and waits for SPACE.

The tests themselves (each between two frame interrupts) call none of this, so the timing is the
same as under DOS.

## VDP testbench

`rtl/peripheral/VIDEO/VDP/tb/run_vdp_vdpcmd.sh gt|nms` runs the same 50 tests in the VDP alone
and compares them with openMSX. It writes port 98h, the command start and the abort at the same
cycles after the frame interrupt as openMSX. The data come from:

```
TRACE_OUT=trace.txt TEND=22 openmsx -machine Panasonic_FS-A1GT -cart vdpcmd.rom -script trace.tcl
python mkdata.py trace.txt 358416 vdpcmd_gt.txt          (NTSC; PAL: 428184)
OUTTXT=vdpcmd_gt_openmsx.txt TEND=25 openmsx -machine Panasonic_FS-A1GT -cart vdpcmd.rom -script screen.tcl
```
