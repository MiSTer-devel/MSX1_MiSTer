# CreateCRC: databáze mapperů

[English](README.md) | **Česky**

Zpět na [nástroje](../README.cs.md) | [hlavní Readme](../../Readme.cs.md).

## Účel

Jádro musí vědět, jaký mapper ROM cartridge používá. U ROM větších než 64 kB se to uhodnout nedá,
proto jádro hledá CRC32 ROM v databázi. Databáze je soubor `vampier.db`, který se v OSD nahrává
přes **Load DB MAPPERS**. `createDB.py` ji vyrobí z veřejné databáze ROM
[romdb.vampier.net](https://romdb.vampier.net/) (SQL dump `sql-msxromdb.zip`).

Bez databáze:
- ROM do 64 kB poběží jako obyčejná ROM, umístěná podle hlavičky `AB`;
- větší ROM skončí hláškou OSD `No CRC32 DB`;
- větší ROM, jejíž CRC32 v nahrané databázi není, skončí hláškou `Not find CRC32 in DB`.

## Musím ji vyrábět?

**Ne, jako uživatel ne.** V repozitáři je hotový `vampier.db`; zkopíruj ho na SD kartu
(`/media/fat/games/MSX1/`) a nahraj přes Load DB MAPPERS.

Znovu ji vyrob, když online databáze obsahuje nové ROM, když chceš změnit mapper některé ROM, nebo
po přidání nového mapperu do jádra.

## Předpoklady

- Python 3.8 nebo novější, jen standardní knihovna.
- Internet (dump se stahuje), nebo stažený soubor `sql-msxromdb.zip` / `.sql`.

## Soubory

| Soubor | Úloha |
|---|---|
| `createDB.py` | Generátor. |
| `romtypes.json` | Typ ROM z online databáze → konfigurace FW packu. **Jediný soubor, který se mění při přidání mapperu.** |
| `mappersOverride.txt` | Výjimky pro jednotlivé ROM, uplatní se nakonec. Edituje se ručně. |
| `vampier.db` | Výstup pro jádro. Tohle jde na SD kartu. |
| `report.md` | Výstup: podporované a nepodporované mappery s počty (viz níže). |

## Použití

```
python createDB.py [--source SOURCE] [--output OUTPUT] [--report REPORT]
                   [--list LIST] [--roms ROMS] [--prune]
```

| Volba | Význam |
|---|---|
| `--source` | URL, `.zip` nebo `.sql` s dumpem. Výchozí `https://romdb.vampier.net/Archive/sql-msxromdb.zip`. |
| `--output` | Soubor databáze. Výchozí `vampier.db`. |
| `--report` | Soubor reportu. Výchozí `report.md`; report se zároveň vypíše. |
| `--list SOUBOR` | Zapíše navíc každý záznam jako text: CRC32, konfigurace FW, typ ROM, velikost v kB, platforma, název. Hodí se k porovnání dvou sestavení. |
| `--roms ADRESÁŘ` | Adresář s tvými ROM (prohledává se rekurzivně). Zrcadlené ROM bez hlavičky na offsetu 0 se pak umístí podle skutečné hlavičky na 4000h místo odhadu. |
| `--prune` | Odstraní z `mappersOverride.txt` řádky, které už dává dump. |

Běžné spuštění:
```
cd tools/CreateCRC
python createDB.py
```
Pak zkopíruj `vampier.db` na SD kartu a nahraj přes Load DB MAPPERS.

## Jak se databáze sestaví

1. SQL dump se načte do SQLite v paměti. Při načítání jsou povolené jen tabulky a vkládání
   (žádné `ATTACH`, `PRAGMA` a podobně).
2. Ponechají se ROM s CRC32, aktivní, platforem uvedených v `romtypes.json` (`MSX`, `MSX2`,
   `MSX2Plus`, `MSX Turbo-R`), do 16 MB. Vynechají se jiné platformy (ColecoVision, SG-1000, SVI)
   a typy v `ignore` (`System` = ROM BIOSů, `auto` = nezařazené).
3. Typ ROM se převede podle `romtypes.json`. Typ, jehož konfigurace FW neexistuje, se nezapíše;
   report ho uvede mezi nepodporovanými.
4. ROM typu `Mirrored` a `Normal` nemají v dumpu adresu. Ta se určí z prvních bajtů ROM
   (`StartBytes` v dumpu): `AB` + INIT v 8000h–BFFFh (nebo INIT 0 a ukazatel BASIC TEXT na 8000h)
   → 8000h; INIT v 0001h–3FFFh → 0000h; jinak 4000h. Bez hlavičky na offsetu 0 jde ROM na 0000h,
   stejně jako to udělá jádro bez záznamu (`--roms` dá přesnou odpověď).
5. Nakonec se uplatní `mappersOverride.txt`.
6. Záznamy se zapíšou seřazené podle CRC32.

## Report

`report.md` má dvě hlavní sekce, každou seřazenou podle počtu ROM:

- **Supported** (podporované): pro každou konfiguraci FW počet ROM, kolik z nich je z výjimek
  a které typy ROM z dumpu na ni vedou.
- **Not supported** (nepodporované): typy ROM z dumpu, pro které jádro nemá konfiguraci, s počtem
  ROM a her, kolik jich má **přes 64 kB** (ty bez mapperu nepoběží vůbec), největší velikostí
  a příklady titulů. To je seznam mapperů, které stojí za to přidat do jádra: čím víc ROM přes
  64 kB, tím víc se to vyplatí.

Hlavička reportu porovná nový soubor s předchozím `vampier.db` (přidané, odebrané a změněné
záznamy). Na konci je, co se z dumpu vynechalo a proč.

## Přidání mapperu

Když má FW pack pro mapper konfiguraci (`<fw name="...">` v `../CreateMSXpack/Extension/*.xml`
a její ID v `../CreateMSXpack/cart_device.json`), stačí jeden řádek:

1. V `romtypes.json`, sekce `types`, přidej `"TypROM": "název fw"`, např. `"Namco": "NAMCO"`.
   `TypROM` je název z tabulky „Not supported“ v reportu.
2. Spusť `python createDB.py` a zkontroluj, že se typ přesunul do „Supported“.
3. Je-li konfigurace ve FW packu nová, znovu sestav FW pack (`createDev.py`) a oba soubory
   zkopíruj na SD kartu.

Je-li mapper nový hardware, nejdřív je potřeba práce v RTL a ve FW, viz
[../CreateMSXpack/DEVELOPERS.cs.md](../CreateMSXpack/DEVELOPERS.cs.md).

Typ, jehož adresa závisí na hlavičce, se zapíše jako
`{"by_header": ["konfigurace na 0000h", "konfigurace na 4000h", "konfigurace na 8000h"]}`.

## Oprava mapperu jedné ROM

Přidej řádek do `mappersOverride.txt`:
```
CRC32<TAB>název
```
`název` je typ ROM z `romtypes.json` (např. `Mirrored8000`) nebo název konfigurace FW (např.
`0x4000`, `KONAMI`). Řádky začínající `#` jsou komentáře. Neznámé názvy skript ohlásí a vynechá.

Záznam v databázi má přednost před rozpoznáním obyčejné ROM podle hlavičky. ROM, která má běžet
jako obyčejná ROM (například ROM `vdptest`), proto v databázi **být nesmí**.

## Formát záznamu databáze

`vampier.db` je prostá posloupnost 8bajtových záznamů bez hlavičky, seřazená podle CRC32:

| Bajty | Obsah |
|---|---|
| 0–3 | CRC32 celého souboru ROM, 32 bitů little endian |
| 4 | FW ID: číslo konfigurace cartridge ve FW packu (`cart_device.json`) |
| 5–7 | 0 (jádro je nepoužívá) |

Jádro prochází soubor od začátku a vezme první shodu; soubor smí mít až 1 MB.

## Poznámky

- Dump obsahuje i sloupce s osobními údaji (IP adresy, adresy firem). Skript čte jen typ ROM,
  CRC32, velikost, první bajty, platformu a název. Dump necommituj; `.gitignore` v této složce
  vylučuje `*.sql` a `*.zip`.
- Adresa zrcadlených ROM nad 16 kB bez hlavičky na offsetu 0 je bez `--roms` odhad (počet je
  v reportu). U ROM do 16 kB se všechny tři zrcadlené varianty chovají stejně.
