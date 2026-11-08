#!/usr/bin/env python3
"""Builds a FAT16 SD card image with one file stored first and contiguous
(as OCM needs OCM-BIOS.DAT), optionally followed by more files in the root
directory (each contiguous). Used by the OCM boot simulation.

usage: make_sd_image.py <file> <image> [--name OCM-BIOS.DAT] [--mbr] [--size-mb 32]
                        [--add NAME.EXT=path ...]
"""
import argparse
import struct

SECTOR = 512
SEC_PER_CLUS = 4            # 2 kB clusters
CLUSTER = SEC_PER_CLUS * SECTOR
RESERVED = 1
NUM_FATS = 2
ROOT_ENTRIES = 512
PART_START = 2048           # first partition LBA with --mbr


def boot_sector(total_sectors, fat_sectors, hidden):
    bs = bytearray(SECTOR)
    bs[0:3] = b'\xEB\x3C\x90'
    bs[3:11] = b'MSDOS5.0'
    struct.pack_into('<HBHBHHBHHHII', bs, 11,
                     SECTOR, SEC_PER_CLUS, RESERVED, NUM_FATS, ROOT_ENTRIES,
                     total_sectors if total_sectors < 0x10000 else 0, 0xF8, fat_sectors,
                     63, 255, hidden, total_sectors if total_sectors >= 0x10000 else 0)
    struct.pack_into('<BBBI', bs, 36, 0x80, 0, 0x29, 0x12345678)
    bs[43:54] = b'NO NAME    '
    bs[54:62] = b'FAT16   '
    bs[510:512] = b'\x55\xAA'
    return bs


def dir_entry(name, cluster, size):
    base, _, ext = name.upper().partition('.')
    e = bytearray(32)
    e[0:11] = base.ljust(8)[:8].encode() + ext.ljust(3)[:3].encode()
    e[11] = 0x20
    struct.pack_into('<HI', e, 26, cluster if size else 0, size)
    return e


def fat16_volume(files, total_sectors, hidden):
    """files: list of (name, payload); the first one starts at cluster 2."""
    clusters_est = total_sectors // SEC_PER_CLUS
    fat_sectors = (clusters_est * 2 + SECTOR - 1) // SECTOR
    root_sectors = ROOT_ENTRIES * 32 // SECTOR
    data_start = RESERVED + NUM_FATS * fat_sectors + root_sectors
    clusters = (total_sectors - data_start) // SEC_PER_CLUS
    assert 4085 <= clusters < 65525, 'not a FAT16 size'

    vol = bytearray(total_sectors * SECTOR)
    vol[0:SECTOR] = boot_sector(total_sectors, fat_sectors, hidden)
    fat = bytearray(fat_sectors * SECTOR)
    struct.pack_into('<HH', fat, 0, 0xFFF8, 0xFFFF)
    root = (RESERVED + NUM_FATS * fat_sectors) * SECTOR

    cl = 2
    first_lba = None
    for k, (name, payload) in enumerate(files):
        n = (len(payload) + CLUSTER - 1) // CLUSTER
        for i in range(n):
            struct.pack_into('<H', fat, (cl + i) * 2, 0xFFFF if i == n - 1 else cl + i + 1)
        vol[root + 32 * k:root + 32 * k + 32] = dir_entry(name, cl, len(payload))
        o = (data_start + (cl - 2) * SEC_PER_CLUS) * SECTOR
        vol[o:o + len(payload)] = payload
        if first_lba is None:
            first_lba = data_start
        cl += n
    for f in range(NUM_FATS):
        o = (RESERVED + f * fat_sectors) * SECTOR
        vol[o:o + len(fat)] = fat
    return vol, first_lba


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('image')
    ap.add_argument('--name', default='OCM-BIOS.DAT')
    ap.add_argument('--mbr', action='store_true', help='partition table, volume at LBA 2048')
    ap.add_argument('--size-mb', type=int, default=32)
    ap.add_argument('--add', action='append', default=[], metavar='NAME=PATH',
                    help='more root directory files (8.3 name)')
    a = ap.parse_args()

    files = [(a.name, open(a.file, 'rb').read())]
    for spec in a.add:
        name, _, path = spec.partition('=')
        files.append((name, open(path, 'rb').read()))
    sectors = a.size_mb * 1024 * 1024 // SECTOR
    if a.mbr:
        vol, data = fat16_volume(files, sectors - PART_START, PART_START)
        img = bytearray(PART_START * SECTOR) + vol
        mbr = bytearray(SECTOR)
        struct.pack_into('<BBBBBBBBII', mbr, 446, 0x00, 1, 1, 0, 0x06, 254, 63, 255,
                         PART_START, sectors - PART_START)
        mbr[510:512] = b'\x55\xAA'
        img[0:SECTOR] = mbr
        data += PART_START
    else:
        img, data = fat16_volume(files, sectors, 0)
    open(a.image, 'wb').write(img)
    print(f'{a.image}: {len(img)} B, {len(files)} files, {a.name} {len(files[0][1])} B at LBA {data}')


if __name__ == '__main__':
    main()
