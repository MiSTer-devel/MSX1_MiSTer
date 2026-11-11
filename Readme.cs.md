# MSX1/MSX2/turbo R pro [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

[English](Readme.md) | **Česky**

> [!CAUTION]
> **Upozornění (WIP)**: Toto jádro je ve vývoji (**Work in Progress**). Některé součásti jsou rozpracované a mohou obsahovat ladicí výstupy nebo experimentální funkce. Některé funkce zatím nemusí fungovat stoprocentně. Mapper ASCII16-X a MoonSound jsou přeložené a vyzkoušené na skutečném hardware. Mappery NEO-8 a NEO-16 zatím na skutečném hardware vyzkoušeny nebyly a časování V99x8, R800 a řadič TC8566AF také nejsou na hardware ověřeny. Viz [Známá omezení](#známá-omezení).

## Přehled jádra
Jádro (na MiSTeru se stále jmenuje `MSX1`, proto složka `games/MSX1`) není přímou syntézou konkrétního počítače MSX. Poskytuje **dynamicky konfigurovatelné hardwarové prostředí**, které se za běhu sestaví z vybrané definice (*ROM PACK*). Každá definice stroje obsahuje nejen zapojení hardware, ale i příslušný **obsah ROM.** Jádro umí spustit:

- stroje **MSX1** (VDP řady TMS9918),
- stroje **MSX2** (Yamaha V9938, RTC, paměťový mapper),
- **MSX turbo R** Panasonic FS-A1ST (V9958, S1990, režim R800 – jeho rychlost viz [Známá omezení](#známá-omezení)),
- **1chipMSX** (ve stylu OCM-PLD, třída MSX2+, V9958), který zavádí BIOS z obrazu SD karty.

Pro plnou funkci jádro potřebuje také **konfiguraci rozšiřujících modulů** (*FW PACK*) s dalšími ROM. Je **nezávislá na konkrétním modelu MSX** a umožňuje:
- více jazykových variant (lokalizované ROM),
- snadné budoucí rozšiřování o nový hardware.

Třetím konfiguračním souborem je **databáze ROM podle CRC32** (*DB MAPPERS*), která známým kontrolním součtům přiřazuje správný typ mapperu. Jádro tak pro každý načtený obraz ROM samo vybere vhodný mapper.

## Podporované modely MSX
**[Podporované modely MSX](ComputersModel.cs.md)** – 224 definic strojů od 36 výrobců:

| Generace | Strojů |
|---|---|
| MSX1 | 135 (124 s VDP TMS99xx, 11 s V9938 a BIOSem MSX1) |
| MSX2 | 80 |
| MSX2+ | 7 |
| MSX turbo R | 1 (Panasonic FS-A1ST; FS-A1GT není podporován) |
| 1chipMSX / OCM (třída MSX2+) | 1 |

Deset strojů z openMSX potřebuje hardware, který jádro zatím nemá; jsou vypsané na konci seznamu modelů. Obrazy ROM strojů nejsou součástí tohoto repozitáře, viz [Začínáme](#začínáme).

## Začínáme
Jádro potřebuje **alespoň balíček stroje** (ROM PACK). Zbytek závisí na tom, co chcete spustit. Soubory dejte na SD kartu MiSTeru do `/media/fat/games/MSX1/`:

| Soubor | Potřeba? | Poznámky |
|---|---|---|
| Balíček stroje `<model>.msx` | **Ano** | Bez něj nic neběží. Vytvoří se z ROM stroje pomocí `createComp.py`. Stroje C-BIOS (MSX, MSX2) a 1chipMSX lze vytvořit bez komerčních ROM, jejich ROM jsou součástí repozitáře. |
| FW balíček `CART_FW_EN.msx` nebo `CART_FW_JP.msx` | Pro **jakoukoli cartridge** | Potřeba pro každý typ cartridge, **včetně obyčejné ROM**. Obsahuje ROM cartridge (BIOS FM-PAC, `GM2.ROM`, `VY0010.ROM`, `mfrsd.ROM`, `yrw801.rom`, ...). Vytvoří se pomocí `createDev.py`. Balíčky EN a JP se liší jen ROM FM-PAC. Cartridge, jejíž ROM v balíčku chybí, se do něj nezahrne. |
| Databáze mapperů `vampier.db` | Volitelná | Potřeba pro ROM větší než 64 KB a pro ROM se speciálním mapperem. ROM do 64 KB běží bez ní jako obyčejná ROM. Hotový soubor: `tools/CreateCRC/vampier.db`. |
| Obrazy ROM `.ROM`, disků `.DSK`, pásek `.CAS` | Volitelné | `.DSK` musí být surový obraz 720K, 640K, 360K nebo 320K. |
| Obraz SD karty `.VHD` | 1chipMSX: ano | FAT16 **s tabulkou oddílů** a `OCM-BIOS.DAT` jako prvním souborem. Volitelný pro cartridge MegaFlashROM SCC+ SD. |

Balíčky pak načtěte v OSD (**Load ROM PACK**, **Load FW PACK**, **Load DB MAPPERS**). MiSTer si tyto tři soubory **pamatuje a při příštím startu jádra je načte automaticky**; ROM cartridge, disky a pásky si nepamatuje. Každé načtení znovu sestaví celý stroj.

Jak balíčky a databázi vytvořit:
- [Přehled nástrojů](tools/README.cs.md)
- [CreateMSXpack – tvorba ROM PACK a FW PACK](tools/CreateMSXpack/README.cs.md)
- Pro vývojáře (formát XML stroje, přidávání zařízení): [DEVELOPERS.cs.md](tools/CreateMSXpack/DEVELOPERS.cs.md)

Stručně: nainstalujte **Python 3**, ROM dejte do adresáře `ROM` v `tools/CreateMSXpack` nebo jinou složku předejte volbou `--rom-dir` (soubory se hledají podle SHA1, na názvech nezáleží) a spusťte `python3 createComp.py` (stroje) a `python3 createDev.py` (cartridge); volby vypíše `--help`. Soubory `.msx` vzniknou v `MSX/`.

SDRAM: MoonSound, ASCII16-X, MegaFlashROM a 1chipMSX (mapper 4 MB) potřebují modul SDRAM. Zda malé konfigurace MSX1 běží bez něj a jaká velikost SDRAM je potřeba, nebylo ověřeno.

## Funkce OSD

| Položka OSD | Poznámky |
|---|---|
| Load ROM PACK (`.MSX`) | Balíček stroje. Pamatuje se a načte se při startu jádra. |
| Load FW PACK (`.MSX`) | Balíček cartridge/rozšíření. Pamatuje se a načte se při startu jádra. |
| Load DB MAPPERS (`.DB`) | Databáze mapperů podle CRC32. Pamatuje se a načte se při startu jádra. Načtení stroj neresetuje, použije se až při dalším načtení ROM. |
| Mount Drive 1 / 2 (`.DSK`) | Zobrazuje se podle počtu mechanik stroje (nebo cartridge FDC). Dvě mechaniky jen u Philips NMS 8255. |
| Slot1 / Slot2 | Typ cartridge v slotu, viz [Rozšiřující cartridge](#podporované-rozšiřující-cartridge). Změna znovu načte konfiguraci. Na 1chipMSX se nezobrazuje, ten má vlastní volby. |
| Slot1 / Slot2 ROM Load (`.ROM`) | Zobrazuje se, je-li slot nastaven na ROM. Až 16 MB. |
| Load SD card (`.VHD`) | 1chipMSX (MegaSD) nebo MegaFlashROM SCC+ SD ve slotu 1. |
| Tape Input | File nebo ADC (analogový vstup MiSTeru). Na 1chipMSX se nezobrazuje. |
| Cas File (`.CAS`) | Obraz pásky, zobrazuje se při Tape Input = File. |
| Tape Rewind | Přetočí obraz pásky na začátek. |
| Firmware switch | Off / On, jen u strojů s S1990 (turbo R). |
| Video | Poměr stran, scandoubler (None, HQ2x, CRT 25/50/75 %), Vertical Crop, Scale (Normal, V-Integer, Narrower/Wider HV-Integer, HV-Integer), Border (platí pro VDP TMS i V99xx). |
| Reset | Reset stroje. |
| Reset & Detach ROM Cartridge | Vyprázdní ROM cartridge v obou slotech a znovu načte. Na 1chipMSX se nezobrazuje. |
| Reset and close OSD | Reset a zavření menu. |
| SRAM Save / SRAM Load | Zobrazují se, má-li cartridge SRAM, ale **nic nedělají** (viz [Známá omezení](#známá-omezení)). |

1chipMSX má navíc blok: CPU speed (Normal / Turbo, přepíná F11), CPU type (Z80 / R800 – jen násobicí instrukce R800), Slot1, Slot2, Internal Mapper (2048 / 4096 KB), Joysticks Swap, Mouse Port 1/2, Reset after Mount.

### Chybová hlášení OSD
Když načtení selže, informační řádek OSD zobrazí jedno z těchto hlášení. Po **No CRC32 DB**, **Not find CRC32 in DB** a **ROM too big** zůstane jádro v resetu do dalšího načtení.

| Hlášení | Význam |
|---|---|
| BAD MSX CONF | Soubor načtený jako ROM PACK není balíčkem stroje. |
| NOT SUPPORTED CONF | Balíček obsahuje neznámý záznam – verze balíčku a jádra si neodpovídají. |
| NOT SUPPORTED BLOCK | Balíček obsahuje neznámý typ bloku – verze balíčku a jádra si neodpovídají. |
| BAD MSX FW CONF | Soubor načtený jako FW PACK není FW balíčkem. |
| NOT FW CONF | FW balíček není načten, ale vybraná cartridge jej potřebuje (každý typ cartridge včetně obyčejné ROM), nebo v FW balíčku chybí ROM, kterou cartridge potřebuje (např. `yrw801.rom` pro MoonSound). |
| Device not in this core build | Konfigurace potřebuje víc kopií zařízení, než jádro obsahuje, např. FM-PAC v obou slotech na stroji s MSX-MUSIC, MoonSound v obou slotech. |
| No CRC32 DB | ROM větší než 64 KB potřebuje mapper, ale databáze mapperů není načtena. |
| Not find CRC32 in DB | ROM větší než 64 KB není v databázi mapperů. |
| FDC already in machine | Dva FDC na stejné pozici – chyba definice stroje. |
| ROM too big | Soubor ROM je větší než 16 MB. |

## Podporované hardwarové součásti
Jádro obsahuje tyto hardwarové moduly:
- `PPI` – [Programmable Peripheral Interface](https://www.msx.org/wiki/Programmable_Peripheral_Interface)
- `RTC` – [hodiny reálného času Ricoh RP-5C01](https://www.msx.org/wiki/Ricoh_RP-5C01) (čas se bere z MiSTeru; obsah CMOS se neukládá)
- `PSG` – [generátor zvuku AY-3-8910 / YM2149](https://www.msx.org/wiki/General_Instrument_AY-3-8910)
- `VDP` – [grafický procesor řady TMS](https://www.msx.org/wiki/Texas_Instruments_TMS9918), PAL nebo NTSC podle definice stroje
- `VDP` – Yamaha [V9938](https://www.msx.org/wiki/Yamaha_V9938) / [V9958](https://www.msx.org/wiki/Yamaha_V9958), 128 KB VRAM
- `CPU` – [Z80](https://www.msx.org/wiki/Z80) na 3,58 MHz; režim R800 u turbo R, viz [Známá omezení](#známá-omezení)
- `MEM_MAPPER` – paměťový mapper MSX2
- `KANJI` – [Kanji ROM](https://www.msx.org/wiki/Kanji_ROM) (úrovně 1 a 2; varianty pro hangul)
- `FDD` – emulace disketové mechaniky nad surovými obrazy `.DSK` (720K, 640K, 360K, 320K; podporována výměna disku)
- `WD2793` – [řadič disket](https://www.msx.org/wiki/Western_Digital_WD2793), čtení i zápis včetně Write Track (formátování); obraz chráněný proti zápisu zápisy ignoruje
- `TC8566AF` – řadič disket Toshiba v Panasonic FS-A1F a FS-A1ST, čtení i zápis
- `OPLL` – [YM2413](https://www.msx.org/wiki/Yamaha_YM2413), [MSX-MUSIC](https://www.msx.org/wiki/MSX-MUSIC) / [FM-PAC](https://www.msx.org/wiki/FM-PAC)
- `OPM` – [YM2151](https://www.msx.org/wiki/Yamaha_YM2151), vestavěný ve strojích Yamaha CX5/CX11
- `SCC` – [Konami SCC](https://www.msx.org/wiki/Konami_SCC)
- `SCC+` – [Konami 052539 Enhanced SCC](https://www.msx.org/wiki/Konami_052539)
- `OPL4` – [Yamaha YMF278B](https://www.msx.org/wiki/MoonSound) (MoonSound: FM OPL3 a 24kanálová vlnová syntéza)
- `DAC` – 8bitový DAC Konami Synthesizer
- `MIDI IN` – rozhraní MIDI YM2148 přes UART MiSTeru (MIDI OUT není podporován)
- `SFG01` – [Yamaha SFG-01](https://www.msx.org/wiki/Yamaha_SFG-01)
- `SFG05` – [Yamaha SFG-05](https://www.msx.org/wiki/Yamaha_SFG-05)
- turbo R: řadič systému `S1990` (přepínání Z80/R800 a ROM/DRAM, přepínač firmware), PCM, klávesa Pause s LED, systémový časovač; viz [MSX turbo R](https://www.msx.org/wiki/MSX_turbo_R)
- [1chipMSX](https://www.msx.org/wiki/1chipMSX): IPL ROM, přepínané I/O porty 40-4F, ESE-RAM, MegaSD s SD kartou (VHD), turbo 3,58 / 5,37 / 10,74 MHz

Neimplementováno: MSX-AUDIO, MSX-MIDI, V9990 / GFX9000, tiskárna, pádla, světelná pistole, RS-232.

## Podporované ROM mappery
ROM cartridge se k mapperu přiřazují podle databáze CRC32 (`vampier.db`, 8096 záznamů, vytvořená nástrojem [tools/CreateCRC](tools/CreateCRC/README.cs.md) z dumpu [romdb.vampier.net](https://romdb.vampier.net/)). ROM, které v databázi nejsou a mají do 64 KB, se umístí jako obyčejná ROM (první řádky tabulky).

| Mapper (název v DB) | Popis |
|---|---|
| obyčejná ROM (`0x0000`, `0x4000`, `0x8000`, `Page12`, `Page2`, `Normal`) | ROM umístěná na dané adrese; také záloha bez databáze |
| zrcadlená ROM (`Mirrored`, `Mirrored0000`, `Mirrored4000`, `Mirrored8000`) | obyčejná ROM zrcadlená přes adresní prostor; počáteční adresa `Mirrored` se určí z hlavičky ROM |
| `16kb`, `8kB` | obecné přepínání bank 16 KB a obecné 8 KB |
| `Konami` | standardní mapper Konami (banky 8 KB) |
| `KonamiSCC` | mapper Konami se zvukem SCC |
| `ASCII8` | mapper ASCII 8 KB |
| `ASCII8SRAM2`, `ASCII8SRAM8` | mapper ASCII 8 KB se 2 / 8 KB SRAM |
| `ASCII16` | mapper ASCII 16 KB |
| `ASCII16SRAM2`, `ASCII16SRAM8` | mapper ASCII 16 KB se 2 / 8 KB SRAM |
| `ASCII16-X` | mapper [ASCII16-X](https://www.grauw.nl/projects/ascii-x/ascii16-x/) s 8 MB flash ROM (změny se neukládají) |
| `NEO-8`, `NEO-16` | mappery NEO-8 (šest bank 8 KB) a NEO-16 (tři banky 16 KB) s 12bitovým číslem banky, ROM do 16 MB |
| `R-Type` | mapper R-Type |
| `Wizardry` | Wizardry (varianta ASCII 8 KB s SRAM) |
| `KoeiSRAM32` | hry KOEI s 32 KB SRAM |
| `GameMaster2` | ROM Konami Game Master 2 s 8 KB SRAM |
| `CrossBlaim` | mapper specifický pro Cross Blaim |
| `HarryFox` | mapper specifický pro Harry Fox |
| `Zemina80in1` | mapper multicartridge Zemina 80-in-1 |
| `Zemina90in1` | mapper multicartridge Zemina 90-in-1 (používá port 77h) |
| `SuperSwangi`, `MSXWrite` | speciální varianty ASCII 16 KB |
| `Synthesizer` | obyčejná ROM s DAC Konami Synthesizer |

Typy ROM z databáze, pro které jádro nemá konfiguraci, se do `vampier.db` nezapisují (27 typů, 71 ROM, např. Yamanooto, MatraCompilation, Namco, Manbow2). Taková ROM do 64 KB poběží jako obyčejná ROM, větší skončí hláškou *Not find CRC32 in DB*. Úplný seznam s počty je v [tools/CreateCRC/report.md](tools/CreateCRC/report.md). Nepodporováno je také MSX-DOS2 a MU-PACK.

Mappery uvnitř stroje (National FS-4600F, Yamaha SFG, Panasonic turbo R, paměťový mapper, ESE RAM) vycházejí z definice stroje a nelze je volit.

## Podporované rozšiřující cartridge
OSD nabízí v **Slot1** a **Slot2** tyto typy:

| Typ | Sloty | Požadavky / poznámky |
|---|---|---|
| ROM | 1, 2 | ROM se načte položkou pod slotem. Mapper z databáze, nebo obyčejná ROM. Vyžaduje FW balíček. |
| Empty | 1, 2 | |
| FDC | jen 1 | Disketové rozhraní Philips VY-0010 (WD2793, 1 mechanika); potřebuje `VY0010.ROM` v FW balíčku. **Jen na stroji bez vlastního FDC** – má-li stroj vlastní FDC, cartridge se vynechá a použije se FDC stroje. |
| SCC | 1, 2 | Zvuková cartridge Konami SCC |
| SCC+ | 1, 2 | [Konami Sound Cartridge](https://www.msx.org/wiki/Konami_Sound_Cartridge) s SCC+ a 128 KB RAM (Snatcher, SD Snatcher) |
| FM-PAC | 1, 2 | Potřebuje BIOS FM-PAC v FW balíčku; 8 KB SRAM (neukládá se). Na stroji, který už MSX-MUSIC má, se vejde jen jeden FM-PAC. |
| MegaSCC+ 1MB | jen 1 | ESE MegaSCC+ |
| MegaSCC+ 2MB | jen 2 | ESE MegaSCC+ |
| MegaRAM ASCII-8K 1MB | jen 2 | ESE [MegaRAM](https://www.msx.org/wiki/MegaRAM) |
| MegaRAM ASCII-16K 2MB | jen 2 | ESE MegaRAM |
| MegaFlashROM SCC+ SD | jen 1 | [MegaFlashROM SCC+ SD](https://www.msx.org/wiki/MegaFlashROM_SCC%2B_SD); potřebuje `mfrsd.ROM` (obraz 8 MB) v FW balíčku; SD karta přes **Load SD card** (VHD); zápisy do flash se neukládají |
| Game Master 2 | jen 1 | [Konami Game Master 2](https://www.msx.org/wiki/Konami_Game_Master_2); potřebuje `GM2.ROM` v FW balíčku; 8 KB SRAM (neukládá se) |
| MoonSound | 1, 2 | [MoonSound](https://www.msx.org/wiki/MoonSound) (OPL4); potřebuje `yrw801.rom` v FW balíčku; jen jeden MoonSound najednou; 4 MB SDRAM; na 1chipMSX není k dispozici |

1chipMSX má vlastní volby Slot1 (Empty, MegaSCC+ 1MB) a Slot2 (Empty, MegaSCC+ 2MB, MegaRAM 1MB / 2MB) a do slotů nelze načítat ROM.

## Podpora platformy MiSTerFPGA
Jádro se integruje s MiSTerFPGA a podporuje tyto funkce platformy:
- `Joystick` – dva joystickové porty MSX (čtyři směry a dvě tlačítka) z prvních dvou joysticků MiSTeru; volba prohození joysticků existuje jen na 1chipMSX
- `Klávesnice` – klávesnice PS/2, maticové rozložení pro každý stroj (`kbd_layout` v definici stroje, generuje [CreateKeyMap](tools/CreateKeyMap/README.cs.md)); klávesa Pause u turbo R, F11 = turbo na 1chipMSX
- `Myš` – myš PS/2 jako myš MSX, jen 1chipMSX
- `Kazeta` – přehrávání souborů `.CAS` (musí být zapnutý motor MSX) nebo skutečná páska přes analogový vstup MiSTeru (ADC); páska je slyšet. Výstup na pásku neexistuje.
- `MIDI IN` – přes nastavení UART/MIDI MiSTeru, předává se do YM2148 ve strojích Yamaha
- `Video` – nativní časování MSX, PAL/NTSC podle definice stroje (TMS) nebo softwarově (V99xx), volby škálování a scandoubleru
- `LED` – aktivita SD/VHD, LED turbo a pause u turbo R
- `Podpora SDRAM` – využívá externí SDRAM pro větší paměťové nároky

## Známá omezení
- Mappery NEO-8 a NEO-16 nejsou vyzkoušené na hardware. Časování V99x8, R800 a TC8566AF není na hardware ověřeno.
- **Nic se neukládá trvale:** SRAM cartridge (FM-PAC, Game Master 2, KOEI, ASCII se SRAM), zápisy do flash (MegaFlashROM, ASCII16-X) a CMOS RTC se při novém načtení ztratí. Položky **SRAM Save / SRAM Load** nic nedělají. FS-A1ST nemá 16 KB SRAM svého mapperu Panasonic.
- **Disky:** jen surové obrazy `.DSK` (720K, 640K, 360K, 320K); žádné 40stopé, 1,44 MB, XSA, D88, HFE ani DMK. WD279x Read Track je jen částečný. Cartridge FDC funguje jen ve slotu 1 a jen na strojích bez FDC; cartridge s TC8566AF neexistuje.
- **Páska:** jen přehrávání, žádné ukládání; konec souboru se nedetekuje (po posledním bloku se přehrávají nesmyslná data).
- **R800:** turbo R běží zhruba 2x rychleji než Z80 místo skutečných 4x (časování R800 není modelováno); chybí mikrofon turbo R, FS-A1GT.
- **ROM:** ROM nad 64 KB potřebuje záznam v databázi, mapper se z hlavičky ROM nerozpoznává. Zrcadla ROM Konami SCC nejsou hotová.
- **V99x8:** chybí sprity v overscanu a okno FH v textových režimech. Nastavení rychlosti VDP a hlasitosti na 1chipMSX se ukládají bez účinku.
- **1chipMSX:** bez MoonSound, bez zvláštních kláves (Pause/PrintScreen/ScrollLock).
- Žádný MIDI OUT, žádná hlasitost ani ztlumení po zdrojích v OSD, chybí deform bity 0/1 SCC+, žádné V9990.

## Poděkování
- [muhanpong/MSX1_MiSTer](https://github.com/muhanpong/MSX1_MiSTer) (větev `nextz80_v9990`) – fork tohoto jádra. Jeho analýzy chyb a hlášení ze skutečného hardware upozornily na chyby v emulaci flash a na úskalí mapperu ASCII16-X a MoonSound. Žádný kód z něj nebyl převzat; zdejší implementace jsou nezávislé.
- [openMSX](https://openmsx.org/) – reference pro chování mapperu ASCII16-X a jeho flash čipu, mapperů NEO-8 a NEO-16, vlnové části OPL4 (YMF278B), sběrnicového rozhraní a časovačů a časování V99x8.
- [Grauw](https://www.grauw.nl/projects/ascii-x/ascii16-x/) – specifikace mapperu ASCII16-X.
- [Nuked OPL3](https://github.com/nukeykt/Nuked-OPL3) od Nuke.YKT – model OPL3, proti kterému se FM část MoonSound kontroluje vzorek po vzorku. Jeho zdroj (LGPL-2.1-or-later) používá pouze test (`rtl/peripheral/SOUND/opl4/tb/nuked`).

## Licence
Toto jádro je licencováno pod GNU General Public License, verze 3 nebo novější
(viz `LICENSE`, `SPDX-License-Identifier: GPL-3.0-or-later` v hlavičkách zdrojů).
Části převzaté z jiných projektů si ponechávají vlastní licence, jak je uvedeno v hlavičkách jejich souborů
(např. framework MiSTer v `sys/`, moduly FDC z X68000_MiSTer pod GPL-3.0,
soubory odvozené z ESE / OCM-PLD, jádra CPU T80 / TV80 a VDP).
