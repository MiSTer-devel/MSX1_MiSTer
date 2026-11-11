# Podporované modely MSX

[English](ComputersModel.md) | **Česky**

Zpět na [Readme](Readme.cs.md).

Jádro není svázáno s jedním počítačem: každý stroj níže je definice (soubor XML v `tools/CreateMSXpack/Computer/`), která se převede na ROM PACK (`.msx`). Je zde **224 definic** od 36 výrobců:

| Generace | Počet |
|---|---|
| MSX1 | 135 (124 s VDP TMS99xx, 11 s V9938 a BIOSem MSX1) |
| MSX2 | 80 |
| MSX2+ | 7 |
| MSX turbo R | 1 |
| 1chipMSX / OCM (třída MSX2+) | 1 |

158 z nich přibylo v listopadu 2026 převodem popisů strojů z openMSX (`share/machines`).
Stroje, které potřebují hardware, jaký jádro nemá, jsou na konci.

**Obrazy ROM nejsou součástí.** ROM si dodáte sami a balíčky si sestavíte nástrojem [CreateMSXpack](tools/CreateMSXpack/README.cs.md) (viz též [Nástroje](tools/README.cs.md)). Bez vlastních ROM lze sestavit jen oba stroje C-BIOS a 1chipMSX. **1chipMSX** navíc potřebuje `OCM-BIOS.DAT` jako první soubor v obrazu SD karty (VHD) s FAT16.

Poznámky k tabulkám:
- Modely jsou odkazovány na [msx.org](https://www.msx.org/). Odkaz označený **†** vede na stránku, která model pokrývá jako variantu (stránka celé rodiny). Starší modely bez odkazu stránku na msx.org nemají; modely převzaté z openMSX zatím odkaz nemají.
- **Boot test** uvádí, co je zaznamenáno: *sim* = start v simulaci, *HW* = použito na skutečném hardware. Prázdná buňka znamená, že výsledek testu není zaznamenán, ne že stroj nefunguje.
- Disky: *FDC* = vestavěný řadič disket. FDC stroje má vždy přednost před cartridge FDC.
- *chybí* uvádí vestavěný hardware, který jádro vynechává. U všech strojů chybí port tiskárny a klávesnice má evropské rozložení; stroje s MSX-engine S1985 nemají jeho 16bajtovou zálohovanou paměť.

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
| AX370 | MSX2 | Arabský MSX2 odvozený od Sanyo PHC-70FD, s disketovou mechanikou a vestavěným softwarem. | mapper 128 KB, RTC, FDC TC8566AF + 1 mechanika, ROM Al Alamiah BASIC 2.03, Sakhr Word Processor, Sakhr BASIC, Painter | |

## Bawareth
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| Perfect MSX1 | MSX1 | Arabský MSX1 odvozený od Daewoo CPC-200. | 64 KB RAM | |

## C-BIOS (open-source firmware, ne skutečný výrobek)
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| MSX - C-BIOS | MSX1 | Obecný MSX1 se svobodným C-BIOSem; ROM jsou v repozitáři. | 64 KB RAM | |
| MSX2 - C-BIOS | MSX2 | Obecný MSX2 se svobodným C-BIOSem; ROM jsou v repozitáři. | mapper 128 KB, RTC | |

## CIEL (Brazílie)
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| Expert Turbo | MSX2+ | Brazilská amatérská základní deska MSX2+ do skříně Gradiente Expert. | V9958, mapper 1024 KB, RTC, MSX-MUSIC, 3 sloty pro cartridge (v jádře 2), chybí: turbo 7,16 MHz | |

## Canon
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| V-10 | MSX1 | Základní japonský MSX1 s 16 KB RAM. | 16 KB RAM | |
| [V-20](https://www.msx.org/wiki/Canon_V-20) | MSX1 | Původní japonský MSX1 Canon. | 64 KB RAM | |
| V-20 (JP) | MSX1 | Hlavní japonský MSX1 firmy Canon. | 64 KB RAM | |
| [V-20E](https://www.msx.org/wiki/Canon_V-20_%28EU%29) | MSX1 | Evropská úprava V-20. | 64 KB RAM | |
| [V-20F](https://www.msx.org/wiki/Canon_V-20_%28FR%29) | MSX1 | Francouzská úprava V-20 (AZERTY). | 64 KB RAM | |
| V-20G | MSX1 | Regionální varianta evropského V-20 s vlastním dumpem BIOSu. | 64 KB RAM | |
| V-20S | MSX1 | Regionální varianta evropského V-20 s vlastním dumpem BIOSu. | 64 KB RAM | |
| V-25 | MSX2 | Velmi základní MSX2, jeden z mála s pouhými 64 KB VRAM. | mapper 64 KB, RTC | |
| V-8 | MSX1 | Velmi kompaktní a úsporný MSX1 bez portu tiskárny. | 16 KB RAM, jeden slot pro cartridge | |

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
| CPC-300E | MSX2 | Vzdělávací verze CPC-300. | mapper 64 KB | |
| [CPC-400S](https://www.msx.org/wiki/Daewoo_CPC-400S) | MSX2 | Korejský stolní MSX2 s podporou hangulu a disketovou mechanikou. | mapper 128 KB, RTC, ROM a font hangul (zařízení Kanji), FDC + 1 mechanika | |
| [CPC-51 Zemmix V](https://www.msx.org/wiki/Daewoo_CPC-51) | MSX1 | Korejská herní konzole MSX1. | 64 KB RAM, jeden slot pro cartridge | |
| CPC-61 Zemmix Super V | MSX2 | Korejská herní konzole MSX2. | mapper 64 KB, RTC, jeden slot pro cartridge | |
| [DPC-100](https://www.msx.org/wiki/Daewoo_DPC-100) | MSX1 | Základní korejský MSX1 s ovladačem hangulu. | 16 KB RAM, ROM hangul | |
| [DPC-180](https://www.msx.org/wiki/Daewoo_DPC-180) | MSX1 | Základní korejský MSX1 s ovladačem hangulu. | 64 KB RAM, ROM hangul | |
| [DPC-200](https://www.msx.org/wiki/Daewoo_DPC-200) | MSX1 | Korejský MSX1, vylepšený DPC-180. | 64 KB RAM, ROM hangul | |
| [DPC-200E(FR)](https://www.msx.org/wiki/Daewoo_DPC-200_%28FR%29) | MSX1 | DPC-200 upravený pro frankofonní Belgii. | 64 KB RAM | |

## Eurohard
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| Dragon MSX | MSX1 | Vzácný MSX1, který se nikdy nevyráběl sériově (Eurohard zkrachoval). | 64 KB RAM | |

## Fenner
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| SPC-800 | MSX1 | MSX1 od Samsungu pro evropský trh. | 64 KB RAM | |

## Frael
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| BRUC 100 (v1) | MSX1 | První verze tohoto italského stroje, většinou kompatibilního s MSX. | 64 KB RAM, bez slotů pro cartridge, chybí: přepínání ROM firmwaru | |
| BRUC 100 (v2) | MSX1 | Druhá verze tohoto italského stroje, většinou kompatibilního s MSX. | 64 KB RAM, chybí: přepínání ROM firmwaru | |

## Fujitsu
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| FM-X | MSX1 | Jediný MSX firmy Fujitsu; propojení s počítačem FM-7 se neemuluje. | 16 KB RAM, jeden slot pro cartridge | |

## General
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| Paxon PCT-55 | MSX1 | MSX1 vestavěný do televizoru, se samostatnou klávesnicí. | 32 KB RAM, jeden slot pro cartridge | |

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
| MB-H1 | MSX1 | Velmi kompaktní japonský MSX1 s vestavěným softwarem. | 32 KB RAM, ROM firmware | |
| [MB-H2](https://www.msx.org/wiki/Hitachi_MB-H2) | MSX1 | Kompaktní japonský MSX1 s vestavěným magnetofonem (magnetofon není emulován). | 64 KB RAM, ROM firmware | |
| MB-H21 | MSX1 | Japonský MSX1 s vestavěným softwarem (ovládání rychlosti se neemuluje). | 32 KB RAM, ROM firmware | |
| MB-H3 | MSX2 | První MSX2 Hitachi, jen s 64 KB VRAM (dotyková plocha se neemuluje). | 64 KB RAM, RTC, ROM firmware | |
| MB-H50 | MSX1 | Kompaktní MSX1 s externí klávesnicí (přídavné LED se neemulují). | 64 KB RAM | |
| MB-H70 | MSX2 | Rozšiřitelný MSX2 se dvěma mechanikami, odvozený od Mitsubishi ML-G30 model 2. | mapper 128 KB, RTC, Kanji ROM, FDC + 2 mechaniky, 4 sloty pro cartridge (v jádře 2) | |

## JVC
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| HC-7GB | MSX1 | MSX1 firmy JVC pro britský trh, s výstupem RGB. | 64 KB RAM | |

## Mitsubishi
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| ML-8000 | MSX1 | První stroj MSX na trhu. | 32 KB RAM, jeden slot pro cartridge | |
| ML-F110 | MSX1 | Základní japonský MSX1 s 16 KB RAM. | 16 KB RAM | |
| ML-F120 | MSX1 | Japonský MSX1 s vestavěným softwarem. | 32 KB RAM, ROM firmware | |
| ML-F80 | MSX1 | Základní MSX1 pro evropský trh. | 64 KB RAM | |
| ML-FX1 | MSX1 | Základní MSX1 pro španělský trh, s numerickou klávesnicí. | 64 KB RAM | |
| ML-G1 (ES) | MSX2 | ML-G10 upravený pro španělský trh. | 64 KB RAM, RTC, ROM MSX Designer | |
| ML-G10 | MSX2 | První MSX2 Mitsubishi, s vestavěným programem Hot Paper. | 64 KB RAM, RTC, ROM firmware, 3 sloty pro cartridge (v jádře 2) | |
| ML-G3 (ES) | MSX2 | Španělský MSX2 s disketovou mechanikou a RS-232C. | mapper 128 KB, RTC, FDC + 1 mechanika, jeden slot pro cartridge, chybí: RS-232C | |
| ML-G30/model 1 | MSX2 | Rozšiřitelný MSX2 s vestavěným softwarem a mnoha sloty. | mapper 128 KB, RTC, Kanji ROM, FDC + 1 mechanika, 4 sloty pro cartridge (v jádře 2) | |
| ML-G30/model 2 | MSX2 | ML-G30 se dvěma mechanikami a RS-232C. | mapper 128 KB, RTC, Kanji ROM, FDC + 2 mechaniky, 3 sloty pro cartridge (v jádře 2), chybí: RS-232C | |

## National
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| CF-1200 | MSX1 | Základní japonský MSX1, levnější verze CF-2700. | 16 KB RAM | |
| CF-2000 | MSX1 | První MSX firmy Matsushita, základní japonský MSX1. | 16 KB RAM | |
| CF-2700 | MSX1 | Základní japonský MSX1. | 32 KB RAM | |
| CF-3000 | MSX1 | Japonský stolní MSX1 se samostatnou klávesnicí. | 64 KB RAM | |
| CF-3300 | MSX1 | Japonský stolní MSX1 s vestavěnou disketovou mechanikou. | 64 KB RAM, FDC + 1 mechanika | |
| FS-1300 | MSX1 | Základní japonský MSX1. | 64 KB RAM | |
| FS-4000 | MSX1 | Japonský MSX1 pro psaní textů s vestavěným softwarem (vestavěná tiskárna se neemuluje). | 64 KB RAM, Kanji ROM, ROM MSX Word | |
| FS-4500 | MSX2 | Japonský MSX2 pro psaní textů s vestavěným softwarem (vestavěná tiskárna se neemuluje). | 64 KB RAM, RTC, Kanji ROM, ROM Word Font, MSX Jusho, MSX Word 1, MSX Word 2, chybí: SRAM firmwaru, Bunsetsu | |
| [FS-4600F](https://www.msx.org/wiki/National_FS-4600F) | MSX2 | Japonský MSX2 pro zpracování textu s vestavěným softwarem, kanji a disketovou mechanikou (vestavěná tiskárna není emulována). | mapper 128 KB, RTC, Kanji ROM, MSX-Word, FDC + 1 mechanika | |
| FS-4700F | MSX2 | FS-4500 s vestavěnou disketovou mechanikou (vestavěná tiskárna se neemuluje). | 64 KB RAM, RTC, Kanji ROM, FDC + 1 mechanika, ROM Word Font, MSX Jusho, MSX Word 1, MSX Word 2, chybí: SRAM firmwaru, Bunsetsu | |
| FS-5000F2 | MSX2 | Japonský stolní MSX2 se dvěma mechanikami. | mapper 128 KB, RTC, Kanji ROM, FDC + 2 mechaniky, ROM Set-Up RTC | |
| FS-5500F1 | MSX2 | Japonský stolní MSX2 s jednou mechanikou (superimpose a digitalizace se neemulují). | 64 KB RAM, RTC, Kanji ROM, FDC + 1 mechanika, ROM Super Impose | |
| FS-5500F2 | MSX2 | Vlajková loď National, MSX2 se dvěma mechanikami (superimpose a digitalizace se neemulují). | 64 KB RAM, RTC, Kanji ROM, FDC + 2 mechaniky, ROM Super Impose | |

## Nikko
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| PC-70100 | MSX1 | Pravděpodobně prototyp MSX1. | 16 KB RAM, jeden slot pro cartridge | |

## OCM
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [1chipMSX](https://www.msx.org/wiki/1chipMSX) | třída MSX2+ | FPGA stroj třídy MSX2+ (OCM-PLD), který zavádí BIOS z obrazu SD karty; potřebuje `OCM-BIOS.DAT` na VHD. | V9958, mapper 4 MB, MSX-MUSIC, RTC, Kanji, sloty ESE-SCC a MegaRAM (volba v OSD), MegaSD; bez slotů pro cartridge | sim, HW (SofaRun) |

## Olympia
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| PHC-2 | MSX1 | Základní francouzský MSX1 vyrobený Daewoo, odvozený od DPC-200. | 64 KB RAM | |

## Panasonic
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| CF-2700 (DE) | MSX1 | Základní německý MSX1, jeden z nejrozšířenějších MSX v Německu. | 64 KB RAM | |
| CF-2700 (GB) | MSX1 | Základní britský MSX1, jeden z mála evropských MSX od Panasonicu. | 64 KB RAM | |
| [FS-A1](https://www.msx.org/wiki/Panasonic_FS-A1) | MSX2 | Základní japonský MSX2 s vestavěným softwarem DESKPAC. | mapper 64 KB, RTC | |
| [FS-A1F](https://www.msx.org/wiki/Panasonic_FS-A1F) | MSX2 | FS-A1mkII s vestavěnou disketovou mechanikou a softwarem. | mapper 64 KB, RTC, Kanji ROM, FDC TC8566AF + 1 mechanika | sim (start z disku OK) |
| FS-A1FX | MSX2+ | Japonský MSX2+ s disketovou mechanikou a vestavěným softwarem, bez MSX-MUSIC. | V9958, mapper 64 KB, RTC, Kanji ROM, FDC TC8566AF + 1 mechanika, ROM A1 Cockpit, chybí: turbo 5,37 MHz a SRAM firmwaru | |
| FS-A1MK2 | MSX2 | Základní japonský MSX2, FS-A1 s numerickou klávesnicí. | 64 KB RAM, RTC, ROM A1 Cockpit 1, A1 Cockpit 2, A1 Cockpit 3 | |
| [FS-A1ST](https://www.msx.org/wiki/Panasonic_FS-A1ST) | turbo R | První MSX turbo R: R800, MSX-MUSIC, PCM, MSX-DOS2, mechanika a software. R800 běží zhruba 2x rychleji než Z80 (viz [Readme](Readme.cs.md#známá-omezení)). | V9958, 256 KB RAM, R800/S1990, MSX-MUSIC, PCM, RTC, Kanji ROM, FDC TC8566AF + 1 mechanika | sim (MSX BASIC 4.0 / Disk BASIC 2.01) |
| FS-A1WSX | MSX2+ | Nástupce FS-A1WX: MSX2+ s MSX-MUSIC, disketovou mechanikou a vestavěným softwarem. | V9958, mapper 64 KB, RTC, MSX-MUSIC, Kanji ROM, FDC TC8566AF + 1 mechanika, ROM firmware, chybí: turbo 5,37 MHz a SRAM firmwaru | |
| FS-A1WX | MSX2+ | Japonský MSX2+ s MSX-MUSIC, disketovou mechanikou a vestavěným softwarem. | V9958, mapper 64 KB, RTC, MSX-MUSIC, Kanji ROM, FDC TC8566AF + 1 mechanika, ROM firmware, chybí: turbo 5,37 MHz a SRAM firmwaru | |

## Philips
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [NMS 801](https://www.msx.org/wiki/Philips_NMS_801) | MSX1 | Italský „MSX compatible“ MSX1 bez slotů pro cartridge. | 64 KB RAM, bez slotů pro cartridge | |
| [NMS 8220](https://www.msx.org/wiki/Philips_NMS_8220) | MSX2 | Základní evropský MSX2 s vestavěným kreslicím programem Designer. | mapper 64 KB, RTC, ROM Designer | |
| [NMS 8245](https://www.msx.org/wiki/Philips_NMS_8245) | MSX2 | Evropský MSX2 s oboustrannou disketovou mechanikou. | mapper 128 KB, RTC, FDC + 1 mechanika | HW (měření VDP) |
| NMS 8245/16 | MSX2 | Španělská verze NMS 8245. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| NMS 8245/19 | MSX2 | Francouzská verze NMS 8245. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| [NMS 8250](https://www.msx.org/wiki/Philips_NMS_8250) | MSX2 | Evropský stolní MSX2 s oboustrannou mechanikou. | mapper 128 KB, RTC, FDC + 1 mechanika | sim (disk OK) |
| [NMS 8250-16](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Španělská verze NMS 8250. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| [NMS 8250-19](https://www.msx.org/wiki/Philips_NMS_8250) † | MSX2 | Francouzská verze NMS 8250. | mapper 128 KB, RTC, FDC + 1 mechanika | |
| [NMS 8255](https://www.msx.org/wiki/Philips_NMS_8255) | MSX2 | NMS 8250 se dvěma oboustrannými mechanikami. | mapper 128 KB, RTC, FDC + 2 mechaniky | |
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
| VG 8235/02 | MSX2 | Německá verze VG 8235. | mapper 128 KB, RTC, FDC + 1 jednostranná mechanika | |
| VG 8235/19 | MSX2 | Francouzská verze VG 8235. | mapper 128 KB, RTC, FDC + 1 jednostranná mechanika | |
| [VG 8240](https://www.msx.org/wiki/Philips_VG-8240) | MSX2 | Nevydaný prototyp MSX2 (vyrobeno asi 15 kusů) s video superimpose. | mapper 64 KB, RTC, FDC + 1 mechanika | |

## Pioneer
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| PX-7 | MSX1 | Japonský MSX1 s ovládáním laserdisku, stereo PSG a superimpose (neemuluje se). | 32 KB RAM, chybí: ovládání laserdisku | |
| PX-7(UK) | MSX1 | Britská verze PX-7. | 32 KB RAM, chybí: ovládání laserdisku | |
| PX-V60 | MSX1 | Jednodušší PX-7 s ovládáním laserdisku (neemuluje se). | 32 KB RAM, chybí: ovládání laserdisku | |
| UC-V102 | MSX2 | Řadič videodisku, uvnitř MSX2. | mapper 64 KB, RTC, Kanji ROM, FDC + 2 mechaniky, jeden slot pro cartridge, chybí: RS-232C | |

## Samsung
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| [SPC-800](https://www.msx.org/wiki/Samsung_SPC-800) | MSX1 | Jediný MSX od Samsungu: korejský MSX1 s hangulským BASICem a vestavěným reproduktorem. | 64 KB RAM, ROM hangul | |

## Sanyo
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| MPC-1/Wavy1 | MSX1 | Základní japonský MSX1 s 16 KB RAM. | 16 KB RAM | |
| MPC-10/Wavy10 | MSX1 | Základní japonský MSX1 s řadičem světelného pera (neemuluje se). | 32 KB RAM | |
| MPC-10/Wavy10mkII | MSX1 | MPC-10 s vestavěným programem Light Pen Graphic (světelné pero se neemuluje). | 32 KB RAM, ROM Light Pen Graphic | |
| MPC-100 | MSX1 | Základní MSX1 oblíbený v Británii, britská verze MPC-6. | 64 KB RAM | |
| MPC-11/Wavy11 | MSX1 | Japonský MSX1 vyšší třídy (digitalizace, superimpose a světelné pero se neemulují). | 32 KB RAM | |
| MPC-2/Wavy2 | MSX1 | Základní japonský MSX1. | 64 KB RAM | |
| MPC-2300 | MSX2 | Sovětský školní MSX2 s azbukou a síťovým rozhraním (neemuluje se). | mapper 128 KB, RTC, chybí: RS-232C | |
| MPC-25FD | MSX2 | Stolní MSX2 s disketovou mechanikou a jedním slotem cartridge. | 64 KB RAM, RTC, FDC + 1 mechanika, jeden slot pro cartridge | |
| MPC-25FS | MSX2 | Stolní MSX2 s jednostrannou mechanikou a jedním slotem cartridge. | 64 KB RAM, RTC, FDC + 1 jednostranná mechanika, jeden slot pro cartridge | |
| MPC-3/Wavy3 | MSX1 | Japonský MSX1 s 16 KB RAM a třemi sloty cartridge. | 16 KB RAM, 3 sloty pro cartridge (v jádře 2) | |
| MPC-6/Wavy6 | MSX1 | Základní japonský MSX1. | 64 KB RAM | |
| MPC-64 | MSX1 | MSX1 pro německý trh. | 64 KB RAM | |
| PHC-23 | MSX2 | Základní japonský MSX2 s klávesnicí JP50on. | 64 KB RAM, RTC | |
| PHC-23J | MSX2 | Základní japonský MSX2 s klávesnicí JIS. | 64 KB RAM, RTC | |
| PHC-23J(B) | MSX2 | Modrá verze PHC-23J. | 64 KB RAM, RTC | |
| PHC-28L | MSX1 | Základní francouzský MSX1, vylepšený PHC-28S. | 64 KB RAM | |
| PHC-28P | MSX1 | Německá verze PHC-28L. | 64 KB RAM | |
| PHC-28S | MSX1 | Základní francouzský MSX1 s 16 KB RAM. | 16 KB RAM, 3 sloty pro cartridge (v jádře 2) | |
| PHC-30N | MSX1 | Japonský MSX1 s vestavěným magnetofonem (neemuluje se). | 64 KB RAM | |
| PHC-33 | MSX1 | Japonský MSX1 s vestavěným rychlým magnetofonem (neemuluje se). | 64 KB RAM | |
| PHC-35J | MSX2+ | Základní MSX2+ bez MSX-MUSIC. | V9958, mapper 64 KB, RTC, Kanji ROM | |
| PHC-70FD | MSX2+ | Japonský MSX2+ s MSX-MUSIC a disketovou mechanikou. | V9958, mapper 64 KB, RTC, MSX-MUSIC, Kanji ROM, FDC TC8566AF + 1 mechanika, ROM BASIC'n 2.0 | sim |
| PHC-70FD2 | MSX2+ | Japonský MSX2+ s MSX-MUSIC a dvěma mechanikami. | V9958, mapper 64 KB, RTC, MSX-MUSIC, Kanji ROM, FDC TC8566AF + 2 mechaniky, ROM BASIC Compiler | |
| PHC-SPC | MSX1 | Základní MSX1 pro japonské školy. | 64 KB RAM | |

## Sharp
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| HB-8000 v1.1 | MSX1 | Původní bílý Hotbit, brazilský MSX1. | 64 KB RAM | |
| HB-8000 v1.2 | MSX1 | Černý Hotbit s novějším BIOSem. | 64 KB RAM | |

## Sony
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| HB-10 | MSX1 | Základní japonský MSX1 s 16 KB RAM. | 16 KB RAM | |
| HB-101 | MSX1 | Základní MSX1 s vestavěným Personal Data Bank. | 16 KB RAM, ROM Personal Data Bank | |
| HB-101P | MSX1 | Evropská verze HB-101 s vestavěným Personal Data Bank. | 32 KB RAM, ROM Personal Data Bank | |
| HB-10P | MSX1 | Základní evropský MSX1 se zvláštním zrcadlením RAM. | 64 KB RAM, chybí: zrcadlo RAM ve slotu 0 | |
| HB-11 | MSX1 | Poslední MSX1 od Sony („Hit Bit U“), s ROM Kanji. | 64 KB RAM, Kanji ROM, ROM firmware | |
| [HB-201](https://www.msx.org/wiki/Sony_HB-201) | MSX1 | Japonský MSX1 s vestavěnou Personal Data Bank. | 64 KB RAM, ROM Personal Data Bank | |
| HB-201P | MSX1 | HB-101P s 64 KB RAM. | 64 KB RAM, ROM Personal Data Bank | |
| HB-20P | MSX1 | Základní španělský MSX1, podobný HB-10P. | 64 KB RAM | |
| HB-501P | MSX1 | Evropský MSX1 s vestavěným magnetofonem (neemuluje se). | 64 KB RAM | |
| HB-55P | MSX1 | Evropská verze HB-55 s vestavěným Personal Data Bank. | 16 KB RAM, ROM Personal Data Bank | |
| HB-701 | MSX1 | Luxusní MSX1 se samostatnou klávesnicí a vestavěným firmwarem (superimpose a S-Link se neemulují). | 64 KB RAM, ROM firmware | |
| HB-701FD | MSX1 | HB-701 s jednostrannou disketovou mechanikou. | 64 KB RAM, FDC + 1 jednostranná mechanika, ROM firmware | |
| HB-75 | MSX1 | Základní japonský MSX1 s vestavěným Personal Data Bank. | 64 KB RAM, ROM Personal Data Bank | |
| HB-75D | MSX1 | Německá verze HB-75. | 64 KB RAM, ROM Personal Data Bank | |
| HB-75P | MSX1 | Evropská verze HB-75; startuje do Personal Data Bank. | 64 KB RAM, ROM Personal Data Bank | sim (startuje do Personal Data Bank) |
| [HB-F1](https://www.msx.org/wiki/Sony_HB-F1) | MSX2 | Japonský MSX2 s vestavěným softwarem (regulátor rychlosti není emulován). | mapper 64 KB, RTC, ROM firmware | |
| HB-F1II | MSX2 | Zlevněný HB-F1 s vestavěným softwarem (ovládání rychlosti se neemuluje). | 64 KB RAM, RTC, ROM firmware | |
| HB-F1XD | MSX2 | Japonský MSX2 s vestavěnou disketovou mechanikou (ovládání rychlosti se neemuluje). | 64 KB RAM, RTC, FDC + 1 mechanika | |
| [HB-F1XDmk2](https://www.msx.org/wiki/Sony_HB-F1XDmk2) | MSX2 | Zlevněný HB-F1XD: japonský MSX2 s vestavěnou disketovou mechanikou. | mapper 64 KB, RTC, FDC + 1 mechanika | |
| [HB-F5](https://www.msx.org/wiki/Sony_HB-F5) | MSX2 | První MSX2 od Sony s vestavěným softwarem Personal Databank. | 64 KB RAM, RTC, ROM firmware | |
| HB-F500 | MSX2 | První stolní MSX2 od Sony s oboustrannou mechanikou; neobvyklé rozložení paměti. | 64 KB RAM, RTC, Kanji ROM, FDC + 1 mechanika | |
| HB-F500 (v2) | MSX2 | Druhá verze HB-F500 s jednodušším rozložením paměti. | 64 KB RAM, RTC, Kanji ROM, FDC + 1 mechanika | |
| HB-F500P | MSX2 | Evropská verze HB-F500 se třemi sloty cartridge; neobvyklé rozložení paměti. | 64 KB RAM, RTC, FDC + 1 mechanika, 3 sloty pro cartridge (v jádře 2) | |
| HB-F700D | MSX2 | Německá verze HB-F700. | mapper 256 KB, RTC, FDC + 1 mechanika | |
| HB-F700F | MSX2 | Francouzská verze HB-F700. | mapper 256 KB, RTC, FDC + 1 mechanika | |
| HB-F700P | MSX2 | Evropský MSX2 s 256 KB RAM a oboustrannou mechanikou. | mapper 256 KB, RTC, FDC + 1 mechanika | sim |
| HB-F700S | MSX2 | Španělská verze HB-F700. | mapper 256 KB, RTC, FDC + 1 mechanika | |
| HB-F900 | MSX2 | Profesionální japonský MSX2 se dvěma mechanikami (superimpose a digitalizace se neemulují). | mapper 256 KB, RTC, Kanji ROM, FDC + 2 mechaniky, ROM HB-F900 Video Utility 1.10 | |
| HB-F9P | MSX2 | Evropský MSX2 s vestavěným programem Memovision. | mapper 128 KB, RTC, ROM Memovision 2, Memovision 1 | |
| HB-F9P Russian | MSX2 | Velmi vzácná ruská verze HB-F9P. | mapper 128 KB, RTC | |
| HB-F9S | MSX2 | Španělská verze HB-F9P. | mapper 128 KB, RTC, ROM Memovision 2, Memovision 1/1, Memovision 1/2 | |
| HB-G900AP | MSX2 | Profesionální evropský MSX2 s 512 KB RAM, mechanikou a video utilitou (superimpose se neemuluje). | mapper 512 KB, RTC, FDC + 1 mechanika, ROM Video Utility, chybí: RS-232C | |
| HB-G900D | MSX2 | Německá verze HB-G900P. | 64 KB RAM, RTC, FDC + 1 mechanika, ROM Video Utility, chybí: RS-232C | |
| HB-G900P | MSX2 | Profesionální evropský MSX2 s mechanikou a video utilitou (superimpose se neemuluje). | 64 KB RAM, RTC, FDC + 1 mechanika, ROM Video Utility, chybí: RS-232C | |
| HB-T600 | MSX2 | Japonský terminál pro obchod s akciemi (MSX2) s mechanikou a modemem. | mapper 128 KB, RTC, Kanji ROM, FDC + 1 mechanika, ROM firmware, chybí: modem | |

## Spectravideo
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| SVI-728 | MSX1 | Základní MSX1 oblíbený v mnoha evropských zemích. | 64 KB RAM | |
| SVI-728 (DK) | MSX1 | Dánská verze SVI-728. | 64 KB RAM | |
| SVI-728 (ES) | MSX1 | Španělská verze SVI-728. | 64 KB RAM | |
| SVI-728 (SE) | MSX1 | Švédská verze SVI-728. | 64 KB RAM | |
| SVI-738 X'PRESS | MSX1 (V9938) | Kompletní MSX1 s V9938, RS-232C a jednostrannou mechanikou. | V9938, 64 KB RAM, FDC + 1 jednostranná mechanika, jeden slot pro cartridge, chybí: RS-232C | |
| SVI-738 X'PRESS (DE) | MSX1 (V9938) | SVI-738 pro německý trh. | V9938, 64 KB RAM, FDC + 1 jednostranná mechanika, jeden slot pro cartridge, chybí: RS-232C | |
| SVI-738 X'PRESS (DK) | MSX1 (V9938) | SVI-738 pro dánský a norský trh. | V9938, 64 KB RAM, FDC + 1 jednostranná mechanika, jeden slot pro cartridge, chybí: RS-232C | |
| SVI-738 X'PRESS (PL) | MSX1 (V9938) | SVI-738 pro polský trh. | V9938, 64 KB RAM, FDC + 1 jednostranná mechanika, jeden slot pro cartridge, chybí: RS-232C | |
| SVI-738 X'PRESS (SE) | MSX1 (V9938) | SVI-738 pro švédský a finský trh. | V9938, 64 KB RAM, FDC + 1 jednostranná mechanika, jeden slot pro cartridge, chybí: RS-232C | |

## Talent
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| DPC-200 | MSX1 | Daewoo DPC-200 upravený pro Argentinu. | 64 KB RAM | |
| TPC-310 | MSX2 | Nejvybavenější argentinský MSX: MSX2 s turbo BASICem a vestavěnými programy (PAL). | mapper 128 KB, RTC, ROM Turbo BASIC, Accessories | |

## Toshiba
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| FS-TM1 | MSX2 | Italský MSX2 odvozený od Panasonic FS-A1(F). | mapper 64 KB, RTC, ROM Utility Part 1, Utility Part 2 | |
| HX-10 | MSX1 | Velmi rozšířený základní MSX1 v Británii. | 64 KB RAM | |
| HX-10D | MSX1 | První MSX firmy Toshiba. | 64 KB RAM | |
| HX-20E | MSX1 | MSX1 prodávaný ve Španělsku, s RAM diskem a anglickým textovým editorem. | 64 KB RAM, ROM Word Processor | |
| HX-21 | MSX1 | Japonský MSX1 s RAM diskem, stereo PSG a textovým editorem. | 64 KB RAM, ROM Software Utility | |
| HX-22 | MSX1 | HX-21 s RS-232C. | 64 KB RAM, ROM Software Utility, chybí: RS-232C | |
| HX-22I | MSX1 | Italský MSX1 s vestavěným textovým editorem. | 64 KB RAM, ROM Word Processor, chybí: RS-232C | |
| HX-23 | MSX2 | Vzácný japonský MSX2 se stereo PSG, 64 KB VRAM a textovým editorem. | 64 KB RAM, RTC, ROM Japanese Word Processor part2 | |
| HX-23F | MSX2 | HX-23 s RS-232C a 128 KB VRAM. | 64 KB RAM, RTC, ROM Japanese Word Processor part2, chybí: RS-232C | |
| HX-32 | MSX1 | Japonský MSX1 s RAM diskem, ROM Kanji, stereo PSG a textovým editorem. | 64 KB RAM, Kanji ROM, ROM Software Utility | |
| HX-33 | MSX2 | Japonský MSX2 se stereo PSG a vestavěným textovým editorem. | mapper 64 KB, RTC, Kanji ROM, chybí: RS-232C, ROM textového editoru (TCX-200x) | |
| HX-51I | MSX1 | Základní evropský MSX1 (Itálie, Španělsko); rozložení paměti shodí špatně napsaný software. | 64 KB RAM | |

## Victor
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| HC-7 | MSX1 | První MSX1 firmy Victor, s vestavěným softwarem (superimpose se neemuluje). | 64 KB RAM, ROM firmware | |
| HC-80 | MSX2 | Japonský MSX2 s vestavěným softwarem. | 64 KB RAM, RTC, ROM firmware | |

## Yamaha
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| AX150 | MSX1 | Arabský MSX1 s vestavěným softwarem. | 64 KB RAM | |
| AX200 | MSX1 (V9938) | Arabský MSX1 s vestavěným softwarem a modulem SFG-05. | V9938, 64 KB RAM, SFG-05 (OPM + MIDI YM2148) | |
| AX350II | MSX2 | Arabský MSX2 prodávaný Al Alamiah, s mechanikou a vestavěným softwarem. | mapper 128 KB, RTC, FDC + 1 mechanika, ROM Sakhr Word Processor, Sakhr Files fragment, Painter | |
| [AX350IIF](https://www.msx.org/wiki/Sakhr_AX-350II) † | MSX2 | Arabsko-francouzský MSX2 vyrobený Yamahou pro Al Alamiah, s mechanikou a vestavěným softwarem. | mapper 128 KB, RTC, arabská ROM, textový procesor, Painter, FDC + 1 mechanika | |
| AX500 | MSX2 | Arabský MSX2 prodávaný Al Alamiah, s 256 KB RAM, dvěma mechanikami a vestavěným softwarem. | mapper 256 KB, RTC, FDC + 2 mechaniky, ROM Arabic BASIC, Arabic Word Processor, Sakhr Files, 3 sloty pro cartridge (v jádře 2) | |
| [CX11](https://www.msx.org/wiki/Yamaha_CX11) | MSX1 (V9938) | Japonský hudební MSX1 s V9938 a FM jednotkou SFG-01. | V9938, 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5F](https://www.msx.org/wiki/Yamaha_CX5F) | MSX1 | Japonský hudební počítač s vestavěnou SFG-01. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5M](https://www.msx.org/wiki/Yamaha_CX5M) | MSX1 | Mezinárodní syntezátorový MSX1 s vestavěnou SFG-01. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| [CX5MII](https://www.msx.org/wiki/Yamaha_CX5MII) | MSX1 (V9938) | Nástupce CX5M: MSX1 s V9938 a SFG-05. | V9938, 64 KB RAM, SFG-05 (OPM + MIDI YM2148), sub ROM pro 80 sloupců, FM Voicing Program II | |
| [CX5MII/128](https://www.msx.org/wiki/Yamaha_CX5MII) † | MSX1 (V9938) | CX5MII se 128 KB RAM. | V9938, mapper 128 KB, SFG-05, sub ROM, FM Voicing Program II | |
| [CX5MU](https://www.msx.org/wiki/Yamaha_CX5M) † | MSX1 | Americká verze CX5M s vlastním BIOSem. | 32 KB RAM, SFG-01 (OPM + MIDI YM2148) | |
| CX7/128 | MSX2 | Hudební počítač jako CX7M/128, ale bez SFG-05. | mapper 128 KB, RTC, 3 sloty pro cartridge (v jádře 2) | |
| CX7M/128 | MSX2 | Japonský hudební MSX2 s vestavěným SFG-05. | mapper 128 KB, RTC, SFG-05 (OPM + MIDI YM2148), ROM FM Voicing Program II | |
| SX-100 | MSX1 | Herní MSX1 s 32 KB RAM. | 32 KB RAM, jeden slot pro cartridge | |
| YIS-503 | MSX1 | Jako CX5F, ale bez zvukového modulu. | 32 KB RAM, 3 sloty pro cartridge (v jádře 2) | |
| YIS-503F | MSX1 | Evropský MSX1 jako CX5M, ale bez modulu SFG. | 32 KB RAM, 3 sloty pro cartridge (v jádře 2) | |
| YIS-503II | MSX1 (V9938) | Japonský MSX1 s V9938. | V9938, 64 KB RAM | |
| YIS-503IIIR | MSX2 | Sovětský školní MSX2 (pracoviště žáka); síťový modul se neemuluje. | mapper 128 KB, RTC, ROM CP/M | |
| YIS-503IIR | MSX1 (V9938) | Sovětská školní verze YIS-503II; síťový modul se neemuluje. | V9938, 64 KB RAM | |
| YIS-604/128 | MSX2 | Domácí počítač shodný s CX7M/128. | mapper 128 KB, RTC | |
| YIS-805/128R2 | MSX2 | Sovětský školní MSX2 (pracoviště učitele) s programem The Painter; síťový modul se neemuluje. | mapper 128 KB, RTC, FDC + 2 mechaniky, ROM Painter | |
| YIS-805/256 | MSX2 | Japonský MSX2 s 256 KB RAM, programem The Painter a textovým editorem (neemuluje se). | mapper 256 KB, RTC, Kanji ROM, FDC + 2 mechaniky, ROM The Painter, 3 sloty pro cartridge (v jádře 2), chybí: RS-232C, ROM textového editoru (SKW-01) | |

## Yashica
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| YC-64 | MSX1 | Základní evropský MSX1, jediný MSX firmy Yashica (Kyocera). | 64 KB RAM, jeden slot pro cartridge | |

## Yeno
| Model | Gen. | Popis | Klíčový vestavěný hardware | Boot test |
|---|---|---|---|---|
| DPC-64 | MSX1 | Přeznačený Daewoo DPC-200 pro francouzsky mluvící trh. | 64 KB RAM | |

## Nepodporováno

Tyto stroje z openMSX potřebují hardware, který jádro zatím nemá:

| Model | Chybí |
|---|---|
| Canon V-30F | zapojení řadiče disket Canon (MB8877A, registry 7FF8–7FFC) |
| Sanyo PHC-77 | zapojení řadiče disket Sanyo |
| Toshiba HX-34 | zapojení řadiče disket Toshiba (registry 7FF0–7FF7) |
| Victor HC-90A, HC-95A | zapojení řadiče disket Victor, systémový registr 7FFD |
| Panasonic FS-A1FM | mappery firmwaru a modemu FS-A1FM |
| Sony HB-F1XDJ, HB-F1XV | mapper Halnote (firmware MSX-JE) |
| Panasonic FS-A1GT | ROM firmwaru 4 MB (formát packu unese nejvýš 4080 KB na ROM), MSX-MIDI |
| Aucnet NIA-2001 | ROM mapper MSX-DOS2 |
