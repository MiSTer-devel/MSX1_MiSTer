# Supported MSX Models

**English** | [Česky](ComputersModel.cs.md)

Back to the [Readme](Readme.md).

The core is not tied to one computer: each machine below is a definition (an XML file in `tools/CreateMSXpack/Computer/`) that is turned into a ROM PACK (`.msx`). There are **66 definitions** from 16 manufacturers:

| Generation | Count |
|---|---|
| MSX1 | 43 (40 with a TMS99xx VDP, 3 Yamaha machines with a V9938 and an MSX1 BIOS) |
| MSX2 | 21 |
| MSX turbo R | 1 |
| 1chipMSX / OCM (MSX2+ class) | 1 |

No factory MSX2+ machine is defined.

**ROM dumps are not included.** You supply the ROM files and build the packs yourself with [CreateMSXpack](tools/CreateMSXpack/README.md) (see also [Tools](tools/README.md)). Only the two C-BIOS machines and the 1chipMSX can be built without your own ROMs. The **1chipMSX** also needs `OCM-BIOS.DAT` as the first file of a FAT16 SD card image (VHD).

Notes on the tables:
- Models are linked to [msx.org](https://www.msx.org/). A link marked **†** leads to a page that covers the model as a variant (family page). Models without a link have no msx.org page.
- **Boot test** lists what has been recorded: *sim* = boot in simulation, *HW* = used on real hardware. An empty cell means that no test result is recorded, not that the machine fails.
- Disk drives: *FDC* = built-in floppy disk controller. The machine's own FDC always wins over an FDC cartridge.

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

## C-BIOS (open-source firmware, not a real product)
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| MSX - C-BIOS | MSX1 | Generic MSX1 running the free C-BIOS; the ROMs ship in the repository. | 64 KB RAM | |
| MSX2 - C-BIOS | MSX2 | Generic MSX2 running the free C-BIOS; the ROMs ship in the repository. | 128 KB mapper, RTC | |

## Canon
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [V-20](https://www.msx.org/wiki/Canon_V-20) | MSX1 | Canon's original Japanese MSX1. | 64 KB RAM | |
| [V-20E](https://www.msx.org/wiki/Canon_V-20_%28EU%29) | MSX1 | European adaptation of the V-20. | 64 KB RAM | |
| [V-20F](https://www.msx.org/wiki/Canon_V-20_%28FR%29) | MSX1 | French (AZERTY) adaptation of the V-20. | 64 KB RAM | |
| V-20G | MSX1 | Regional variant of the European V-20 with its own BIOS dump. | 64 KB RAM | |
| V-20S | MSX1 | Regional variant of the European V-20 with its own BIOS dump. | 64 KB RAM | |

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
| [CPC-400S](https://www.msx.org/wiki/Daewoo_CPC-400S) | MSX2 | Korean desktop MSX2 with Hangul support and a disk drive. | 128 KB mapper, RTC, Hangul ROM and font (Kanji device), FDC + 1 drive | |
| [CPC-51 Zemmix V](https://www.msx.org/wiki/Daewoo_CPC-51) | MSX1 | Korean MSX1 game console. | 64 KB RAM, one cartridge slot | |
| [DPC-100](https://www.msx.org/wiki/Daewoo_DPC-100) | MSX1 | Basic Korean MSX1 with a Hangul driver. | 16 KB RAM, Hangul ROM | |
| [DPC-180](https://www.msx.org/wiki/Daewoo_DPC-180) | MSX1 | Basic Korean MSX1 with a Hangul driver. | 64 KB RAM, Hangul ROM | |
| [DPC-200](https://www.msx.org/wiki/Daewoo_DPC-200) | MSX1 | Korean MSX1, improved DPC-180. | 64 KB RAM, Hangul ROM | |
| [DPC-200E(FR)](https://www.msx.org/wiki/Daewoo_DPC-200_%28FR%29) | MSX1 | DPC-200 adapted for French-speaking Belgium. | 64 KB RAM | |

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
| [MB-H2](https://www.msx.org/wiki/Hitachi_MB-H2) | MSX1 | Compact Japanese MSX1 with a built-in data recorder (recorder not emulated). | 64 KB RAM, firmware ROM | |

## National
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [FS-4600F](https://www.msx.org/wiki/National_FS-4600F) | MSX2 | Japanese word-processing MSX2 with built-in software, Kanji and a disk drive (built-in printer not emulated). | 128 KB mapper, RTC, Kanji ROM, MSX-Word, FDC + 1 drive | |

## OCM
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [1chipMSX](https://www.msx.org/wiki/1chipMSX) | MSX2+ class | FPGA MSX2+-class machine (OCM-PLD) that loads its BIOS from an SD card image; needs `OCM-BIOS.DAT` on a VHD. | V9958, 4 MB mapper, MSX-MUSIC, RTC, Kanji, ESE-SCC and MegaRAM slots (via OSD), MegaSD; no cartridge slots | sim, HW (SofaRun) |

## Panasonic
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [FS-A1](https://www.msx.org/wiki/Panasonic_FS-A1) | MSX2 | Basic Japanese MSX2 with built-in DESKPAC software. | 64 KB mapper, RTC | |
| [FS-A1F](https://www.msx.org/wiki/Panasonic_FS-A1F) | MSX2 | FS-A1mkII with a built-in disk drive and software. | 64 KB mapper, RTC, Kanji ROM, TC8566AF FDC + 1 drive | sim (disk boot OK) |
| [FS-A1ST](https://www.msx.org/wiki/Panasonic_FS-A1ST) | turbo R | The first MSX turbo R: R800, MSX-MUSIC, PCM, MSX-DOS2, drive and software. R800 runs at about 2x Z80 speed (see [Readme](Readme.md#known-limitations)). | V9958, 256 KB RAM, R800/S1990, MSX-MUSIC, PCM, RTC, Kanji ROM, TC8566AF FDC + 1 drive | sim (MSX BASIC 4.0 / Disk BASIC 2.01) |

## Philips
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [NMS 801](https://www.msx.org/wiki/Philips_NMS_801) | MSX1 | Italian "MSX compatible" MSX1 without cartridge slots. | 64 KB RAM, no cartridge slots | |
| [NMS 8220](https://www.msx.org/wiki/Philips_NMS_8220) | MSX2 | Basic European MSX2 with the built-in drawing program Designer. | 64 KB mapper, RTC, Designer ROM | |
| [NMS 8245](https://www.msx.org/wiki/Philips_NMS_8245) | MSX2 | European MSX2 with a double-sided disk drive. | 128 KB mapper, RTC, FDC + 1 drive | HW (VDP measurements) |
| [NMS 8250](https://www.msx.org/wiki/Philips_NMS_8250) | MSX2 | European desktop MSX2 with a double-sided drive. | 128 KB mapper, RTC, FDC + 1 drive | sim (disk OK) |
| [NMS 8250-16](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Spanish version of the NMS 8250. | 128 KB mapper, RTC, FDC + 1 drive | |
| [NMS 8250-19](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | French version of the NMS 8250. | 128 KB mapper, RTC, FDC + 1 drive | |
| [NMS 8255](https://www.msx.org/wiki/Philips_NMS_8255) | MSX2 | NMS 8250 with two double-sided disk drives (the only machine with two drives). | 128 KB mapper, RTC, FDC + 2 drives | |
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
| [VG 8240](https://www.msx.org/wiki/Philips_VG-8240) | MSX2 | Unreleased prototype MSX2 (about 15 made) with video superimpose. | 64 KB mapper, RTC, FDC + 1 drive | |

## Samsung
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [SPC-800](https://www.msx.org/wiki/Samsung_SPC-800) | MSX1 | Samsung's only MSX: Korean MSX1 with Hangul BASIC and a built-in speaker. | 64 KB RAM, Hangul ROM | |

## Sony
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [HB-201](https://www.msx.org/wiki/Sony_HB-201) | MSX1 | Japanese MSX1 with the built-in Personal Data Bank. | 64 KB RAM, Personal Data Bank ROM | |
| [HB-F1](https://www.msx.org/wiki/Sony_HB-F1) | MSX2 | Japanese MSX2 with built-in software (speed controller not emulated). | 64 KB mapper, RTC, firmware ROMs | |
| [HB-F1XDmk2](https://www.msx.org/wiki/Sony_HB-F1XDmk2) | MSX2 | Cost-reduced HB-F1XD: Japanese MSX2 with a built-in disk drive. | 64 KB mapper, RTC, FDC + 1 drive | |
| [HB-F5](https://www.msx.org/wiki/Sony_HB-F5) | MSX2 | Sony's first MSX2 with built-in Personal Databank software. | 64 KB RAM, RTC, firmware ROM | |

## Yamaha
| Model | Gen | Description | Key built-in hardware | Boot test |
|---|---|---|---|---|
| [AX350IIF](https://www.msx.org/wiki/Sakhr_AX-350II) † | MSX2 | Arabic/French MSX2 made by Yamaha for Al Alamiah, with a drive and built-in software. | 128 KB mapper, RTC, Arabic ROM, word processor, Painter, FDC + 1 drive | |
| [CX11](https://www.msx.org/wiki/Yamaha_CX11) | MSX1 (V9938) | Japanese music MSX1 with a V9938 and the SFG-01 FM unit. | V9938, 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5F](https://www.msx.org/wiki/Yamaha_CX5F) | MSX1 | Japanese music computer with the built-in SFG-01. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5M](https://www.msx.org/wiki/Yamaha_CX5M) | MSX1 | International synthesizer MSX1 with the built-in SFG-01. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
| [CX5MII](https://www.msx.org/wiki/Yamaha_CX5MII) | MSX1 (V9938) | CX5M successor: MSX1 with a V9938 and the SFG-05. | V9938, 64 KB RAM, SFG-05 (OPM + YM2148 MIDI), 80-column sub ROM, FM Voicing Program II | |
| [CX5MII/128](https://www.msx.org/wiki/Yamaha_CX5MII) † | MSX1 (V9938) | CX5MII with 128 KB RAM. | V9938, 128 KB mapper, SFG-05, sub ROM, FM Voicing Program II | |
| [CX5MU](https://www.msx.org/wiki/Yamaha_CX5M) † | MSX1 | US version of the CX5M with its own BIOS. | 32 KB RAM, SFG-01 (OPM + YM2148 MIDI) | |
