# CreateCRC: databáze mapperů

[English](README.md) | **Česky**

Zpět na [nástroje](../README.cs.md) | [hlavní Readme](../../Readme.md).

## Účel

Jádro musí vědět, jaký mapper ROM cartridge používá. U ROM větších než 64 kB se to uhodnout
nedá, proto jádro hledá CRC32 ROM v databázi. Databáze je soubor `vampier.db`, který se v OSD
nahrává položkou **Load DB MAPPERS**. Skripty v této složce ji vyrábějí.

Bez databáze:
- ROM do 64 kB s hlavičkou `AB` se pořád spustí jako plain ROM;
- větší ROM skončí hláškou OSD `No CRC32 DB`;
- větší ROM, jejíž CRC32 není v nahrané databázi, skončí hláškou `Not find CRC32 in DB`.

## Musím ji stavět?

**Ne, jako uživatel ne.** V repozitáři je hotový `vampier.db`; zkopíruj ho na SD kartu
(`/media/fat/games/MSX1/`) a nahraj přes Load DB MAPPERS. Kopíruj `vampier.db`, **ne**
`mappers.db` (to je starý výstup zastaralého skriptu `crc32.py`).

Přestavuj ji jen když chceš přidat ROM, změnit mapper ROM nebo přidat nový typ mapperu.

## Požadavky

- Python 3.8 nebo novější, jen standardní knihovna.
- Internet pro `createDB.py` (stahuje veřejnou databázi z romdb.vampier.net).
- Skripty spouštěj z této složky (`tools/CreateCRC`): soubory otevírají relativním jménem.

## Soubory a skripty

| Soubor | Role |
|---|---|
| `createDB.py` | **Hlavní generátor.** Stáhne `https://romdb.vampier.net/Archive//msxcoreromdb.txt` (řádky `CRC32 <mezera> jméno mapperu`), přimíchá `mappersOverride.txt` (přepis vyhrává podle řetězce CRC), **přepíše** `mappersSplit.txt` sloučeným seznamem, zapíše `vampier.db` pro jména nalezená v `mappers.json` a vypíše tabulky „Known mappers“ / „Unknown mappers“. Bez voleb. Obsahuje i zbytkový ladicí výpis `NALEZENO` pro jedno CRC. |
| `mappers.json` | Jméno mapperu v databázi → `[FW ID, b5, b6, b7]`. FW ID je číslo konfigurace cartridge ve FW packu. Aliasy: `Normal` = 26, `basic` = 28, `GenericKonami` = 25 (Generic8kB), `Mirrored0000/4000/8000` = 26/27/28. |
| `mappersOverride.txt` | Tvoje doplňky a přepisy, jeden `CRC32<TAB>jméno` na řádek. **Edituje se ručně.** |
| `mappersSplit.txt` | Sloučený seznam z posledního běhu `createDB.py` (CRC velkými písmeny, tabulátor). Vstup pro `sort.py`. Při každém běhu se přepíše. |
| `vampier.db` | Výstup. Tohle jde na SD kartu. |
| `crc32toTxt.py` | Projde složku s ROM (`.ROM .rom .BIN .bin`, rekurzivně) a pro ROM do 64 kB zapíše řádky `CRC32<TAB>mapper`: `0x0000`, `0x4000` nebo `0x8000` podle hlavičky `AB`, nebo `ASCII16-X`, když bajty 16–23 jsou `ASCII16X`. Větší ROM ohlásí (`Chyba při zpracování souboru ...`) a přeskočí. |
| `crc32.py` | Zastaralý generátor `mappers.db`. Nepoužívat (viz Úskalí). |
| `mappers.db`, `mappers2.json` | Starý výstup / stará varianta `mappers.json`. Nepoužité. |
| `sort.py` | Pomůcka: přesune ROM z `ROM/` do `ROM_NALEZENO/<mapper>/` podle CRC z `mappersSplit.txt`. Soubory **přesouvá**. |
| `platform.py`, `platform.txt` | Pomůcka: přesune ROM z `ROM/` do `ROM_NALEZENO/<platforma>/` podle SHA1 z `platform.txt`. Soubory **přesouvá**. |

### createDB.py

```
python createDB.py
```

Bez voleb. Vstup: stažený soubor, `mappersOverride.txt`, `mappers.json`. Výstup: `vampier.db`,
`mappersSplit.txt`. Na konci si přečti seznam „Unknown mappers“: tato jména nejsou v
`mappers.json`, takže se jejich záznamy zahodí (ROM do 64 kB pak běží jako plain ROM, větší
selžou).

### crc32toTxt.py

Skutečný výstup nápovědy:

```
usage: crc32toTxt.py [-h] [--rom-dir ROM_DIR] [--output OUTPUT]

Process ROM auto, Mirrored, Normal mappers and detect start

options:
  -h, --help         show this help message and exit
  --rom-dir ROM_DIR  Path to the ROM files directory (default:
                     c:/Project/_OBSAH/ROMS)
  --output OUTPUT    Path to the output file (default: mappersOverride.txt)
```

Příklad (výstup jde do nového souboru, ne přes tvůj seznam přepisů):

```
python crc32toTxt.py --rom-dir C:\roms\new --output new.txt
```

## Jak přidat nebo přepsat mapper ROM

1. Zjisti CRC32 **celého souboru ROM** jako 8 hexadecimálních číslic velkými písmeny. U malé ROM
   ho zapíše `crc32toTxt.py --rom-dir <adresář> --output new.txt` spolu s odhadnutým mapperem;
   stejně dobře poslouží jiný nástroj na CRC32. Piš velkými písmeny: klíč při slučování je
   doslovný řetězec, takže `99c1fdb4` a `99C1FDB4` by byly dva různé záznamy.
2. Na konec `mappersOverride.txt` připiš řádek `CRC32<TAB>JménoMapperu`. `JménoMapperu` musí být
   klíč v `mappers.json` (například `ASCII16-X`, `Konami`, `KonamiSCC`, `ASCII8SRAM8`,
   `Mirrored4000`, `0x4000`).
3. Spusť `python createDB.py` a zkontroluj seznam „Unknown mappers“.
4. Nový `vampier.db` zkopíruj na SD kartu a nahraj přes Load DB MAPPERS.

Záznam v databázi má přednost před rozpoznáním plain ROM podle hlavičky. ROM, která má běžet jako
plain ROM (například ROM `vdptest`), proto v databázi **být nesmí**.

Chceš-li použít mapper, který v `mappers.json` ještě není, musí mít nejdřív konfiguraci ve FW
packu a pak záznam v `mappers.json` s jejím číslem. To je práce pro vývojáře, viz
[../CreateMSXpack/DEVELOPERS.cs.md](../CreateMSXpack/DEVELOPERS.cs.md).

## Formát záznamu databáze

`vampier.db` je prostá posloupnost 8bajtových záznamů bez hlavičky:

| Bajty | Obsah |
|---|---|
| 0–3 | CRC32 ROM, 32bitové little endian |
| 4 | FW ID (první hodnota v `mappers.json`): konfigurace cartridge, která se použije |
| 5–7 | zbylé tři hodnoty z `mappers.json` |

Jádro používá jen CRC32 a FW ID; bajty 5–7 se k volbě mapperu nepoužívají.

## Úskalí

- **`crc32toTxt.py` bez `--output` přepíše `mappersOverride.txt`** (nesloučí). Vždy zadej
  `--output` a soubor s přepisy si zálohuj.
- **`crc32.py` je zastaralý.** Mapper bere z `[jména]` v názvu souboru ROM, má pevně zadanou
  složku s ROM a **neznámá jména připisuje do `mappers.json` s novými ID**, čímž rozbije vazbu ID
  na konfigurace. Použij `createDB.py`.
- **`platform.py` zastíní standardní modul `platform`**, když Python běží s touto složkou jako
  složkou skriptu nebo jako aktuálním adresářem. Jiný skript či balíček, který odsud importuje
  `platform`, spustí tento soubor. Jiné pythonovské nástroje spouštěj z jiné složky.
- **ID mapperů bez konfigurace cartridge.** `mappers.json` mapuje některá jména na ID, pro která
  FW pack dnes konfiguraci nemá: Arc 37, MatraInk 38, MatraCompilation 39, playball 43,
  AlQuranDecoded 44, Majutsushi 45, SuperLodeRunner 46, Halnote 47, NettouYakyuu 48 (22 záznamů
  v `vampier.db`) a `"vv NERESENO vv"` = 3. ROM uvedené pod těmito jmény dostanou prázdnou
  konfiguraci. Co pak slot ukáže, nebylo ověřeno.
- **Jména neznámá `mappers.json`** `createDB.py` zahodí (například `Mirrored`, `Page2`, `8kB`,
  `auto`); ROM do 64 kB pak běží jako plain ROM.
- `crc32toTxt.py` má výchozí složku s ROM, která existuje jen na autorově počítači; vždy zadej
  `--rom-dir`.
- `sort.py` a `platform.py` soubory z `ROM/` přesouvají; zkus je na kopii.
