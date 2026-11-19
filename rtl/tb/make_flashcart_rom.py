#!/usr/bin/env python3
"""Test ROM for the KUC (Konami Ultimate Collection) or Yamanooto mapper and a mapper database
holding only its CRC32 (behaviour as openMSX KonamiUltimateCollection.cc / Yamanooto.cc).

    python3 rtl/tb/make_flashcart_rom.py kuc|yamanooto <out.rom> <out.db>

The ROM (256 kB, 8 kB banks, the first byte of bank n is B0h + n) copies its test to RAM and
checks bank switching, the offset register, the SCC (wave RAM written and read back), the
Konami (KUC) or Konami4 (Yamanooto) mode, byte program and autoselect of the flash and, for
Yamanooto, its registers and FPGA ID. It prints "KUC PASS" / "YAMA PASS" or "... FAIL n".

    wsl.exe -- bash -c 'SIMARGS="+fw=<CART_FW_EN.msx> +db=<out.db> +rom=<out.rom>" \\
        bash rtl/tb/run_machine_boot.sh <machine.msx> none "KUC PASS"'
"""
import os
import struct
import sys
import zlib

sys.dont_write_bytecode = True                  # no __pycache__ in rtl/tb
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_ascii16x_rom import Asm, RAM     # noqa: E402  (same assembler and RAM address)

BANK = 0x2000
BANKS = 32
CONF_ID = {'kuc': 24, 'yamanooto': 37}     # cart_device.json
NAME = {'kuc': b'KUC', 'yamanooto': b'YAMA'}
ERASED = 0x20                               # a bank above the image: erased flash (FF)


def common_start(a):
    a.db(0xF3)                                              # DI
    # the slot of page 1 (the cartridge, not expanded) into page 2 as well
    a.db(0xDB, 0xA8, 0x47, 0xE6, 0x0C, 0x87, 0x87, 0x4F)    # IN A,(A8) / LD B,A / AND 0C / ADD A,A x2 / LD C,A
    a.db(0x78, 0xE6, 0xCF, 0xB1, 0xD3, 0xA8)                # LD A,B / AND CF / OR C / OUT (A8),A


def kuc_steps(a):
    # 1: Konami SCC bank registers
    a.write(0x9000, 5);  a.expect(0x8000, 0xB5, 'fail1')
    a.write(0x7000, 6);  a.expect(0x6000, 0xB6, 'fail1')
    a.write(0x7000, 1);  a.expect(0x6000, 0xB1, 'fail1')
    # 2: offset 7FFE added to every bank
    a.write(0x7FFE, 1);  a.expect(0x8000, 0xB6, 'fail2')
    a.write(0x7FFE, 0);  a.expect(0x8000, 0xB5, 'fail2')
    # 3: SCC: bank 2 = 3F, wave RAM at 9800 written and read back; 9900 (address bit 8) is flash
    a.write(0x9000, 0x3F)
    a.write(0x9800, 0x55);  a.expect(0x9800, 0x55, 'fail3')
    a.write(0x9801, 0xAA);  a.expect(0x9801, 0xAA, 'fail3')
    a.expect(0x9900, 0xFF, 'fail3')
    a.write(0x9000, 5);  a.expect(0x9800, 0xB5, 'fail3')
    # 4: Konami mode: 6000-BFFF whole pages, 5000-57FF for 4000-5FFF
    a.write(0x7FFF, 0x20)
    a.write(0x6000, 2);  a.expect(0x6000, 0xB2, 'fail4')
    a.write(0x8000, 7);  a.expect(0x8000, 0xB7, 'fail4')
    a.write(0x5000, 3);  a.expect(0x4000, 0xB3, 'fail4')
    a.write(0x5000, 0);  a.expect(0x4000, ord('A'), 'fail4')
    # 5: program a byte into erased flash (write enable 7FFF bit 4); Konami SCC mode, where a
    #    write to 8100 does not switch the bank
    a.write(0x7FFF, 0x10)
    a.write(0x9000, ERASED);  a.expect(0x8100, 0xFF, 'fail5')
    a.call('unlock');  a.write(0x4AAA, 0xA0);  a.write(0x8100, 0x5A)
    a.poll(0x8100, 0x5A, 'fail5')
    a.expect(0x8101, 0xFF, 'fail5')
    # 6: autoselect (M29W640GB)
    a.call('unlock');  a.write(0x4AAA, 0x90)
    a.expect(0x4000, 0x20, 'fail6')
    a.expect(0x4002, 0x7E, 'fail6')
    a.write(0x4000, 0xF0)
    a.expect(0x4000, ord('A'), 'fail6')
    # 7: A21-A20 = 1: 2 MB further, erased
    a.write(0x9000, 7)
    a.write(0x7FFF, 0x40);  a.expect(0x8000, 0xFF, 'fail7')
    a.write(0x7FFF, 0x00);  a.expect(0x8000, 0xB7, 'fail7')
    return 7


def yama_steps(a):
    # 1: Konami SCC bank registers, registers hidden without REGEN
    a.write(0x9000, 5);  a.expect(0x8000, 0xB5, 'fail1')
    a.expect(0x7FFF, 0xB1, 'fail1')                         # flash, bank 1
    # 2: REGEN: registers readable
    a.write(0x7FFF, 0x01)
    a.expect(0x7FFF, 0x01, 'fail2')
    a.expect(0x7FFD, 0x80, 'fail2')
    # 3: offset 7FFE (x4) added when the bank is written
    a.write(0x7FFE, 1);  a.expect(0x8000, 0xB5, 'fail3')
    a.write(0x9000, 1);  a.expect(0x8000, 0xB5, 'fail3')
    a.write(0x7FFE, 0)
    # 4: SCC: raw bank 2 = 3F, wave RAM at 9800, also at 9900 (no address bit 8 rule)
    a.write(0x9000, 0x3F)
    a.write(0x9800, 0x55);  a.expect(0x9800, 0x55, 'fail4')
    a.expect(0x9900, 0x55, 'fail4')
    # 5: Konami4: no SCC, 6000-BFFF whole pages
    a.write(0x7FFD, 0x08)
    a.write(0x8000, 6);  a.expect(0x9800, 0xB6, 'fail5')
    a.write(0x6000, 2);  a.expect(0x6000, 0xB2, 'fail5')
    a.write(0x7FFD, 0x00)
    a.write(0x7000, 1);  a.expect(0x6000, 0xB1, 'fail5')
    # 6: WREN: program a byte into erased flash, banks frozen
    a.write(0x9000, ERASED);  a.expect(0x8100, 0xFF, 'fail6')
    a.write(0x7FFF, 0x11)
    a.call('unlock');  a.write(0x4AAA, 0xA0);  a.write(0x8100, 0x5A)
    a.poll(0x8100, 0x5A, 'fail6')
    a.expect(0x8101, 0xFF, 'fail6')
    # 7: autoselect (S29GL064)
    a.call('unlock');  a.write(0x4AAA, 0x90)
    a.expect(0x4000, 0x01, 'fail7')
    a.expect(0x4002, 0x7E, 'fail7')
    a.write(0x4000, 0xF0)
    a.expect(0x4000, ord('A'), 'fail7')
    a.write(0x7FFF, 0x01)
    # 8: FPGA ID
    a.write(0x7FFD, 0x40)
    a.write(0x7FFC, 0x9F);  a.expect(0x7FFC, 0x1F, 'fail8')
    a.write(0x7FFC, 0x00);  a.expect(0x7FFC, 0x23, 'fail8')
    a.write(0x7FFC, 0x00);  a.write(0x7FFC, 0x00);  a.write(0x7FFC, 0x00)
    a.expect(0x7FFC, 0xFF, 'fail8')
    a.write(0x7FFD, 0x00)
    return 8


def test_code(kind):
    a = Asm(RAM)
    common_start(a)
    steps = kuc_steps(a) if kind == 'kuc' else yama_steps(a)
    name = NAME[kind]
    a.db(0x21); a.word('msg_pass')                          # LD HL,msg_pass
    a.jp('print')
    for n in range(1, steps + 1):
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
    a.label('msg_pass'); a.db(*(name + b' PASS\0'))
    a.label('msg_fail'); a.db(*(name + b' FAIL '))
    a.label('digit');    a.db(ord('?'), 0)
    return a.build()


def make_rom(kind):
    rom = bytearray()
    for b in range(BANKS):
        rom += bytes([0xB0 + b]) * BANK
    code = test_code(kind)
    src = 0x4100                                            # the test in bank 0
    rom[0:0x20] = bytes(0x20)
    rom[0:4] = b'AB' + struct.pack('<H', 0x4020)            # INIT
    rom[0x10:0x10 + len(NAME[kind])] = NAME[kind]
    boot = bytes([0x21]) + struct.pack('<H', src)           # LD HL,src
    boot += bytes([0x11]) + struct.pack('<H', RAM)          # LD DE,RAM
    boot += bytes([0x01]) + struct.pack('<H', len(code))    # LD BC,len
    boot += bytes([0xED, 0xB0, 0xC3]) + struct.pack('<H', RAM)   # LDIR / JP RAM
    rom[0x20:0x20 + len(boot)] = boot
    assert src - 0x4000 + len(code) <= BANK, 'test does not fit into bank 0'
    rom[src - 0x4000:src - 0x4000 + len(code)] = code
    return bytes(rom)


if __name__ == '__main__':
    kind = sys.argv[1]
    rom = make_rom(kind)
    open(sys.argv[2], 'wb').write(rom)
    crc = zlib.crc32(rom) & 0xFFFFFFFF
    open(sys.argv[3], 'wb').write(struct.pack('<I4B', crc, CONF_ID[kind], 0, 0, 0))
    print(f'{sys.argv[2]}: {kind}, {len(rom)} B, CRC32 {crc:08X}')
