# MSX1/MSX2/turbo R for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

**English** | [Česky](Readme.cs.md)

> [!CAUTION]
> **WIP Notice**: This core is currently in **WIP (Work in Progress)** status. Some components are still under development and may include debug outputs or experimental features. Certain functionalities may not yet work 100% as intended. The ASCII16-X mapper and the MoonSound have been built and tested on real hardware. The NEO-8 and NEO-16 mappers have not been tested on real hardware yet, and V99x8 timing, the R800 and the TC8566AF controller are not verified on hardware either. See [Known limitations](#known-limitations).

## Core Overview
The core (its MiSTer name is still `MSX1`, hence the folder `games/MSX1`) is not a direct synthesis of a specific MSX computer model. Instead, it provides a **dynamically configurable hardware environment** that is built at run time from a selected definition (a *ROM PACK*). Each machine definition includes not only the hardware setup but also the corresponding **ROM binary content.** The core can run:

- **MSX1** machines (TMS9918 family VDP),
- **MSX2** machines (Yamaha V9938, RTC, memory mapper),
- the **MSX turbo R** Panasonic FS-A1ST (V9958, S1990, R800 mode – see [Known limitations](#known-limitations) for its speed),
- the **1chipMSX** (OCM-PLD style, MSX2+ class, V9958), which loads its BIOS from an SD card image.

For full functionality, the core also relies on an **extension module configuration** (the *FW PACK*), which includes additional ROM binaries. It is **independent of any specific MSX model**, allowing support for:
- Multiple language variants (via localized ROMs)
- Easy future expansion with new hardware extensions

The third configuration file is a **CRC32-based ROM database** (the *DB MAPPERS*), which maps known ROM checksums to their correct mapper types. This allows the core to automatically select the appropriate ROM mapper for each loaded image.

## Supported MSX Models
**[Supported MSX models](ComputersModel.md)** – 224 machine definitions from 36 manufacturers:

| Generation | Machines |
|---|---|
| MSX1 | 135 (124 with a TMS99xx VDP, 11 with a V9938 and an MSX1 BIOS) |
| MSX2 | 80 |
| MSX2+ | 7 |
| MSX turbo R | 1 (Panasonic FS-A1ST; the FS-A1GT is not supported) |
| 1chipMSX / OCM (MSX2+ class) | 1 |

Ten openMSX machines need hardware the core does not have yet; they are listed at the end of the model list. The ROM dumps of the machines are not part of this repository; see [Getting started](#getting-started).

## Getting Started
The core needs **at least a machine pack** (ROM PACK). Everything else depends on what you want to run. Put the files on the MiSTer SD card into `/media/fat/games/MSX1/`:

| File | Needed? | Notes |
|---|---|---|
| Machine pack `<model>.msx` | **Yes** | Nothing runs without it. Built from the machine ROMs with `createComp.py`. The C-BIOS machines (MSX, MSX2) and the 1chipMSX can be built without commercial ROMs, their ROMs are part of the repository. |
| FW pack `CART_FW_EN.msx` or `CART_FW_JP.msx` | For **any cartridge** | Needed for every cartridge type, **including a plain ROM**. It holds the ROMs of the cartridges (FM-PAC BIOS, `GM2.ROM`, `VY0010.ROM`, `mfrsd.ROM`, `yrw801.rom`, ...). Built with `createDev.py`. The EN and JP packs differ only in the FM-PAC ROM. A cartridge whose ROM is missing in the pack is left out of it. |
| Mapper database `vampier.db` | Optional | Needed for ROMs larger than 64 KB and for ROMs on a special mapper. A ROM up to 64 KB runs as plain ROM without it. Ready-made file: `tools/CreateCRC/vampier.db`. |
| ROM images `.ROM`, disk images `.DSK`, tape images `.CAS` | Optional | `.DSK` must be a raw image of 720K, 640K, 360K or 320K. |
| SD card image `.VHD` | 1chipMSX: yes | FAT16 **with a partition table** and `OCM-BIOS.DAT` as the first file. Optional for the MegaFlashROM SCC+ SD cartridge. |

Then load the packs in the OSD (**Load ROM PACK**, **Load FW PACK**, **Load DB MAPPERS**). MiSTer **remembers these three files and loads them again automatically at the next core start**; ROM cartridges, disks and tapes are not remembered. Every load rebuilds the whole machine.

How to build the packs and the database:
- [Tools overview](tools/README.md)
- [CreateMSXpack – building the ROM PACK and FW PACK](tools/CreateMSXpack/README.md)
- Developers (machine XML format, adding devices): [DEVELOPERS.md](tools/CreateMSXpack/DEVELOPERS.md)

In short: install **Python 3**, put the ROM binaries into the `ROM` directory of `tools/CreateMSXpack` or pass another folder with `--rom-dir` (files are matched by SHA1, names do not matter), then run `python3 createComp.py` (machines) and `python3 createDev.py` (cartridges); `--help` lists the options. The `.msx` files appear in `MSX/`.

SDRAM: the MoonSound, ASCII16-X, MegaFlashROM and the 1chipMSX (4 MB mapper) need the SDRAM module. Whether small MSX1 configurations run without it, and the required SDRAM size, has not been verified.

## OSD Features

| OSD item | Notes |
|---|---|
| Load ROM PACK (`.MSX`) | The machine pack. Remembered and loaded at core start. |
| Load FW PACK (`.MSX`) | The cartridge/extension pack. Remembered and loaded at core start. |
| Load DB MAPPERS (`.DB`) | The CRC32 mapper database. Remembered and loaded at core start. Loading it does not reset the machine, it is used by the next ROM load. |
| Mount Drive 1 / 2 (`.DSK`) | Shown according to the number of drives of the machine (or of the FDC cartridge). Two drives only on the Philips NMS 8255. |
| Slot1 / Slot2 | Cartridge type per slot, see [Expansion cartridges](#supported-expansion-cartridges). Changing it reloads the configuration. Not shown on the 1chipMSX, which has its own options. |
| Slot1 / Slot2 ROM Load (`.ROM`) | Shown when the slot is set to ROM. Up to 16 MB. |
| Load SD card (`.VHD`) | 1chipMSX (MegaSD) or MegaFlashROM SCC+ SD in slot 1. |
| Tape Input | File or ADC (analog input of MiSTer). Not shown on the 1chipMSX. |
| Cas File (`.CAS`) | Tape image, shown when Tape Input is File. |
| Tape Rewind | Rewinds the tape image. |
| Firmware switch | Off / On, only on machines with the S1990 (turbo R). |
| Video | Aspect ratio, scandoubler (None, HQ2x, CRT 25/50/75 %), Vertical Crop, Scale (Normal, V-Integer, Narrower/Wider HV-Integer, HV-Integer), Border (applies to the TMS and V99xx VDP). |
| Reset | Reset of the machine. |
| Reset & Detach ROM Cartridge | Clears the ROM cartridges in both slots and reloads. Not shown on the 1chipMSX. |
| Reset and close OSD | Reset and leave the menu. |
| SRAM Save / SRAM Load | Shown when a cartridge has SRAM, but **they do nothing** (see [Known limitations](#known-limitations)). |

1chipMSX has an extra block: CPU speed (Normal / Turbo, F11 toggles), CPU type (Z80 / R800 – only the R800 multiply instructions), Slot1, Slot2, Internal Mapper (2048 / 4096 KB), Joysticks Swap, Mouse Port 1/2, Reset after Mount.

### OSD error messages
When a load fails, the OSD info line shows one of these. After **No CRC32 DB**, **Not find CRC32 in DB** and **ROM too big** the core stays in reset until the next load.

| Message | Meaning |
|---|---|
| BAD MSX CONF | The file loaded as ROM PACK is not a machine pack. |
| NOT SUPPORTED CONF | The pack contains an unknown record – the pack and the core versions do not match. |
| NOT SUPPORTED BLOCK | The pack contains an unknown block type – the pack and the core versions do not match. |
| BAD MSX FW CONF | The file loaded as FW PACK is not a FW pack. |
| NOT FW CONF | The FW pack is not loaded but the selected cartridge needs it (every cartridge type, plain ROM included), or a ROM the cartridge needs is missing in the FW pack (e.g. `yrw801.rom` for MoonSound). |
| Device not in this core build | The configuration needs more copies of a device than the core contains, e.g. FM-PAC in both slots on a machine with MSX-MUSIC, MoonSound in both slots. |
| No CRC32 DB | A ROM larger than 64 KB needs a mapper but no mapper database is loaded. |
| Not find CRC32 in DB | A ROM larger than 64 KB is not in the mapper database. |
| FDC already in machine | Two FDCs in the same position – an error of the machine definition. |
| ROM too big | The ROM file is larger than 16 MB. |

## Supported Hardware Components
The core includes the following hardware modules:
- `PPI` – [Programmable Peripheral Interface](https://www.msx.org/wiki/Programmable_Peripheral_Interface)
- `RTC` – [Ricoh RP-5C01 Real-Time Clock](https://www.msx.org/wiki/Ricoh_RP-5C01) (time from MiSTer; the CMOS contents are not saved)
- `PSG` – [AY-3-8910 / YM2149 Programmable Sound Generator](https://www.msx.org/wiki/General_Instrument_AY-3-8910)
- `VDP` – [Video Display Processor (TMS family)](https://www.msx.org/wiki/Texas_Instruments_TMS9918), PAL or NTSC per machine definition
- `VDP` – Yamaha [V9938](https://www.msx.org/wiki/Yamaha_V9938) / [V9958](https://www.msx.org/wiki/Yamaha_V9958), 128 KB VRAM
- `CPU` – [Z80](https://www.msx.org/wiki/Z80) at 3.58 MHz; R800 mode of the turbo R, see [Known limitations](#known-limitations)
- `MEM_MAPPER` – MSX2 memory mapper
- `KANJI` – [Kanji ROM](https://www.msx.org/wiki/Kanji_ROM) (levels 1 and 2; Hangul variants)
- `FDD` – Floppy Disk Drive emulation on raw `.DSK` images (720K, 640K, 360K, 320K; disk change supported)
- `WD2793` – [Floppy Disk Controller](https://www.msx.org/wiki/Western_Digital_WD2793), read and write including Write Track (format); a write-protected image ignores writes
- `TC8566AF` – Toshiba floppy disk controller of the Panasonic FS-A1F and FS-A1ST, read and write
- `OPLL` – [YM2413](https://www.msx.org/wiki/Yamaha_YM2413), [MSX-MUSIC](https://www.msx.org/wiki/MSX-MUSIC) / [FM-PAC](https://www.msx.org/wiki/FM-PAC)
- `OPM` – [YM2151](https://www.msx.org/wiki/Yamaha_YM2151), built into the Yamaha CX5/CX11 machines
- `SCC` – [Konami SCC](https://www.msx.org/wiki/Konami_SCC)
- `SCC+` – [Konami 052539 Enhanced SCC](https://www.msx.org/wiki/Konami_052539)
- `OPL4` – [Yamaha YMF278B](https://www.msx.org/wiki/MoonSound) (MoonSound: OPL3 FM and 24 channel wave table synthesis)
- `DAC` – Konami Synthesizer 8-bit DAC
- `MIDI IN` – YM2148 MIDI interface via the MiSTer UART (MIDI OUT is not supported)
- `SFG01` – [Yamaha SFG-01](https://www.msx.org/wiki/Yamaha_SFG-01)
- `SFG05` – [Yamaha SFG-05](https://www.msx.org/wiki/Yamaha_SFG-05)
- turbo R: `S1990` system controller (Z80/R800 and ROM/DRAM switch, firmware switch), PCM, Pause key with LEDs, system timer; see [MSX turbo R](https://www.msx.org/wiki/MSX_turbo_R)
- [1chipMSX](https://www.msx.org/wiki/1chipMSX): IPL ROM, switched I/O ports 40-4F, ESE-RAM, MegaSD with SD card (VHD), turbo 3.58 / 5.37 / 10.74 MHz

Not implemented: MSX-AUDIO, MSX-MIDI, V9990 / GFX9000, printer, paddles, light gun, RS-232.

## Supported ROM Mappers
Cartridge ROMs are assigned to a mapper by the CRC32 database (`vampier.db`, 8096 entries, built by [tools/CreateCRC](tools/CreateCRC/README.md) from the [romdb.vampier.net](https://romdb.vampier.net/) dump). ROMs not in the database and up to 64 KB are placed as plain ROM (see the first rows).

| Mapper (name in the DB) | Description |
|---|---|
| plain ROM (`0x0000`, `0x4000`, `0x8000`, `Page12`, `Page2`, `Normal`) | ROM placed at that address; also the fallback without a database |
| mirrored ROM (`Mirrored`, `Mirrored0000`, `Mirrored4000`, `Mirrored8000`) | plain ROM mirrored over the address space; the start address of `Mirrored` comes from the ROM header |
| `16kb`, `8kB` | generic 16 KB and generic 8 KB bank switching |
| `Konami` | standard Konami mapper (8 KB banks) |
| `KonamiSCC` | Konami mapper with SCC sound |
| `ASCII8` | ASCII 8 KB mapper |
| `ASCII8SRAM2`, `ASCII8SRAM8` | ASCII 8 KB mapper with 2 / 8 KB SRAM |
| `ASCII16` | ASCII 16 KB mapper |
| `ASCII16SRAM2`, `ASCII16SRAM8` | ASCII 16 KB mapper with 2 / 8 KB SRAM |
| `ASCII16-X` | [ASCII16-X](https://www.grauw.nl/projects/ascii-x/ascii16-x/) mapper with an 8 MB flash ROM (changes are not saved) |
| `NEO-8`, `NEO-16` | NEO-8 (six 8 KB banks) and NEO-16 (three 16 KB banks) mappers with 12-bit bank numbers, ROMs up to 16 MB |
| `R-Type` | R-Type mapper |
| `Wizardry` | Wizardry (ASCII 8 KB variant with SRAM) |
| `KoeiSRAM32` | KOEI games with 32 KB SRAM |
| `GameMaster2` | Konami Game Master 2 ROM with 8 KB SRAM |
| `CrossBlaim` | Cross Blaim specific mapper |
| `HarryFox` | Harry Fox specific mapper |
| `Zemina80in1` | Zemina 80-in-1 multicart mapper |
| `Zemina90in1` | Zemina 90-in-1 multicart mapper (uses port 77h) |
| `SuperSwangi`, `MSXWrite` | special ASCII 16 KB variants |
| `Synthesizer` | plain ROM with the Konami Synthesizer DAC |

ROM types of the database without a configuration in the core are not written into `vampier.db` (27 types, 71 ROMs, e.g. Yamanooto, MatraCompilation, Namco, Manbow2). Such a ROM up to 64 KB runs as plain ROM, a bigger one stops with *Not find CRC32 in DB*. The full list with counts is in [tools/CreateCRC/report.md](tools/CreateCRC/report.md). Also not supported: MSX-DOS2, MU-PACK.

Machine-internal mappers (National FS-4600F, Yamaha SFG, Panasonic turbo R, memory mapper, ESE RAM) come from the machine definition and are not selectable.

## Supported Expansion Cartridges
The OSD offers the following types in **Slot1** and **Slot2**:

| Type | Slots | Requirements / notes |
|---|---|---|
| ROM | 1, 2 | Load the ROM with the item under the slot. Mapper from the database, or plain ROM. FW pack required. |
| Empty | 1, 2 | |
| FDC | 1 only | Philips VY-0010 floppy interface (WD2793, 1 drive); needs `VY0010.ROM` in the FW pack. **Only in a machine without its own FDC** – on a machine that has one, the cartridge is left out and the machine's FDC is used. |
| SCC | 1, 2 | Konami SCC sound cartridge |
| SCC+ | 1, 2 | [Konami Sound Cartridge](https://www.msx.org/wiki/Konami_Sound_Cartridge) with SCC+ and 128 KB RAM (Snatcher, SD Snatcher) |
| FM-PAC | 1, 2 | Needs the FM-PAC BIOS in the FW pack; 8 KB SRAM (not saved). On a machine that already has MSX-MUSIC only one FM-PAC fits. |
| MegaSCC+ 1MB | 1 only | ESE MegaSCC+ |
| MegaSCC+ 2MB | 2 only | ESE MegaSCC+ |
| MegaRAM ASCII-8K 1MB | 2 only | ESE [MegaRAM](https://www.msx.org/wiki/MegaRAM) |
| MegaRAM ASCII-16K 2MB | 2 only | ESE MegaRAM |
| MegaFlashROM SCC+ SD | 1 only | [MegaFlashROM SCC+ SD](https://www.msx.org/wiki/MegaFlashROM_SCC%2B_SD); needs `mfrsd.ROM` (8 MB image) in the FW pack; SD card via **Load SD card** (VHD); flash writes are not saved |
| Game Master 2 | 1 only | [Konami Game Master 2](https://www.msx.org/wiki/Konami_Game_Master_2); needs `GM2.ROM` in the FW pack; 8 KB SRAM (not saved) |
| MoonSound | 1, 2 | [MoonSound](https://www.msx.org/wiki/MoonSound) (OPL4); needs `yrw801.rom` in the FW pack; only one MoonSound at a time; 4 MB SDRAM; not available on the 1chipMSX |

The 1chipMSX has its own Slot1 (Empty, MegaSCC+ 1MB) and Slot2 (Empty, MegaSCC+ 2MB, MegaRAM 1MB / 2MB) options and cannot load ROMs into the slots.

## MiSTerFPGA Platform Support
The core integrates with MiSTerFPGA and supports the following features provided by the platform:
- `Joystick input` – two MSX joystick ports (four directions and two buttons) from the first two MiSTer joysticks; the joystick swap option exists on the 1chipMSX only
- `Keyboard input` – PS/2 keyboard, per-machine matrix layout (`kbd_layout` in the machine definition, generated by [CreateKeyMap](tools/CreateKeyMap/README.md)); Pause key on the turbo R, F11 = turbo on the 1chipMSX
- `Mouse` – PS/2 mouse as MSX mouse, 1chipMSX only
- `Cassette` – playback of `.CAS` files (the MSX motor must be on) or real tape through the MiSTer analog input (ADC); the tape is audible. There is no tape output.
- `MIDI IN` – via the MiSTer UART/MIDI setting, delivered to the YM2148 of the Yamaha machines
- `Video` – native MSX timing, PAL/NTSC per machine definition (TMS) or software (V99xx), scaling and scandoubler options
- `LEDs` – SD/VHD activity, turbo R turbo and pause LEDs
- `SDRAM support` – utilizes external SDRAM for extended memory requirements

## Known Limitations
- The NEO-8 and NEO-16 mappers are not tested on hardware. V99x8 timing, the R800 and the TC8566AF are not verified on hardware.
- **Nothing is persistent:** cartridge SRAM (FM-PAC, Game Master 2, KOEI, ASCII with SRAM), flash writes (MegaFlashROM, ASCII16-X) and the RTC CMOS are lost on reload. The **SRAM Save / SRAM Load** items do nothing. The FS-A1ST lacks the 16 KB SRAM of its Panasonic mapper.
- **Disks:** only raw `.DSK` images (720K, 640K, 360K, 320K); no 40-track, 1.44 MB, XSA, D88, HFE or DMK. WD279x Read Track is partial. The FDC cartridge works only in slot 1 and only in machines without an FDC; there is no TC8566AF cartridge.
- **Tape:** playback only, no saving; the end of the file is not detected (garbage is played after the last block).
- **R800:** the turbo R runs at about 2x the Z80 speed instead of the real 4x (R800 timings are not modelled); no turbo R microphone, no FS-A1GT.
- **ROMs:** a ROM over 64 KB needs an entry in the database, there is no mapper detection from the ROM header. Konami SCC ROM mirrors are not done.
- **V99x8:** sprites in the overscan and the FH window in text modes are not done. The VDP speed and volume settings of the 1chipMSX are stored without effect.
- **1chipMSX:** no MoonSound, no special keys (Pause/PrintScreen/ScrollLock).
- No MIDI OUT, no per-source volume or mute in the OSD, SCC+ deform bits 0/1 missing, no V9990.

## Acknowledgements
- [muhanpong/MSX1_MiSTer](https://github.com/muhanpong/MSX1_MiSTer) (branch `nextz80_v9990`) – a fork of this core. Its bug analyses and reports from real hardware pointed out faults in the flash emulation and the pitfalls of the ASCII16-X mapper and the MoonSound. No code was taken from it; the implementations here are independent.
- [openMSX](https://openmsx.org/) – reference for the behaviour of the ASCII16-X mapper and its flash chip, of the NEO-8 and NEO-16 mappers, of the OPL4 (YMF278B) wave part, bus interface and timers, and of the V99x8 timing.
- [Grauw](https://www.grauw.nl/projects/ascii-x/ascii16-x/) – specification of the ASCII16-X mapper.
- [Nuked OPL3](https://github.com/nukeykt/Nuked-OPL3) by Nuke.YKT – the OPL3 model the FM part of the MoonSound is checked against, sample by sample. Its source (LGPL-2.1-or-later) is used by the test only (`rtl/peripheral/SOUND/opl4/tb/nuked`).

## License
This core is licensed under the GNU General Public License, version 3 or later
(see `LICENSE`, `SPDX-License-Identifier: GPL-3.0-or-later` in the source headers).
Parts taken from other projects keep their own licenses, as stated in their file headers
(e.g. the MiSTer framework in `sys/`, the X68000_MiSTer FDC modules under GPL-3.0, the
ESE / OCM-PLD derived files, the T80 / TV80 CPU and VDP cores).
