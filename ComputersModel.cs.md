# Podporované modely MSX

[English](ComputersModel.md) | **Česky**

Zpět na [Readme](Readme.cs.md).

Jádro není svázáno s jedním počítačem: každý stroj níže je definice (soubor XML v `tools/CreateMSXpack/Computer/`), která se převede na ROM PACK (`.msx`). Je zde **66 definic** od 16 výrobců:

| Generace | Počet |
|---|---|
| MSX1 | 43 (40 s VDP TMS99xx, 3 stroje Yamaha s V9938 a BIOSem MSX1) |
| MSX2 | 21 |
| MSX turbo R | 1 |
| 1chipMSX / OCM (třída MSX2+) | 1 |

Žádný tovární stroj MSX2+ definován není.

**Obrazy ROM nejsou součástí.** ROM si dodáte sami a balíčky si sestavíte nástrojem [CreateMSXpack](tools/CreateMSXpack/README.cs.md) (viz též [Nástroje](tools/README.cs.md)). Bez vlastních ROM lze sestavit jen oba stroje C-BIOS a 1chipMSX. **1chipMSX** navíc potřebuje `OCM-BIOS.DAT` jako první soubor v obrazu SD karty (VHD) s FAT16.

Poznámky k tabulkám:
- Modely jsou odkazovány na [msx.org](https://www.msx.org/). Odkaz označený **†** vede na stránku, která model pokrývá jako variantu (stránka celé rodiny). Modely bez odkazu stránku na msx.org nemají.
- **Boot test** uvádí, co je zaznamenáno: *sim* = start v simulaci, *HW* = použito na skutečném hardware. Prázdná buňka znamená, že výsledek testu není zaznamenán, ne že stroj nefunguje.
- Disky: *FDC* = vestavěný řadič disket. FDC stroje má vždy přednost před cartridge FDC.

Známý problém: **Philips VG 8235-00** v simulaci hlásí „Disk offline“ (předpokládaná příčina: jednostranná mechanika s obrazem 720 KB). Na hardware neověřeno.

## AVT
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [DPC-200](https://www.msx.org/wiki/AVT_DPC-200) | MSX1 | Verze Daewoo DPC-200 pro evropský trh, základní MSX1. | 64 KB RAM | |

## Al Alamiah (Sakhr)
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [AX170](https://www.msx.org/wiki/Sakhr_AX-170) | MSX1 | Rozšířený arabský MSX1 s vestavěnou arabskou ROM. | 64 KB RAM, arabská ROM | |
| [AX230](https://www.msx.org/wiki/Sakhr_AX-230) | MSX1 | Arabský MSX1 s vestavěnými hrami. | 64 KB RAM, arabská ROM, ROM s hrami, jeden slot pro cartridge | |

## C-BIOS (open-source firmware, ne skutečný výrobek)
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| MSX - C-BIOS | MSX1 | Obecný MSX1 se svobodným C-BIOSem; ROM jsou v repozitáři. | 64 KB RAM | |
| MSX2 - C-BIOS | MSX2 | Obecný MSX2 se svobodným C-BIOSem; ROM jsou v repozitáři. | mapper 128 KB, RTC | |

## Canon
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [V-20](https://www.msx.org/wiki/Canon_V-20) | MSX1 | Původní japonský MSX1 Canon. | 64 KB RAM | |
| [V-20E](https://www.msx.org/wiki/Canon_V-20_%28EU%29) | MSX1 | Evropská úprava V-20. | 64 KB RAM | |
| [V-20F](https://www.msx.org/wiki/Canon_V-20_%28FR%29) | MSX1 | Francouzská úprava V-20 (AZERTY). | 64 KB RAM | |
| V-20G | MSX1 | Regionální varianta evropského V-20 s vlastním dumpem BIOSu. | 64 KB RAM | |
| V-20S | MSX1 | Regionální varianta evropského V-20 s vlastním dumpem BIOSu. | 64 KB RAM | |

## Casio
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [MX-10](https://www.msx.org/wiki/Casio_MX-10) | MSX1 | Levný japonský herní MSX1 s tlačítky joysticku. | 16 KB RAM | |
| [MX-15](https://www.msx.org/wiki/Casio_MX-15) | MSX1 | Evropská verze MX-10. | 16 KB RAM | |
| [PV-16](https://www.msx.org/wiki/Casio_PV-16) | MSX1 | Levný japonský herní MSX1. | 16 KB RAM | |
| [PV-7](https://www.msx.org/wiki/Casio_PV-7) | MSX1 | Velmi levný japonský MSX1 (skutečný stroj má 8 KB RAM, definice mu dává 16 KB). | 16 KB RAM | |

## Daewoo
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [CPC-300](https://www.msx.org/wiki/Daewoo_CPC-300) | MSX2 | Korejský MSX2 s podporou hangulu. | mapper 128 KB, RTC, ROM hangul | |
| [CPC-400S](https://www.msx.org/wiki/Daewoo_CPC-400S) | MSX2 | Korejský stolní MSX2 s podporou hangulu a disketovou mechanikou. | mapper 128 KB, RTC, ROM a font hangul (zařízení Kanji), FDC + 1 mechanika | |
| [CPC-51 Zemmix V](https://www.msx.org/wiki/Daewoo_CPC-51) | MSX1 | Korejská herní konzole MSX1. | 64 KB RAM, jeden slot pro cartridge | |
| [DPC-100](https://www.msx.org/wiki/Daewoo_DPC-100) | MSX1 | Základní korejský MSX1 s ovladačem hangulu. | 16 KB RAM, ROM hangul | |
| [DPC-180](https://www.msx.org/wiki/Daewoo_DPC-180) | MSX1 | Základní korejský MSX1 s ovladačem hangulu. | 64 KB RAM, ROM hangul | |
| [DPC-200](https://www.msx.org/wiki/Daewoo_DPC-200) | MSX1 | Korejský MSX1, vylepšený DPC-180. | 64 KB RAM, ROM hangul | |
| [DPC-200E(FR)](https://www.msx.org/wiki/Daewoo_DPC-200_%28FR%29) | MSX1 | DPC-200 upravený pro frankofonní Belgii. | 64 KB RAM | |

## Goldstar
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [FC-200](https://www.msx.org/wiki/Goldstar_FC-200) | MSX1 | Evropská verze FC-80. | 64 KB RAM | |
| [FC-80](https://www.msx.org/wiki/Goldstar_FC-80) | MSX1 | První korejský MSX1, s ROM hangul 1.0. | 64 KB RAM, ROM hangul | |
| [FC-80U](https://www.msx.org/wiki/Goldstar_FC-80U) | MSX1 | Korejský MSX1 s BIOSem hangul 2.0. | 64 KB RAM, ROM hangul | |
| [GFC-1080](https://www.msx.org/wiki/Goldstar_GFC-1080) | MSX1 | Korejský MSX1 s hangulským BASICem a vestavěným firmware Pasocalc. | 64 KB RAM, ROM hangul, ROM Pasocalc | |
| [GFC-1080A](https://www.msx.org/wiki/Goldstar_GFC-1080A) | MSX1 | GFC-1080 bez firmware; definice používá ROM z FC-80U. | 64 KB RAM, ROM hangul | |

## Gradiente (Brazílie)
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [Expert DD Plus](https://www.msx.org/wiki/Gradiente_Expert_DDPlus) | MSX1 | Brazilský Expert Plus s vestavěnou 3,5" disketovou mechanikou. | 64 KB RAM, FDC + 1 mechanika | |
| [Expert GPC-1](https://www.msx.org/wiki/Gradiente_Expert_GPC-1) | MSX1 | Brazilský MSX1, nástupce XP-800 (Expert 1.1). | 64 KB RAM | |
| [Expert Plus](https://www.msx.org/wiki/Gradiente_Expert_Plus) | MSX1 | Třetí iterace brazilského Expertu. | 64 KB RAM, demo ROM | |
| [Expert XP-800](https://www.msx.org/wiki/Gradiente_Expert_XP-800) | MSX1 | Brazilský MSX1 založený na National CF-3000 (Expert 1.0). | 64 KB RAM | |

## Hitachi
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [MB-H2](https://www.msx.org/wiki/Hitachi_MB-H2) | MSX1 | Kompaktní japonský MSX1 s vestavěným magnetofonem (magnetofon není emulován). | 64 KB RAM, ROM firmware | |

## National
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [FS-4600F](https://www.msx.org/wiki/National_FS-4600F) | MSX2 | Japonský MSX2 pro zpracování textu s vestavěným softwarem, kanji a disketovou mechanikou (vestavěná tiskárna není emulována). | mapper 128 KB, RTC, Kanji ROM, MSX-Word, FDC + 1 mechanika | |

## OCM
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [1chipMSX](https://www.msx.org/wiki/1chipMSX) | třída MSX2+ | FPGA stroj třídy MSX2+ (OCM-PLD), který zavádí BIOS z obrazu SD karty; potřebuje `OCM-BIOS.DAT` na VHD. | V9958, mapper 4 MB, MSX-MUSIC, RTC, Kanji, sloty ESE-SCC a MegaRAM (volba v OSD), MegaSD; bez slotů pro cartridge | sim, HW (SofaRun) |

## Panasonic
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [FS-A1](https://www.msx.org/wiki/Panasonic_FS-A1) | MSX2 | Základní japonský MSX2 s vestavěným softwarem DESKPAC. | mapper 64 KB, RTC | |
| [FS-A1F](https://www.msx.org/wiki/Panasonic_FS-A1F) | MSX2 | FS-A1mkII s vestavěnou disketovou mechanikou a softwarem. | mapper 64 KB, RTC, Kanji ROM, FDC TC8566AF + 1 mechanika | sim (start z disku OK) |
| [FS-A1ST](https://www.msx.org/wiki/Panasonic_FS-A1ST) | turbo R | První MSX turbo R: R800, MSX-MUSIC, PCM, MSX-DOS2, mechanika a software. R800 běží zhruba 2x rychleji než Z80 (viz [Readme](Readme.cs.md#známá-omezení)). | V9958, 256 KB RAM, R800/S1990, MSX-MUSIC, PCM, RTC, Kanji ROM, FDC TC8566AF + 1 mechanika | sim (MSX BASIC 4.0 / Disk BASIC 2.01) |

## Philips
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [NMS 801](https://www.msx.org/wiki/Philips_NMS_801) | MSX1 | Italský „MSX compatible“ MSX1 bez slotů pro cartridge. | 64 KB RAM, bez slotů pro cartridge | |
| [NMS 8220](https://www.msx.org/wiki/Philips_NMS_8220) | MSX2 | Základní evropský MSX2 s vestavěným kreslicím programem Designer. | mapper 64 KB, RTC, ROM Designer | |
| [NMS 8245](https://www.msx.org/wiki/Philips_NMS_8245) | MSX2 | Evropský MSX2 s oboustrannou disketovou mechanikou. | mapper 128 KB, RTC, FDC + 1 mechanika | HW (měření VDP) |
| [NMS 8250](https://www.msx.org/wiki/Philips_NMS_8250) | MSX2 | Evropský stolní MSX2 s oboustrannou mechanikou. | mapper 128 KB, RTC, FDC + 1 mechanika | sim (disk OK) |
| [NMS 8250-16](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Španělská verze NMS 8250. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| [NMS 8250-19](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Francouzská verze NMS 8250. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| [NMS 8255](https://www.msx.org/wiki/Philips_NMS_8255) | MSX2 | NMS 8250 se dvěma oboustrannými mechanikami (jediný stroj se dvěma mechanikami). | mapper 128 KB, RTC, FDC + 2 mechaniky | |
| [VG 8000-00](https://www.msx.org/wiki/Philips_VG-8000) | MSX1 | První MSX od Philipsu. | 16 KB RAM | |
| [VG 8010-00](https://www.msx.org/wiki/Philips_VG-8010) | MSX1 | VG 8000 s větší RAM. | 32 KB RAM | |
| [VG 8010-19](https://www.msx.org/wiki/Philips_VG-8010) † | MSX1 | Francouzská verze VG 8010. | 32 KB RAM | |
| [VG 8020-00](https://www.msx.org/wiki/Philips_VG-8020) | MSX1 | Základní evropský MSX1, velmi oblíbený v Nizozemsku. | 64 KB RAM | sim, HW (demo) |
| [VG 8020-19](https://www.msx.org/wiki/Philips_VG-8020) † | MSX1 | Francouzská verze VG 8020. | 64 KB RAM | |
| [VG 8020-20](https://www.msx.org/wiki/Philips_VG-8020) † | MSX1 | Druhá verze VG 8020 s jiným rozložením paměti. | 64 KB RAM | |
| [VG 8230](https://www.msx.org/wiki/Philips_VG-8230) | MSX2 | První MSX2 od Philipsu s jednostrannou mechanikou. | mapper 64 KB, RTC, FDC + 1 jednostranná mechanika | |
| [VG 8235-00](https://www.msx.org/wiki/Philips_VG-8235) | MSX2 | Vylepšený VG 8230 s větší RAM. Známý problém: „Disk offline“. | mapper 128 KB, RTC, FDC + 1 jednostranná mechanika | sim (hlásí „Disk offline“) |
| [VG 8235-20](https://www.msx.org/wiki/Philips_VG-8235) † | MSX2 | Aktualizovaný VG 8235 s MSX-BASIC 2.1. | mapper 128 KB, RTC, FDC + 1 jednostranná mechanika | |
| [VG 8235-39](https://www.msx.org/wiki/Philips_VG-8235) † | MSX2 | Francouzská verze VG 8235. | mapper 128 KB, RTC, FDC + 1 jednostranná mechanika | |
| [VG 8240](https://www.msx.org/wiki/Philips_VG-8240) | MSX2 | Nevydaný prototyp MSX2 (vyrobeno asi 15 kusů) s video superimpose. | mapper 64 KB, RTC, FDC + 1 mechanika | |

## Samsung
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [SPC-800](https://www.msx.org/wiki/Samsung_SPC-800) | MSX1 | Jediný MSX od Samsungu: korejský MSX1 s hangulským BASICem a vestavěným reproduktorem. | 64 KB RAM, ROM hangul | |

## Sony
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [HB-201](https://www.msx.org/wiki/Sony_HB-201) | MSX1 | Japonský MSX1 s vestavěnou Personal Data Bank. | 64 KB RAM, ROM Personal Data Bank | |
| [HB-F1](https://www.msx.org/wiki/Sony_HB-F1) | MSX2 | Japonský MSX2 s vestavěným softwarem (regulátor rychlosti není emulován). | mapper 64 KB, RTC, ROM firmware | |
| [HB-F1XDmk2](https://www.msx.org/wiki/Sony_HB-F1XDmk2) | MSX2 | Zlevněný HB-F1XD: japonský MSX2 s vestavěnou disketovou mechanikou. | mapper 64 KB, RTC, FDC + 1 mechanika | |
| [HB-F5](https://www.msx.org/wiki/Sony_HB-F5) | MSX2 | První MSX2 od Sony s vestavěným softwarem Personal Databank. | 64 KB RAM, RTC, ROM firmware | |

## Yamaha
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [AX350IIF](https://www.msx.org/wiki/Sakhr_AX-350II) † | MSX2 | Arabsko-francouzský MSX2 vyrobený Yamahou pro Al Alamiah, s mechanikou a vestavěným softwarem. | mapper 128 KB, RTC, arabská ROM, textový procesor, Painter, FDC + 1 mechanika | |
| [CX11](https://www.msx.org/wiki/Yamaha_CX11) | MSX1 (V9938) | Japonský hudební MSX1 s V9938 a FM jednotkou SFG-01. | V9938, 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5F](https://www.msx.org/wiki/Yamaha_CX5F) | MSX1 | Japonský hudební počítač s vestavěnou SFG-01. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5M](https://www.msx.org/wiki/Yamaha_CX5M) | MSX1 | Mezinárodní syntezátorový MSX1 s vestavěnou SFG-01. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5MII](https://www.msx.org/wiki/Yamaha_CX5MII) | MSX1 (V9938) | Nástupce CX5M: MSX1 s V9938 a SFG-05. | V9938, 64 KB RAM, SFG-05 (OPM + MIDI YM2148), sub ROM pro 80 sloupců, FM Voicing Program II | |
| [CX5MII/128](https://www.msx.org/wiki/Yamaha_CX5MII) † | MSX1 (V9938) | CX5MII se 128 KB RAM. | V9938, mapper 128 KB, SFG-05, sub ROM, FM Voicing Program II | |
| [CX5MU](https://www.msx.org/wiki/Yamaha_CX5M) † | MSX1 | Americká verze CX5M s vlastním BIOSem. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
