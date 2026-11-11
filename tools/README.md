# Tools

**English** | [Česky](README.cs.md)

Helper tools of the MSX core for MiSTer. Back to the [main Readme](../Readme.md).

| Tool | What it is for | Who needs it |
|---|---|---|
| [CreateMSXpack](CreateMSXpack/README.md) | Builds the machine packs and the FW pack | users and developers |
| [CreateCRC](CreateCRC/README.md) | Builds the mapper database for ROM cartridges | developers (users take the ready-made `vampier.db`) |
| [CreateKeyMap](CreateKeyMap/README.md) | Builds the PS/2 to MSX keyboard tables | developers |
| [vdptest](vdptest/README.md) | VDP timing test ROMs | developers and testers |

## Quick start for users

Copy these files to the SD card into `/media/fat/games/MSX1/`:

| File | Required? | Made by | OSD item |
|---|---|---|---|
| machine pack `.msx` (one per machine, e.g. `<Vendor>/<Machine>.msx`) | yes, at least one | `createComp.py` from [CreateMSXpack](CreateMSXpack/README.md) | Load ROM PACK |
| FW pack `CART_FW_EN.msx` or `CART_FW_JP.msx` (they differ only in the FM-PAC ROM) | practically yes: without it cartridge slots do not work, not even "Empty" | `createDev.py` from [CreateMSXpack](CreateMSXpack/README.md) | Load FW  PACK |
| mapper database `vampier.db` | optional; needed for ROM cartridges larger than 64 kB | ready-made in `CreateCRC/vampier.db`, no build needed | Load DB MAPPERS |

Steps:
1. Install Python 3.
2. Put the BIOS/firmware ROM dumps into `tools/CreateMSXpack/ROM/` (you must supply them yourself;
   only the C-BIOS ROMs are included).
3. In `tools/CreateMSXpack` run `python createComp.py` and `python createDev.py`; the packs appear
   in `MSX/`. Details and the meaning of the console messages are in the
   [CreateMSXpack README](CreateMSXpack/README.md).
4. Copy the contents of `MSX/` and `tools/CreateCRC/vampier.db` to `/media/fat/games/MSX1/`.
5. In the OSD load the FW pack, the database (optional) and the machine pack.

Game ROMs (`*.rom`) are loaded straight from the SD card in the OSD (slot 1/slot 2 = ROM); they
are not made by any tool. The keyboard tables are not copied to the SD card: they are embedded in
the machine packs.

## Tools

### CreateMSXpack

Converts the machine definitions (`Computer/**/*.xml`) and your BIOS ROM images into the machine
packs `.msx`, and the cartridge definitions (`Extension/*.xml`) into the FW pack. ROMs are matched
by SHA1 of the file content, not by file name.

Start (in `tools/CreateMSXpack`): `python createComp.py` and `python createDev.py`.
Documentation: [README](CreateMSXpack/README.md) | [README.cs](CreateMSXpack/README.cs.md).

### CreateCRC

Builds the CRC32 to mapper table (`vampier.db`) that the core uses to choose the mapper of a ROM
cartridge. Users do not have to build it. It is useful when a ROM is missing in the database or
needs a different mapper.

Start (in `tools/CreateCRC`): `python createDB.py` (needs internet access).
Documentation: [README](CreateCRC/README.md) | [README.cs](CreateCRC/README.cs.md).

### CreateKeyMap

Builds the 512-byte tables that translate PS/2 scancodes to the MSX keyboard matrix. They are
embedded in the machine XML files; all machines currently use the `eu` table.

Start (in `tools/CreateKeyMap`): `python createKeyMap.py`.
Documentation: [README](CreateKeyMap/README.md) | [README.cs](CreateKeyMap/README.cs.md).

### vdptest

Test ROMs (`vdptest.rom`, `vdptest_auto.rom`, `cmdbench.rom`) that measure VDP timing: status
flags, interrupts and command duration on TMS9918A/28A/29A, V9938 and V9958. The ROMs are built
and in the repository, you just load them as a game ROM into slot A.

Start: `sh tools/vdptest/build.sh` (rebuild only).
Documentation: [README](vdptest/README.md) | [README.cs](vdptest/README.cs.md).

## For developers

- **New machine model or extension cartridge:** see
  [CreateMSXpack/DEVELOPERS.md](CreateMSXpack/DEVELOPERS.md)
  ([Česky](CreateMSXpack/DEVELOPERS.cs.md)).
- **New keyboard layout:** [CreateKeyMap](CreateKeyMap/README.md).
- **Mapper of a specific ROM (override) or a new mapper name:** [CreateCRC](CreateCRC/README.md).
- **VDP timing checks:** [vdptest](vdptest/README.md).

The Python scripts use only the standard library, except the debugging helper
`CreateKeyMap/scancode_debugger.py` (needs the `keyboard` package). The scripts must be run from
their own folder, because they open their data files by relative name.
