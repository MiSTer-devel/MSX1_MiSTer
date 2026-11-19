#!/usr/bin/env python3
"""Generate cpu_switch_prog.svh: Z80 / R800 switch program for cpu_switch_tb.

Modelled on the FS-A1ST BIOS (doc/turboR.md 6.1): CHGCPU pushes all registers, stores SP at
FFFDh and writes the S1990 register 6 with OTIR (B = 2 on the Z80, 1 on the R800); the CPU that
takes over continues where it was frozen and pops what the other one pushed. Reset path:
F4 bit 7 = warm boot, bit 5 = R800 already initialized (R800 first start: IM 1, back to Z80).
"""
import os
from collections import defaultdict

prog = []

def L(name):            prog.append((name, b''))
def B(*bs):             prog.append((None, bytes(bs)))
def W(op, lbl):         prog.append((None, lambda lb, pc, op=op, lbl=lbl: bytes([op]) + lb[lbl].to_bytes(2, 'little')))
def REL(op, lbl):       prog.append((None, lambda lb, pc, op=op, lbl=lbl: bytes([op, (lb[lbl] - (pc + 2)) & 0xFF])))
def ORG(addr):          prog.append(('@org', addr))

def handler(counter):   # count, acknowledge INT (port 10h), return
    B(0xF5)                             # PUSH AF
    B(0x3A, counter, 0xE0)              # LD A,(E0xxh)
    B(0x3C)                             # INC A
    B(0x32, counter, 0xE0)              # LD (E0xxh),A
    B(0xD3, 0x10)                       # OUT (10h),A
    B(0xF1)                             # POP AF
    B(0xFB)                             # EI
    B(0xED, 0x4D)                       # RETI

def chg(mode):
    B(0x3E, mode)                       # LD A,mode
    W(0xCD, 'chg')                      # CALL chg

def store(addr, *regs):                 # LD (addr),rr for BC / DE / HL
    op = {'BC': (0xED, 0x43), 'DE': (0xED, 0x53), 'HL': (0x22,)}
    for i, r in enumerate(regs):
        a = addr + 2 * i
        B(*op[r], a & 0xFF, a >> 8)

ORG(0x0000)                             # reset entry of both CPUs
B(0xF3)                                 # DI
W(0xC3, 'reset')                        # JP reset

ORG(0x0038)                             # IM 1 (R800)
L('im1')
handler(0x10)

ORG(0x0060)                             # IM 2 vector 8000h (Z80)
L('im2')
handler(0x11)

ORG(0x0100)
L('reset')
B(0xDB, 0xF4)                           # IN A,(F4h)
B(0xCB, 0x7F)                           # BIT 7,A
REL(0x20, 'warm')                       # JR NZ,warm
B(0xCB, 0x6F)                           # BIT 5,A
REL(0x20, 'r800first')                  # JR NZ,r800first
B(0xF6, 0x20)                           # OR 20h
B(0xD3, 0xF4)                           # OUT (F4h),A
B(0x31, 0x00, 0xF0)                     # LD SP,F000h
B(0x3E, 0x80)                           # LD A,80h
B(0xED, 0x47)                           # LD I,A
B(0xED, 0x5E)                           # IM 2
B(0x3E, 0x06)                           # LD A,06h
B(0xD3, 0xE4)                           # OUT (E4h),A
W(0x21, 'tbl_r800')                     # LD HL,tbl_r800 (40h 60h)
B(0x01, 0xE5, 0x02)                     # LD BC,02E5h
L('otir_cold')
B(0xED, 0xB3)                           # OTIR
W(0xC3, 'main')                         # JP main
L('r800first')
B(0xED, 0x56)                           # IM 1
B(0xAF)                                 # XOR A
W(0xC3, 'chg2')                         # JP chg2 (back to the Z80, park here)
L('warm')
B(0x31, 0x00, 0xF0)                     # LD SP,F000h
B(0x3E, 0x80)                           # LD A,80h
B(0xED, 0x47)                           # LD I,A
B(0xED, 0x5E)                           # IM 2
W(0xC3, 'main2')                        # JP main2

ORG(0x0200)                             # CHGCPU, A = 0 Z80, 1 R800 ROM, 2 R800 DRAM
L('chg')
B(0xF3)                                 # DI
B(0xE5); B(0xD5); B(0xC5); B(0xF5)      # PUSH HL / DE / BC / AF
B(0xDD, 0xE5); B(0xFD, 0xE5)            # PUSH IX / IY
B(0xD9); B(0x08)                        # EXX; EX AF,AF'
B(0xE5); B(0xD5); B(0xC5); B(0xF5)      # PUSH HL' / DE' / BC' / AF'
B(0xED, 0x57); B(0xF5)                  # LD A,I; PUSH AF
B(0xED, 0x73, 0xFD, 0xFF)               # LD (FFFDh),SP
B(0x08)                                 # EX AF,AF'      A = mode
L('chg2')
B(0xE6, 0x03)                           # AND 03h
B(0x87)                                 # ADD A,A
B(0x4F)                                 # LD C,A
B(0x06, 0x00)                           # LD B,0
W(0x21, 'tbl')                          # LD HL,tbl
B(0x09)                                 # ADD HL,BC
B(0x3E, 0x06)                           # LD A,06h
B(0xD3, 0xE4)                           # OUT (E4h),A
B(0xDB, 0xE5)                           # IN A,(E5h)
B(0x06, 0x01)                           # LD B,1
B(0xCB, 0x6F)                           # BIT 5,A
REL(0x28, 'chg_b')                      # JR Z,chg_b     (R800: 1 byte)
B(0x04)                                 # INC B          (Z80: 2 bytes)
L('chg_b')
B(0x0E, 0xE5)                           # LD C,E5h
L('otir_chg')
B(0xED, 0xB3)                           # OTIR
L('resume')
B(0xF3)                                 # DI
B(0x00)                                 # NOP
B(0xED, 0x7B, 0xFD, 0xFF)               # LD SP,(FFFDh)
B(0xF1); B(0xED, 0x47)                  # POP AF; LD I,A
B(0xF1); B(0xC1); B(0xD1); B(0xE1)      # POP AF' / BC' / DE' / HL'
B(0xD9); B(0x08)                        # EXX; EX AF,AF'
B(0xFD, 0xE1); B(0xDD, 0xE1)            # POP IY / IX
B(0xF1); B(0xC1); B(0xD1); B(0xE1)      # POP AF / BC / DE / HL
B(0xFB)                                 # EI
L('chg_ret')
B(0xC9)                                 # RET
L('tbl')
B(0x60, 0x60)                           # Z80
L('tbl_r800')
B(0x40, 0x60)                           # R800 ROM
B(0x00, 0x60)                           # R800 DRAM

ORG(0x0300)
L('main')
B(0x01, 0x11, 0x11)                     # LD BC,1111h
B(0x11, 0x22, 0x22)                     # LD DE,2222h
B(0x21, 0x33, 0x33)                     # LD HL,3333h
B(0xDD, 0x21, 0x44, 0x44)               # LD IX,4444h
B(0xFD, 0x21, 0x55, 0x55)               # LD IY,5555h
B(0xD9)                                 # EXX
B(0x01, 0x66, 0x66)                     # LD BC',6666h
B(0x11, 0x77, 0x77)                     # LD DE',7777h
B(0x21, 0x88, 0x88)                     # LD HL',8888h
B(0xD9)                                 # EXX
B(0xD3, 0x11)                           # OUT (11h),A    INT at the next switch
chg(1)                                  # Z80 -> R800
B(0xD3, 0x20)                           # marker 1 (R800)
store(0xE020, 'BC', 'DE', 'HL')
B(0xDD, 0x22, 0x26, 0xE0)               # LD (E026h),IX
B(0xFD, 0x22, 0x28, 0xE0)               # LD (E028h),IY
B(0xD9)                                 # EXX
store(0xE02A, 'BC', 'DE', 'HL')
B(0xD9)                                 # EXX
B(0x01, 0xA1, 0xA1)                     # LD BC,A1A1h
B(0x11, 0xA2, 0xA2)                     # LD DE,A2A2h
B(0x21, 0xA3, 0xA3)                     # LD HL,A3A3h
B(0xD3, 0x11)                           # OUT (11h),A
chg(0)                                  # R800 -> Z80
B(0xD3, 0x21)                           # marker 2 (Z80)
store(0xE030, 'BC', 'DE', 'HL')
chg(2)                                  # Z80 -> R800 DRAM
B(0xD3, 0x22)                           # marker 3 (R800)
chg(0)                                  # R800 -> Z80
B(0xD3, 0x23)                           # marker 4 (Z80)
B(0xDB, 0xF4)                           # IN A,(F4h)
B(0xF6, 0x80)                           # OR 80h         warm boot flag
B(0xD3, 0xF4)                           # OUT (F4h),A
chg(1)                                  # Z80 -> R800
B(0xD3, 0x24)                           # marker 5 (R800): warm reset by the tb
L('hang1')
REL(0x18, 'hang1')                      # JR $

ORG(0x0400)
L('main2')                              # Z80 after the warm reset
B(0x01, 0xB1, 0xB1)                     # LD BC,B1B1h
B(0x11, 0xB2, 0xB2)                     # LD DE,B2B2h
B(0x21, 0xB3, 0xB3)                     # LD HL,B3B3h
chg(1)                                  # Z80 -> R800 (still parked from before the reset)
B(0xD3, 0x25)                           # marker 6 (R800)
store(0xE040, 'BC', 'DE', 'HL')
chg(0)                                  # R800 -> Z80
B(0xD3, 0x26)                           # marker 7 (Z80)
B(0xD3, 0x2F)                           # end: cold reset by the tb
L('hang2')
REL(0x18, 'hang2')                      # JR $

ORG(0x8000)                             # IM 2 table, vector 00h
B(0x60, 0x00)


def assemble():
    labels, mem = {}, {}
    for pass_ in (0, 1):
        pc = 0
        for name, item in prog:
            if name == '@org':
                pc = item; continue
            if name:
                labels[name] = pc; continue
            lb = labels if pass_ == 1 else defaultdict(int, labels)
            data = item(lb, pc) if callable(item) else item
            if pass_ == 1:
                for i, b in enumerate(data):
                    assert pc + i not in mem, hex(pc + i)
                    mem[pc + i] = b
            pc += len(data)
    return labels, mem

labels, mem = assemble()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'cpu_switch_prog.svh')
with open(out, 'w', newline='\n') as f:
    f.write('// Generated by cpu_switch_prog.py, do not edit\n')
    for n in ('otir_cold', 'otir_chg', 'resume', 'chg', 'chg2', 'chg_ret', 'im1', 'im2'):
        f.write("localparam logic [15:0] L_%s = 16'h%04X;\n" % (n.upper(), labels[n]))
    f.write('task automatic load_prog();\n')
    for a in sorted(mem):
        f.write("    mem[16'h%04X] = 8'h%02X;\n" % (a, mem[a]))
    f.write('endtask\n')
print('wrote', out, len(mem), 'bytes')
