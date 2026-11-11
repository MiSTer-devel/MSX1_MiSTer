#!/usr/bin/env python3
"""Test ROM for the MoonSound (OPL4) in the machine.

    python3 rtl/tb/make_opl4_rom.py <out.rom> <yrw801.rom>

A 16 kB cartridge ROM for slot A; the MoonSound goes into slot B (OSD item 8). It checks the
detection as programs do it (status, NEW2, device ID), the read back of an FM register, the
wave ROM and the sample RAM through the memory registers, timer 1 with its status flags, and
starts a wave tone and an FM tone. It prints "OPL4 PASS" or "OPL4 FAIL n" (n = the step):

    wsl.exe -- bash -c 'SIMARGS="+fw=<CART_FW_EN.msx> +rom=<out.rom> +slotb=8 +audio_min=2000" \\
        bash rtl/tb/run_machine_boot.sh <machine.msx> none "OPL4 PASS"'

+audio=<file.raw> writes the sound (16 bit stereo, 44100 Hz); the FW pack must hold yrw801.rom.
rtl/tb/check_opl4_audio.py compares the wave tone in that file with the reference model.
"""
import struct
import sys


WAVE = 53               # 12 bit samples at 081CC6h (in the SDRAM), instant attack, no decay


class Asm:
    def __init__(self, org):
        self.org, self.code, self.labels, self.fix = org, bytearray(), {}, []

    def label(self, name):
        self.labels[name] = self.org + len(self.code)

    def db(self, *b):
        self.code += bytes(b)

    def word(self, target):
        if isinstance(target, str):
            self.fix.append((len(self.code), target))
            target = 0
        self.code += struct.pack('<H', target)

    def jp(self, t):            self.db(0xC3); self.word(t)
    def jp_z(self, t):          self.db(0xCA); self.word(t)
    def jp_nz(self, t):         self.db(0xC2); self.word(t)
    def call(self, t):          self.db(0xCD); self.word(t)

    def out(self, port, n):                 # LD A,n / OUT (port),A
        self.db(0x3E, n, 0xD3, port)

    def expect(self, port, n, fail, mask=0xFF):     # IN A,(port) / AND mask / CP n / JP NZ,fail
        self.db(0xDB, port, 0xE6, mask, 0xFE, n)
        self.jp_nz(fail)

    def poll(self, port, mask, n, fail):    # until (port) & mask = n, at most 65536 reads
        loop, done = f'poll{len(self.code)}', f'done{len(self.code)}'
        self.db(0x01, 0x00, 0x00)           # LD BC,0
        self.label(loop)
        self.db(0xDB, port, 0xE6, mask, 0xFE, n)
        self.jp_z(done)
        self.db(0x0B, 0x78, 0xB1)           # DEC BC / LD A,B / OR C
        self.jp_nz(loop)
        self.jp(fail)
        self.label(done)

    def fm(self, reg, n):                   # FM register, array 0 / 1
        self.out(0xC6 if reg & 0x100 else 0xC4, reg & 0xFF)
        self.out(0xC7 if reg & 0x100 else 0xC5, n)

    def wave(self, reg, n):
        self.out(0x7E, reg)
        self.out(0x7F, n)

    def mem_addr(self, addr):
        self.wave(3, addr >> 16)
        self.wave(4, (addr >> 8) & 0xFF)
        self.wave(5, addr & 0xFF)
        self.out(0x7E, 6)

    def delay(self, n):                     # n * 24 T states
        loop = f'delay{len(self.code)}'
        self.db(0x01); self.word(n)         # LD BC,n
        self.label(loop)
        self.db(0x0B, 0x78, 0xB1)           # DEC BC / LD A,B / OR C
        self.jp_nz(loop)

    def build(self):
        for pos, name in self.fix:
            self.code[pos:pos + 2] = struct.pack('<H', self.labels[name])
        return bytes(self.code)


def test_code(org, wrom):
    a = Asm(org)
    a.db(0xF3)                                              # DI

    # 1: status after reset, NEW2 (status bit 1 once), device ID in wave register 2
    a.expect(0xC4, 0x00, 'fail1')
    a.fm(0x105, 0x03)
    a.expect(0xC4, 0x02, 'fail1')
    a.expect(0xC4, 0x00, 'fail1')
    a.out(0x7E, 2)
    a.expect(0x7F, 0x20, 'fail1', 0xE0)

    # 2: FM register read back
    a.fm(0x020, 0x5A)
    a.out(0xC4, 0x20)
    a.expect(0xC5, 0x5A, 'fail2')
    a.fm(0x020, 0x00)

    # wave WAVE of the ROM at its recorded pitch in tone 0, alone for 0.14 s (check_opl4_audio.py
    # compares that part of the sound with the model), then FM channel 0 joins
    a.wave(0xF9, 0x00)
    a.wave(0x20, 0x00)
    a.wave(0x38, 0x10)
    a.wave(0x08, WAVE)
    a.poll(0xC4, 0x02, 0x00, 'fail3')                       # 3: header load (LD) ends
    a.wave(0x50, 0x01)
    a.wave(0x68, 0x80)
    a.delay(0x5000)
    for reg, n in ((0x20, 0x01), (0x40, 0x10), (0x60, 0xF0), (0x80, 0x77),
                   (0x23, 0x01), (0x43, 0x00), (0x63, 0xF0), (0x83, 0x77),
                   (0xC0, 0x30), (0xA0, 0x98), (0xB0, 0x31)):
        a.fm(reg, n)

    # 4: wave ROM through the memory registers: start, end, then the (erased) RAM
    a.wave(2, 0x01)
    a.mem_addr(0x000000)
    for i in range(4):
        a.expect(0x7F, wrom[i], 'fail4')
    a.mem_addr(0x1FFFFE)
    a.expect(0x7F, wrom[0x1FFFFE], 'fail4')
    a.expect(0x7F, wrom[0x1FFFFF], 'fail4')
    a.expect(0x7F, 0xFF, 'fail4')

    # 5: sample RAM, the 4 MB address space wraps
    a.mem_addr(0x200000)
    for n in (0x55, 0xAA, 0x12):
        a.out(0x7F, n)
    a.mem_addr(0x3FFFFF)
    a.out(0x7F, 0x77)
    a.mem_addr(0x200000)
    for n in (0x55, 0xAA, 0x12, 0xFF):
        a.expect(0x7F, n, 'fail5')
    a.mem_addr(0x3FFFFF)
    a.expect(0x7F, 0x77, 'fail5')
    a.expect(0x7F, wrom[0], 'fail5')

    # 6: the ROM cannot be written; without the access bit the data register reads FF
    a.mem_addr(0x000000)
    a.out(0x7F, wrom[0] ^ 0xFF)
    a.mem_addr(0x000000)
    a.expect(0x7F, wrom[0], 'fail6')
    a.wave(2, 0x00)
    a.out(0x7E, 6)
    a.expect(0x7F, 0xFF, 'fail6')

    # 7: timer 1 (2 ticks of 80.8 us), flag with IRQ, reset, masked
    a.fm(0x002, 0xFE)
    a.fm(0x004, 0x01)
    a.poll(0xC4, 0x40, 0x40, 'fail7')
    a.expect(0xC4, 0xC0, 'fail7', 0xE0)
    a.fm(0x004, 0x80)
    a.fm(0x004, 0x60)
    a.expect(0xC4, 0x00, 'fail7', 0xE0)

    a.delay(0x4000)                                         # 0.1 s of both tones, then the result

    a.db(0x21); a.word('msg_pass')                          # LD HL,msg_pass
    a.jp('print')

    for n in range(1, 8):
        a.label(f'fail{n}')
        a.db(0x3E, ord('0') + n)
        a.jp('fail')
    a.label('fail')
    a.db(0x32); a.word(0xE000)                              # LD (E000h),A: the step
    a.db(0x21); a.word('msg_fail')
    a.label('print')
    a.db(0xE5); a.call(0x006C); a.db(0xE1)                  # PUSH HL / CALL INITXT / POP HL
    a.label('next')
    a.db(0x7E, 0xB7); a.jp_z('digit')                       # LD A,(HL) / OR A
    a.call(0x00A2); a.db(0x23); a.jp('next')                # CALL CHPUT / INC HL
    a.label('digit')
    a.db(0x3A); a.word(0xE000); a.db(0xB7)                  # LD A,(E000h) / OR A
    a.jp_z('stop')
    a.call(0x00A2)
    a.label('stop')
    a.jp('stop')

    a.label('msg_pass'); a.db(*b'OPL4 PASS\0')
    a.label('msg_fail'); a.db(*b'OPL4 FAIL \0')
    return a.build()


def make_rom(wrom):
    rom = bytearray(b'\xFF' * 0x4000)
    rom[0:0x10] = bytes(0x10)
    rom[0:4] = b'AB' + struct.pack('<H', 0x4010)            # INIT
    boot = bytes([0xAF, 0x32, 0x00, 0xE0])                  # XOR A / LD (E000h),A
    code = boot + test_code(0x4010 + len(boot), wrom)
    rom[0x10:0x10 + len(code)] = code
    return bytes(rom)


if __name__ == '__main__':
    wrom = open(sys.argv[2], 'rb').read()
    assert len(wrom) == 0x200000, 'the wave ROM (yrw801.rom) is 2 MB'
    open(sys.argv[1], 'wb').write(make_rom(wrom))
    print(f'{sys.argv[1]}: 16384 B')
