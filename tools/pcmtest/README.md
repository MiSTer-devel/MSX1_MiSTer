# PCMTEST for MSX turbo R

**English** | [Česky](README.cs.md)

A test ROM that plays PCM on the turbo R with the player of the game Criterion and counts the
samples it had to skip. It shows how the sound depends on how often the player gets the CPU.

## How Criterion plays PCM

The game does not use the BIOS (`PCMPLY`). Its own player (ROM block 0, 4F03h / 4F18h) is
called from hooks in RAM (C6E7h, C29Bh, C1A3h): while it waits for the VDP, after every 16 bytes
it copies to the VRAM, after OPLL writes and in its frame loop. Each call:

1. reads the S1990 system timer (E7h, E6h; 3.911 µs per tick) and subtracts the due time;
2. not yet due: returns;
3. less than 32 ticks late: outputs the next sample (`OUT (A4h)`), due time + 32 ticks;
4. 32 to 2047 ticks late: skips the missed samples, outputs the next one;
5. 2048 ticks or more: no skip, the due time restarts from now.

The rate is therefore fixed by the timer: 32 ticks = 125.2 µs, **7990 Hz**, on every CPU. The
CPU speed only decides how many samples are skipped. Long stretches without a call (a 256 byte
`OTIR` to the VRAM at 4444h: on the R800 every VDP access waits 62 R800 cycles, 8.7 µs, so
256 bytes take 2.2 ms = 17 samples) cut pieces out of the sound.

The game fills two buffers of 384 bytes (3D00h, 3E80h) from the ROM and hands them to the
player (the first at 0189h, the next ones at 4FC7h).

The sounds are in a table in ROM block 0: 475Eh bank (8 kB), 4769h address, 477Fh length,
4795h priority (a sound only interrupts one with the same or a lower priority); 11 sounds,
stored uncompressed (8 bit unsigned, sent to A4h unchanged) at bank * 2000h + (address & 1FFFh).

| Sound | ROM | Samples | Length | Priority | Name |
|---|---|---|---|---|---|
| snd00 | 0B72CFh | 4794 | 0.60 s | 3 | P01 orchestra hit |
| snd01 | 0B8589h | 4794 | 0.60 s | 3 | P02 orchestra hit, minor third down |
| snd02 | 0B9843h | 6392 | 0.80 s | 3 | P03 orchestra hit, octave down |
| snd03 | 0BB13Bh | 1997 | 0.25 s | 1 | P05 snare |
| snd04 | 0BB908h | 7990 | 1.00 s | 2 | P06 large explosion |
| snd05 | 0BD83Eh | 10025 | 1.25 s | 4 | V01 voice "INFINITAS LAUNCH" |
| snd06 | 0BFF67h | 3795 | 0.47 s | 4 | V02 voice "WARNING" |
| snd07 | 0C0E3Ah | 8789 | 1.10 s | 4 | V03 voice "SYSTEM ONLINE" |
| snd08 | 0C308Fh | 7397 | 0.93 s | 4 | V04 voice "UNMEASURABLE" |
| snd09 | 0C4D74h | 5889 | 0.74 s | 4 | V05 voice "GAME OVER" |
| snd10 | 0C6475h | 6632 | 0.83 s | 4 | V06 voice "CALIBRATION" |

## Build

The sound data come from the game and are not part of the repository:

```
python mkraw.py Criterion.rom   # -> data/snd00..10.raw and .wav (7990 Hz, 8 bit unsigned)
sh build.sh                     # -> pcmtest.rom with snd07 snd09 snd05 (keys 1, 2, 3)
sh build.sh 07 10 03            # other sounds, up to 9 and 32 kB in total
```

`data/sndNN.wav` is the sound exactly as stored in the game, without any skipped sample: what
it should sound like.

## Keys

| Key | |
|---|---|
| 1–9 | play a sound (the list is on the screen) |
| L | VDP load per frame (16.7 ms): 0, 1, 2, 4 blocks of 256 bytes `OTIR` |
| C | chunked: the player also runs after every 16 bytes of a block (as the game at 54D8h) |
| I | interrupts on / off while playing |
| Z R D | CPU: Z80, R800 ROM, R800 DRAM (BIOS `CHGCPU`); after the start R800 DRAM, as the game |

After a sound: `played` / `skipped` samples, `restart` (2048 ticks late), `late max` (ticks
after the due time) and `calls` of the player (a measure of the CPU speed).

## Results in openMSX (FS-A1ST, snd07 without its first 384 samples: 8405 samples)

| CPU | Load | Skipped | Calls |
|---|---|---|---|
| Z80 | 0 | 4252 | 4175 |
| R800 ROM / DRAM | 0 | 0 | 25776 |
| R800 DRAM | 1 block | 1133 | 13870 |
| R800 DRAM | 1 block, chunked | 962 | 12346 |

On the Z80 one call takes longer than a sample once the player is late (the skip path), so it
never catches up. The ROM runs from the cartridge slot (slower on the R800 than the game's
code in RAM).

The core in simulation (`machine_boot_tb`, R800 speed Real) gives the same: load 0 skipped 0,
25834 calls; 1 block skipped 1127, 13894 calls.
