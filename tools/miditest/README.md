# MIDITEST for MSX

**English** | [Česky](README.cs.md)

A test ROM for MIDI output through MSX-MIDI (8251 + 8254 at ports E8h–EFh): an MT32-pi on the
user port, MidiLink or a MIDI adapter. It plays on channels 2–10 and shows on screen what is
sounding. Channels 2–9 are the MT-32 parts 1–8 and channel 10 is the rhythm part; General MIDI
works the same way.

## Build

```
sh tools/miditest/build.sh
```

| File | Content |
|---|---|
| `miditest.rom` | 16 kB cartridge at 4000h |
| `miditest.asm` | the program |
| `gen_data.py` | makes `data.inc`: instrument and drum names (MT-32, GM), demo song, test sequences |

The assembler is `pasmo.exe` from `tools/vdptest`. The ROM starts without an entry in the
mapper database (`AB` header at offset 0, see [vdptest](../vdptest/README.md)).

## Running

**FPGA**, machine **Panasonic FS-A1GT** (MSX-MIDI built in):
1. Load the `Panasonic_FS-A1GT.msx` pack and the FW pack (`CART_FW_EN.msx`).
2. Firmware switch off (otherwise the firmware starts instead of the cartridge).
3. `miditest.rom` into slot A (Cartridge = ROM).
4. OSD, MIDI page: *User Port* = MT32-pi (default). For MidiLink: UART in MIDI mode.

Another machine: any MSX with the MSX-MIDI cartridge in slot B (OSD Slot2 = MSX-MIDI) and the
ROM in slot A.

On a turbo R the ROM switches to the Z80 (BIOS `CHGCPU`).

**openMSX** (MIDI output to a file):

```
openmsx -machine Panasonic_FS-A1GT -cart miditest.rom
  (console: set midi-out-logfilename out.bin; plug MSX-MIDI-out midi-out-logger)
```

## Screen

```
MSX-MIDI TEST     MT-32  ROM -  SF -      map, last ROM set / SoundFont sent
F1 SONG    SPEED 07                       mode and its values
UP/DN SPEED  SPACE PAUSE                  keys of the mode
■02 Flute 1          G5  100              channel, instrument, last note, velocity
▒▒▒▒▒▒▒▒▒▒▒▒▒▒█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒         notes sounding on the channel (128 notes, 2 pixels each)
...                                       channels 3–10
▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌         keyboard
   0  1  2  3  4  5  6  7  8  9          octaves (C4 = note 60)
F1-4 MODE F5 MAP R/S ROM/SF ESC
```

Channel 10 shows the name of the last drum key instead of an instrument. The MT32-pi display
in the picture (*Show Info* = LCD-On) covers the top left corner, i.e. the first two rows.

## Keys

| Key | Function |
|---|---|
| F1 | demo song (9 channels, 16 bars, repeated) |
| F2 | instruments: channel 2, programs 0–127 in turn (C major arpeggio and chord) |
| F3 | drums: channel 10, keys 35–81 in turn |
| F4 | play from the keyboard on channel 2: Z S X D C V G B H N J M , L . and Q 2 W 3 E R 5 T 6 Y 7 U I |
| F5 | map MT-32 / GM and the mt32-pi SysEx "switch synth" (`F0 7D 03 xx F7`) |
| R | mt32-pi SysEx "ROM set" (`F0 7D 01 xx F7`): old MT-32, new MT-32, CM-32L (not in F4) |
| S | mt32-pi SysEx "SoundFont" (`F0 7D 02 xx F7`), index 0–7 (not in F4) |
| Space | pause (not in F4) |
| ESC | All Notes Off on all channels |
| ↑ / ↓ | F1: speed (frames per 1/16 note, 2–20); F4: program |
| ← / → | F2: program; F3: key; F4: octave |

After a SysEx the ROM waits 0.5 s ("WAIT" on the status line) and then sends the programs
again, because the new synth starts with the default channel settings.

## MIDI

- 8254 counter 0: mode 3, divider 8 (4 MHz / 8 = 500 kHz). 8251: ×16, 8N1, i.e. 31,250 Bd.
  Interrupts stay off (DTR and RTS 0).
- If the 8251 status register reports an error or reads FFh after the setup, the ROM shows
  `NO MIDI AT E8H` in the first row and sends nothing.
- At the start of a mode it sends All Notes Off, Reset All Controllers, volume 100, pan and
  program on channels 2–10. Channel 10 gets no program.
- Notes are Note On, the note end is Note On with velocity 0, with running status.
- Timing follows the VDP interrupt (`JIFFY`), so at 50 Hz the song plays slower than at 60 Hz.

Song programs:

| Channel | Role | MT-32 | GM |
|---|---|---|---|
| 2 | melody | 72 Flute 1 | 73 Flute |
| 3 | piano | 0 Acoustic Piano 1 | 0 Acoustic Grand Piano |
| 4 | strings | 48 String Section 1 | 48 String Ensemble 1 |
| 5 | bass | 66 Electric Bass 1 | 33 Electric Bass (finger) |
| 6 | arpeggio | 104 Marimba | 12 Marimba |
| 7 | brass | 95 Brass Section 1 | 61 Brass Section |
| 8 | counter melody | 52 Violin 1 | 40 Violin |
| 9 | harp | 57 Harp 1 | 46 Orchestral Harp |
| 10 | drums | – | – |

The drum names of the MT-32 map come from the CM-32L rhythm set. Keys 76–81 (sound effects)
exist only on the CM-32L; an MT-32 stays silent on them. Keys shown as "-" are not in the set.

The song is an original piece written for this test.
