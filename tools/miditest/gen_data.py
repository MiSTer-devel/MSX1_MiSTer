#!/usr/bin/env python3
"""Generates data.inc for miditest.asm: instrument and drum names (MT-32 and GM),
programs of the demo song and the event streams (song, instrument sweep, drum sweep).

Stream format: [delta][n][n x (status, note, velocity)] ... [delta][FFh]
  delta = steps (1/16 notes) since the previous group, FFh as n = end, play again.
  Note off = note on with velocity 0 (running status). Drum stream note 0 = current key.
"""
import os

W = 16  # name field width

MT32 = """Acoustic Piano 1|Acoustic Piano 2|Acoustic Piano 3|Electric Piano 1|Electric Piano 2|
Electric Piano 3|Electric Piano 4|Honkytonk|Electric Organ 1|Electric Organ 2|Electric Organ 3|
Electric Organ 4|Pipe Organ 1|Pipe Organ 2|Pipe Organ 3|Accordion|Harpsichord 1|Harpsichord 2|
Harpsichord 3|Clavinet 1|Clavinet 2|Clavinet 3|Celesta 1|Celesta 2|Synth Brass 1|Synth Brass 2|
Synth Brass 3|Synth Brass 4|Synth Bass 1|Synth Bass 2|Synth Bass 3|Synth Bass 4|Fantasy|Harmo Pan|
Chorale|Glasses|Soundtrack|Atmosphere|Warm Bell|Funny Vox|Echo Bell|Ice Rain|Oboe 2001|Echo Pan|
Doctor Solo|School Daze|Bellsinger|Square Wave|String Section 1|String Section 2|String Section 3|
Pizzicato|Violin 1|Violin 2|Cello 1|Cello 2|Contrabass|Harp 1|Harp 2|Guitar 1|Guitar 2|
Electric Gtr 1|Electric Gtr 2|Sitar|Acoustic Bass 1|Acoustic Bass 2|Electric Bass 1|Electric Bass 2|
Slap Bass 1|Slap Bass 2|Fretless 1|Fretless 2|Flute 1|Flute 2|Piccolo 1|Piccolo 2|Recorder|
Pan Pipes|Sax 1|Sax 2|Sax 3|Sax 4|Clarinet 1|Clarinet 2|Oboe|English Horn|Bassoon|Harmonica|
Trumpet 1|Trumpet 2|Trombone 1|Trombone 2|French Horn 1|French Horn 2|Tuba|Brass Section 1|
Brass Section 2|Vibe 1|Vibe 2|Synth Mallet|Windbell|Glock|Tube Bell|Xylophone|Marimba|Koto|Sho|
Shakuhachi|Whistle 1|Whistle 2|Bottleblow|Breathpipe|Timpani|Melodic Tom|Deep Snare|Elec Perc 1|
Elec Perc 2|Taiko|Taiko Rim|Cymbal|Castanets|Triangle|Orchestral Hit|Telephone|Bird Tweet|
One Note Jam|Water Bells|Jungle Tune"""

GM = """Acou Grand Piano|Bright Acou Pno|Elec Grand Piano|Honky-tonk Piano|Electric Piano 1|
Electric Piano 2|Harpsichord|Clavinet|Celesta|Glockenspiel|Music Box|Vibraphone|Marimba|Xylophone|
Tubular Bells|Dulcimer|Drawbar Organ|Percussive Organ|Rock Organ|Church Organ|Reed Organ|Accordion|
Harmonica|Tango Accordion|Ac Guitar nylon|Ac Guitar steel|E.Guitar jazz|E.Guitar clean|
E.Guitar muted|Overdrive Guitar|Distortion Gtr|Guitar Harmonics|Acoustic Bass|E.Bass finger|
E.Bass pick|Fretless Bass|Slap Bass 1|Slap Bass 2|Synth Bass 1|Synth Bass 2|Violin|Viola|Cello|
Contrabass|Tremolo Strings|Pizzicato Str|Orchestral Harp|Timpani|String Ens. 1|String Ens. 2|
Synth Strings 1|Synth Strings 2|Choir Aahs|Voice Oohs|Synth Voice|Orchestra Hit|Trumpet|Trombone|
Tuba|Muted Trumpet|French Horn|Brass Section|Synth Brass 1|Synth Brass 2|Soprano Sax|Alto Sax|
Tenor Sax|Baritone Sax|Oboe|English Horn|Bassoon|Clarinet|Piccolo|Flute|Recorder|Pan Flute|
Blown Bottle|Shakuhachi|Whistle|Ocarina|Lead 1 (square)|Lead 2 (saw)|Lead 3 calliope|
Lead 4 (chiff)|Lead 5 (charang)|Lead 6 (voice)|Lead 7 (fifths)|Lead 8 bass+lead|Pad 1 (new age)|
Pad 2 (warm)|Pad 3 polysynth|Pad 4 (choir)|Pad 5 (bowed)|Pad 6 (metallic)|Pad 7 (halo)|
Pad 8 (sweep)|FX 1 (rain)|FX 2 soundtrack|FX 3 (crystal)|FX 4 atmosphere|FX 5 brightness|
FX 6 (goblins)|FX 7 (echoes)|FX 8 (sci-fi)|Sitar|Banjo|Shamisen|Koto|Kalimba|Bag pipe|Fiddle|
Shanai|Tinkle Bell|Agogo|Steel Drums|Woodblock|Taiko Drum|Melodic Tom|Synth Drum|Reverse Cymbal|
Gtr Fret Noise|Breath Noise|Seashore|Bird Tweet|Telephone Ring|Helicopter|Applause|Gunshot"""

# keys 35..81
GM_DRUM = """Acou Bass Drum|Bass Drum 1|Side Stick|Acoustic Snare|Hand Clap|Electric Snare|
Low Floor Tom|Closed Hi-Hat|High Floor Tom|Pedal Hi-Hat|Low Tom|Open Hi-Hat|Low-Mid Tom|Hi-Mid Tom|
Crash Cymbal 1|High Tom|Ride Cymbal 1|Chinese Cymbal|Ride Bell|Tambourine|Splash Cymbal|Cowbell|
Crash Cymbal 2|Vibraslap|Ride Cymbal 2|Hi Bongo|Low Bongo|Mute Hi Conga|Open Hi Conga|Low Conga|
High Timbale|Low Timbale|High Agogo|Low Agogo|Cabasa|Maracas|Short Whistle|Long Whistle|
Short Guiro|Long Guiro|Claves|Hi Wood Block|Low Wood Block|Mute Cuica|Open Cuica|Mute Triangle|
Open Triangle"""

# CM-32L rhythm set (keys 76-81 are CM-32L sound effects, silent on an MT-32)
MT_DRUM = """Acou Bass Drum|Acou Bass Drum|Rim Shot|Acou Snare Drum|Hand Clap|Elec Snare Drum|
Acou Low Tom|Closed Hi-Hat|Acou Low Tom|Open Hi-Hat 1|Acou Mid Tom|Open Hi-Hat 2|Acou Mid Tom|
Acou Hi Tom|Crash Cymbal|Acou Hi Tom|Ride Cymbal|-|-|Tambourine|-|Cowbell|-|Vibra-Slap|-|
High Bongo|Low Bongo|Mute Hi Conga|High Conga|Low Conga|High Timbale|Low Timbale|High Agogo|
Low Agogo|Cabasa|Maracas|Short Whistle|Long Whistle|Quijada|-|Claves|Laughing|Screaming|Punch|
Heartbeat|Footsteps 1|Footsteps 2"""


def names(text, count):
    n = [s.strip() for s in text.replace("\n", "").split("|")]
    assert len(n) == count, (len(n), count)
    for s in n:
        assert len(s) <= W and all(32 <= ord(c) < 127 for c in s), s
    return n


def db_names(label, lst, out):
    out.append(f"{label}:")
    for i, s in enumerate(lst):
        out.append(f'        DB      "{s.ljust(W)}"   ; {i}')


# ---------------------------------------------------------------- demo song (original)
SONG_PROG_MT = [72, 0, 48, 66, 104, 95, 52, 57, 0]   # Flute 1, Acoustic Piano 1, String Section 1,
SONG_PROG_GM = [73, 0, 48, 33, 12, 61, 40, 46, 0]    # Electric Bass 1, Marimba, Brass Section 1, Violin 1, Harp 1
MEL, PNO, STR, BAS, MAR, BRS, VLN, HRP, DRM = range(9)

CHORD = {  # voicing around C4, bass root
    "C": ([60, 64, 67], 36), "Am": ([57, 60, 64], 33), "F": ([60, 65, 69], 29),
    "G": ([59, 62, 67], 31), "Dm": ([62, 65, 69], 38), "Em": ([59, 64, 67], 40),
}
PROG = ["C", "Am", "F", "G", "C", "Am", ("Dm", "G"), "C",
        "F", "G", "Em", "Am", "Dm", "G", "C", "G"]

# melody per bar: (step, MIDI note, duration)
MELODY = [
    [(0, 76, 4), (4, 79, 2), (6, 84, 2), (8, 83, 4), (12, 79, 4)],
    [(0, 81, 6), (6, 79, 2), (8, 76, 4), (12, 72, 4)],
    [(0, 77, 4), (4, 81, 4), (8, 84, 6), (14, 81, 2)],
    [(0, 79, 8), (8, 74, 4), (12, 77, 4)],
    [(0, 76, 2), (2, 77, 2), (4, 79, 4), (8, 84, 4), (12, 88, 4)],
    [(0, 86, 4), (4, 84, 4), (8, 81, 8)],
    [(0, 77, 4), (4, 81, 4), (8, 83, 4), (12, 86, 4)],
    [(0, 84, 12)],
    [(0, 81, 6), (6, 84, 2), (8, 81, 4), (12, 77, 4)],
    [(0, 83, 6), (6, 86, 2), (8, 83, 4), (12, 79, 4)],
    [(0, 79, 4), (4, 83, 4), (8, 88, 8)],
    [(0, 84, 4), (4, 83, 4), (8, 81, 4), (12, 76, 4)],
    [(0, 77, 4), (4, 76, 4), (8, 74, 4), (12, 77, 4)],
    [(0, 79, 4), (4, 83, 4), (8, 86, 4), (12, 89, 4)],
    [(0, 88, 8), (8, 86, 4), (12, 84, 4)],
    [(0, 83, 8), (8, 74, 4), (12, 79, 4)],
]
COUNTER = {  # violin, second half
    8: [(0, 77, 8), (8, 76, 8)], 9: [(0, 74, 8), (8, 71, 8)], 10: [(0, 76, 16)],
    11: [(0, 76, 8), (8, 72, 8)], 12: [(0, 74, 8), (8, 69, 8)], 13: [(0, 71, 8), (8, 74, 8)],
    14: [(0, 79, 8), (8, 76, 8)], 15: [(0, 74, 16)],
}


class Stream:
    def __init__(self, length):
        self.length = length
        self.ev = []   # (step, off first, status, note, vel)

    def note(self, slot, step, pitch, dur, vel):
        st = 0x90 | (slot + 1)
        assert 0 <= pitch < 128 and 0 < vel < 128
        self.ev.append((step, 1, st, pitch, vel))
        self.ev.append((min(step + dur, self.length), 0, st, pitch, 0))

    def data(self):
        groups = {}
        for step, on, st, n, v in self.ev:
            groups.setdefault(step, []).append((on, st, n, v))
        out, prev = [], 0
        for step in sorted(groups):
            g = sorted(groups[step])
            d = step - prev
            assert d < 255 and len(g) < 255
            out += [d, len(g)]
            for _, st, n, v in g:
                out += [st, n, v]
            prev = step
        d = self.length - prev
        assert d < 255
        out += [d, 0xFF]
        return out


def song():
    bars = len(PROG)
    s = Stream(bars * 16)
    for b, ch in enumerate(PROG):
        t = b * 16
        halves = [(0, 16, ch)] if isinstance(ch, str) else [(0, 8, ch[0]), (8, 8, ch[1])]
        for h0, hl, name in halves:
            voic, root = CHORD[name]
            for p in voic:
                s.note(STR, t + h0, p, hl, 64)                                   # strings pad
            for o in range(2, hl, 4):
                for p in voic:
                    s.note(PNO, t + h0 + o, p, 2, 72)                            # piano offbeats
            for o, iv, du in [(0, 0, 3), (4, 0, 2), (6, 7, 2)][: 3 if hl == 16 else 3]:
                if o < hl:
                    s.note(BAS, t + h0 + o, root + iv, du, 100)                  # bass
            if hl == 16:
                for o, iv, du in [(8, 0, 3), (12, 12, 2), (14, 7, 2)]:
                    s.note(BAS, t + o, root + iv, du, 96)
            arp = [voic[0], voic[1], voic[2], voic[0] + 12, voic[2], voic[1], voic[0], voic[1]]
            for i in range(hl // 2):
                s.note(MAR, t + h0 + 2 * i, arp[i] + 12, 2, 58)                  # marimba 8ths
        for st, p, du in MELODY[b]:
            s.note(MEL, t + st, p, du, 100)                                      # melody
        for st, p, du in COUNTER.get(b, []):
            s.note(VLN, t + st, p, du, 76)                                       # counter melody
        last = PROG[b] if isinstance(PROG[b], str) else PROG[b][1]
        voic, _ = CHORD[last]
        if b % 4 == 3:
            if b % 8 == 3:
                for p in voic:
                    s.note(BRS, t + 8, p, 2, 92)                                 # brass stabs
                    s.note(BRS, t + 12, p, 4, 100)
            else:
                for p in voic:
                    s.note(BRS, t + 0, p, 4, 100)
            run = [voic[0], voic[1], voic[2], voic[0] + 12, voic[1] + 12, voic[2] + 12,
                   voic[0] + 24, voic[1] + 24]
            for i, p in enumerate(run):
                s.note(HRP, t + 8 + i, p, 2, 70)                                 # harp run
        # drums
        for o in range(0, 16, 2):
            if b % 4 == 3 and o == 14:
                s.note(DRM, t + o, 46, 2, 80)                                    # open hat
            else:
                s.note(DRM, t + o, 42, 1, 84 if o % 4 == 0 else 64)              # closed hat
        if b == bars - 1:
            for o, k in [(0, 36), (4, 38), (8, 50), (10, 48), (12, 45), (14, 41)]:
                s.note(DRM, t + o, k, 1, 108)                                    # fill
        else:
            for o in [0, 8] + ([10] if b % 2 else []):
                s.note(DRM, t + o, 36, 1, 112)                                   # kick
            for o in [4, 12]:
                s.note(DRM, t + o, 38, 1, 100)                                   # snare
        if b % 8 == 0:
            s.note(DRM, t, 49, 2, 110)                                           # crash
    return s.data()


def inst():
    s = Stream(16)
    for i, p in enumerate([60, 64, 67, 72]):
        s.note(MEL, 2 * i, p, 2, 100)
    for p in [60, 64, 67]:
        s.note(MEL, 8, p, 6, 100)
    return s.data()


def drum():
    s = Stream(6)
    s.ev.append((0, 1, 0x99, 0, 110))   # note 0 = current key
    s.ev.append((2, 0, 0x99, 0, 0))
    return s.data()


def db_bytes(label, data, out):
    out.append(f"{label}:")
    for i in range(0, len(data), 16):
        out.append("        DB      " + ", ".join(f"{x:03X}h" for x in data[i:i + 16]))


def main():
    out = ["; Generated by gen_data.py - do not edit", ""]
    db_names("NAMES_MT", names(MT32, 128), out)
    db_names("NAMES_GM", names(GM, 128), out)
    db_names("DRUM_MT", names(MT_DRUM, 47), out)
    db_names("DRUM_GM", names(GM_DRUM, 47), out)
    db_bytes("PROG_MT", SONG_PROG_MT, out)
    db_bytes("PROG_GM", SONG_PROG_GM, out)
    sd = song()
    db_bytes("SONG", sd, out)
    db_bytes("INSTS", inst(), out)
    db_bytes("DRUMS", drum(), out)
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data.inc")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print(f"data.inc: song {len(sd)} bytes")


main()
