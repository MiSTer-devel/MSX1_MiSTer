#!/usr/bin/env python3
"""Test ROM for the NEO-8 / NEO-16 mapper (openMSX RomNeo8 / RomNeo16) and a mapper database
holding only its CRC32.

    python3 rtl/tb/make_neo_rom.py <8|16> <out.rom> <out.db>

The ROM (128 kB, every 8 kB block filled with C0h + block number) copies its test to RAM and
checks: bank registers, a register mirror in page 2, the odd address (bits 11-8), wrap of a bank
past the end of the ROM, registers that must not do anything. It prints "NEO8 PASS" / "NEO16 PASS"
or "... FAIL n" (n = the step). Run in the machine:

    wsl.exe -- bash -c 'SIMARGS="+fw=<CART_FW_EN.msx> +db=<out.db> +rom=<out.rom>" \\
        bash rtl/tb/run_machine_boot.sh <machine.msx> none "NEO8 PASS"'
"""
import os
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ascii16x_rom import Asm, RAM          # noqa: E402

BLOCKS = 16                                     # 8 kB blocks, 128 kB
CONF_ID = {8: 58, 16: 59}                       # cart_device.json "NEO8", "NEO16"


def mark(block):
    return 0xC0 + block


def test_neo8(a):
    # 1: register 4 (8000h) at 7000h, 2: register 5 (A000h) at 7800h
    a.write(0x7000, 5);  a.expect(0x8000, mark(5), 'fail1')
    a.write(0x7800, 7);  a.expect(0xA000, mark(7), 'fail2'); a.expect(0x8000, mark(5), 'fail2')
    # 3: mirror of register 4 at B000h
    a.write(0xB000, 9);  a.expect(0x8000, mark(9), 'fail3')
    # 4: bits 11-8 at the odd address; 107h and 103h wrap to 7 and 3 (16 blocks)
    a.write(0x7801, 1);  a.expect(0xA000, mark(7), 'fail4')
    a.write(0x7800, 3);  a.expect(0xA000, mark(3), 'fail4')
    # 5: register 2 (4000h) at 6000h
    a.write(0x6000, 2);  a.expect(0x4000, mark(2), 'fail5')
    a.write(0x6000, 0);  a.expect(0x4000, ord('A'), 'fail5')
    # 6: register 1 (2000h) and the high byte of register 4 leave the visible pages alone
    a.write(0x5800, 4);  a.write(0x7001, 0)
    a.expect(0x8000, mark(9), 'fail6'); a.expect(0xA000, mark(3), 'fail6'); a.expect(0x4000, ord('A'), 'fail6')


def test_neo16(a):
    # 1: register 2 (8000h) at 7000h: 16 kB bank 3 = blocks 6, 7
    a.write(0x7000, 3);  a.expect(0x8000, mark(6), 'fail1'); a.expect(0xA000, mark(7), 'fail1')
    # 2: 7800h is not a register
    a.write(0x7800, 5);  a.expect(0x8000, mark(6), 'fail2')
    # 3: mirror of register 2 at B000h
    a.write(0xB000, 2);  a.expect(0x8000, mark(4), 'fail3')
    # 4: bits 11-8 at the odd address; 102h and 105h wrap to 2 and 5 (8 banks)
    a.write(0x7001, 1);  a.expect(0x8000, mark(4), 'fail4')
    a.write(0x7000, 5);  a.expect(0x8000, mark(10), 'fail4')
    # 5: register 1 (4000h) at 6000h
    a.write(0x6000, 1);  a.expect(0x4000, mark(2), 'fail5')
    a.write(0x6000, 0);  a.expect(0x4000, ord('A'), 'fail5')
    # 6: 6800h is not a register, register 0 (0000h) leaves the visible pages alone
    a.write(0x6800, 7);  a.write(0x5000, 3)
    a.expect(0x4000, ord('A'), 'fail6'); a.expect(0x8000, mark(10), 'fail6')


def test_code(kind):
    a = Asm(RAM)
    a.db(0xF3)                                              # DI
    # the slot of page 1 (the cartridge, not expanded) into page 2 as well
    a.db(0xDB, 0xA8, 0x47, 0xE6, 0x0C, 0x87, 0x87, 0x4F)    # IN A,(A8) / LD B,A / AND 0C / ADD A,A x2 / LD C,A
    a.db(0x78, 0xE6, 0xCF, 0xB1, 0xD3, 0xA8)                # LD A,B / AND CF / OR C / OUT (A8),A

    (test_neo8 if kind == 8 else test_neo16)(a)

    a.db(0x21); a.word('msg_pass')                          # LD HL,msg_pass
    a.jp('print')

    for n in range(1, 7):
        a.label(f'fail{n}')
        a.ld_a(ord('0') + n)
        a.jp('fail')
    a.label('fail')
    a.ld_mem_a('digit')
    a.db(0x21); a.word('msg_fail')

    a.label('print')
    a.db(0xE5); a.call(0x006C); a.db(0xE1)                  # PUSH HL / CALL INITXT / POP HL
    a.label('next')
    a.db(0x7E, 0xB7); a.jp_z('stop')                        # LD A,(HL) / OR A
    a.call(0x00A2); a.db(0x23); a.jp('next')                # CALL CHPUT / INC HL
    a.label('stop')
    a.jp('stop')

    a.label('msg_pass'); a.db(*f'NEO{kind} PASS\0'.encode())
    a.label('msg_fail'); a.db(*f'NEO{kind} FAIL '.encode())
    a.label('digit');    a.db(ord('?'), 0)
    return a.build()


def make_rom(kind):
    rom = bytearray()
    for b in range(BLOCKS):
        rom += bytes([mark(b)]) * 0x2000
    code = test_code(kind)
    src = 0x4100                                            # the test in block 0
    rom[0:0x20] = bytes(0x20)
    rom[0:4] = b'AB' + struct.pack('<H', 0x4020)            # INIT
    rom[0x10:0x18] = b'ROM_NEO8' if kind == 8 else b'ROM_NE16'
    boot = bytes([0x21]) + struct.pack('<H', src)           # LD HL,src
    boot += bytes([0x11]) + struct.pack('<H', RAM)          # LD DE,RAM
    boot += bytes([0x01]) + struct.pack('<H', len(code))    # LD BC,len
    boot += bytes([0xED, 0xB0, 0xC3]) + struct.pack('<H', RAM)   # LDIR / JP RAM
    rom[0x20:0x20 + len(boot)] = boot
    rom[src - 0x4000:src - 0x4000 + len(code)] = code
    return bytes(rom)


if __name__ == '__main__':
    kind = int(sys.argv[1])
    rom = make_rom(kind)
    crc = zlib.crc32(rom) & 0xFFFFFFFF
    open(sys.argv[2], 'wb').write(rom)
    open(sys.argv[3], 'wb').write(struct.pack('<I4B', crc, CONF_ID[kind], 0, 0, 0))
    print(f'{sys.argv[2]}: NEO-{kind}, {len(rom)} B, CRC32 {crc:08X}')
