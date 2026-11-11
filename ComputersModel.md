# Supported MSX Models

**English** | [Česky](ComputersModel.cs.md)

Back to the [Readme](Readme.md).

The core is not tied to one computer: each machine below is a definition (an XML file in `tools/CreateMSXpack/Computer/`) that is turned into a ROM PACK (`.msx`). There are **224 definitions** from 36 manufacturers:

| Generation | Count |
|---|---|
| MSX1 | 135 (124 with a TMS99xx VDP, 11 with a V9938 and an MSX1 BIOS) |
| MSX2 | 80 |
| MSX2+ | 7 |
| MSX turbo R | 1 |
| 1chipMSX / OCM (MSX2+ class) | 1 |

158 of them were added in November 2026 by converting the openMSX machine descriptions
(`share/machines`). Machines that need hardware the core does not have are listed at the end.

**ROM dumps are not included.** You supply the ROM files and build the packs yourself with [CreateMSXpack](tools/CreateMSXpack/README.md) (see also [Tools](tools/README.md)). Only the two C-BIOS machines and the 1chipMSX can be built without your own ROMs. The **1chipMSX** also needs `OCM-BIOS.DAT` as the first file of a FAT16 SD card image (VHD).

Notes on the tables:
- Models are linked to [msx.org](https://www.msx.org/). A link marked **†** leads to a page that covers the model as a variant (family page). Older models without a link have no msx.org page; the models added from openMSX are not linked yet.
- **Boot test** lists what has been recorded: *sim* = boot in simulation, *HW* = used on real hardware. An empty cell means that no test result is recorded, not that the machine fails.
- Disk drives: *FDC* = built-in floppy disk controller. The machine's own FDC always wins over an FDC cartridge.
- *not emulated* lists built-in hardware the core leaves out. On every machine the printer port is missing and the keyboard map is the European one; machines with the S1985 MSX-engine also lack its 16-byte backup RAM.

Known issue: **Philips VG 8235-00** reports "Disk offline" in simulation (suspected cause: single-sided drive with a 720 KB image). Not verified on hardware.

## AVT
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [DPC-200](https://www.msx.org/wiki/AVT_DPC-200) | MSX1 | European-market version of the Daewoo DPC-200, a basic MSX1. | 64 KB RAM | |

## Al Alamiah (Sakhr)
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [AX170](https://www.msx.org/wiki/Sakhr_AX-170) | MSX1 | Common Arabic MSX1 with a built-in Arabic ROM. | 64 KB RAM, Arabic ROM | |
| [AX230](https://www.msx.org/wiki/Sakhr_AX-230) | MSX1 | Arabic MSX1 with built-in games. | 64 KB RAM, Arabic ROM, games ROM, one cartridge slot | |
| AX370 | MSX2 | Arabic MSX2 based on the Sanyo PHC-70FD, with a disk drive and built-in software. | 128 KB mapper, RTC, TC8566AF FDC + 1 drive, Al Alamiah BASIC 2.03, Sakhr Word Processor, Sakhr BASIC, Painter ROM | |

## Bawareth
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| Perfect MSX1 | MSX1 | Arabic MSX1 based on the Daewoo CPC-200. | 64 KB RAM | |

## C-BIOS (open-source firmware, not a real product)
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| MSX - C-BIOS | MSX1 | Generic MSX1 running the free C-BIOS; the ROMs ship in the repository. | 64 KB RAM | |
| MSX2 - C-BIOS | MSX2 | Generic MSX2 running the free C-BIOS; the ROMs ship in the repository. | 128 KB mapper, RTC | |

## CIEL (Brazil)
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| Expert Turbo | MSX2+ | Brazilian homebrew MSX2+ motherboard for a Gradiente Expert case. | V9958, 1024 KB mapper, RTC, MSX-MUSIC, 3 cartridge slots (2 in the core), not emulated: 7.16 MHz turbo | |

## Canon
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| V-10 | MSX1 | Basic Japanese MSX1 with 16 KB RAM. | 16 KB RAM | |
| [V-20](https://www.msx.org/wiki/Canon_V-20) | MSX1 | Canon's original Japanese MSX1. | 64 KB RAM | |
| V-20 (JP) | MSX1 | Canon's mainstream Japanese MSX1. | 64 KB RAM | |
| [V-20E](https://www.msx.org/wiki/Canon_V-20_%28EU%29) | MSX1 | European adaptation of the V-20. | 64 KB RAM | |
| [V-20F](https://www.msx.org/wiki/Canon_V-20_%28FR%29) | MSX1 | French (AZERTY) adaptation of the V-20. | 64 KB RAM | |
| V-20G | MSX1 | Regional variant of the European V-20 with its own BIOS dump. | 64 KB RAM | |
| V-20S | MSX1 | Regional variant of the European V-20 with its own BIOS dump. | 64 KB RAM | |
| V-25 | MSX2 | Very basic MSX2, one of the few with only 64 KB VRAM. | 64 KB mapper, RTC | |
| V-8 | MSX1 | Very compact and minimal MSX1 without a printer port. | 16 KB RAM, one cartridge slot | |

## Casio
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [MX-10](https://www.msx.org/wiki/Casio_MX-10) | MSX1 | Cheap Japanese gaming MSX1 with joystick buttons. | 16 KB RAM | |
| [MX-15](https://www.msx.org/wiki/Casio_MX-15) | MSX1 | European version of the MX-10. | 16 KB RAM | |
| [PV-16](https://www.msx.org/wiki/Casio_PV-16) | MSX1 | Cheap Japanese gaming MSX1. | 16 KB RAM | |
| [PV-7](https://www.msx.org/wiki/Casio_PV-7) | MSX1 | Very cheap Japanese MSX1 (the real machine has 8 KB RAM, the definition gives it 16 KB). | 16 KB RAM | |

## Daewoo
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [CPC-300](https://www.msx.org/wiki/Daewoo_CPC-300) | MSX2 | Korean MSX2 with Hangul support. | 128 KB mapper, RTC, Hangul ROM | |
| CPC-300E | MSX2 | Educational version of the CPC-300. | 64 KB mapper | |
| [CPC-400S](https://www.msx.org/wiki/Daewoo_CPC-400S) | MSX2 | Korean desktop MSX2 with Hangul support and a disk drive. | 128 KB mapper, RTC, Hangul ROM and font (Kanji device), FDC + 1 drive | |
| [CPC-51 Zemmix V](https://www.msx.org/wiki/Daewoo_CPC-51) | MSX1 | Korean MSX1 game console. | 64 KB RAM, one cartridge slot | |
| CPC-61 Zemmix Super V | MSX2 | Korean MSX2 game console. | 64 KB mapper, RTC, one cartridge slot | |
| [DPC-100](https://www.msx.org/wiki/Daewoo_DPC-100) | MSX1 | Basic Korean MSX1 with a Hangul driver. | 16 KB RAM, Hangul ROM | |
| [DPC-180](https://www.msx.org/wiki/Daewoo_DPC-180) | MSX1 | Basic Korean MSX1 with a Hangul driver. | 64 KB RAM, Hangul ROM | |
| [DPC-200](https://www.msx.org/wiki/Daewoo_DPC-200) | MSX1 | Korean MSX1, improved DPC-180. | 64 KB RAM, Hangul ROM | |
| [DPC-200E(FR)](https://www.msx.org/wiki/Daewoo_DPC-200_%28FR%29) | MSX1 | DPC-200 adapted for French-speaking Belgium. | 64 KB RAM | |

## Eurohard
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| Dragon MSX | MSX1 | Rare MSX1 that was never mass-produced (Eurohard closed down). | 64 KB RAM | |

## Fenner
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| SPC-800 | MSX1 | Samsung MSX1 for the European market. | 64 KB RAM | |

## Frael
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| BRUC 100 (v1) | MSX1 | First version of this mostly MSX-compatible Italian machine. | 64 KB RAM, no cartridge slots, not emulated: firmware ROM switch | |
| BRUC 100 (v2) | MSX1 | Second version of this mostly MSX-compatible Italian machine. | 64 KB RAM, not emulated: firmware ROM switch | |

## Fujitsu
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| FM-X | MSX1 | Fujitsu's only MSX; the link to the FM-7 computer is not emulated. | 16 KB RAM, one cartridge slot | |

## General
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| Paxon PCT-55 | MSX1 | MSX1 built into a TV, with a separate keyboard. | 32 KB RAM, one cartridge slot | |

## Goldstar
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [FC-200](https://www.msx.org/wiki/Goldstar_FC-200) | MSX1 | European version of the FC-80. | 64 KB RAM | |
| [FC-80](https://www.msx.org/wiki/Goldstar_FC-80) | MSX1 | First Korean MSX1, with Hangul ROM 1.0. | 64 KB RAM, Hangul ROM | |
| [FC-80U](https://www.msx.org/wiki/Goldstar_FC-80U) | MSX1 | Korean MSX1 with Hangul BIOS ROM 2.0. | 64 KB RAM, Hangul ROM | |
| [GFC-1080](https://www.msx.org/wiki/Goldstar_GFC-1080) | MSX1 | Korean MSX1 with Hangul BASIC and built-in Pasocalc firmware. | 64 KB RAM, Hangul ROM, Pasocalc ROM | |
| [GFC-1080A](https://www.msx.org/wiki/Goldstar_GFC-1080A) | MSX1 | GFC-1080 without the firmware; the definition uses the FC-80U ROMs. | 64 KB RAM, Hangul ROM | |

## Gradiente (Brazil)
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [Expert DD Plus](https://www.msx.org/wiki/Gradiente_Expert_DDPlus) | MSX1 | Brazilian Expert Plus with a built-in 3.5" disk drive. | 64 KB RAM, FDC + 1 drive | |
| [Expert GPC-1](https://www.msx.org/wiki/Gradiente_Expert_GPC-1) | MSX1 | Brazilian MSX1, successor of the XP-800 (Expert 1.1). | 64 KB RAM | |
| [Expert Plus](https://www.msx.org/wiki/Gradiente_Expert_Plus) | MSX1 | Third iteration of the Brazilian Expert. | 64 KB RAM, demo ROM | |
| [Expert XP-800](https://www.msx.org/wiki/Gradiente_Expert_XP-800) | MSX1 | Brazilian MSX1 based on the National CF-3000 (Expert 1.0). | 64 KB RAM | |

## Hitachi
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| MB-H1 | MSX1 | Very compact Japanese MSX1 with built-in software. | 32 KB RAM, firmware ROM | |
| [MB-H2](https://www.msx.org/wiki/Hitachi_MB-H2) | MSX1 | Compact Japanese MSX1 with a built-in data recorder (recorder not emulated). | 64 KB RAM, firmware ROM | |
| MB-H21 | MSX1 | Japanese MSX1 with built-in software (speed control not emulated). | 32 KB RAM, firmware ROM | |
| MB-H3 | MSX2 | First Hitachi MSX2, with only 64 KB VRAM (touch pad not emulated). | 64 KB RAM, RTC, firmware ROM | |
| MB-H50 | MSX1 | Compact MSX1 with an external keyboard (extra LEDs not emulated). | 64 KB RAM | |
| MB-H70 | MSX2 | Expandable MSX2 with two disk drives, based on the Mitsubishi ML-G30 model 2. | 128 KB mapper, RTC, Kanji ROM, FDC + 2 drives, 4 cartridge slots (2 in the core) | |

## JVC
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| HC-7GB | MSX1 | JVC MSX1 for the UK market, with RGB output. | 64 KB RAM | |

## Mitsubishi
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| ML-8000 | MSX1 | The first MSX machine on the market. | 32 KB RAM, one cartridge slot | |
| ML-F110 | MSX1 | Basic Japanese MSX1 with 16 KB RAM. | 16 KB RAM | |
| ML-F120 | MSX1 | Japanese MSX1 with built-in software. | 32 KB RAM, firmware ROM | |
| ML-F80 | MSX1 | Basic MSX1 for the European market. | 64 KB RAM | |
| ML-FX1 | MSX1 | Basic MSX1 for the Spanish market, with a numeric keypad. | 64 KB RAM | |
| ML-G1 (ES) | MSX2 | ML-G10 adapted for the Spanish market. | 64 KB RAM, RTC, MSX Designer ROM | |
| ML-G10 | MSX2 | Mitsubishi's first MSX2, with the built-in Hot Paper software. | 64 KB RAM, RTC, firmware ROM, 3 cartridge slots (2 in the core) | |
| ML-G3 (ES) | MSX2 | Spanish MSX2 with a disk drive and RS-232C. | 128 KB mapper, RTC, FDC + 1 drive, one cartridge slot, not emulated: RS-232C | |
| ML-G30/model 1 | MSX2 | Expandable MSX2 with built-in software and many slots. | 128 KB mapper, RTC, Kanji ROM, FDC + 1 drive, 4 cartridge slots (2 in the core) | |
| ML-G30/model 2 | MSX2 | ML-G30 with two disk drives and RS-232C. | 128 KB mapper, RTC, Kanji ROM, FDC + 2 drives, 3 cartridge slots (2 in the core), not emulated: RS-232C | |

## National
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| CF-1200 | MSX1 | Basic Japanese MSX1, cheaper version of the CF-2700. | 16 KB RAM | |
| CF-2000 | MSX1 | First MSX by Matsushita, basic Japanese MSX1. | 16 KB RAM | |
| CF-2700 | MSX1 | Basic Japanese MSX1. | 32 KB RAM | |
| CF-3000 | MSX1 | Japanese desktop MSX1 with a separate keyboard. | 64 KB RAM | |
| CF-3300 | MSX1 | Japanese desktop MSX1 with a built-in disk drive. | 64 KB RAM, FDC + 1 drive | |
| FS-1300 | MSX1 | Basic Japanese MSX1. | 64 KB RAM | |
| FS-4000 | MSX1 | Japanese word-processing MSX1 with built-in software (built-in printer not emulated). | 64 KB RAM, Kanji ROM, MSX Word ROM | |
| FS-4500 | MSX2 | Japanese word-processing MSX2 with built-in software (built-in printer not emulated). | 64 KB RAM, RTC, Kanji ROM, Word Font, MSX Jusho, MSX Word 1, MSX Word 2 ROM, not emulated: firmware SRAM, Bunsetsu | |
| [FS-4600F](https://www.msx.org/wiki/National_FS-4600F) | MSX2 | Japanese word-processing MSX2 with built-in software, Kanji and a disk drive (built-in printer not emulated). | 128 KB mapper, RTC, Kanji ROM, MSX-Word, FDC + 1 drive | |
| FS-4700F | MSX2 | FS-4500 with a built-in disk drive (built-in printer not emulated). | 64 KB RAM, RTC, Kanji ROM, FDC + 1 drive, Word Font, MSX Jusho, MSX Word 1, MSX Word 2 ROM, not emulated: firmware SRAM, Bunsetsu | |
| FS-5000F2 | MSX2 | Japanese desktop MSX2 with two disk drives. | 128 KB mapper, RTC, Kanji ROM, FDC + 2 drives, Set-Up RTC ROM | |
| FS-5500F1 | MSX2 | Japanese desktop MSX2 with one drive (superimpose and digitizer not emulated). | 64 KB RAM, RTC, Kanji ROM, FDC + 1 drive, Super Impose ROM | |
| FS-5500F2 | MSX2 | National's flagship MSX2 with two drives (superimpose and digitizer not emulated). | 64 KB RAM, RTC, Kanji ROM, FDC + 2 drives, Super Impose ROM | |

## Nikko
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| PC-70100 | MSX1 | Probably a prototype MSX1. | 16 KB RAM, one cartridge slot | |

## OCM
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [1chipMSX](https://www.msx.org/wiki/1chipMSX) | MSX2+ class | FPGA MSX2+-class machine (OCM-PLD) that loads its BIOS from an SD card image; needs `OCM-BIOS.DAT` on a VHD. | V9958, 4 MB mapper, MSX-MUSIC, RTC, Kanji, ESE-SCC and MegaRAM slots (via OSD), MegaSD; no cartridge slots | sim, HW (SofaRun) |

## Olympia
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| PHC-2 | MSX1 | Basic French MSX1 built by Daewoo, based on the DPC-200. | 64 KB RAM | |

## Panasonic
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| CF-2700 (DE) | MSX1 | Basic German MSX1, one of the most common MSX machines in Germany. | 64 KB RAM | |
| CF-2700 (GB) | MSX1 | Basic British MSX1, one of the few European Panasonic MSX machines. | 64 KB RAM | |
| [FS-A1](https://www.msx.org/wiki/Panasonic_FS-A1) | MSX2 | Basic Japanese MSX2 with built-in DESKPAC software. | 64 KB mapper, RTC | |
| [FS-A1F](https://www.msx.org/wiki/Panasonic_FS-A1F) | MSX2 | FS-A1mkII with a built-in disk drive and software. | 64 KB mapper, RTC, Kanji ROM, TC8566AF FDC + 1 drive | sim (disk boot OK) |
| FS-A1FX | MSX2+ | Japanese MSX2+ with a disk drive and built-in software, no MSX-MUSIC. | V9958, 64 KB mapper, RTC, Kanji ROM, TC8566AF FDC + 1 drive, A1 Cockpit ROM, not emulated: 5.37 MHz turbo and firmware SRAM | |
| FS-A1MK2 | MSX2 | Basic Japanese MSX2, the FS-A1 with a numeric keypad. | 64 KB RAM, RTC, A1 Cockpit 1, A1 Cockpit 2, A1 Cockpit 3 ROM | |
| [FS-A1ST](https://www.msx.org/wiki/Panasonic_FS-A1ST) | turbo R | The first MSX turbo R: R800, MSX-MUSIC, PCM, MSX-DOS2, drive and software. R800 runs at about 2x Z80 speed (see [Readme](Readme.md#known-limitations)). | V9958, 256 KB RAM, R800/S1990, MSX-MUSIC, PCM, RTC, Kanji ROM, TC8566AF FDC + 1 drive | sim (MSX BASIC 4.0 / Disk BASIC 2.01) |
| FS-A1WSX | MSX2+ | Successor of the FS-A1WX: MSX2+ with MSX-MUSIC, disk drive and built-in software. | V9958, 64 KB mapper, RTC, MSX-MUSIC, Kanji ROM, TC8566AF FDC + 1 drive, firmware ROM, not emulated: 5.37 MHz turbo and firmware SRAM | |
| FS-A1WX | MSX2+ | Japanese MSX2+ with MSX-MUSIC, disk drive and built-in software. | V9958, 64 KB mapper, RTC, MSX-MUSIC, Kanji ROM, TC8566AF FDC + 1 drive, firmware ROM, not emulated: 5.37 MHz turbo and firmware SRAM | |

## Philips
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [NMS 801](https://www.msx.org/wiki/Philips_NMS_801) | MSX1 | Italian "MSX compatible" MSX1 without cartridge slots. | 64 KB RAM, no cartridge slots | |
| [NMS 8220](https://www.msx.org/wiki/Philips_NMS_8220) | MSX2 | Basic European MSX2 with the built-in drawing program Designer. | 64 KB mapper, RTC, Designer ROM | |
| [NMS 8245](https://www.msx.org/wiki/Philips_NMS_8245) | MSX2 | European MSX2 with a double-sided disk drive. | 128 KB mapper, RTC, FDC + 1 drive | HW (VDP measurements) |
| NMS 8245/16 | MSX2 | Spanish version of the NMS 8245. | 128 KB mapper, RTC, FDC + 1 drive | |
| NMS 8245/19 | MSX2 | French version of the NMS 8245. | 128 KB mapper, RTC, FDC + 1 drive | |
| [NMS 8250](https://www.msx.org/wiki/Philips_NMS_8250) | MSX2 | European desktop MSX2 with a double-sided drive. | 128 KB mapper, RTC, FDC + 1 drive | sim (disk OK) |
| [NMS 8250-16](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Spanish version of the NMS 8250. | 128 KB mapper, RTC, FDC + 1 drive | |
| [NMS 8250-19](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | French version of the NMS 8250. | 128 KB mapper, RTC, FDC + 1 drive | |
| [NMS 8255](https://www.msx.org/wiki/Philips_NMS_8255) | MSX2 | NMS 8250 with two double-sided disk drives. | 128 KB mapper, RTC, FDC + 2 drives | |
| [VG 8000-00](https://www.msx.org/wiki/Philips_VG-8000) | MSX1 | First Philips MSX. | 16 KB RAM | |
| [VG 8010-00](https://www.msx.org/wiki/Philips_VG-8010) | MSX1 | VG 8000 with more RAM. | 32 KB RAM | |
| [VG 8010-19](https://www.msx.org/wiki/Philips_VG-8010) † | MSX1 | French version of the VG 8010. | 32 KB RAM | |
| [VG 8020-00](https://www.msx.org/wiki/Philips_VG-8020) | MSX1 | Basic European MSX1, very popular in the Netherlands. | 64 KB RAM | sim, HW (demo) |
| [VG 8020-19](https://www.msx.org/wiki/Philips_VG-8020) † | MSX1 | French version of the VG 8020. | 64 KB RAM | |
| [VG 8020-20](https://www.msx.org/wiki/Philips_VG-8020) † | MSX1 | Second VG 8020 version with a different memory layout. | 64 KB RAM | |
| [VG 8230](https://www.msx.org/wiki/Philips_VG-8230) | MSX2 | First Philips MSX2 with a single-sided drive. | 64 KB mapper, RTC, FDC + 1 single-sided drive | |
| [VG 8235-00](https://www.msx.org/wiki/Philips_VG-8235) | MSX2 | VG 8230 update with more RAM. Known issue: "Disk offline". | 128 KB mapper, RTC, FDC + 1 single-sided drive | sim (reports "Disk offline") |
| [VG 8235-20](https://www.msx.org/wiki/Philips_VG-8235) † | MSX2 | Updated VG 8235 with MSX-BASIC 2.1. | 128 KB mapper, RTC, FDC + 1 single-sided drive | |
| [VG 8235-39](https://www.msx.org/wiki/Philips_VG-8235) † | MSX2 | French version of the VG 8235. | 128 KB mapper, RTC, FDC + 1 single-sided drive | |
| VG 8235/02 | MSX2 | German version of the VG 8235. | 128 KB mapper, RTC, FDC + 1 single-sided drive | |
| VG 8235/19 | MSX2 | French version of the VG 8235. | 128 KB mapper, RTC, FDC + 1 single-sided drive | |
| [VG 8240](https://www.msx.org/wiki/Philips_VG-8240) | MSX2 | Unreleased prototype MSX2 (about 15 made) with video superimpose. | 64 KB mapper, RTC, FDC + 1 drive | |

## Pioneer
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| PX-7 | MSX1 | Japanese MSX1 with LaserDisc control, stereo PSG and superimpose (not emulated). | 32 KB RAM, not emulated: LaserDisc control | |
| PX-7(UK) | MSX1 | UK version of the PX-7. | 32 KB RAM, not emulated: LaserDisc control | |
| PX-V60 | MSX1 | Simpler PX-7 with LaserDisc control (not emulated). | 32 KB RAM, not emulated: LaserDisc control | |
| UC-V102 | MSX2 | Videodisc controller, internally an MSX2. | 64 KB mapper, RTC, Kanji ROM, FDC + 2 drives, one cartridge slot, not emulated: RS-232C | |

## Samsung
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [SPC-800](https://www.msx.org/wiki/Samsung_SPC-800) | MSX1 | Samsung's only MSX: Korean MSX1 with Hangul BASIC and a built-in speaker. | 64 KB RAM, Hangul ROM | |

## Sanyo
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| MPC-1/Wavy1 | MSX1 | Basic Japanese MSX1 with 16 KB RAM. | 16 KB RAM | |
| MPC-10/Wavy10 | MSX1 | Basic Japanese MSX1 with a light pen controller (not emulated). | 32 KB RAM | |
| MPC-10/Wavy10mkII | MSX1 | MPC-10 with the built-in Light Pen Graphic software (light pen not emulated). | 32 KB RAM, Light Pen Graphic ROM | |
| MPC-100 | MSX1 | Basic MSX1 popular in the UK, British version of the MPC-6. | 64 KB RAM | |
| MPC-11/Wavy11 | MSX1 | High-end Japanese MSX1 (digitizer, superimpose and light pen not emulated). | 32 KB RAM | |
| MPC-2/Wavy2 | MSX1 | Basic Japanese MSX1. | 64 KB RAM | |
| MPC-2300 | MSX2 | Soviet school MSX2 with a Cyrillic keyboard and a network interface (not emulated). | 128 KB mapper, RTC, not emulated: RS-232C | |
| MPC-25FD | MSX2 | Desktop MSX2 with a disk drive and one cartridge slot. | 64 KB RAM, RTC, FDC + 1 drive, one cartridge slot | |
| MPC-25FS | MSX2 | Desktop MSX2 with a single-sided drive and one cartridge slot. | 64 KB RAM, RTC, FDC + 1 single-sided drive, one cartridge slot | |
| MPC-3/Wavy3 | MSX1 | Japanese MSX1 with 16 KB RAM and three cartridge slots. | 16 KB RAM, 3 cartridge slots (2 in the core) | |
| MPC-6/Wavy6 | MSX1 | Basic Japanese MSX1. | 64 KB RAM | |
| MPC-64 | MSX1 | MSX1 for the German market. | 64 KB RAM | |
| PHC-23 | MSX2 | Basic Japanese MSX2 with a JP50on keyboard. | 64 KB RAM, RTC | |
| PHC-23J | MSX2 | Basic Japanese MSX2 with a JIS keyboard. | 64 KB RAM, RTC | |
| PHC-23J(B) | MSX2 | Blue version of the PHC-23J. | 64 KB RAM, RTC | |
| PHC-28L | MSX1 | Basic French MSX1, upgrade of the PHC-28S. | 64 KB RAM | |
| PHC-28P | MSX1 | German version of the PHC-28L. | 64 KB RAM | |
| PHC-28S | MSX1 | Basic French MSX1 with 16 KB RAM. | 16 KB RAM, 3 cartridge slots (2 in the core) | |
| PHC-30N | MSX1 | Japanese MSX1 with a built-in tape drive (not emulated). | 64 KB RAM | |
| PHC-33 | MSX1 | Japanese MSX1 with a built-in high-speed tape drive (not emulated). | 64 KB RAM | |
| PHC-35J | MSX2+ | Basic MSX2+ without MSX-MUSIC. | V9958, 64 KB mapper, RTC, Kanji ROM | |
| PHC-70FD | MSX2+ | Japanese MSX2+ with MSX-MUSIC and a disk drive. | V9958, 64 KB mapper, RTC, MSX-MUSIC, Kanji ROM, TC8566AF FDC + 1 drive, BASIC'n 2.0 ROM | sim |
| PHC-70FD2 | MSX2+ | Japanese MSX2+ with MSX-MUSIC and two disk drives. | V9958, 64 KB mapper, RTC, MSX-MUSIC, Kanji ROM, TC8566AF FDC + 2 drives, BASIC Compiler ROM | |
| PHC-SPC | MSX1 | Basic MSX1 for Japanese schools. | 64 KB RAM | |

## Sharp
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| HB-8000 v1.1 | MSX1 | Original white Hotbit, a Brazilian MSX1. | 64 KB RAM | |
| HB-8000 v1.2 | MSX1 | Black Hotbit with an updated BIOS. | 64 KB RAM | |

## Sony
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| HB-10 | MSX1 | Basic Japanese MSX1 with 16 KB RAM. | 16 KB RAM | |
| HB-101 | MSX1 | Basic MSX1 with the built-in Personal Data Bank. | 16 KB RAM, Personal Data Bank ROM | |
| HB-101P | MSX1 | European HB-101 with the built-in Personal Data Bank. | 32 KB RAM, Personal Data Bank ROM | |
| HB-10P | MSX1 | Basic European MSX1 with a RAM mirroring quirk. | 64 KB RAM, not emulated: RAM mirror in slot 0 | |
| HB-11 | MSX1 | The last Sony MSX1 ("Hit Bit U"), with a Kanji ROM. | 64 KB RAM, Kanji ROM, firmware ROM | |
| [HB-201](https://www.msx.org/wiki/Sony_HB-201) | MSX1 | Japanese MSX1 with the built-in Personal Data Bank. | 64 KB RAM, Personal Data Bank ROM | |
| HB-201P | MSX1 | HB-101P with 64 KB RAM. | 64 KB RAM, Personal Data Bank ROM | |
| HB-20P | MSX1 | Basic Spanish MSX1, like the HB-10P. | 64 KB RAM | |
| HB-501P | MSX1 | European MSX1 with a built-in tape deck (not emulated). | 64 KB RAM | |
| HB-55P | MSX1 | European HB-55 with the built-in Personal Data Bank. | 16 KB RAM, Personal Data Bank ROM | |
| HB-701 | MSX1 | Luxury MSX1 with a separate keyboard and built-in firmware (superimpose and S-Link not emulated). | 64 KB RAM, firmware ROM | |
| HB-701FD | MSX1 | HB-701 with a single-sided disk drive. | 64 KB RAM, FDC + 1 single-sided drive, firmware ROM | |
| HB-75 | MSX1 | Basic Japanese MSX1 with the built-in Personal Data Bank. | 64 KB RAM, Personal Data Bank ROM | |
| HB-75D | MSX1 | German version of the HB-75. | 64 KB RAM, Personal Data Bank ROM | |
| HB-75P | MSX1 | European version of the HB-75; starts into the Personal Data Bank. | 64 KB RAM, Personal Data Bank ROM | sim (starts into Personal Data Bank) |
| [HB-F1](https://www.msx.org/wiki/Sony_HB-F1) | MSX2 | Japanese MSX2 with built-in software (speed controller not emulated). | 64 KB mapper, RTC, firmware ROMs | |
| HB-F1II | MSX2 | Cost-reduced HB-F1 with built-in software (speed controller not emulated). | 64 KB RAM, RTC, firmware ROM | |
| HB-F1XD | MSX2 | Japanese MSX2 with a built-in disk drive (speed controller not emulated). | 64 KB RAM, RTC, FDC + 1 drive | |
| [HB-F1XDmk2](https://www.msx.org/wiki/Sony_HB-F1XDmk2) | MSX2 | Cost-reduced HB-F1XD: Japanese MSX2 with a built-in disk drive. | 64 KB mapper, RTC, FDC + 1 drive | |
| [HB-F5](https://www.msx.org/wiki/Sony_HB-F5) | MSX2 | Sony's first MSX2 with built-in Personal Databank software. | 64 KB RAM, RTC, firmware ROM | |
| HB-F500 | MSX2 | First Sony desktop MSX2 with a double-sided drive; unusual memory layout. | 64 KB RAM, RTC, Kanji ROM, FDC + 1 drive | |
| HB-F500 (v2) | MSX2 | Second HB-F500 version with a simpler memory layout. | 64 KB RAM, RTC, Kanji ROM, FDC + 1 drive | |
| HB-F500P | MSX2 | European HB-F500 with three cartridge slots; unusual memory layout. | 64 KB RAM, RTC, FDC + 1 drive, 3 cartridge slots (2 in the core) | |
| HB-F700D | MSX2 | German version of the HB-F700. | 256 KB mapper, RTC, FDC + 1 drive | |
| HB-F700F | MSX2 | French version of the HB-F700. | 256 KB mapper, RTC, FDC + 1 drive | |
| HB-F700P | MSX2 | European MSX2 with 256 KB RAM and a double-sided drive. | 256 KB mapper, RTC, FDC + 1 drive | sim |
| HB-F700S | MSX2 | Spanish version of the HB-F700. | 256 KB mapper, RTC, FDC + 1 drive | |
| HB-F900 | MSX2 | Professional Japanese MSX2 with two drives (superimpose and digitizer not emulated). | 256 KB mapper, RTC, Kanji ROM, FDC + 2 drives, HB-F900 Video Utility 1.10 ROM | |
| HB-F9P | MSX2 | European MSX2 with the built-in Memovision software. | 128 KB mapper, RTC, Memovision 2, Memovision 1 ROM | |
| HB-F9P Russian | MSX2 | Very rare Russian version of the HB-F9P. | 128 KB mapper, RTC | |
| HB-F9S | MSX2 | Spanish version of the HB-F9P. | 128 KB mapper, RTC, Memovision 2, Memovision 1/1, Memovision 1/2 ROM | |
| HB-G900AP | MSX2 | Professional European MSX2 with 512 KB RAM, disk drive and video utility (superimpose not emulated). | 512 KB mapper, RTC, FDC + 1 drive, Video Utility ROM, not emulated: RS-232C | |
| HB-G900D | MSX2 | German version of the HB-G900P. | 64 KB RAM, RTC, FDC + 1 drive, Video Utility ROM, not emulated: RS-232C | |
| HB-G900P | MSX2 | Professional European MSX2 with a disk drive and video utility (superimpose not emulated). | 64 KB RAM, RTC, FDC + 1 drive, Video Utility ROM, not emulated: RS-232C | |
| HB-T600 | MSX2 | Japanese stock-trading terminal (MSX2) with a disk drive and modem. | 128 KB mapper, RTC, Kanji ROM, FDC + 1 drive, firmware ROM, not emulated: modem | |

## Spectravideo
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| SVI-728 | MSX1 | Basic MSX1 popular in many European countries. | 64 KB RAM | |
| SVI-728 (DK) | MSX1 | Danish version of the SVI-728. | 64 KB RAM | |
| SVI-728 (ES) | MSX1 | Spanish version of the SVI-728. | 64 KB RAM | |
| SVI-728 (SE) | MSX1 | Swedish version of the SVI-728. | 64 KB RAM | |
| SVI-738 X'PRESS | MSX1 (V9938) | Complete MSX1 with a V9938, RS-232C and a single-sided drive. | V9938, 64 KB RAM, FDC + 1 single-sided drive, one cartridge slot, not emulated: RS-232C | |
| SVI-738 X'PRESS (DE) | MSX1 (V9938) | SVI-738 for the German market. | V9938, 64 KB RAM, FDC + 1 single-sided drive, one cartridge slot, not emulated: RS-232C | |
| SVI-738 X'PRESS (DK) | MSX1 (V9938) | SVI-738 for the Danish and Norwegian market. | V9938, 64 KB RAM, FDC + 1 single-sided drive, one cartridge slot, not emulated: RS-232C | |
| SVI-738 X'PRESS (PL) | MSX1 (V9938) | SVI-738 for the Polish market. | V9938, 64 KB RAM, FDC + 1 single-sided drive, one cartridge slot, not emulated: RS-232C | |
| SVI-738 X'PRESS (SE) | MSX1 (V9938) | SVI-738 for the Swedish and Finnish market. | V9938, 64 KB RAM, FDC + 1 single-sided drive, one cartridge slot, not emulated: RS-232C | |

## Talent
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| DPC-200 | MSX1 | Daewoo DPC-200 localized for Argentina. | 64 KB RAM | |
| TPC-310 | MSX2 | The most advanced Argentinian MSX: MSX2 with turbo BASIC and built-in programs (PAL). | 128 KB mapper, RTC, Turbo BASIC, Accessories ROM | |

## Toshiba
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| FS-TM1 | MSX2 | Italian MSX2 based on the Panasonic FS-A1(F). | 64 KB mapper, RTC, Utility Part 1, Utility Part 2 ROM | |
| HX-10 | MSX1 | Very common basic MSX1 in the UK. | 64 KB RAM | |
| HX-10D | MSX1 | First Toshiba MSX. | 64 KB RAM | |
| HX-20E | MSX1 | MSX1 sold in Spain, with a RAM disk and an English word processor. | 64 KB RAM, Word Processor ROM | |
| HX-21 | MSX1 | Japanese MSX1 with a RAM disk, stereo PSG and word processor. | 64 KB RAM, Software Utility ROM | |
| HX-22 | MSX1 | HX-21 with RS-232C. | 64 KB RAM, Software Utility ROM, not emulated: RS-232C | |
| HX-22I | MSX1 | Italian MSX1 with a built-in word processor. | 64 KB RAM, Word Processor ROM, not emulated: RS-232C | |
| HX-23 | MSX2 | Rare Japanese MSX2 with stereo PSG, 64 KB VRAM and a word processor. | 64 KB RAM, RTC, Japanese Word Processor part2 ROM | |
| HX-23F | MSX2 | HX-23 with RS-232C and 128 KB VRAM. | 64 KB RAM, RTC, Japanese Word Processor part2 ROM, not emulated: RS-232C | |
| HX-32 | MSX1 | Japanese MSX1 with a RAM disk, Kanji ROM, stereo PSG and word processor. | 64 KB RAM, Kanji ROM, Software Utility ROM | |
| HX-33 | MSX2 | Japanese MSX2 with stereo PSG and a built-in word processor. | 64 KB mapper, RTC, Kanji ROM, not emulated: RS-232C, word processor ROM (TCX-200x) | |
| HX-51I | MSX1 | Basic European MSX1 (Italy, Spain); its memory layout crashes some badly written software. | 64 KB RAM | |

## Victor
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| HC-7 | MSX1 | First Victor MSX1, with built-in software (superimpose not emulated). | 64 KB RAM, firmware ROM | |
| HC-80 | MSX2 | Japanese MSX2 with built-in software. | 64 KB RAM, RTC, firmware ROM | |

## Yamaha
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| AX150 | MSX1 | Arabic MSX1 with built-in software. | 64 KB RAM | |
| AX200 | MSX1 (V9938) | Arabic MSX1 with built-in software and the SFG-05 module. | V9938, 64 KB RAM, SFG-05 (OPM + YM2148 MIDI) | |
| AX350II | MSX2 | Arabic MSX2 sold by Al Alamiah, with a disk drive and built-in software. | 128 KB mapper, RTC, FDC + 1 drive, Sakhr Word Processor, Sakhr Files fragment, Painter ROM | |
| [AX350IIF](https://www.msx.org/wiki/Sakhr_AX-350II) † | MSX2 | Arabic/French MSX2 made by Yamaha for Al Alamiah, with a drive and built-in software. | 128 KB mapper, RTC, Arabic ROM, word processor, Painter, FDC + 1 drive | |
| AX500 | MSX2 | Arabic MSX2 sold by Al Alamiah, with 256 KB RAM, two drives and built-in software. | 256 KB mapper, RTC, FDC + 2 drives, Arabic BASIC, Arabic Word Processor, Sakhr Files ROM, 3 cartridge slots (2 in the core) | |
| [CX11](https://www.msx.org/wiki/Yamaha_CX11) | MSX1 (V9938) | Japanese music MSX1 with a V9938 and the SFG-01 FM unit. | V9938, 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5F](https://www.msx.org/wiki/Yamaha_CX5F) | MSX1 | Japanese music computer with the built-in SFG-01. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5M](https://www.msx.org/wiki/Yamaha_CX5M) | MSX1 | International synthesizer MSX1 with the built-in SFG-01. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5MII](https://www.msx.org/wiki/Yamaha_CX5MII) | MSX1 (V9938) | CX5M successor: MSX1 with a V9938 and the SFG-05. | V9938, 64 KB RAM, SFG-05 (OPM + YM2148 MIDI), 80-column sub ROM, FM Voicing Program II | |
| [CX5MII/128](https://www.msx.org/wiki/Yamaha_CX5MII) † | MSX1 (V9938) | CX5MII with 128 KB RAM. | V9938, 128 KB mapper, SFG-05, sub ROM, FM Voicing Program II | |
| [CX5MU](https://www.msx.org/wiki/Yamaha_CX5M) † | MSX1 | US version of the CX5M with its own BIOS. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| CX7/128 | MSX2 | Music computer like the CX7M/128, but without the SFG-05. | 128 KB mapper, RTC, 3 cartridge slots (2 in the core) | |
| CX7M/128 | MSX2 | Japanese music MSX2 with the built-in SFG-05. | 128 KB mapper, RTC, SFG-05 (OPM + YM2148 MIDI), FM Voicing Program II ROM | |
| SX-100 | MSX1 | Game-oriented MSX1 with 32 KB RAM. | 32 KB RAM, one cartridge slot | |
| YIS-503 | MSX1 | Like the CX5F, but without the sound module. | 32 KB RAM, 3 cartridge slots (2 in the core) | |
| YIS-503F | MSX1 | European MSX1 like the CX5M, but without the SFG module. | 32 KB RAM, 3 cartridge slots (2 in the core) | |
| YIS-503II | MSX1 (V9938) | Japanese MSX1 with a V9938. | V9938, 64 KB RAM | |
| YIS-503IIIR | MSX2 | Soviet classroom MSX2 (student station); network module not emulated. | 128 KB mapper, RTC, CP/M ROM | |
| YIS-503IIR | MSX1 (V9938) | Soviet school version of the YIS-503II; network module not emulated. | V9938, 64 KB RAM | |
| YIS-604/128 | MSX2 | Home computer identical to the CX7M/128. | 128 KB mapper, RTC | |
| YIS-805/128R2 | MSX2 | Soviet classroom MSX2 (teacher station) with The Painter; network module not emulated. | 128 KB mapper, RTC, FDC + 2 drives, Painter ROM | |
| YIS-805/256 | MSX2 | Japanese MSX2 with 256 KB RAM, The Painter and a word processor (not emulated). | 256 KB mapper, RTC, Kanji ROM, FDC + 2 drives, The Painter ROM, 3 cartridge slots (2 in the core), not emulated: RS-232C, word processor ROM (SKW-01) | |

## Yashica
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| YC-64 | MSX1 | Basic European MSX1, the only MSX by Yashica (Kyocera). | 64 KB RAM, one cartridge slot | |

## Yeno
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| DPC-64 | MSX1 | Rebranded Daewoo DPC-200 for the French-speaking market. | 64 KB RAM | |

## Not supported

These openMSX machines need hardware the core does not have yet:

| Model | Missing |
|---|---|
| Canon V-30F | Canon floppy controller wiring (MB8877A, registers 7FF8-7FFC) |
| Sanyo PHC-77 | Sanyo floppy controller wiring |
| Toshiba HX-34 | Toshiba floppy controller wiring (registers 7FF0-7FF7) |
| Victor HC-90A, HC-95A | Victor floppy controller wiring, system control register 7FFD |
| Panasonic FS-A1FM | FS-A1FM firmware and modem mappers |
| Sony HB-F1XDJ, HB-F1XV | Halnote mapper (MSX-JE firmware) |
| Panasonic FS-A1GT | 4 MB firmware ROM (the pack format holds up to 4080 KB per ROM), MSX-MIDI |
| Aucnet NIA-2001 | MSX-DOS2 ROM mapper |
