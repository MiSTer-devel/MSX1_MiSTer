#!/usr/bin/env python3
"""Z80 instruction timing cases for z80_timing_tb.

Writes <outdir>/z80_timing.hex (64 kB memory image) and <outdir>/z80_timing_cases.svh
(per case: address X of the instruction, address Y of the M1 that ends the measurement,
T states of the Zilog data sheet, number of M1 cycles, name).

Expected time on an MSX = Zilog T states + one wait state per M1 cycle (openMSX Z80.hh:
every opcode fetch is 5 T, a prefix byte is another M1; DD CB d op has two M1 cycles).
"""
import sys

RAM = 0xC000
out = bytearray(0x10000)
pc = 0x0100
cases = []          # (x, y, t, m1, name, int_trigger)

PROLOGUE = bytes([0x31, 0x00, 0xF0,             # LD SP,F000h
                  0x21, 0x00, 0xC0,             # LD HL,C000h
                  0x01, 0x10, 0xC0,             # LD BC,C010h
                  0x11, 0x20, 0xC0,             # LD DE,C020h
                  0xDD, 0x21, 0x40, 0xC0,       # LD IX,C040h
                  0xFD, 0x21, 0x50, 0xC0])      # LD IY,C050h

CC_TRUE  = [[0x3E, 0x01, 0xB7], [0xAF], [0xB7], [0x37], [0x3E, 0x01, 0xB7], [0xAF], [0xAF], [0x3E, 0x80, 0xB7]]
CC_FALSE = [[0xAF], [0x3E, 0x01, 0xB7], [0x37], [0xB7], [0xAF], [0x3E, 0x01, 0xB7], [0x3E, 0x80, 0xB7], [0xAF]]
CC_NAME  = ['NZ', 'Z', 'NC', 'C', 'PO', 'PE', 'P', 'M']


def emit(bs):
    global pc
    out[pc:pc + len(bs)] = bytes(bs)
    pc += len(bs)


PROLOGUE_CB = bytes([0x21, 0x00, 0xC0,          # LD HL,C000h
                     0xDD, 0x21, 0x40, 0xC0,    # LD IX,C040h
                     0xFD, 0x21, 0x50, 0xC0])   # LD IY,C050h


def case(name, instr, t, m1, kind='seq', setup=(), vec=None, pro=PROLOGUE):
    """kind: seq  Y = X + len
             jump Y = landing address behind two HALT traps (instr may be callable(y))
             rep  Y = X (repeating block instruction)
             ret  Y = landing address, pushed on the stack first
             vec  Y = fixed address (RST), the code there returns
             reg  Y = landing address, loaded into the register by setup(y)"""
    emit(pro)
    if kind == 'ret':
        y_fix = pc + 4 + len(setup) + len(instr) + 2
        emit([0x21, y_fix & 0xFF, y_fix >> 8, 0xE5])        # LD HL,Y; PUSH HL
        emit(setup)
    elif kind == 'reg':
        probe = setup(0)
        y_fix = pc + len(probe) + len(instr) + 2
        emit(setup(y_fix))
    else:
        emit(setup)
    x = pc
    if kind == 'jump':
        n = len(instr(0))
        y = x + n + 2
        emit(instr(y))
        emit([0x76, 0x76])
    elif kind in ('ret', 'reg'):
        emit(instr)
        emit([0x76, 0x76])
        y = pc
        assert y == y_fix
    elif kind == 'rep':
        emit(instr)
        y = x
    elif kind == 'vec':
        emit(instr)
        y = vec
    else:
        emit(instr)
        y = pc
    cases.append((x, y, t, m1, name, 0))


def main_cases(pfx):
    """All unprefixed opcodes, or the same behind DD / FD (pfx = [0xDD] / [0xFD])."""
    p = list(pfx)
    xy = bool(p)
    pt = 4 if xy else 0                 # prefix M1
    m1 = 2 if xy else 1
    tag = ('%02X ' % p[0]) if xy else ''
    d = [0x05] if xy else []            # displacement of (IX+d)

    def add(op, tail, t, name, **kw):
        case(tag + name, p + [op] + tail, t + pt, m1, **kw)

    for op in range(256):
        x, y, z = op >> 6, (op >> 3) & 7, op & 7
        q, pp = y & 1, y >> 1
        n = '%02X' % op
        if op in (0xCB, 0xDD, 0xED, 0xFD, 0x76, 0xC7):
            continue                    # prefixes; HALT and RST 00 are separate / skipped
        if x == 0:
            if z == 0:
                if y == 0:   add(op, [], 4, n + ' NOP')
                elif y == 1: add(op, [], 4, n + ' EX AF')
                elif y == 2:
                    case(tag + n + ' DJNZ taken', lambda yy: p + [op, 2], 13 + pt, m1, kind='jump')
                    add(op, [2], 8, n + ' DJNZ not taken', setup=[0x06, 0x01])
                elif y == 3:
                    case(tag + n + ' JR', lambda yy: p + [op, 2], 12 + pt, m1, kind='jump')
                else:
                    c = y - 4
                    case(tag + n + ' JR %s taken' % CC_NAME[c], lambda yy: p + [op, 2], 12 + pt, m1,
                         kind='jump', setup=CC_TRUE[c])
                    add(op, [2], 7, n + ' JR %s not taken' % CC_NAME[c], setup=CC_FALSE[c])
            elif z == 1:
                if q == 0: add(op, [0x34, 0x12], 10, n + ' LD rr,nn')
                else:      add(op, [], 11, n + ' ADD HL,rr')
            elif z == 2:
                if op in (0x02, 0x12, 0x0A, 0x1A): add(op, [], 7, n + ' LD (rr),A / A,(rr)')
                elif op in (0x22, 0x2A):           add(op, [0x60, 0xC0], 16, n + ' LD (nn),HL / HL,(nn)')
                else:                              add(op, [0x60, 0xC0], 13, n + ' LD (nn),A / A,(nn)')
            elif z == 3:
                add(op, [], 6, n + ' INC/DEC rr')
            elif z in (4, 5):
                if y == 6: add(op, d, 23 - 4 if xy else 11, n + ' INC/DEC (HL)')
                else:      add(op, [], 4, n + ' INC/DEC r')
            elif z == 6:
                if y == 6: add(op, d + [0x55], 19 - 4 if xy else 10, n + ' LD (HL),n')
                else:      add(op, [0x55], 7, n + ' LD r,n')
            else:
                add(op, [], 4, n + ' RLCA..CCF')
        elif x == 1:
            if y == 6 or z == 6: add(op, d, 19 - 4 if xy else 7, n + ' LD r,(HL) / (HL),r')
            else:                add(op, [], 4, n + ' LD r,r')
        elif x == 2:
            if z == 6: add(op, d, 19 - 4 if xy else 7, n + ' ALU (HL)')
            else:      add(op, [], 4, n + ' ALU r')
        else:
            if z == 0:
                case(tag + n + ' RET %s taken' % CC_NAME[y], p + [op], 11 + pt, m1, kind='ret', setup=CC_TRUE[y])
                add(op, [], 5, n + ' RET %s not taken' % CC_NAME[y], setup=CC_FALSE[y])
            elif z == 1:
                if q == 0:     add(op, [], 10, n + ' POP')
                elif pp == 0:  case(tag + n + ' RET', p + [op], 10 + pt, m1, kind='ret')
                elif pp == 1:  add(op, [], 4, n + ' EXX')
                elif pp == 2:  # JP (HL) / (IX) / (IY)
                    ld = [0x21] if not xy else p + [0x21]
                    case(tag + n + ' JP (HL)', p + [op], 4 + pt, m1, kind='reg',
                         setup=lambda yy: ld + [yy & 0xFF, yy >> 8])
                else:          add(op, [], 6, n + ' LD SP,HL')
            elif z == 2:
                case(tag + n + ' JP %s taken' % CC_NAME[y], lambda yy: p + [op, yy & 0xFF, yy >> 8], 10 + pt, m1,
                     kind='jump', setup=CC_TRUE[y])
                add(op, [0x00, 0x00], 10, n + ' JP %s not taken' % CC_NAME[y], setup=CC_FALSE[y])
            elif z == 3:
                if y == 0:   case(tag + n + ' JP', lambda yy: p + [op, yy & 0xFF, yy >> 8], 10 + pt, m1, kind='jump')
                elif y == 2: add(op, [0x10], 11, n + ' OUT (n),A')
                elif y == 3: add(op, [0x10], 11, n + ' IN A,(n)')
                elif y == 4: add(op, [], 19, n + ' EX (SP),HL')
                elif y == 5: add(op, [], 4, n + ' EX DE,HL')
                elif y == 6: add(op, [], 4, n + ' DI')
                else:        add(op, [], 4, n + ' EI')
            elif z == 4:
                case(tag + n + ' CALL %s taken' % CC_NAME[y], lambda yy: p + [op, yy & 0xFF, yy >> 8], 17 + pt, m1,
                     kind='jump', setup=CC_TRUE[y])
                add(op, [0x00, 0x00], 10, n + ' CALL %s not taken' % CC_NAME[y], setup=CC_FALSE[y])
            elif z == 5:
                if q == 0: add(op, [], 11, n + ' PUSH')
                else:      case(tag + n + ' CALL', lambda yy: p + [op, yy & 0xFF, yy >> 8], 17 + pt, m1, kind='jump')
            elif z == 6:
                add(op, [0x55], 7, n + ' ALU n')
            else:
                add(op, [], 11, n + ' RST', kind='vec', vec=op & 0x38)


def cb_cases():
    for op in range(256):
        x, z = op >> 6, op & 7
        if z == 6: t = 12 if x == 1 else 15
        else:      t = 8
        case('CB %02X' % op, [0xCB, op], t, 2, pro=PROLOGUE_CB)
    for pfx in (0xDD, 0xFD):
        for op in range(256):
            t = 20 if (op >> 6) == 1 else 23
            case('%02X CB d %02X' % (pfx, op), [pfx, 0xCB, 0x05, op], t, 2, pro=PROLOGUE_CB)


def ed_cases():
    for op in range(256):
        n = 'ED %02X' % op
        z = op & 7
        i = [0xED, op]
        if 0x40 <= op <= 0x7F:
            if z in (0, 1):   case(n + ' IN r,(C) / OUT (C),r', i, 12, 2)
            elif z == 2:      case(n + ' SBC/ADC HL,rr', i, 15, 2)
            elif z == 3:      case(n + ' LD (nn),rr / rr,(nn)', i + [0x60, 0xC0], 20, 2)
            elif z == 4:      case(n + ' NEG', i, 8, 2)
            elif z == 5:      case(n + ' RETN/RETI', i, 14, 2, kind='ret')
            elif z == 6:      case(n + ' IM', i, 8, 2)
            elif op in (0x47, 0x4F, 0x57, 0x5F): case(n + ' LD I/R', i, 9, 2)
            elif op in (0x67, 0x6F):             case(n + ' RRD/RLD', i, 18, 2)
            else:             case(n + ' NOP', i, 8, 2)
        elif op in (0xA0, 0xA1, 0xA2, 0xA3, 0xA8, 0xA9, 0xAA, 0xAB):
            case(n + ' block', i, 16, 2)
        elif op in (0xB0, 0xB8):        # LDIR / LDDR
            case(n + ' LDIR/LDDR repeat', i, 21, 2, kind='rep', setup=[0x01, 0x02, 0x00])
            case(n + ' LDIR/LDDR last', i, 16, 2, setup=[0x01, 0x01, 0x00])
        elif op in (0xB1, 0xB9):        # CPIR / CPDR (D000h is never written: 00, A = 55h)
            pre = [0x21, 0x00, 0xD0, 0x3E, 0x55]
            case(n + ' CPIR/CPDR repeat', i, 21, 2, kind='rep', setup=pre + [0x01, 0x02, 0x00])
            case(n + ' CPIR/CPDR last', i, 16, 2, setup=pre + [0x01, 0x01, 0x00])
            case(n + ' CPIR/CPDR found', i, 16, 2, setup=[0x21, 0x00, 0xD0, 0xAF, 0x01, 0x02, 0x00])
        elif op in (0xB2, 0xB3, 0xBA, 0xBB):
            case(n + ' INIR..OTDR repeat', i, 21, 2, kind='rep', setup=[0x06, 0x02])
            case(n + ' INIR..OTDR last', i, 16, 2, setup=[0x06, 0x01])
        else:
            case(n + ' NOP', i, 8, 2)


def int_case(name, setup, t, y):
    """INT accepted after the NOP in front of X; measured from the M1 of the acknowledge."""
    emit(PROLOGUE)
    emit(setup)
    emit([0xFB, 0x00])                  # EI; NOP (the INT is raised during this NOP)
    trig = pc - 1
    x = pc
    emit([0x00])
    cases.append((x, y, t, 0, name, trig))


# reset vector and RST / interrupt vectors
out[0x0000:0x0003] = bytes([0xC3, 0x00, 0x01])              # JP 0100h
for v in range(0x08, 0x40, 0x08):
    out[v] = 0xC9                                           # RET
out[0xE0FF:0xE101] = bytes([0xE1, 0xE1])                    # IM 2: I = E0h, vector FFh -> E1E1h
out[0xE1E1] = 0xC9

emit([0xF3])                                                # DI
main_cases([])
cb_cases()
ed_cases()
main_cases([0xDD])
main_cases([0xFD])
int_case('INT IM 1', [0xED, 0x56], 13, 0x0038)
int_case('INT IM 0 (RST 38h on the bus)', [0xED, 0x46], 13, 0x0038)
int_case('INT IM 2', [0x3E, 0xE0, 0xED, 0x47, 0xED, 0x5E], 19, 0xE1E1)
# HALT: the opcode fetch, then the halted CPU repeats M1 cycles at X + 1
emit(PROLOGUE)
x = pc
emit([0x76])
cases.append((x, x + 1, 4, 1, '76 HALT', 0))
cases.append((x + 1, x + 1, 4, 1, 'halted M1', 0))
assert pc < RAM, hex(pc)

outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
with open(outdir + '/z80_timing.hex', 'w') as f:
    for b in out:
        f.write('%02x\n' % b)
with open(outdir + '/z80_timing_cases.svh', 'w') as f:
    f.write('// generated by z80_timing_prog.py\n')
    f.write('localparam int N_CASES = %d;\n' % len(cases))
    for nm, idx in (('case_x', 0), ('case_y', 1), ('case_t', 2), ('case_m1', 3), ('case_trig', 5)):
        f.write('int %s [N_CASES] = \'{%s};\n' % (nm, ', '.join(str(c[idx]) for c in cases)))
    f.write('string case_name [N_CASES] = \'{%s};\n' % ', '.join('"%s"' % c[4] for c in cases))
print('%d cases, program end %04Xh' % (len(cases), pc))
