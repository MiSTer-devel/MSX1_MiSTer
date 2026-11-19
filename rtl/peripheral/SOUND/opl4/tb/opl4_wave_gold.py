#!/usr/bin/env python3
# Reference model of the OPL4 wave part (YMF278B) and test scenarios for opl4_wave_tb.sv.
#
# The arithmetic is the one of openMSX YMF278.cc (sample position, interpolation, envelope,
# LFO, volume and panning). Differences, as in opl4_wave.sv (doc/moonsound.md):
#   - a register write takes effect with the next sample;
#   - a tone restart (key on, wave number write) costs one silent sample: the engine reads the
#     sample data of the new position first; the envelope of a key on starts in that sample,
#     with the registers as they are then;
#   - the counters run also while every tone is off (openMSX freezes them).
#
#   opl4_wave_gold.py <out dir> [seed [frames [chord]]]   ->  mem.bin, scen.txt, expect.txt
#   chord: 24 tones playing at once instead of the random music

import random
import sys

MAX_ATT = 0x280
EG_ATT, EG_DEC, EG_SUS, EG_REL, EG_OFF = 4, 3, 2, 1, 0
PAN_L = [0, 8, 16, 24, 32, 40, 48, 255, 255, 0, 0, 0, 0, 0, 0, 0]
PAN_R = [0, 0, 0, 0, 0, 0, 0, 0, 255, 255, 48, 40, 32, 24, 16, 8]
DL_TAB = [i * 0x20 for i in range(15)] + [31 * 0x20]
EG_INC = [
    0, 1, 0, 1, 0, 1, 0, 1,  0, 1, 0, 1, 1, 1, 0, 1,  0, 1, 1, 1, 0, 1, 1, 1,  0, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1,  1, 1, 1, 2, 1, 1, 1, 2,  1, 2, 1, 2, 1, 2, 1, 2,  1, 2, 2, 2, 1, 2, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 2,  2, 2, 2, 4, 2, 2, 2, 4,  2, 4, 2, 4, 2, 4, 2, 4,  2, 4, 4, 4, 2, 4, 4, 4,
    4, 4, 4, 4, 4, 4, 4, 4,  8, 8, 8, 8, 8, 8, 8, 8,  0, 0, 0, 0, 0, 0, 0, 0]
LFO_PERIOD = [1, 12, 19, 25, 31, 35, 37, 42]
VIB_DEPTH = [0, 2, 3, 4, 6, 12, 24, 48]
AM_DEPTH = [0x00, 0x14, 0x20, 0x28, 0x30, 0x40, 0x50, 0x80]
MIX = [16, 12, 8, 6, 4, 3, 2, 0]                        # / 16


def rate_select(rate):
    if rate < 4:
        return 14 * 8
    if rate < 52:
        return (rate & 3) * 8
    if rate < 56:
        return (4 + (rate & 3)) * 8
    if rate < 60:
        return (8 + (rate & 3)) * 8
    return 12 * 8


def rate_shift(rate):
    return 12 - (rate >> 2) if rate < 48 else 0


def cdiv(a, b):                                         # C division, towards zero
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def calc_step(octv, fn, vib=0):
    if octv == -8:
        return 0
    return ((fn + 1024 + vib) << (8 + octv)) >> 3


def vol_factor(x, v):
    if v >= MAX_ATT:
        return 0
    mul = 0x80 - (v & 0x3F)
    return (x * ((0x8000 * mul) >> (7 + (v >> 6)))) >> 15


def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


class Slot:
    def __init__(self):
        self.wave = self.FN = self.TLdest = self.TL = self.pan = self.vib = self.AM = 0
        self.OCT = self.DL = self.AR = self.D1R = self.D2R = self.RC = self.RR = 0
        self.PRVB = self.keyon = self.DAMP = False
        self.stepPtr = self.pos = 0
        self.bits = self.startAddr = self.loopAddr = self.endAddr = 0
        self.env_vol = MAX_ATT
        self.lfo_active = False
        self.lfo_cnt = self.lfo = 0
        self.state = EG_OFF
        self.stall = False
        self.kon_pending = False

    def compute_rate(self, val):
        if val == 0:
            return 0
        if val == 15:
            return 63
        res = val * 4
        if self.RC != 15:
            res += 2 * min(max(self.OCT + self.RC, 0), 15)
            res += 1 if self.FN & 0x200 else 0
        return min(max(res, 0), 63)

    def compute_decay_rate(self, val):
        if self.DAMP:
            return 48 if self.env_vol < DL_TAB[4] else 63
        if self.PRVB and self.env_vol >= DL_TAB[6]:
            return 20
        return self.compute_rate(val)

    def compute_vib(self):
        fm = self.lfo_cnt >> 12
        if fm & 0x10:
            fm ^= 0x1F
        if fm & 0x20:
            fm = -(fm & 0x0F)
        return cdiv(fm * VIB_DEPTH[self.vib], 12)

    def compute_am(self):
        am = self.lfo_cnt >> 10
        if am >= 0x80:
            am ^= 0xFF
        return (am * AM_DEPTH[self.AM]) >> 7


class Wave:
    def __init__(self, mem, ram_chunks=16):
        self.mem = mem                                  # bytearray, 4 MB: ROM, RAM
        self.ram_chunks = ram_chunks                    # RAM size in 128 kB
        self.slots = [Slot() for _ in range(24)]
        self.regs = [0] * 256
        self.regs[0xF8] = 0x1B                          # FM mix level after reset
        self.memadr = 0
        self.eg_cnt = 0
        for r in range(0xF7, -1, -1):                   # reset = every register written with 0:
            self.write(r, 0)                            # LFO on, header of wave 0 in every tone

    # ---- sample memory: 2 MB ROM, RAM from 200000h (mode 0) or its first 512 kB at 380000h
    def map(self, a):
        a &= 0x3FFFFF
        if a < 0x200000:
            return a, False
        chunk = (a >> 17) & 15
        if self.regs[2] & 2:
            chunk -= 12
            if chunk < 0:
                return None, False
        if chunk >= self.ram_chunks:
            return None, False
        return 0x200000 + (chunk << 17) + (a & 0x1FFFF), True

    def read_mem(self, a):
        m, _ = self.map(a)
        return 0xFF if m is None else self.mem[m]

    def write_mem(self, a, v):
        m, ram = self.map(a)
        if m is not None and ram:
            self.mem[m] = v

    def get_sample(self, sl, pos):
        if sl.bits == 0:
            return s16(self.read_mem(sl.startAddr + pos) << 8)
        if sl.bits == 1:
            a = sl.startAddr + (pos // 2) * 3
            if pos & 1:
                return s16(self.read_mem(a + 2) << 8 | (self.read_mem(a + 1) & 0xF0))
            return s16(self.read_mem(a) << 8 | ((self.read_mem(a + 1) << 4) & 0xF0))
        if sl.bits == 2:
            a = sl.startAddr + pos * 2
            return s16(self.read_mem(a) << 8 | self.read_mem(a + 1))
        return 0

    @staticmethod
    def next_pos(sl, pos, inc):
        pos = (pos + inc) & 0xFFFF
        if pos + sl.endAddr >= 0x10000:
            pos = (pos + sl.endAddr + sl.loopAddr) & 0xFFFF
        return pos

    @staticmethod
    def key_on(sl):
        sl.kon_pending = True                           # envelope starts with the next sample
        sl.stepPtr = 0
        sl.pos = 0
        sl.stall = True

    # ---- registers
    def write(self, reg, data):
        if 0x08 <= reg <= 0xF7:
            n = (reg - 8) % 24
            sl = self.slots[n]
            row = (reg - 8) // 24
            if row == 0:
                sl.wave = (sl.wave & 0x100) | data
                hdr = (self.regs[2] >> 2) & 7
                base = sl.wave * 12 if sl.wave < 384 or not hdr else hdr * 0x80000 + (sl.wave - 384) * 12
                buf = [self.read_mem(base + i) for i in range(12)]
                sl.bits = buf[0] >> 6
                sl.startAddr = buf[2] | buf[1] << 8 | (buf[0] & 0x3F) << 16
                sl.loopAddr = buf[4] | buf[3] << 8
                sl.endAddr = buf[6] | buf[5] << 8
                for i in range(7, 12):
                    self.write(8 + n + (i - 2) * 24, buf[i])
                if sl.keyon:
                    self.key_on(sl)
                else:
                    sl.stepPtr = 0
                    sl.pos = 0
                    sl.stall = True
            elif row == 1:
                sl.wave = (sl.wave & 0xFF) | (data & 1) << 8
                sl.FN = (sl.FN & 0x380) | data >> 1
            elif row == 2:
                sl.FN = (sl.FN & 0x07F) | (data & 7) << 7
                sl.PRVB = bool(data & 8)
                sl.OCT = ((data >> 4) ^ 8) - 8
            elif row == 3:
                t = data >> 1
                sl.TLdest = t if t != 0x7F else 0xFF
                if data & 1:
                    sl.TL = sl.TLdest
            elif row == 4:
                sl.pan = 8 if data & 0x10 else data & 0x0F
                if data & 0x20:
                    sl.lfo_active = False
                    sl.lfo_cnt = 0
                else:
                    sl.lfo_active = True
                sl.DAMP = bool(data & 0x40)
                if data & 0x80:
                    if not sl.keyon:
                        sl.keyon = True
                        self.key_on(sl)
                elif sl.keyon:
                    sl.keyon = False
                    sl.state = EG_REL
            elif row == 5:
                sl.lfo = (data >> 3) & 7
                sl.vib = data & 7
            elif row == 6:
                sl.AR = data >> 4
                sl.D1R = data & 15
            elif row == 7:
                sl.DL = DL_TAB[data >> 4]
                sl.D2R = data & 15
            elif row == 8:
                sl.RC = data >> 4
                sl.RR = data & 15
            elif row == 9:
                sl.AM = data & 7
        elif reg == 3:
            data &= 0x3F
        elif reg == 5:
            self.memadr = self.regs[3] << 16 | self.regs[4] << 8 | data
        elif reg == 6:
            if self.regs[2] & 1:
                self.write_mem(self.memadr, data)
                self.memadr += 1
        self.regs[reg] = data

    def read(self, reg):
        if reg == 2:
            return (self.regs[2] & 0x1F) | 0x20
        if reg == 6:
            if self.regs[2] & 1:
                v = self.read_mem(self.memadr)
                self.memadr += 1
                return v
            return 0xFF
        return self.regs[reg]

    # ---- one sample: left, right before the mix level, and after it
    def sample(self):
        self.eg_cnt += 1
        cnt = self.eg_cnt
        tl_cnt = cnt % 9
        tl_step = (cnt // 9) % 3
        left = right = 0
        for sl in self.slots:
            if sl.stall:
                sl.stall = False
                if sl.kon_pending:                      # key on: attack by the registers as they are now
                    sl.kon_pending = False
                    sl.env_vol = MAX_ATT
                    if sl.compute_rate(sl.AR) < 63:
                        sl.state = EG_ATT
                    else:
                        sl.env_vol = 0
                        sl.state = EG_DEC if sl.DL else EG_SUS
                    if not sl.keyon:
                        sl.state = EG_REL
                continue
            if sl.state != EG_OFF:
                smp = (self.get_sample(sl, sl.pos) * (0x10000 - sl.stepPtr) +
                       self.get_sample(sl, self.next_pos(sl, sl.pos, 1)) * sl.stepPtr) >> 16
                env = min(sl.env_vol + (sl.compute_am() if sl.lfo_active and sl.AM else 0), MAX_ATT)
                out = vol_factor(vol_factor(smp, env), sl.TL << 2)
                vl, vr = PAN_L[sl.pan], PAN_R[sl.pan]
                vl = (0x20 - (vl & 15)) >> (vl >> 4)
                vr = (0x20 - (vr & 15)) >> (vr >> 4)
                left += (out * vl) >> 5
                right += (out * vr) >> 5
                step = calc_step(sl.OCT, sl.FN, sl.compute_vib()) if sl.lfo_active and sl.vib \
                    else calc_step(sl.OCT, sl.FN)
                sl.stepPtr += step
                if sl.stepPtr >= 0x10000:
                    sl.pos = self.next_pos(sl, sl.pos, (sl.stepPtr >> 16) & 0xFFFF)
                    sl.stepPtr &= 0xFFFF
            # counters and envelope
            if tl_cnt == 0:
                if tl_step == 0:
                    if sl.TL < sl.TLdest:
                        sl.TL += 1
                elif sl.TL > sl.TLdest:
                    sl.TL -= 1
            if sl.lfo_active:
                sl.lfo_cnt = (sl.lfo_cnt + LFO_PERIOD[sl.lfo]) & 0x3FFFF
            if sl.state == EG_ATT:
                rate = sl.compute_rate(sl.AR)
                if rate < 63:
                    sh = rate_shift(rate)
                    if not cnt & ((1 << sh) - 1):
                        inc = EG_INC[rate_select(rate) + ((cnt >> sh) & 7)]
                        sl.env_vol += (~sl.env_vol * inc) >> 4
                        if sl.env_vol <= 0:
                            sl.env_vol = 0
                            sl.state = EG_DEC if sl.DL else EG_SUS
            elif sl.state != EG_OFF:
                rate = sl.compute_decay_rate({EG_DEC: sl.D1R, EG_SUS: sl.D2R, EG_REL: sl.RR}[sl.state])
                sh = rate_shift(rate)
                if not cnt & ((1 << sh) - 1):
                    sl.env_vol += EG_INC[rate_select(rate) + ((cnt >> sh) & 7)]
                    if sl.state == EG_DEC:
                        if sl.env_vol >= sl.DL:
                            sl.state = EG_SUS if sl.env_vol < MAX_ATT else EG_OFF
                    elif sl.env_vol >= MAX_ATT:
                        sl.env_vol = MAX_ATT
                        sl.state = EG_OFF
        mix = self.regs[0xF9]
        return (left * MIX[mix & 7]) >> 4, (right * MIX[(mix >> 3) & 7]) >> 4


# -------------------------------------------------------------------- scenario
def build_memory(rnd):
    """ROM with a wave table of all formats and loop shapes, RAM with a second table."""
    mem = bytearray(rnd.getrandbits(8) for _ in range(0x400000))
    waves = []

    def put_wave(table, idx, data_addr, bits, n, loop, params):
        end = (-n) & 0xFFFF if n else 0                 # stored negated: last position is n - 1
        h = bytes([bits << 6 | (data_addr >> 16) & 0x3F, (data_addr >> 8) & 0xFF, data_addr & 0xFF,
                   loop >> 8, loop & 0xFF, end >> 8, end & 0xFF]) + bytes(params)
        mem[table + idx * 12: table + idx * 12 + 12] = h

    addr = 0x2000                                       # ROM samples after the table
    for i in range(64):
        bits = i % 3
        n = rnd.choice([2, 3, 4, 7, 16, 100, 1000, 5000, 40000])
        loop = rnd.randrange(n) if rnd.random() < 0.7 else n - 1
        if i % 7 == 0:
            addr |= 1                                   # odd start address
        params = [rnd.getrandbits(6), rnd.choice([0xF0, 0xF4, 0xC6, 0x93, 0x72, 0xFF]) & 0xFF,
                  rnd.getrandbits(8), rnd.choice([0x07, 0x0A, 0x3C, 0xF5, 0x0F]), rnd.getrandbits(3)]
        put_wave(0, i, addr, bits, n, loop, params)
        waves.append(i)
        addr += n * 2 + 16
    # wave 60: the address space wraps at 4 MB; wave 61: sample across the ROM / RAM border
    put_wave(0, 60, 0x3FFFF0, 2, 64, 3, [0, 0xF0, 0, 0x0F, 0])
    put_wave(0, 61, 0x1FFFF8, 1, 32, 1, [0, 0xF0, 0, 0x0F, 0])
    # RAM: wave table header 4 at 200000h (waves 384..), samples behind it
    addr = 0x201000
    for i in range(16):
        bits = (i + 1) % 3
        n = rnd.choice([5, 64, 300, 9000])
        put_wave(0x200000, i, addr, bits, n, rnd.randrange(n),
                 [rnd.getrandbits(6), 0xF0 | rnd.getrandbits(4), rnd.getrandbits(8), 0x08 | rnd.getrandbits(4), 0])
        addr += n * 2 + 16
    return mem


def scenario(seed, frames):
    rnd = random.Random(seed)
    mem = build_memory(rnd)
    w = Wave(bytearray(mem))
    ops = []                                            # (frame, 'W' / 'R', reg, value)
    out = []

    def wr(f, reg, val):
        ops.append((f, 'W', reg, val))
        w.write(reg, val)

    def rd(f, reg):
        ops.append((f, 'R', reg, w.read(reg)))

    f = 0
    wr(f, 0xF9, 0x00)
    while f < frames:
        r = rnd.random()
        n = rnd.randrange(24)
        if r < 0.004:                                   # new tone: wave, pitch, level, key on
            if rnd.random() < 0.3:
                wr(f, 0x02, 0x10 | (rnd.getrandbits(1)))            # wave table header 4
                wave = 384 + rnd.randrange(16)
            else:
                wr(f, 0x02, rnd.choice([0x00, 0x01]))
                wave = rnd.choice(list(range(64)))
            fn = rnd.getrandbits(10)
            octv = rnd.choice([-8, -7, -6, -3, -2, -1, 0, 0, 0, 1, 1, 2, 3, 5, 7])
            wr(f, 0x20 + n, (fn & 0x7F) << 1 | wave >> 8)
            wr(f, 0x38 + n, (octv & 15) << 4 | rnd.getrandbits(1) << 3 | fn >> 7)
            wr(f, 0x08 + n, wave & 0xFF)
            if rnd.random() < 0.5:
                wr(f, 0x98 + n, rnd.choice([0xF0, 0xF3, 0xA2, 0x71, 0x52, 0xE8]))
                wr(f, 0xB0 + n, rnd.getrandbits(8))
                wr(f, 0xC8 + n, rnd.choice([0x06, 0x09, 0x3C, 0xFA, 0x8F, 0x00]))
            wr(f, 0x50 + n, rnd.choice([0, 0, 8, 20, 60]) << 1 | rnd.getrandbits(1))
            wr(f, 0x80 + n, rnd.getrandbits(6))
            wr(f, 0xE0 + n, rnd.getrandbits(3))
            wr(f, 0x68 + n, 0x80 | rnd.choice([0, 0, 0, 0x20]) | rnd.choice([0, 0, 0, 0x10]) | rnd.getrandbits(4))
        elif r < 0.006:                                 # key off, sometimes with damping
            wr(f, 0x68 + n, (w.regs[0x68 + n] & 0x3F) | rnd.choice([0, 0, 0x40]))
        elif r < 0.007:                                 # retrigger within one sample
            wr(f, 0x68 + n, w.regs[0x68 + n] & 0x7F)
            wr(f, 0x68 + n, w.regs[0x68 + n] | 0x80)
        elif r < 0.008:                                 # key on and off within one sample
            wr(f, 0x68 + n, w.regs[0x68 + n] | 0x80)
            wr(f, 0x68 + n, w.regs[0x68 + n] & 0x7F)
        elif r < 0.010:                                 # pitch bend
            fn = rnd.getrandbits(10)
            wr(f, 0x20 + n, (fn & 0x7F) << 1 | (w.regs[0x20 + n] & 1))
            wr(f, 0x38 + n, (w.regs[0x38 + n] & 0xF8) | fn >> 7)
        elif r < 0.012:                                 # level, ramp or direct
            wr(f, 0x50 + n, rnd.getrandbits(8))
        elif r < 0.013:                                 # direct level, then a ramp target
            wr(f, 0x50 + n, rnd.getrandbits(7) << 1 | 1)
            wr(f, 0x50 + n, rnd.getrandbits(7) << 1)
        elif r < 0.014:
            wr(f, rnd.choice([0x80, 0x98, 0xB0, 0xC8, 0xE0]) + n, rnd.getrandbits(8))
        elif r < 0.0145:
            wr(f, 0x68 + n, (w.regs[0x68 + n] & 0x80) | rnd.getrandbits(7))
        elif r < 0.015:                                 # wave change while the tone plays / is off
            wr(f, 0x08 + n, rnd.randrange(64))
        elif r < 0.0152:
            wr(f, 0xF9, rnd.getrandbits(6))
        elif r < 0.0157:                                # memory: write a block into the RAM, read back
            a = 0x200000 + rnd.randrange(0x1FFF00) if rnd.random() < 0.8 else rnd.randrange(0x400000)
            wr(f, 0x02, (w.regs[2] & 0x1C) | 1)
            wr(f, 0x03, a >> 16)
            wr(f, 0x04, (a >> 8) & 0xFF)
            wr(f, 0x05, a & 0xFF)
            k = rnd.randrange(1, 12)
            for _ in range(k):
                wr(f, 0x06, rnd.getrandbits(8))
            wr(f, 0x03, a >> 16)
            wr(f, 0x04, (a >> 8) & 0xFF)
            wr(f, 0x05, a & 0xFF)
            for _ in range(k + 1):
                rd(f, 0x06)
            wr(f, 0x02, w.regs[2] & 0x1C)
            rd(f, 0x06)
        elif r < 0.0159:                                # write just ahead of a tone playing from the RAM
            for n2 in range(24):                        # (two samples further: not read by the tone yet)
                sl = w.slots[n2]
                last = (0x10000 - sl.endAddr) & 0xFFFF
                if sl.state == EG_OFF or sl.stall or sl.startAddr < 0x200000 or sl.bits > 2 or sl.pos + 5 >= last:
                    continue
                t = sl.pos + 2 + (sl.pos & 1 if sl.bits == 1 else 0)
                a = sl.startAddr + {0: t, 1: (t // 2) * 3, 2: t * 2}[sl.bits]
                wr(f, 0x02, (w.regs[2] & 0x1C) | 1)
                wr(f, 0x03, (a >> 16) & 0x3F)
                wr(f, 0x04, (a >> 8) & 0xFF)
                wr(f, 0x05, a & 0xFF)
                for _ in range((1, 3, 2)[sl.bits]):
                    wr(f, 0x06, rnd.getrandbits(8))
                wr(f, 0x02, w.regs[2] & 0x1C)
                break
        elif r < 0.0162:                                # read back registers
            rd(f, rnd.choice([0x02, 0x03, 0x04, 0x05, 0xF8, 0xF9, 0x01]))
            for row in range(10):
                rd(f, 8 + n + 24 * row)
        elif r < 0.0164:                                # memory type 1: RAM at the top
            wr(f, 0x02, (w.regs[2] & 0x1D) ^ 2)
        out.append(w.sample())
        f += 1
    return mem, ops, out


def chord(seed, frames):
    """All 24 tones at the recorded pitch (one new sample per tone and frame), long waves of
    every format: the load of a full arrangement on the sample memory."""
    rnd = random.Random(seed)
    mem = build_memory(rnd)
    w = Wave(bytearray(mem))
    ops, out = [], []
    long_waves = [i for i in range(60) if (-(mem[i * 12 + 5] << 8 | mem[i * 12 + 6])) & 0xFFFF >= 1000]

    def wr(reg, val):
        ops.append((0, 'W', reg, val))
        w.write(reg, val)

    wr(0xF9, 0x00)
    for n in range(24):
        wr(0x20 + n, 0x00)
        wr(0x38 + n, 0x10)                              # octave 1, F-number 0: step 1.0
        wr(0x08 + n, long_waves[n % len(long_waves)])
        wr(0x98 + n, 0xF0)
        wr(0xB0 + n, 0x00)
        wr(0x50 + n, 0x31)
        wr(0x68 + n, 0x80 | (n & 15))
    for _ in range(frames):
        out.append(w.sample())
    return mem, ops, out


def main():
    d = sys.argv[1]
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    frames = int(sys.argv[3]) if len(sys.argv) > 3 else 60000
    mem, ops, out = chord(seed, frames) if len(sys.argv) > 4 and sys.argv[4] == 'chord' else scenario(seed, frames)
    with open(d + '/mem.bin', 'wb') as fh:
        fh.write(mem)
    with open(d + '/scen.txt', 'w') as fh:
        for f, k, reg, val in ops:
            fh.write('%d %d %d %d\n' % (f, 1 if k == 'W' else 0, reg, val))
    with open(d + '/expect.txt', 'w') as fh:
        for left, right in out:
            fh.write('%d %d\n' % (left, right))
    loud = sum(1 for left, right in out if left or right)
    print('scenario seed %d: %d frames (%d with sound), %d register accesses' % (seed, frames, loud, len(ops)))


if __name__ == '__main__':
    main()
