# MIDITEST pro MSX

[English](README.md) | **Česky**

Testovací ROM pro výstup MIDI přes MSX-MIDI (8251 + 8254 na portech E8h–EFh): MT32-pi na
uživatelském portu, MidiLink nebo adaptér MIDI. Hraje na kanálech 2–10 a na obrazovce
ukazuje, co právě zní. Kanály 2–9 jsou části 1–8 MT-32 a kanál 10 je rytmus, stejně funguje
i General MIDI.

## Překlad

```
sh tools/miditest/build.sh
```

| Soubor | Obsah |
|---|---|
| `miditest.rom` | 16 kB cartridge na 4000h |
| `miditest.asm` | program |
| `gen_data.py` | vyrobí `data.inc`: názvy nástrojů a bicích (MT-32, GM), demo píseň, sekvence testů |

Assembler je `pasmo.exe` z `tools/vdptest`. ROM se spustí bez záznamu v databázi mapperů
(hlavička `AB` na offsetu 0, viz [vdptest](../vdptest/README.cs.md)).

## Spuštění

**FPGA**, stroj **Panasonic FS-A1GT** (MSX-MIDI má vestavěné):
1. Nahrát pack `Panasonic_FS-A1GT.msx` a FW pack (`CART_FW_EN.msx` nebo `CART_FW_JP.msx`).
2. Přepínač firmwaru vypnutý (jinak se místo cartridge spustí firmware).
3. `miditest.rom` do slotu A (OSD **Slot1** = ROM).
4. OSD, stránka MIDI: *User Port* = MT32-pi (výchozí). Pro MidiLink: UART v režimu MIDI.

Jiný stroj: libovolné MSX s cartridgí MSX-MIDI ve slotu B (OSD Slot2 = MSX-MIDI) a ROM ve
slotu A.

Na turbo R se ROM přepne na Z80 (BIOS `CHGCPU`).

**openMSX** (výstup MIDI do souboru):

```
openmsx -machine Panasonic_FS-A1GT -cart miditest.rom
  (v konzoli: set midi-out-logfilename out.bin; plug MSX-MIDI-out midi-out-logger)
```

## Obrazovka

```
MSX-MIDI TEST     MT-32  ROM -  SF -      mapa, poslední ROM set / SoundFont
F1 SONG    SPEED 07                       režim a jeho hodnoty
UP/DN SPEED  SPACE PAUSE                  klávesy režimu
■02 Flute 1          G5  100              kanál, nástroj, poslední nota, síla úhozu
▒▒▒▒▒▒▒▒▒▒▒▒▒▒█▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒         znějící noty kanálu (128 not, 2 body na notu)
...                                       kanály 3–10
▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌▌         klaviatura
   0  1  2  3  4  5  6  7  8  9          oktávy (C4 = nota 60)
F1-4 MODE F5 MAP R/S ROM/SF ESC
```

Kanál 10 místo nástroje ukazuje název poslední bicí klávesy. Displej MT32-pi v obraze
(*Show Info* = LCD-On) zakryje levý horní roh, tedy první dva řádky.

## Ovládání

| Klávesa | Funkce |
|---|---|
| F1 | demo píseň (9 kanálů, 16 taktů dokola) |
| F2 | nástroje: kanál 2, programy 0–127 po sobě (arpeggio a akord C dur) |
| F3 | bicí: kanál 10, klávesy 35–81 po sobě |
| F4 | hra z klávesnice na kanálu 2: Z S X D C V G B H N J M , L . a Q 2 W 3 E R 5 T 6 Y 7 U I |
| F5 | mapa MT-32 / GM a SysEx mt32-pi „přepni syntezátor“ (`F0 7D 03 xx F7`) |
| R | SysEx mt32-pi „ROM set“ (`F0 7D 01 xx F7`): staré MT-32, nové MT-32, CM-32L (ne v F4) |
| S | SysEx mt32-pi „SoundFont“ (`F0 7D 02 xx F7`), index 0–7 (ne v F4) |
| mezerník | pauza (ne v F4) |
| ESC | All Notes Off na všech kanálech |
| ↑ / ↓ | F1: rychlost (snímky na šestnáctinu, 2–20); F4: program |
| ← / → | F2: program; F3: klávesa; F4: oktáva |

Po SysEx čeká ROM 0,5 s (na stavovém řádku „WAIT“) a pak pošle programy znovu, protože
nový syntezátor začne s výchozím nastavením kanálů.

## MIDI

- 8254 čítač 0: mód 3, dělitel 8 (4 MHz / 8 = 500 kHz). 8251: ×16, 8N1, tedy 31 250 Bd.
  Přerušení zůstává vypnuté (DTR a RTS v 0).
- Pokud stavový registr 8251 po inicializaci hlásí chybu nebo FFh, napíše ROM v prvním řádku
  `NO MIDI AT E8H` a nic neposílá.
- Na začátku režimu pošle na kanálech 2–10 All Notes Off, Reset All Controllers, hlasitost 100,
  panorama a program. Kanál 10 program nedostává.
- Noty jdou jako Note On, konec noty jako Note On s úhozem 0, s running status.
- Časování podle přerušení VDP (`JIFFY`), takže na 50 Hz hraje píseň pomaleji než na 60 Hz.

Programy písně:

| Kanál | Role | MT-32 | GM |
|---|---|---|---|
| 2 | melodie | 72 Flute 1 | 73 Flute |
| 3 | klavír | 0 Acoustic Piano 1 | 0 Acoustic Grand Piano |
| 4 | smyčce | 48 String Section 1 | 48 String Ensemble 1 |
| 5 | basa | 66 Electric Bass 1 | 33 Electric Bass (finger) |
| 6 | arpeggio | 104 Marimba | 12 Marimba |
| 7 | žestě | 95 Brass Section 1 | 61 Brass Section |
| 8 | protimelodie | 52 Violin 1 | 40 Violin |
| 9 | harfa | 57 Harp 1 | 46 Orchestral Harp |
| 10 | bicí | – | – |

Názvy bicích v mapě MT-32 jsou z rytmické sady CM-32L. Klávesy 76–81 (zvukové efekty) má jen
CM-32L, MT-32 na nich mlčí. Klávesy s „-“ v sadě nejsou.

Píseň je původní skladba vytvořená pro tento test.
