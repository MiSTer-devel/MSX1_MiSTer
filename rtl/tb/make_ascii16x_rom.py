#!/usr/bin/env python3
"""Test ROM for the ASCII16-X mapper (https://www.grauw.nl/projects/ascii-x/ascii16-x/) and a
mapper database holding only its CRC32.

    python3 rtl/tb/make_ascii16x_rom.py <out.rom> <out.db>

The ROM (128 kB) copies its test to RAM (flash commands must not run from the flash) and
checks: bank select with the bank number in the address, the erased flash above the image,
byte program, autoselect, erase of a 64 kB and of an 8 kB sector. It prints "A16X PASS" or
"A16X FAIL n" (n = the step). Run in the machine:

    wsl.exe -- bash -c 'SIMARGS="+fw=<CART_FW_EN.msx> +db=<out.db> +rom=<out.rom>" \\
        bash rtl/tb/run_machine_boot.sh <machine.msx> none "A16X PASS"'
"""
import struct
import sys
import zlib

BANK = 0x4000
BANKS = 8
RAM = 0xD000            # the test runs here
CONF_ID = 57            # cart_device.json "ASCII16X"


class Asm:
    def __init__(self, org):
        self.org, self.code, self.labels, self.fix = org, bytearray(), {}, []

    def label(self, name):
        self.labels[name] = self.org + len(self.code)

    def db(self, *b):
        self.code += bytes(b)

    def word(self, target):                 # address: number or label
        if isinstance(target, str):
            self.fix.append((len(self.code), target))
            target = 0
        self.code += struct.pack('<H', target)

    def ld_a(self, n):          self.db(0x3E, n)
    def ld_a_mem(self, addr):   self.db(0x3A); self.word(addr)
    def ld_mem_a(self, addr):   self.db(0x32); self.word(addr)
    def cp(self, n):            self.db(0xFE, n)
    def jp(self, t):            self.db(0xC3); self.word(t)
    def jp_z(self, t):          self.db(0xCA); self.word(t)
    def jp_nz(self, t):         self.db(0xC2); self.word(t)
    def call(self, t):          self.db(0xCD); self.word(t)

    def write(self, addr, n):               # LD A,n / LD (addr),A
        self.ld_a(n); self.ld_mem_a(addr)

    def expect(self, addr, n, fail):        # LD A,(addr) / CP n / JP NZ,fail
        self.ld_a_mem(addr); self.cp(n); self.jp_nz(fail)

    def poll(self, addr, n, fail):          # until (addr) = n, at most 65536 reads
        loop, done = f'poll{len(self.code)}', f'done{len(self.code)}'
        self.db(0x01, 0x00, 0x00)           # LD BC,0
        self.label(loop)
        self.ld_a_mem(addr); self.cp(n); self.jp_z(done)
        self.db(0x0B, 0x78, 0xB1)           # DEC BC / LD A,B / OR C
        self.jp_nz(loop)
        self.jp(fail)
        self.label(done)

    def build(self):
        for pos, name in self.fix:
            self.code[pos:pos + 2] = struct.pack('<H', self.labels[name])
        return bytes(self.code)


def test_code():
    a = Asm(RAM)
    a.db(0xF3)                                              # DI
    # the slot of page 1 (the cartridge, not expanded) into page 2 as well
    a.db(0xDB, 0xA8, 0x47, 0xE6, 0x0C, 0x87, 0x87, 0x4F)    # IN A,(A8) / LD B,A / AND 0C / ADD A,A x2 / LD C,A
    a.db(0x78, 0xE6, 0xCF, 0xB1, 0xD3, 0xA8)                # LD A,B / AND CF / OR C / OUT (A8),A

    # 1: page 2 bank register, 2: page 1 register
    a.write(0x7000, 2);  a.expect(0x8000, 0xB2, 'fail1')
    a.write(0x6000, 3);  a.expect(0x4000, 0xB3, 'fail2')
    a.write(0x6000, 0);  a.expect(0x4000, ord('A'), 'fail2')

    # 3: bank 102h (bit 8 in the address): above the image, erased flash
    a.write(0x7100, 2);  a.expect(0x8100, 0xFF, 'fail3')

    # 4: program a byte there
    a.call('unlock');    a.write(0x4AAA, 0xA0);  a.write(0x8100, 0x5A)
    a.poll(0x8100, 0x5A, 'fail4')
    a.expect(0x8101, 0xFF, 'fail4')

    # 5: autoselect
    a.call('unlock');    a.write(0x4AAA, 0x90)
    a.expect(0x4000, 0x01, 'fail5')
    a.expect(0x4002, 0x7E, 'fail5')
    a.expect(0x401C, 0x10, 'fail5')
    a.write(0x4000, 0xF0)
    a.expect(0x4000, ord('A'), 'fail5')

    # 6: erase its 64 kB sector; the flash is busy right after the command
    a.call('unlock');    a.write(0x4AAA, 0x80)
    a.call('unlock');    a.write(0x8000, 0x30)
    a.ld_a_mem(0x8100);  a.cp(0xFF);  a.jp_z('fail6')
    a.poll(0x8100, 0xFF, 'fail6')

    # 7: program inside the image (bank 3)
    a.write(0x7000, 3)
    a.call('unlock');    a.write(0x4AAA, 0xA0);  a.write(0x8010, 0x21)
    a.poll(0x8010, 0x21, 'fail7')
    a.expect(0x8011, 0xB3, 'fail7')

    # 8: erase the 8 kB sector 6000-7FFF of the flash (bank 1, second half); the write to
    #    A000h also sets the page 1 register, which is put back
    a.write(0x7000, 1)
    a.call('unlock');    a.write(0x4AAA, 0x80)
    a.call('unlock');    a.write(0xA000, 0x30)
    a.write(0x6000, 0)
    a.poll(0xA000, 0xFF, 'fail8')
    a.expect(0xBFFF, 0xFF, 'fail8')
    a.expect(0x9FFF, 0xB1, 'fail8')
    a.write(0x7000, 2);  a.expect(0x8000, 0xB2, 'fail8')
    a.expect(0x4000, ord('A'), 'fail8')

    a.db(0x21); a.word('msg_pass')                          # LD HL,msg_pass
    a.jp('print')

    for n in range(1, 9):
        a.label(f'fail{n}')
        a.ld_a(ord('0') + n)
        a.jp('fail')
    a.label('fail')
    a.ld_mem_a('digit')
    a.write(0x4000, 0xF0)                                   # flash back to reading
    a.db(0x21); a.word('msg_fail')

    a.label('print')
    a.db(0xE5); a.call(0x006C); a.db(0xE1)                  # PUSH HL / CALL INITXT / POP HL
    a.label('next')
    a.db(0x7E, 0xB7); a.jp_z('stop')                        # LD A,(HL) / OR A
    a.call(0x00A2); a.db(0x23); a.jp('next')                # CALL CHPUT / INC HL
    a.label('stop')
    a.jp('stop')

    a.label('unlock')
    a.write(0x4AAA, 0xAA); a.write(0x4555, 0x55)
    a.db(0xC9)

    a.label('msg_pass'); a.db(*b'A16X PASS\0')
    a.label('msg_fail'); a.db(*b'A16X FAIL ')
    a.label('digit');    a.db(ord('?'), 0)
    return a.build()


def make_rom():
    rom = bytearray()
    for b in range(BANKS):
        rom += bytes([0xB0 + b]) * BANK
    code = test_code()
    src = 0x4100                                            # the test in bank 0
    rom[0:0x20] = bytes(0x20)
    rom[0:4] = b'AB' + struct.pack('<H', 0x4020)            # INIT
    rom[0x10:0x18] = b'ASCII16X'
    boot = bytes([0x21]) + struct.pack('<H', src)           # LD HL,src
    boot += bytes([0x11]) + struct.pack('<H', RAM)          # LD DE,RAM
    boot += bytes([0x01]) + struct.pack('<H', len(code))    # LD BC,len
    boot += bytes([0xED, 0xB0, 0xC3]) + struct.pack('<H', RAM)   # LDIR / JP RAM
    rom[0x20:0x20 + len(boot)] = boot
    rom[src - 0x4000:src - 0x4000 + len(code)] = code
    return bytes(rom)


if __name__ == '__main__':
    rom = make_rom()
    open(sys.argv[1], 'wb').write(rom)
    open(sys.argv[2], 'wb').write(struct.pack('<I4B', zlib.crc32(rom) & 0xFFFFFFFF, CONF_ID, 0, 0, 0))
    print(f'{sys.argv[1]}: {len(rom)} B, CRC32 {zlib.crc32(rom) & 0xFFFFFFFF:08X}')
