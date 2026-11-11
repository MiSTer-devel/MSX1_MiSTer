#!/usr/bin/env python3
"""The wave tone of the MoonSound test ROM (make_opl4_rom.py) in the sound output of the machine
(run_machine_boot.sh +audio=<file>) against the reference model of the wave part.

    python3 rtl/tb/check_opl4_audio.py <audio.raw> <yrw801.rom>

The tone plays alone for 0.14 s: about 6000 samples that must be, one by one, the samples of
the model after the mix (/ 4 in dev_opl4, x 2 in sound_mix). The output file takes a sample
every 487 clk and the wave part makes one every 487.013, so one sample may repeat or drop.
"""
import os
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../peripheral/SOUND/opl4/tb'))
import opl4_wave_gold as gold           # noqa: E402
from make_opl4_rom import WAVE          # noqa: E402

N = 5000

raw = open(sys.argv[1], 'rb').read()
left = [struct.unpack_from('<h', raw, i)[0] for i in range(0, len(raw) - 3, 4)]
rom = open(sys.argv[2], 'rb').read()

w = gold.Wave(bytearray(rom) + bytearray(b'\xFF' * 0x200000))
for _ in range(100):
    w.sample()
for reg, val in ((0xF9, 0x00), (0x20, 0x00), (0x38, 0x10), (0x08, WAVE)):
    w.write(reg, val)
for _ in range(20):
    w.sample()
w.write(0x50, 0x01)
w.write(0x68, 0x80)
exp = []
for _ in range(N):
    lv, _ = w.sample()
    v = lv >> 2
    exp.append(max(-32768, min(32767, 2 * v)) if -16384 <= v <= 16383 else (32767 if v > 0 else -32768))

# find a stretch of the model in the output, then count how far the two agree
key = exp[500:800]
start = -1
for i in range(len(left) - len(key)):
    if left[i] == key[0] and left[i:i + len(key)] == key:
        start = i - 500
        break
if start < 0 or max(abs(v) for v in key) < 500:
    print('FAILED check_opl4_audio: the wave tone of the model is not in the sound output')
    sys.exit(1)
good = slips = 0
j = start
for k in range(1, N):
    if j + k >= len(left):
        break
    if left[j + k] == exp[k]:
        good += 1
    elif left[j + k + 1] == exp[k]:                 # a sample repeated in the output
        j += 1; slips += 1; good += 1
    elif left[j + k - 1] == exp[k]:                 # a sample dropped
        j -= 1; slips += 1; good += 1
    else:
        break
print('wave tone found at output sample %d: %d samples as the model, %d slips, peak %d'
      % (start, good, slips, max(abs(v) for v in exp[:good + 1])))
if good >= 4000 and slips <= 2:
    print('PASS check_opl4_audio')
else:
    print('FAILED check_opl4_audio: only %d samples agree' % good)
    sys.exit(1)
