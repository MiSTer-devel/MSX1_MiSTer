# CreateKeyMap: keyboard tables

**English** | [Česky](README.cs.md)

Back to [tools](../README.md) | [main Readme](../../Readme.md).

## Purpose

The core translates the PS/2 keyboard (as MiSTer delivers it) to the MSX keyboard matrix with a
512-byte table. This tool builds those tables from readable JSON files. It is a developer tool:
users do not need it, because the tables are already embedded in the machine packs.

The table is indexed by the MiSTer key code `ps2_key[8:0]` (bit 8 = E0-extended key). The value is
one byte: the high nibble is the MSX matrix row, the low nibble is the column bit. `0xFF` means no
key.

## Prerequisites

- Python 3, standard library only (`createKeyMap.py`).
- Run it from this folder (`tools/CreateKeyMap`): it reads `map/` and `keyboard/` by relative path
  and writes the `.bin` files into the current directory.

## Usage

```
cd tools/CreateKeyMap
python createKeyMap.py
```

There are no options. For every `map/**/*.json` it writes `key_map_<name>.bin` (512 bytes, filled
with `FF`). It always rewrites all of them; re-running on unchanged inputs gives byte-identical
files.

Messages:

| Message | Meaning |
|---|---|
| `<name>` | the map being processed |
| `Nenalezen <key>` ("not found") | a key assigned in the map is not in `keyboard/ps2.json`; it is ignored |
| `Klavesa nema scancode <key>` | the key is in `ps2.json` but has an empty scancode |

## Files

| File | Role |
|---|---|
| `createKeyMap.py` | the generator |
| `keyboard/ps2.json` | key name to PS/2 set-2 scancode string, `"0xNN"`. E0-extended keys are `0x1NN` (for example GRAPH = right Alt `0x111`, STOP `0x17c`, HOME `0x16c`, the cursors `0x16b`/`0x175`/`0x172`/`0x174`, INS `0x170`, DEL `0x171`). CODE = F10 (`0x09`), SELECT = F11 (`0x78`). |
| `map/eu.json`, `map/us.json`, `map/International.json` | a comment block with the matrix and an `"assign"` object: key name to `"0xRC"` (row R, column bit C) or `null` |
| `key_map_eu.bin`, `key_map_us.bin`, `key_map_International.bin` | the generated tables |
| `matrix.yaml` | not used by any script |
| `ps2map.py` | helper, see below |
| `scancode_debugger.py` | helper, see below |

`map/eu.json` describes the standard MSX international matrix (rows 0-10). Its comment block is the
reference table of the matrix.

## How the keymaps get into machine packs

1. `createKeyMap.py` writes `key_map_<name>.bin`.
2. The `.bin` is encoded as base64 and pasted into the `<kbd_layout>` element of the machine XML
   (`tools/CreateMSXpack/Computer/<Vendor>/<Machine>.xml`).
3. `createComp.py` decodes it and writes it into the machine pack as a KEYBOARD_LAYOUT record
   (a record header followed by the 512 bytes).
4. When the pack is loaded, the core copies the table into the keyboard RAM.

The `.bin` files are therefore **not copied to the SD card**. All machine XMLs currently embed
`key_map_eu.bin`. After you change a table you must update `<kbd_layout>` and rebuild the packs.

## Adding a new keyboard layout

1. Copy `map/eu.json` to `map/<name>.json`.
2. Edit the `"assign"` object. Each key name (the left side) is a PC key from `keyboard/ps2.json`,
   the value is the matrix position `"0xRC"` from the comment table (R = row, C = column bit
   number). Several PC keys may point to the same matrix position. One PC key gives exactly one
   position: the table has no notion of Shift state, so you cannot make one PC key produce
   different MSX keys depending on Shift.
3. If a key you assign is not in `keyboard/ps2.json`, add it there (`"NAME": "0xNN"`, or `"0x1NN"`
   for an E0-extended key). Keys missing from `ps2.json` are skipped with the message
   `Nenalezen <key>`.
4. Run `python createKeyMap.py`. A new file `key_map_<name>.bin` appears (the existing ones are
   rewritten too).
5. Encode it as base64 on one line, for example `base64 -w0 key_map_<name>.bin`, or in Python
   `base64.b64encode(open("key_map_<name>.bin", "rb").read()).decode()`.
6. Paste the result into `<kbd_layout>` in the machine XML and rebuild the pack with
   `createComp.py` (see [../CreateMSXpack](../CreateMSXpack/README.md)).
7. Test on the machine; check especially Shift, Ctrl, Graph, Code, the cursors and the function
   keys.

## Helper scripts

- `ps2map.py`: only defines a dictionary `ps2set2` of PS/2 set-2 scancodes with the MiSTer
  modifier flags. Nothing imports it; it is a reference.
- `scancode_debugger.py`: an interactive helper that prints the PC scancodes of pressed keys.
  Needs the pip package `keyboard`. It has bugs (it refers to an undefined variable `scancode`
  after a match and stops after the first dictionary entry), so treat it as a scratch tool, not
  as something to rely on.

## Known limitations

- **The `us` and `International` maps have no SHIFT key.** Their `assign` uses the name `SHIFT`,
  but `ps2.json` has only `SHIFT_L` and `SHIFT_R`, so the entries are dropped (the Shift scancodes
  stay `FF`). `International` also loses `~ ^ : @`, and `us` loses `~`. These two maps describe a
  different matrix than `eu`; where it comes from has not been verified.
- **The keypad (`NUM_*` keys) is not mapped in any of the three tables.**
- **All machines use the `eu` map.** The other two are not used by any machine XML.
- One PC key maps to one matrix position; no Shift-dependent translation.
- `matrix.yaml` is unused (no script reads YAML) and uses a non-standard row list; do not treat it
  as the reference, use the comment block of `map/eu.json`.
