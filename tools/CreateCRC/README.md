# CreateCRC: mapper database

**English** | [Česky](README.cs.md)

Back to [tools](../README.md) | [main Readme](../../Readme.md).

## Purpose

The core has to know which mapper a ROM cartridge uses. For ROMs larger than 64 kB there is no way
to guess it, so the core looks the ROM's CRC32 up in a database. The database is the file
`vampier.db`, loaded in the OSD with **Load DB MAPPERS**. `createDB.py` builds it from the public
ROM database [romdb.vampier.net](https://romdb.vampier.net/) (SQL dump `sql-msxromdb.zip`).

Without a database:
- a ROM up to 64 kB still runs as a plain ROM, placed by its `AB` header;
- a larger ROM fails with the OSD message `No CRC32 DB`;
- a larger ROM whose CRC32 is not in the loaded database fails with `Not find CRC32 in DB`.

## Do I need to build it?

**No, as a user you do not.** The repository contains a ready-made `vampier.db`; copy it to the SD
card (`/media/fat/games/MSX1/`) and load it with Load DB MAPPERS.

Rebuild it when the online database has new ROMs, when you want to change the mapper of a ROM, or
after a new mapper was added to the core.

## Prerequisites

- Python 3.8 or newer, standard library only.
- Internet access (the dump is downloaded), or a downloaded `sql-msxromdb.zip` / `.sql` file.

## Files

| File | Role |
|---|---|
| `createDB.py` | The builder. |
| `romtypes.json` | ROM type of the online database → FW pack configuration. **The only file to edit when a mapper is added.** |
| `mappersOverride.txt` | Exceptions for single ROMs, applied last. Edit by hand. |
| `vampier.db` | Output for the core. This is what goes to the SD card. |
| `report.md` | Output: supported and unsupported mappers with counts (see below). |

## Usage

```
python createDB.py [--source SOURCE] [--output OUTPUT] [--report REPORT]
                   [--list LIST] [--roms ROMS] [--prune]
```

| Option | Meaning |
|---|---|
| `--source` | URL, `.zip` or `.sql` of the dump. Default `https://romdb.vampier.net/Archive/sql-msxromdb.zip`. |
| `--output` | Database file. Default `vampier.db`. |
| `--report` | Report file. Default `report.md`; the report is also printed. |
| `--list FILE` | Also write every record as text: CRC32, FW configuration, ROM type, size in kB, platform, name. Handy to compare two builds. |
| `--roms DIR` | Folder with your ROM files (searched recursively). Mirrored ROMs without a header at offset 0 are then placed by the real header at 4000h instead of a guess. |
| `--prune` | Remove lines from `mappersOverride.txt` that the dump already gives. |

Typical run:
```
cd tools/CreateCRC
python createDB.py
```
Then copy `vampier.db` to the SD card and load it with Load DB MAPPERS.

## How the database is built

1. The SQL dump is loaded into an in-memory SQLite database. Only tables and inserts are allowed
   while it loads (no `ATTACH`, `PRAGMA` and the like).
2. Kept: ROMs with a CRC32, active, of the platforms in `romtypes.json` (`MSX`, `MSX2`, `MSX2Plus`,
   `MSX Turbo-R`), up to 16 MB. Left out: other platforms (ColecoVision, SG-1000, SVI), the
   types in `ignore` (`System` = BIOS ROMs, `auto` = not classified).
3. The ROM type is translated by `romtypes.json`. A type whose FW configuration does not exist is
   not written; it is listed in the report as unsupported.
4. `Mirrored` and `Normal` ROMs have no address in the dump. It comes from the first bytes of the
   ROM (`StartBytes` in the dump): `AB` + INIT in 8000h-BFFFh (or INIT 0 and a BASIC TEXT pointer
   at 8000h) → 8000h; INIT in 0001h-3FFFh → 0000h; otherwise 4000h. Without a header at offset 0
   the ROM goes to 0000h, as the core does without a record (`--roms` gives the exact answer).
5. `mappersOverride.txt` is applied last.
6. Records are written sorted by CRC32.

## The report

`report.md` has two main sections, each sorted by the number of ROMs:

- **Supported**: per FW configuration the number of ROMs, how many come from an override, and the
  ROM types of the dump that map to it.
- **Not supported**: ROM types of the dump the core has no configuration for, with the number of
  ROMs and games, how many are **over 64 kB** (those cannot run at all without the mapper), the
  biggest size and example titles. This is the list of mappers worth adding to the core: the more
  ROMs over 64 kB, the more it pays off.

The head of the report compares the new file with the previous `vampier.db` (added, removed,
changed records). At the end it lists what was left out of the dump and why.

## Adding a mapper

When the FW pack has a configuration for the mapper (`<fw name="...">` in
`../CreateMSXpack/Extension/*.xml` and its ID in `../CreateMSXpack/cart_device.json`), only one
line is needed:

1. In `romtypes.json`, section `types`, add `"RomType": "fw name"`, e.g.
   `"Namco": "NAMCO"`. `RomType` is the name from the "Not supported" table of the report.
2. Run `python createDB.py` and check that the type moved to "Supported".
3. Rebuild the FW pack (`createDev.py`) if its configuration is new, copy both files to the SD card.

If the mapper is new hardware, the RTL and FW work comes first, see
[../CreateMSXpack/DEVELOPERS.md](../CreateMSXpack/DEVELOPERS.md).

A type whose address depends on the header is written as
`{"by_header": ["config at 0000h", "config at 4000h", "config at 8000h"]}`.

## Fixing the mapper of one ROM

Add a line to `mappersOverride.txt`:
```
CRC32<TAB>name
```
`name` is a ROM type from `romtypes.json` (e.g. `Mirrored8000`) or a FW configuration name (e.g.
`0x4000`, `KONAMI`). Lines starting with `#` are comments. Unknown names are reported and ignored.

A database record beats the plain-ROM detection by header. A ROM that should run as a plain ROM
(for example the `vdptest` ROMs) must therefore **not** be in the database.

## Database record format

`vampier.db` is a plain sequence of 8-byte records with no header, sorted by CRC32:

| Bytes | Content |
|---|---|
| 0-3 | CRC32 of the whole ROM file, 32-bit little endian |
| 4 | FW ID: number of the cartridge configuration in the FW pack (`cart_device.json`) |
| 5-7 | 0 (not used by the core) |

The core searches the file from the start and takes the first match; the file may be up to 1 MB.

## Notes

- The dump also contains columns with personal data (IP addresses, company addresses). The
  script reads only ROM type, CRC32, size, first bytes, platform and name. Do not commit the dump;
  `.gitignore` here excludes `*.sql` and `*.zip`.
- The address of mirrored ROMs over 16 kB without a header at offset 0 is a guess unless `--roms`
  is used (count in the report). For ROMs up to 16 kB all three mirrored variants behave the same.
