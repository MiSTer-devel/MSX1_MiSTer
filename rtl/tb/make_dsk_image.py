#!/usr/bin/env python3
"""Builds a 720 kB MSX-DOS floppy image (FAT12, media F9h, 2 sides, 9 sectors, 80
tracks) with files in the root directory. The boot sector has a jump at 0 and RET at
1Eh, so the disk ROM finds no DOS and Disk BASIC starts (and runs AUTOEXEC.BAS).
Used by the machine boot simulation.

usage: make_dsk_image.py <image> [--add NAME.EXT=path ...] [--text NAME.EXT="line|line"]
  --text writes an ASCII BASIC / text file, '|' separates lines (CR LF, ends with 1Ah)
"""
import argparse
import struct

SECTOR = 512
TOTAL = 1440
SEC_PER_CLUS = 2
RESERVED = 1
NUM_FATS = 2
FAT_SECTORS = 3
ROOT_ENTRIES = 112
MEDIA = 0xF9
ROOT_START = RESERVED + NUM_FATS * FAT_SECTORS          # 7
DATA_START = ROOT_START + ROOT_ENTRIES * 32 // SECTOR   # 14
CLUSTER = SEC_PER_CLUS * SECTOR


def boot_sector():
    bs = bytearray(SECTOR)
    bs[0:3] = b'\xEB\xFE\x90'
    bs[3:11] = b'MSXSIM  '
    struct.pack_into('<HBHBHHBHHHH', bs, 11, SECTOR, SEC_PER_CLUS, RESERVED, NUM_FATS,
                     ROOT_ENTRIES, TOTAL, MEDIA, FAT_SECTORS, 9, 2, 0)
    bs[0x1E] = 0xC9                                     # boot code: RET (no DOS)
    return bs


def dir_entry(name, cluster, size):
    base, _, ext = name.upper().partition('.')
    e = bytearray(32)
    e[0:11] = base.ljust(8)[:8].encode() + ext.ljust(3)[:3].encode()
    e[11] = 0x20
    struct.pack_into('<HHHI', e, 22, 0, 0x5821, cluster, size)    # date 2024-01-01
    return e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--add', action='append', default=[], metavar='NAME.EXT=path')
    ap.add_argument('--text', action='append', default=[], metavar='NAME.EXT=lines')
    a = ap.parse_args()

    files = []
    for spec in a.add:
        name, _, path = spec.partition('=')
        files.append((name, open(path, 'rb').read()))
    for spec in a.text:
        name, _, text = spec.partition('=')
        files.append((name, ('\r\n'.join(text.split('|')) + '\r\n').encode('ascii') + b'\x1A'))

    img = bytearray(TOTAL * SECTOR)
    img[0:SECTOR] = boot_sector()
    fat = [0xFF9, 0xFFF]                                # media F9h
    root = bytearray()
    clus = 2
    for name, data in files:
        n = max(1, (len(data) + CLUSTER - 1) // CLUSTER)
        off = (DATA_START + (clus - 2) * SEC_PER_CLUS) * SECTOR
        img[off:off + len(data)] = data
        fat += [clus + i + 1 for i in range(n - 1)] + [0xFFF]
        root += dir_entry(name, clus if data else 0, len(data))
        clus += n
    fat_bytes = bytearray(FAT_SECTORS * SECTOR)
    fat_bytes[0] = MEDIA
    for i in range(0, len(fat), 2):
        lo, hi = fat[i], fat[i + 1] if i + 1 < len(fat) else 0
        fat_bytes[i * 3 // 2:i * 3 // 2 + 3] = bytes([lo & 0xFF, (lo >> 8) | ((hi & 0xF) << 4), hi >> 4])
    fat_bytes[0] = MEDIA
    for f in range(NUM_FATS):
        o = (RESERVED + f * FAT_SECTORS) * SECTOR
        img[o:o + len(fat_bytes)] = fat_bytes
    img[ROOT_START * SECTOR:ROOT_START * SECTOR + len(root)] = root
    open(a.image, 'wb').write(img)
    print(f'{a.image}: {len(files)} files, {clus - 2} clusters')


if __name__ == '__main__':
    main()
