#!/usr/bin/env python3
# Extracts the PCM sounds of Criterion from the game ROM by its sound table (block 0):
#   475Eh bank (8 kB), 4769h address (word), 477Fh length (word), 4795h priority; 11 sounds.
# The samples are stored uncompressed (8 bit unsigned, sent to A4h unchanged) at
# bank * 2000h + (address & 1FFFh). Output: data/sndNN.raw and data/sndNN.wav at the rate of
# the player (S1990 timer 3.579545 MHz / 14, 32 ticks per sample = 7990 Hz).
#   python mkraw.py Criterion.rom
import os, sys, wave

rom = open(sys.argv[1], 'rb').read()
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data')
os.makedirs(out, exist_ok=True)
RATE = round(3579545 / 14 / 32)
# names from the game sources (tools/snd_pcm.py, build()): same order as the table
NAMES = ['P01 orchestra hit', 'P02 orchestra hit, minor third down', 'P03 orchestra hit, octave down', 'P05 snare', 'P06 large explosion', 'V01 voice "INFINITAS LAUNCH"', 'V02 voice "WARNING"', 'V03 voice "SYSTEM ONLINE"', 'V04 voice "UNMEASURABLE"', 'V05 voice "GAME OVER"', 'V06 voice "CALIBRATION"']

def byte(a): return rom[a - 0x4000]
def word(a): return byte(a) | byte(a + 1) << 8

for i in range(11):
    bank, addr = byte(0x475E + i), word(0x4769 + 2 * i)
    length, prio = word(0x477F + 2 * i), byte(0x4795 + i)
    off = bank * 0x2000 + (addr & 0x1FFF)
    data = rom[off:off + length]
    open(os.path.join(out, 'snd%02d.raw' % i), 'wb').write(data)
    w = wave.open(os.path.join(out, 'snd%02d.wav' % i), 'wb')
    w.setnchannels(1); w.setsampwidth(1); w.setframerate(RATE); w.writeframes(data); w.close()
    print('snd%02d: ROM %06Xh, %5d samples, %.2f s, priority %d  %s' % (i, off, length, length / RATE, prio, NAMES[i]))
