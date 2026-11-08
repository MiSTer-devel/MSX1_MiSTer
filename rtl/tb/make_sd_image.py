#!/usr/bin/env python3
"""Builds a FAT16 SD card image with one file stored first and contiguous
(as OCM needs OCM-BIOS.DAT). Used by the OCM boot simulation.

usage: make_sd_image.py <file> <image> [--name OCM-BIOS.DAT] [--mbr] [--size-mb 32]
"""
import argparse
import struct

SECTOR = 512
SEC_PER_CLUS = 4            # 2 kB clusters
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


def fat16_volume(payload, name, total_sectors, hidden):
    clusters_est = total_sectors // SEC_PER_CLUS
    fat_sectors = (clusters_est * 2 + SECTOR - 1) // SECTOR
    root_sectors = ROOT_ENTRIES * 32 // SECTOR
    data_start = RESERVED + NUM_FATS * fat_sectors + root_sectors
    clusters = (total_sectors - data_start) // SEC_PER_CLUS
    assert 4085 <= clusters < 65525, 'not a FAT16 size'

    vol = bytearray(total_sectors * SECTOR)
    vol[0:SECTOR] = boot_sector(total_sectors, fat_sectors, hidden)

    n = (len(payload) + SEC_PER_CLUS * SECTOR - 1) // (SEC_PER_CLUS * SECTOR)
    fat = bytearray(fat_sectors * SECTOR)
    struct.pack_into('<HH', fat, 0, 0xFFF8, 0xFFFF)
    for i in range(n):
        struct.pack_into('<H', fat, (2 + i) * 2, 0xFFFF if i == n - 1 else 3 + i)
    for f in range(NUM_FATS):
        o = (RESERVED + f * fat_sectors) * SECTOR
        vol[o:o + len(fat)] = fat

    base, ext = name.upper().split('.')
    entry = bytearray(32)
    entry[0:11] = base.ljust(8).encode() + ext.ljust(3).encode()
    entry[11] = 0x20
    struct.pack_into('<HI', entry, 26, 2, len(payload))
    o = (RESERVED + NUM_FATS * fat_sectors) * SECTOR
    vol[o:o + 32] = entry

    o = data_start * SECTOR
    vol[o:o + len(payload)] = payload
    return vol, data_start


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('image')
    ap.add_argument('--name', default='OCM-BIOS.DAT')
    ap.add_argument('--mbr', action='store_true', help='partition table, volume at LBA 2048')
    ap.add_argument('--size-mb', type=int, default=32)
    a = ap.parse_args()

    payload = open(a.file, 'rb').read()
    sectors = a.size_mb * 1024 * 1024 // SECTOR
    if a.mbr:
        vol, data = fat16_volume(payload, a.name, sectors - PART_START, PART_START)
        img = bytearray(PART_START * SECTOR) + vol
        mbr = bytearray(SECTOR)
        struct.pack_into('<BBBBBBBBII', mbr, 446, 0x00, 1, 1, 0, 0x06, 254, 63, 255,
                         PART_START, sectors - PART_START)
        mbr[510:512] = b'\x55\xAA'
        img[0:SECTOR] = mbr
        data += PART_START
    else:
        img, data = fat16_volume(payload, a.name, sectors, 0)
    open(a.image, 'wb').write(img)
    print(f'{a.image}: {len(img)} B, {a.name} {len(payload)} B at LBA {data}')


if __name__ == '__main__':
    main()
