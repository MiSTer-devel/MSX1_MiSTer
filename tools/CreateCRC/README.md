# CreateCRC: mapper database

**English** | [Česky](README.cs.md)

Back to [tools](../README.md) | [main Readme](../../Readme.md).

## Purpose

The core has to know which mapper a ROM cartridge uses. For ROMs larger than 64 kB there is no way
to guess it, so the core looks the ROM's CRC32 up in a database. The database is the file
`vampier.db`, loaded in the OSD with **Load DB MAPPERS**. The scripts here build it.

Without a database:
- a ROM up to 64 kB with an `AB` header still runs as a plain ROM;
- a larger ROM fails with the OSD message `No CRC32 DB`;
- a larger ROM whose CRC32 is not in the loaded database fails with `Not find CRC32 in DB`.

## Do I need to build it?

**No, as a user you do not.** The repository contains a ready-made `vampier.db`; copy it to the SD
card (`/media/fat/games/MSX1/`) and load it with Load DB MAPPERS. Copy `vampier.db`, **not**
`mappers.db` (that is an old output of the legacy script `crc32.py`).

Rebuild it only when you want to add a ROM, change the mapper of a ROM, or add a new mapper type.

## Prerequisites

- Python 3.8 or newer, standard library only.
- Internet access for `createDB.py` (it downloads the public database from romdb.vampier.net).
- Run the scripts from this folder (`tools/CreateCRC`): they open their files by relative name.

## Files and scripts

| File | Role |
|---|---|
| `createDB.py` | **Main builder.** Downloads `https://romdb.vampier.net/Archive//msxcoreromdb.txt` (lines `CRC32 <whitespace> mapper name`), merges in `mappersOverride.txt` (the override wins per CRC string), **overwrites** `mappersSplit.txt` with the merged list, writes `vampier.db` for the names found in `mappers.json`, and prints the tables "Known mappers" / "Unknown mappers". No options. It also contains a leftover debug print `NALEZENO` for one CRC. |
| `mappers.json` | Mapper name in the database to `[FW ID, b5, b6, b7]`. FW ID is the configuration number of the cartridge in the FW pack. Aliases: `Normal` = 26, `basic` = 28, `GenericKonami` = 25 (Generic8kB), `Mirrored0000/4000/8000` = 26/27/28. |
| `mappersOverride.txt` | Your additions and overrides, one `CRC32<TAB>name` per line. **Edit by hand.** |
| `mappersSplit.txt` | The merged list from the last `createDB.py` run (uppercase CRC, tab). Input for `sort.py`. Rewritten on every run. |
| `vampier.db` | The output. This is what goes to the SD card. |
| `crc32toTxt.py` | Scans a folder of ROMs (`.ROM .rom .BIN .bin`, recursively) and writes `CRC32<TAB>mapper` lines for ROMs up to 64 kB: `0x0000`, `0x4000` or `0x8000` from the `AB` header, or `ASCII16-X` when bytes 16-23 are `ASCII16X`. Larger ROMs are reported (`Chyba při zpracování souboru ...`) and skipped. |
| `crc32.py` | Legacy generator of `mappers.db`. Do not use (see Pitfalls). |
| `mappers.db`, `mappers2.json` | Old output / old variant of `mappers.json`. Unused. |
| `sort.py` | Helper: moves ROMs from `ROM/` into `ROM_NALEZENO/<mapper>/` by CRC from `mappersSplit.txt`. It **moves** files. |
| `platform.py`, `platform.txt` | Helper: moves ROMs from `ROM/` into `ROM_NALEZENO/<platform>/` by SHA1 from `platform.txt`. It **moves** files. |

### createDB.py

```
python createDB.py
```

No options. Input: the download, `mappersOverride.txt`, `mappers.json`. Output: `vampier.db`,
`mappersSplit.txt`. Read the "Unknown mappers" list at the end: those names are not in
`mappers.json`, so their records are dropped (those ROMs then fall back to a plain ROM when they are
up to 64 kB, otherwise they fail).

### crc32toTxt.py

Real help output:

```
usage: crc32toTxt.py [-h] [--rom-dir ROM_DIR] [--output OUTPUT]

Process ROM auto, Mirrored, Normal mappers and detect start

options:
  -h, --help         show this help message and exit
  --rom-dir ROM_DIR  Path to the ROM files directory (default:
                     c:/Project/_OBSAH/ROMS)
  --output OUTPUT    Path to the output file (default: mappersOverride.txt)
```

Example (the output goes to a new file, not over your override list):

```
python crc32toTxt.py --rom-dir C:\roms\new --output new.txt
```

## How to add or override a ROM's mapper

1. Get the CRC32 of the **whole ROM file** as 8 uppercase hex digits. For a small ROM
   `crc32toTxt.py --rom-dir <dir> --output new.txt` writes it together with a guessed mapper; any
   other CRC32 tool works as well. Use uppercase: the merge key is the literal string, so
   `99c1fdb4` and `99C1FDB4` would be two different entries.
2. Append a line `CRC32<TAB>MapperName` to `mappersOverride.txt`. `MapperName` must be a key of
   `mappers.json` (for example `ASCII16-X`, `Konami`, `KonamiSCC`, `ASCII8SRAM8`, `Mirrored4000`,
   `0x4000`).
3. Run `python createDB.py` and check the "Unknown mappers" list.
4. Copy the new `vampier.db` to the SD card and load it with Load DB MAPPERS.

A database entry beats the plain-ROM detection by header. So a ROM that should run as a plain ROM
(for example the `vdptest` ROMs) must **not** be in the database.

To use a mapper that is not in `mappers.json` yet, the mapper first needs a configuration in the FW
pack, then a `mappers.json` entry with its number. That is a developer task, see
[../CreateMSXpack/DEVELOPERS.md](../CreateMSXpack/DEVELOPERS.md).

## Database record format

`vampier.db` is a plain sequence of 8-byte records with no header:

| Bytes | Content |
|---|---|
| 0-3 | CRC32 of the ROM, 32-bit little endian |
| 4 | FW ID (first value in `mappers.json`): the cartridge configuration to use |
| 5-7 | the remaining three values from `mappers.json` |

The core uses only the CRC32 and the FW ID; bytes 5-7 are not used for the mapper choice.

## Pitfalls

- **`crc32toTxt.py` without `--output` overwrites `mappersOverride.txt`** (it does not merge). Always
  pass `--output`, and keep a copy of the override file.
- **`crc32.py` is legacy.** It reads the mapper from `[name]` in the ROM file name, uses a hard-coded
  ROM folder, and **appends unknown names to `mappers.json` with new IDs**, which breaks the mapping
  of IDs to configurations. Use `createDB.py`.
- **`platform.py` shadows the stdlib module `platform`** when Python runs with this folder as the
  script folder or as the current directory. Another script or package that imports `platform` from
  here will run this file instead. Run other Python tools from a different folder.
- **Mapper IDs without a cartridge configuration.** `mappers.json` maps some names to IDs for which
  the FW pack currently has no configuration: Arc 37, MatraInk 38, MatraCompilation 39,
  playball 43, AlQuranDecoded 44, Majutsushi 45, SuperLodeRunner 46, Halnote 47, NettouYakyuu 48
  (22 records in `vampier.db`), and `"vv NERESENO vv"` = 3. ROMs listed under those names get an empty
  configuration. What the slot then shows has not been verified.
- **Names unknown to `mappers.json`** are dropped by `createDB.py` (for example `Mirrored`, `Page2`,
  `8kB`, `auto`); the ROMs fall back to a plain ROM when they are up to 64 kB.
- `crc32toTxt.py` has a default ROM folder that exists only on the author's machine; always pass
  `--rom-dir`.
- `sort.py` and `platform.py` move files out of `ROM/`; try them on a copy.
