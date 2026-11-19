"""Test set for run_mu_equiv.sh: synthetic cartridge ROMs and mapper databases.

usage: mu_equiv_roms.py <output dir>

rom00.rom .. romNN.rom: different sizes and MSX headers (plain ROM placement of memory_upload).
db0.db .. db5.db: mapper databases (8 bytes per ROM: CRC32 LE, FW configuration id, 3 x 0).
Each database gives the ROMs other configurations of tools/CreateMSXpack/cart_device.json,
so that all of them are loaded; a few ROMs stay out of each database (plain ROM / no entry),
and one id points to an unused configuration.
"""
import os
import random
import struct
import sys
import zlib

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
rnd = random.Random(20261110)

# (size, offset of 'AB' or None, INIT)
ROMS = [
    (0x2000,  0x0000, 0x4010),   # 8 kB, page 1
    (0x4000,  0x0000, 0x8010),   # 16 kB, page 2
    (0x4000,  0x0000, 0x0000),   # INIT 0
    (0x8000,  0x0000, 0x4010),
    (0x8000,  None,   0),        # no header
    (0xC000,  0x4000, 0x4010),   # 'AB' only at 4000h
    (0x10000, 0x0000, 0x0010),   # 64 kB, page 0
    (40000,   0x0000, 0x4010),   # not a multiple of 8 kB
    (0x12000, 0x0000, 0x4010),   # 72 kB: needs a mapper
    (0x20000, 0x0000, 0x4010),
    (0x40000, 0x0000, 0x4010),
    (100,     None,   0),        # shorter than a header page
]

# FW configuration ids of ROM mappers (cart_device.json) and one unused id
IDS = [20, 21, 22, 23, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 40, 41, 42, 49, 50, 51, 52, 53, 54, 55, 56, 60]

crcs = []
for i, (size, hdr, init) in enumerate(ROMS):
    d = bytearray(rnd.getrandbits(8) for _ in range(size))
    for a in range(0, size - 1, 0x4000):         # no stray 'AB'
        d[a] = 0
    if hdr is not None and hdr + 4 <= size:
        d[hdr:hdr + 4] = b'AB' + struct.pack('<H', init)
    open(os.path.join(out, f'rom{i:02d}.rom'), 'wb').write(d)
    crcs.append(zlib.crc32(d) & 0xFFFFFFFF)

for k in range(6):
    db = bytearray()
    for i, crc in enumerate(crcs):
        if (i + k) % 5 == 4:                     # not in this database
            continue
        db += struct.pack('<I4B', crc, IDS[(i * 7 + k * 5) % len(IDS)], 0, 0, 0)
    for _ in range(40):                          # entries of other ROMs around
        db[rnd.randrange(0, len(db) // 8 + 1) * 8:0] = struct.pack('<I4B', rnd.getrandbits(32), rnd.choice(IDS), 0, 0, 0)
    open(os.path.join(out, f'db{k}.db'), 'wb').write(db)
print(f'{len(ROMS)} ROMs, 6 databases in {out}')
