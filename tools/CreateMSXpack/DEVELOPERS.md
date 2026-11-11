# CreateMSXpack: developer guide

**English** | [Česky](DEVELOPERS.cs.md)

How to add a machine model, an extension cartridge or a new mapper/device. User instructions (running the tools, ROM preparation) are in [README.md](README.md). Back to the [project readme](../../Readme.md).

Related: keyboard layouts [../CreateKeyMap/README.md](../CreateKeyMap/README.md), mapper database [../CreateCRC/README.md](../CreateCRC/README.md).

## 1. Overview and data flow

```
Computer/**/*.xml  ─┐
ROM/ (by SHA1)      ├─ createComp.py ─> MSX/<Vendor>/<Machine>.msx   (header "MSx")  ─ Load ROM PACK ─┐
*.json tables      ─┘                                                                                 │
Extension/*.xml    ─┐                                                                                 ├─> rtl/memory_upload.sv
ROM/ (by SHA1)      ├─ createDev.py  ─> MSX/CART_FW_EN.msx / _JP.msx (header "MsX")  ─ Load FW PACK ──┤   (builds the slot map
*.json tables      ─┘                                                                                 │    and device config)
CreateCRC: vampier.db (CRC32 -> FW ID)                                          ─ Load DB MAPPERS ────┘
```

- `createComp.py` converts a machine XML (`<msxConfig>`) into a binary list of 8-byte records (blocks, devices, keyboard layout) followed by the ROM data. The core loader `memory_upload.sv` reads it and fills its slot, memory and device tables.
- `createDev.py` converts `Extension/*.xml` (`<fwConfig>`) into a table of cartridge configurations indexed by an ID (the "FW ID"). When a cartridge slot is filled, the loader looks up the configuration for the chosen cartridge. For a ROM file, the CRC32 is looked up in the mapper DB and the DB gives the FW ID.
- `tools.py` holds the shared helpers: SHA1 scan of the ROM folder, number parsing, JSON loading and device parameter encoding.
- The JSON tables hold the numeric IDs. **They must match the RTL enums exactly.**

| JSON table | RTL enum (`rtl/package.sv`) | Content |
|---|---|---|
| `conf.json` | `conf_t` | record types (BLOCK 0, DEVICE 1, KEYBOARD_LAYOUT 2, CARTRIGE 3, END 7) |
| `block.json` | `block_t` | block types 0-11 |
| `device.json` | `device_t` (5 bit) | device names 0-22 (MEM_MAPPER = `DEV_MSX2_RAM`, TMS99xx = `DEV_VDP_TMS`, V99xx = `DEV_VDP_V99xx`) |
| `mapper.json` | `mapper_typ_t` (6 bit) | mapper names 0-40 (the spellings `GENRIC_16KB`/`GENRIC_8KB` are as in the RTL) |
| `cart_device.json` | `cart_typ_t` | FW IDs: 0-13 menu cartridges, 20-57 ROM mappers selected by the DB |
| `deviceParams.json` | `io_device.param` use of each device module | named device parameters, see section 2.6 |

Run all tools from inside `tools/CreateMSXpack`: the JSON tables and `ROM` (unless `--rom-dir`), `Extension`, `MSX` are opened by relative name (`createDev.py` also uses a temporary `ROM.bin` in the current directory).

## 2. Machine XML (`Computer/<Vendor>/<Machine>.xml`)

Root element `<msxConfig>`. Numbers can be decimal or `0x` hex (machine XML only; see the extension XML for the exception).

### 2.1 Root children

| Element | Content | Meaning |
|---|---|---|
| `<cpu>` | `Z80` or `R800` | header bits 7:6. Turbo R machines still declare `Z80`; the R800 is switched at run time by the S1990 device |
| `<wait_count>` | 0-7 | M1 wait states (header bits 5:3). All machines use `1` |
| `<cpu_frequency>` | 0, 1, 2 | 0 = 3.58, 1 = 5.39, 2 = 10.7 MHz. All machines use `0` |
| `<device>` | device name | top-level I/O device, see 2.2 |
| `<kbd_layout>` | base64 | 512-byte key map from [../CreateKeyMap/README.md](../CreateKeyMap/README.md), becomes the KEYBOARD_LAYOUT record. Every current machine embeds `key_map_eu.bin` |
| `<primary slot="0..3">` | slot tree | primary slot, see 2.3 |

Other root text elements are stored and ignored (comments in the XMLs mention `type` and `video_standard`; they have no effect).

### 2.2 Top-level `<device>`

The element text is a name from `device.json`; an unknown name prints `Device '<x>' nenalezeno` and the record is skipped. Attributes:

| Attribute | Meaning |
|---|---|
| `port`, `mask` | 8 bit each. The device decodes an access when `(addr & mask) == port` |
| named parameters | encoded through `deviceParams.json` (section 2.6): `MODE` (TMS99xx: PAL/NTSC), `VDP_ID` (V99xx: V9938/V9958), `system` (PSG: true = the machine PSG with the joystick/keyboard ports), `OCM` (PPI), `inverted` (RESET_STATUS) |
| `param` | raw 8-bit parameter for devices **without** an entry in `deviceParams.json` (for example KANJI: bit 0 = hangul, bit 1 = lascom) |
| `ROM_SHA1`, `rom_skip`, `rom_size` | the device's own ROM, appended to the record (KANJI font). If the ROM is missing the whole machine is skipped and its `.msx` is deleted |
| `shared_slot`, `shared_subslot`, `shared_block`, `shared_size` (all required together), `shared_offset` (default 0) | the device memory is a window into an existing block (1chipMSX KANJI uses the ESE-RAM block) |

Top-level devices without `shared_slot` are written first, devices with `shared_slot` after the slot tree. A device with `shared_slot` must therefore only reference blocks created by the slot tree.

### 2.3 Slot tree

```xml
<primary slot="P" [expander="0|1"] [expander_wo="0|1"] [expander_init="0xNN"]>
   <secondary slot="S"> <block ...>...</block> ... </secondary>   <!-- S = 0..3 -->
   <!-- or directly: -->
   <block ...>...</block>
</primary>
```

- A non-expanded slot has either `<block>` directly under `<primary>` or one `<secondary slot="0">`. Both give subslot 0.
- **The expander (subslot register FFFFh) is enabled automatically** when any `<secondary slot>` is greater than 0, or forced by `expander="1"`. `expander_init` is the value of FFFFh after reset (1chipMSX uses `0x2B`). `expander_wo` is stored but currently ignored by the RTL.
- **Do not mix `<block>` and `<secondary>` in one `<primary>`**: only the direct blocks are written.
- Slots are written in XML order. Convention in all files: external slots (`<cart>`) last. The reason is not documented; plausibly it is because the `FLASH` block (section 3.2) extends the memory allocated last (not verified as a hard requirement).
- Core limits: at most 64 blocks (4 slots x 4 subslots x 4 pages), 16 memory entries, 8 memory-mapped device entries.

### 2.4 `<block>`

Attributes: `start` (first 16 kB page 0-3, default 0) and `count` (pages, default 4, clipped to `4 - start`). A `<count>` child is also accepted but not used by any file; do not give both.

Children, each at most once per block (except `<device>`, which may repeat, e.g. OPM + YM2148 in one block). They are written in this order: memory, shared_memory, mapper, cart, device(s), ref.

| Child | Attributes and content | Effect |
|---|---|---|
| `<memory>ROM</memory>` | `SHA1` (lowercase hex, required), `filename` (informational, printed in the "not found" message), `skip` and `size` (bytes, decimal or hex, cut a slice from the dump), `exactFilename` (path, bypasses the SHA1 lookup; supported, unused) | ROM block. Stored in the pack padded with FF to a multiple of 16 kB (ceil(size/16 kB) must be at most 255) |
| `<memory>RAM</memory>` | `size` (bytes, default = pages x 16 kB), `pattern` (fill, default 1) | RAM block. 4 MB is encoded as 0. Fill patterns: 1 = FF, 2 = 00, 3/4/5 = DRAM power-on stripes (0 = "data from DDR", do not use for RAM). Machines use 1, 2, 3, 4 |
| `<shared_memory>` | text `ROM` = read-only, anything else read/write; `slot`, `subslot`, `block` (source), `offset`, `size` (bytes) | a window into another block's memory. The source block must already exist in the pack. See the `offset` pitfall in section 6 |
| `<mapper>NAME</mapper>` | name from `mapper.json`; optional `param` 0-3 | MAPPER record. `param` is used only by `DRAM` (which 16 kB page of the top 64 kB RAM). A ROM block without a mapper is linear (`MAPPER_OFFSET`) in the core |
| `<cart>A</cart>` | `A`/`a`/`0` or `B`/`b`/`1` | marks this block as the cartridge slot A or B (SLOT record). Normally `<block start="0">` (all 4 pages) |
| `<device>NAME</device>` | `port` + `mask` (adds an IO_DEVICE record; mask defaults to FF if only `port` is given), named parameters or raw `param` | device bound to this block (memory-mapped device or device with a mapper): `MEM_MAPPER`, `WD2793`, `TC8566AF`, `OPM`, `YM2148`, `SCC`, ... |
| `<ref to_block="n">DEVICE</ref>` or `MEMORY` | `to_block` 0-3 | `DEVICE`: this block also selects the device of block `n` (FDC registers visible in page 2 too). `MEMORY`: copy memory, mapper, mapper param and offset of block `n` |

`REF_*` refer to a block in the **same slot and subslot**, and the referenced block must come first.

Machine XML cannot declare battery SRAM; `<sram>` is honoured only in the FW pack.

### 2.5 FDC rules

- The core has **one FDC position** (and one TC8566AF). A second FDC at an occupied position raises the OSD error `FDC already in machine`.
- **The internal FDC wins over an FDC cartridge.** If the machine has an FDC and the user selects the FDC cartridge in slot A, the loader silently repeats the load without cartridge A. This is not an error.
- A slot cartridge FDC (`VY0010`) is possible **only in slot A and with 1 drive**. In slot B, or if the FDC position is not built, the error is `Device not in this core build`.
- Device copy limits (`MSX::N_*` in `rtl/package.sv`, counted over the machine and both cartridges): OPLL 2, OPM 1, SCC 2, PSG 1, DAC 2, LATCH_PORT 2, MEM_MAPPER 2, RESET_STATUS 1, OPL4 1, FDC positions 1, TC8566AF 1; others 1. Exceeding a limit gives `Device not in this core build`.

### 2.6 Device parameter encoding (`deviceParams.json`)

For a device with an entry, each named attribute contributes bits and the results are ORed. A parameter is either an `int` (value, optionally divided by `div`, checked against `min`/`max`, mapped through `values`, shifted by `value_offset`) or an `enum` (index in `enums`). An out-of-range or unknown value prints a warning and takes the `default`.

**An attribute that is absent contributes 0, not its `default`.**

| Device | Parameter | Encoding | Used by |
|---|---|---|---|
| WD2793 | `fdd_count` 1/2 | bits 3:2 = 01 / 11 | drive enable |
| | `style` Philips/National/Sony | bits 1:0 = 0/1/2 | FDC model |
| | `single_sided` false/true | bit 4 | |
| | `density` MFM/FM | bit 5 | |
| TC8566AF | `fdd_count` | bits 3:2 | |
| | `ioRegs` ""/7FF2/7FF8 | bits 1:0 = 0/1/2 | register model |
| | `single_sided` | bit 4 | |
| MEM_MAPPER | `size` bytes, divided by 16384, 1..255 | number of segments; absent = 0 = 256 segments (4 MB) | `msx2_ram.sv` |
| V99xx | `VDP_ID` V9938/V9958/UNKNOWN | values 0/2/1 | `v99.sv` |
| TMS99xx | `MODE` PAL/NTSC | 0/1 | `tms.sv` |
| PSG | `system` | bit 0 | `psg.sv` |
| PPI | `OCM` | bit 0 | `ppi.sv` |
| RESET_STATUS | `inverted` | bit 0 | `reset_status.sv` |
| OPL4 | `sampleram` bytes, divided by 131072, 0..16 | bits 4:0 | `opl4.sv` |
| YM2148 | `variant` SFG-01/SFG-05 | bit 0 | `ym2148.sv` |

Devices without an entry take the raw `param` attribute (8 bit, default 0).

### 2.7 Annotated minimal example

Derived from `Computer/Philips/Philips_NMS_8245.xml`.

```xml
<?xml version="1.0" ?>
<msxConfig>
  <cpu>Z80</cpu>                         <!-- Z80 | R800 -->
  <wait_count>1</wait_count>             <!-- M1 wait states -->
  <cpu_frequency>0</cpu_frequency>       <!-- 0=3.58 1=5.39 2=10.7 MHz -->
  <!-- I/O devices of the machine: decoded when (port & mask) == port -->
  <device mask="0xFC" port="0x98" VDP_ID="V9938">V99xx</device>   <!-- MSX1: <device mask="0xFE" port="0x98" MODE="PAL">TMS99xx</device> -->
  <device mask="0xF8" port="0xA0" system="true">PSG</device>
  <device mask="0xF8" port="0xA8">PPI</device>
  <device mask="0xFE" port="0xB4">RTC</device>
  <kbd_layout>BASE64 OF key_map_eu.bin (684 chars)</kbd_layout>
  <primary slot="0">                     <!-- not expanded: one secondary slot 0 -->
    <secondary slot="0">
      <block start="0" count="2">        <!-- pages 0-1 = 0000h-7FFFh -->
        <memory SHA1="6103b39f1e38d1aa2d84b1c3219c44f1abb5436e" filename="nms8245_basic-bios2.rom">ROM</memory>
      </block>
    </secondary>
  </primary>
  <primary slot="3">                     <!-- secondaries > 0 => expander on -->
    <secondary slot="0">
      <block start="0" count="1">
        <memory SHA1="e7905d16d2ccd57a013c122dc432106cd59ef52c" filename="nms8245_msx2sub.rom">ROM</memory>
      </block>
    </secondary>
    <secondary slot="2">
      <block start="0">                  <!-- count defaults to 4 -->
        <memory size="131072" pattern="4">RAM</memory>
        <mapper>MSX2_RAM</mapper>
        <device mask="0xFC" port="0xFC" size="131072">MEM_MAPPER</device>
      </block>
    </secondary>
    <secondary slot="3">
      <block start="1" count="1">        <!-- disk ROM at 4000h + memory-mapped FDC -->
        <memory SHA1="c3f3ca454d66a0bc791f1d4b60e6857b44eb8755" filename="nms8245_disk.rom">ROM</memory>
        <device style="Philips" fdd_count="1">WD2793</device>
      </block>
      <block start="2" count="1">        <!-- FDC registers also in page 2 -->
        <ref to_block="1">DEVICE</ref>
      </block>
    </secondary>
  </primary>
  <!-- external slots last -->
  <primary slot="1"><secondary slot="0"><block start="0"><cart>A</cart></block></secondary></primary>
  <primary slot="2"><secondary slot="0"><block start="0"><cart>B</cart></block></secondary></primary>
</msxConfig>
```

Reference files for special features:

| Feature | File |
|---|---|
| direct `<block>` under `<primary>` + `expander="1"` | `Computer/Philips/Philips_VG_8020-19.xml` |
| ROM slices (`skip`/`size`), `DRAM` mapper `param`, `PANASONIC`, `TURBO_R_FDC`, TC8566AF, `ROM_SHA1` KANJI, turbo R devices | `Computer/Panasonic/Panasonic_FS-A1ST.xml` |
| `shared_memory`, `shared_*` device, `expander_init`, OCM devices, 4 MB mapper | `Computer/OCM/1chipMSX.xml` |
| two devices in one block (OPM + YM2148) | `Computer/Yamaha/Yamaha_CX5MII_128.xml` |
| `ref MEMORY`, `NATIONAL` mapper | `Computer/National/National_FS-4600F.xml` |

## 3. Extension XML (`Extension/CART_FW_EN.xml`, `CART_FW_JP.xml`)

Root `<fwConfig>`, children `<fw name="X">`. `X` must be a key of `cart_device.json`, otherwise it is skipped (`FW name: X SKIP. Not in cart_device.json`). The two files differ only in the FM-PAC ROM SHA1, so **every change goes to both files**.

### 3.1 `<fw>` children

| Child | Meaning |
|---|---|
| `<block [start] [count] [offset] [fix_offset]>` | configuration of subslot 0. `start` default 0, `count` default 4. `offset` 0-3 gives `0x80\|offset` as the mapper parameter (for the `OFFSET` mapper: `0x0000`, `0x4000`, `0x8000`, `Synthesizer`). `fix_offset` 0-3 gives `0xC0\|n` (for `MIRROR`) |
| `<secondary slot="n"><block>...</block></secondary>` | subslot n of the cartridge (MegaFlashROM SCC+ SD uses 0-3) |
| `<expander>` | expander record for the cartridge slot; the text `expander_wo` sets the write-only flag |
| `<io_device>` | accepted and ignored |

**In the extension XML numbers are parsed with `int()`: hex values are not accepted.**

### 3.2 `<block>` children

| Child | Meaning |
|---|---|
| `<SHA1 [skip] [size]>sha1</SHA1>` | ROM of the block from the ROM folder (decimal skip/size) |
| `<filename>` | informational |
| `<mapper>` | name from `mapper.json` |
| `<device [port] [mask] [param] [named params] [memory="block"]>NAME</device>` | device. Named parameters are encoded via `deviceParams.json`. `memory="block"` means the device uses the block's memory (OPL4 wave ROM/RAM). A missing block memory gives `NOT FW CONF` in the core |
| `<ram>bytes</ram>` | RAM, pattern FF |
| `<sram>bytes</sram>` | battery SRAM, stored in 1 kB units (slot A and B get separate SRAM areas) |
| `<flash>bytes</flash>` | the memory is a flash chip of this size: loaded ROM, FF to the end (ASCII16-X, 8 MB) |
| `<extend>bytes</extend>` | same record, meaning "RAM behind the ROM" (MoonSound: 2 MB ROM + 2 MB sample RAM = 4 MB) |
| `<device_param>` | parsed but unused |

Unknown tags are logged and skipped. Per block the records are generated in this order: ROM, FLASH, RAM, MAPPER, DEVICE (+ IO_DEVICE if `port`), SRAM. `<flash>`/`<extend>` size must be below 0x2000 x 16 kB. `FLASH` extends only the memory allocated last (the cartridge ROM).

### 3.3 How menu cartridges map to FW IDs

The OSD item value is converted to `cart_typ_t` in `rtl/msx_config.sv`, and the loader fetches the FW configuration whose number is that enum value. **For menu cartridges the FW ID equals the `cart_typ_t` value** (`rtl/package.sv`).

| Slot A menu | Slot B menu | `cart_typ_t` = FW ID | `cart_device.json` name |
|---|---|---|---|
| ROM | ROM | 11 `CART_TYP_ROM` | none (via the DB, IDs 20-57) |
| FDC | not available | 5 | `VY0010` |
| SCC | SCC | 0 | `SCC` |
| SCC+ | SCC+ | 1 | `SCC+` |
| FM-PAC | FM-PAC | 2 | `FM_PAC` |
| MegaSCC+ 1MB | not available | 6 | `MEGASCC1` |
| MegaFlashROM SCC+ SD | not available | 3 | `MEGA_FLASH_ROM` |
| GameMaster2 | not available | 4 | `GM2` |
| not available | MegaSCC+ 2MB | 7 | `MEGASCC2` |
| not available | MegaRAM ASCII-8K 1MB | 8 | `MEGAASCII8` |
| not available | MegaRAM ASCII-16K 2MB | 9 | `MEGAASCII16` |
| Empty | Empty | 12 | none (the empty configuration) |
| MoonSound | MoonSound | 13 | `MOONSOUND` |
| not in a menu | not in a menu | 10 | `MEGARAM` (no menu item uses it; 1chipMSX uses the MEGARAM mapper directly in its XML) |

- `CART_TYP_ROM` (11) is special: the loader computes the CRC32 of the loaded ROM and asks the DB. The DB record gives the FW ID (20-57). A ROM of at most 64 kB that is not in the DB runs as a plain ROM, with FW ID 20/21/22 chosen from the `AB` header.
- `CART_TYP_EMPTY` (12) has no `<fw>` entry; its table slot points to the empty configuration. That is why an empty slot also needs a FW pack.
- **Free FW IDs**: 14 and 15 for new menu cartridges (`cart_typ_t` and the status fields are 4 bits). For DB mappers: 24, 37-48 except 40-42, and 58 and up.
- Menu text: `CONF_STR_SLOT_A` / `CONF_STR_SLOT_B` in `rtl/msx_config.sv`.

## 4. Recipes

### 4.1 New machine model (no new hardware)

1. Copy the closest XML in `Computer/<Vendor>/`. openMSX `share/machines/<name>.xml` is the reference the existing files follow.
2. Fill the devices, the slot tree and the ROM SHA1s (`sha1sum` of the dumps). Embed a key map in `<kbd_layout>` (base64 of a `.bin` from CreateKeyMap).
3. Respect the core limits in 2.3 and 2.5.
4. Build only this machine and watch the console:
   ```
   python createComp.py --xml-dir Computer/<Vendor> --output-dir <dir> --debug
   ```
   There must be no `ROM SHA1 not found` line. `--debug` prints every record (`DEVIC:`, `BLOCK:` with slot/subslot/page).
5. Test (section 8).

### 4.2 New menu cartridge

1. `cart_device.json`: add the name with ID 14 or 15 (must equal the new `cart_typ_t` value).
2. Add `<fw name="...">` in **both** `CART_FW_EN.xml` and `CART_FW_JP.xml`.
3. RTL: add the value to `cart_typ_t` (`rtl/package.sv`) at that position. In `rtl/msx_config.sv` add the menu text to `CONF_STR_SLOT_A` / `_B` and the `case` lines. Status fields are 4 bits: at most 16 items.
4. Rebuild the FW pack (`python createDev.py`) and copy it to the SD card.
5. If the cartridge needs a new mapper, device or block type, see 4.4.

### 4.3 New ROM mapper selected by the DB

1. Give the FW configuration a free ID (24, 37-48 except 40-42, 58+) in `cart_device.json` and add `<fw>` in both Extension XMLs.
2. In `../CreateCRC/romtypes.json` add one line `"RomType": "fw name"` to `types`. `RomType` is the name in the "Not supported" table of `../CreateCRC/report.md`; the FW ID is taken from `cart_device.json`.
3. Rebuild the FW pack and `vampier.db` (see [../CreateCRC/README.md](../CreateCRC/README.md)).
4. If the mapper itself is new hardware, see 4.4.

`createDB.py` writes only types whose FW configuration exists, so a ROM never gets an empty configuration. Its report lists the unsupported types with counts, which tells which mapper is worth adding.

### 4.4 New device, mapper or block type (RTL places)

- **Device**: add the name to `device.json` and to `device_t` (`rtl/package.sv`, same position, 5 bit, max 31); optionally an entry in `deviceParams.json`; the module in `rtl/msx/devices/` (listed in its `files.qip`); an instance in `rtl/msx/devices.sv` taking `io_device[DEV_X]` (OPL4 is an example). For a device that can exist in several copies add `N_X` and the `dev_slots()` case in `rtl/package.sv`. Sound devices must also be added to the sound mixer.
- **Mapper**: add to `mapper.json` and to `mapper_typ_t` (insert before `MAPPER_UNUSED` and keep the numbering identical to the JSON); the module in `rtl/msx/msx_slots/mappers/` and its `files.qip`; an instance in `rtl/msx/msx_slots/mappers.sv` selected by `block_info.typ == MAPPER_X` (see `ascii16x.sv`).
- **Block or record type**: add to `block.json` / `conf.json` and to `block_t` / `conf_t`, and handle it in `memory_upload.sv` (`STATE_PROCESS_BLOCK` / `STATE_LOAD_CONF`). Otherwise the core reports `NOT SUPPORTED BLOCK` / `NOT SUPPORTED CONF`.
- Code must pass Quartus 17 (watch 32-bit literals in typed expressions, packed-to-unpacked array assignments and size casts).

## 5. Pack binary format (brief)

### 5.1 Machine pack (`MSx`)

- Header, 8 bytes: `'M' 'S' 'x' conf 0 0 0 0`, where `conf = cpu<<6 | (wait_count & 7)<<3 | (cpu_frequency & 7)`.
- Records are 8 bytes, the first byte is the record type. Order: top-level devices without `shared_slot`, all `<primary>` slots in XML order, top-level devices with `shared_slot`, the keyboard layout. There is no END record: the end of the file ends the pack.
- BLOCK record: `00 addr type p0 p1 p2 p3 p4` with `addr = slot<<6 | subslot<<4 | start_page<<2 | (count-1)`.
- DEVICE record (top level): `01 dev_id port mask param size16k shared_ref shared_off`. If `size16k` > 0 and there is no `shared_ref`, the ROM data follows. `shared_ref = 0x80 | slot<<4 | subslot<<2 | block`.
- KEYBOARD_LAYOUT: `02 00 00 00 00 00 00 00` followed by the 512-byte table.

| Block type | Name | Parameters (createComp) |
|---|---|---|
| 0 | RAM | p0 = size/16 kB (0 = 256 = 4 MB), p1 = fill pattern |
| 1 | ROM | p0 = ceil(size/16 kB); data follows |
| 2 | SRAM | FW pack only |
| 3 | DEVICE | p0 = device id, p1 = param |
| 4 | MAPPER | p0 = mapper id, p1 = (param&3)<<2 |
| 5 | SLOT (cartridge) | p0 = 0 (A) / 1 (B) |
| 6 | REF_MEM | p0 = to_block |
| 7 | REF_DEV | p0 = to_block |
| 8 | IO_DEVICE | p0 = port, p1 = mask, p2 = param |
| 9 | EXPANDER | addr = slot<<6 only; p0 = wo<<1 \| enable, p1 = init value of FFFFh |
| 10 | SHARED_MEM | p0 = slot<<4\|subslot<<2\|block, p1 = offset/16 kB, p2 = size/16 kB, p3 = ro |
| 11 | FLASH | FW pack only; extend the last memory to N x 16 kB |

### 5.2 FW pack (`MsX`)

- 16-byte header: `'M' 's' 'X' 00`, a uint32 LE file offset of the ROM table, 8 zero bytes.
- At 0x10: 256 x uint32 LE file offset of configuration N (N = FW ID). Unused IDs point to an empty configuration (a single END record).
- A configuration is a list of 6-byte records `type addr block_type p1 p2 p3`, ended by `07 00 00 00 00 00`. The slot bits of `addr` are 0, the core ORs in the cartridge slot.
- The ROM table is a uint32 LE offset per distinct ROM (deduplicated by skip, size and SHA1), followed by the ROM images padded with FF to 16 kB.

## 6. Pitfalls

1. **An absent named parameter encodes as 0**, not as its `default` (e.g. WD2793 without `fdd_count` gives no enabled drive bits; the effect in the core has not been verified).
2. **MEM_MAPPER `size` of 4 MB: omit the attribute.** `size="4194304"` gives 256 segments, which is above the maximum 255, so a warning is printed and the default (1 segment, 16 kB) is used. Absent means 256 segments.
3. **`shared_memory offset="0"` is decoded by the core as 4 MB.** Do not use offset 0.
4. The **`variant` attribute of OPM has no effect** (OPM has no `deviceParams.json` entry and the module ignores `param`). The YM2148 `variant` (`SFG-01`/`SFG-05`) does work.
5. **In the extension XML a device with `port` gets the raw `param`**, not the encoded named parameters (the IO_DEVICE record is written with the raw attribute and overwrites the DEVICE param in the core). MegaFlashROM SCC+ SD relies on it: MEM_MAPPER `param="32"` = 32 x 16 kB = 512 kB. createComp, in contrast, writes the encoded value into IO_DEVICE.
6. Hex numbers work in the machine XML but **not in the extension XML**.
7. Do not mix `<block>` and `<secondary>` in one `<primary>`.
8. SHA1 values in XML must be lowercase hex.
9. A pack is written even when ROMs are missing; only a missing top-level device `ROM_SHA1` deletes it. Check the console.
10. `<sram>` works only in FW configurations; a machine XML cannot declare SRAM.
11. `expander_wo` is stored but ignored by the RTL.
12. Run the tools from inside `tools/CreateMSXpack` (JSON tables by relative name). The ROM folder can be elsewhere: `--rom-dir` in both tools.
13. Both extension XMLs must be edited together.

## 7. Console messages

The full table of messages and OSD errors with their meaning is in the [README](README.md#troubleshooting). Developer-relevant extras:

| Message | Where | Meaning |
|---|---|---|
| `Missing SHA1 for ROM in slot s/ss` | createComp | `<memory>ROM</memory>` with neither `SHA1` nor `exactFilename` |
| `Error, block contain multiple count` | createComp | both `count` attribute and `<count>` child |
| `Processing unknown element: <tag>` | createComp | unknown child of `<primary>` |
| `Error: missing attribut ... in shared_memory` | createComp | the rest of that slot is abandoned |
| `Device 'X' parameter 'p' value v ... setting to default` | tools.py | bad named parameter, default used |
| `Unknown mapper type`, `Unknown device type`, `Tag name: X SKIP` | createDev | name not in the JSON tables, or an unknown tag |

## 8. Testing

1. Build and read the console (section 4.1). No `ROM SHA1 not found`.
2. On the MiSTer: Load FW PACK, Load ROM PACK. Watch for OSD errors (README, "OSD errors in the core").
3. Simulation (Verilator runs in WSL; paths there are `/mnt/c/...`):
   - Machine boot: `wsl.exe -- bash rtl/tb/run_machine_boot.sh <machine.msx> <image.dsk|none> [expected text]`. Plusargs, passed in `SIMARGS`: `+run_ms=`, `+fw=<FW pack>`, `+db=`, `+rom=<cart ROM>`, `+slota=`, `+slotb=`, `+key=`, `+vram_dump=`. Disk image helper: `rtl/tb/make_dsk_image.py`.
   - Loader regression: `rtl/tb/run_mu_equiv.sh <packs dir> <CART_FW.msx> <ROM set dir>`, `run_memory_upload.sh` (OCM), `run_cart_rom.sh <VG_8020 pack> <CART_FW_EN.msx>`, `run_mu_restart.sh`, `run_ocm_boot.sh`.
   - `run_mu_equiv.sh` compares the loader against the reference revision; run it after any change of `memory_upload.sv` or of the pack format.
4. Synthesis with Quartus is run separately; its result was not part of these tools.
