#!/usr/bin/env python3
"""Test fixtures for the MSX-DOS2 cartridge boot (run_msxdos2_boot.sh).

From msxdos2-asc8-mapper.rom (MSX-DOS 2.20 patched for the ASCII8 mapper) it writes:
  <out>/dos2_msxdos2.rom  the patch undone: bank switch "ld (6000h),a / ret" at 0092h in every
                          16 KB bank (byte 94h = 60h, openMSX RomMSXDOS2 range 60h) and INIT
                          406Ah; a reconstruction, not necessarily equal to the original cartridge
  <out>/mappers.db        <db> plus both ROMs: the patched one -> ASCII8, the other -> MSXDOS2
Usage: msxdos2_rom.py <msxdos2-asc8-mapper.rom> <vampier.db> <out dir>
"""
import os
import struct
import sys
import zlib

PATCH_SHA_LEN = 0x10000
FW_ASCII8, FW_MSXDOS2 = 50, 60                     # cart_device.json

src, db_in, out = sys.argv[1:4]
rom = bytearray(open(src, 'rb').read())
assert len(rom) == PATCH_SHA_LEN, 'expected the 64 KB ASCII8 patched MSX-DOS2 ROM'

for b in range(0, len(rom), 0x4000):
    k = rom[b:b + 0x4000]
    # patched: INIT 409Dh, at 0092h push af/rlca/ld (6000h),a/inc a/ld (6800h),a/pop af/ret,
    # at 009Dh ld a,1/ld (6800h),a/jp 406Ah
    assert k[0:4] == b'AB\x9d\x40', 'unexpected header'
    assert k[0x92:0xA5] == bytes.fromhex('f507320060 3c320068f1c9 3e01320068c36a40'.replace(' ', '')), \
        'unexpected bank switch code'
    rom[b + 2:b + 4] = b'\x6a\x40'
    rom[b + 0x92:b + 0xA5] = bytes.fromhex('320060c9') + bytes(0xA5 - 0x96)
    assert rom[b + 0x94] == 0x60

os.makedirs(out, exist_ok=True)
with open(os.path.join(out, 'dos2_msxdos2.rom'), 'wb') as f:
    f.write(rom)

db = open(db_in, 'rb').read()
rec = {struct.unpack_from('<I', db, i)[0]: db[i + 4] for i in range(0, len(db) - 7, 8)}
rec[zlib.crc32(open(src, 'rb').read())] = FW_ASCII8
rec[zlib.crc32(rom)] = FW_MSXDOS2
with open(os.path.join(out, 'mappers.db'), 'wb') as f:
    for c in sorted(rec):
        f.write(struct.pack('<I4B', c, rec[c], 0, 0, 0))
print(f'dos2_msxdos2.rom CRC32 {zlib.crc32(rom):08X}, mappers.db {len(rec)} records')
