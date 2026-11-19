# PCMTEST pro MSX turbo R

[English](README.md) | **Česky**

Testovací ROM, která na turbo R přehrává PCM přehrávačem ze hry Criterion a počítá vzorky,
které musela přeskočit. Ukazuje, jak zvuk závisí na tom, jak často se přehrávač dostane k CPU.

## Jak Criterion přehrává PCM

Hra nepoužívá BIOS (`PCMPLY`). Vlastní přehrávač (blok ROM 0, 4F03h / 4F18h) se volá přes háčky
v RAM (C6E7h, C29Bh, C1A3h): při čekání na VDP, po každých 16 bajtech kopírovaných do VRAM, po
zápisech do OPLL a ve smyčce snímku. Každé volání:

1. přečte systémový časovač S1990 (E7h, E6h; 3,911 µs na tik) a odečte čas dalšího vzorku;
2. ještě není čas: vrátí se;
3. zpoždění pod 32 tiků: pošle další vzorek (`OUT (A4h)`), čas + 32 tiků;
4. zpoždění 32 až 2047 tiků: zmeškané vzorky přeskočí a pošle následující;
5. 2048 tiků a víc: nic nepřeskočí, čas začne znovu od teď.

Rychlost tedy určuje časovač: 32 tiků = 125,2 µs, **7990 Hz**, na každém CPU. Rychlost CPU
rozhoduje jen o tom, kolik vzorků se přeskočí. Dlouhé úseky bez volání (`OTIR` 256 bajtů do VRAM
na 4444h: na R800 čeká každý přístup k VDP 62 cyklů R800, 8,7 µs, takže 256 bajtů trvá 2,2 ms
= 17 vzorků) vyřezávají ze zvuku kusy.

Hra plní z ROM dva buffery po 384 bajtech (3D00h, 3E80h) a předává je přehrávači (první
na 0189h, další na 4FC7h).

Zvuky jsou v tabulce v bloku ROM 0: 475Eh banka (8 kB), 4769h adresa, 477Fh délka, 4795h
priorita (zvuk přeruší jen zvuk se stejnou nebo nižší prioritou); 11 zvuků, uložených bez
komprese (8 bitů bez znaménka, na A4h jdou beze změny) na banka * 2000h + (adresa & 1FFFh).

| Zvuk | ROM | Vzorků | Délka | Priorita | Jméno |
|---|---|---|---|---|---|
| snd00 | 0B72CFh | 4794 | 0,60 s | 3 | P01 orchestrální úder |
| snd01 | 0B8589h | 4794 | 0,60 s | 3 | P02 orchestrální úder o malou tercii níž |
| snd02 | 0B9843h | 6392 | 0,80 s | 3 | P03 orchestrální úder o oktávu níž |
| snd03 | 0BB13Bh | 1997 | 0,25 s | 1 | P05 malý buben |
| snd04 | 0BB908h | 7990 | 1,00 s | 2 | P06 velký výbuch |
| snd05 | 0BD83Eh | 10025 | 1,25 s | 4 | V01 hlas „INFINITAS LAUNCH“ |
| snd06 | 0BFF67h | 3795 | 0,47 s | 4 | V02 hlas „WARNING“ |
| snd07 | 0C0E3Ah | 8789 | 1,10 s | 4 | V03 hlas „SYSTEM ONLINE“ |
| snd08 | 0C308Fh | 7397 | 0,93 s | 4 | V04 hlas „UNMEASURABLE“ |
| snd09 | 0C4D74h | 5889 | 0,74 s | 4 | V05 hlas „GAME OVER“ |
| snd10 | 0C6475h | 6632 | 0,83 s | 4 | V06 hlas „CALIBRATION“ |

## Sestavení

Zvuková data jsou ze hry a v repozitáři nejsou:

```
python mkraw.py Criterion.rom   # -> data/snd00..10.raw a .wav (7990 Hz, 8 bitů bez znaménka)
sh build.sh                     # -> pcmtest.rom se snd07 snd09 snd05 (klávesy 1, 2, 3)
sh build.sh 07 10 03            # jiné zvuky, nejvýš 9 a celkem 32 kB
```

`data/sndNN.wav` je zvuk přesně tak, jak je uložený ve hře, bez jediného přeskočeného vzorku:
takhle má znít.

## Klávesy

| Klávesa | |
|---|---|
| 1–9 | přehrát zvuk (seznam je na obrazovce) |
| L | zátěž VDP na snímek (16,7 ms): 0, 1, 2, 4 bloky po 256 bajtech `OTIR` |
| C | po částech: přehrávač běží i po každých 16 bajtech bloku (jako hra na 54D8h) |
| I | přerušení při přehrávání zapnutá / vypnutá |
| Z R D | CPU: Z80, R800 ROM, R800 DRAM (BIOS `CHGCPU`); po startu R800 DRAM jako hra |

Po zvuku: vzorky `played` / `skipped`, `restart` (zpoždění 2048 tiků), `late max` (tiky po
čase vzorku) a `calls` = počet volání přehrávače (míra rychlosti CPU).

## Výsledky v openMSX (FS-A1ST, snd07 bez prvních 384 vzorků: 8405 vzorků)

| CPU | Zátěž | Přeskočeno | Volání |
|---|---|---|---|
| Z80 | 0 | 4252 | 4175 |
| R800 ROM / DRAM | 0 | 0 | 25776 |
| R800 DRAM | 1 blok | 1133 | 13870 |
| R800 DRAM | 1 blok, po částech | 962 | 12346 |

Na Z80 trvá jedno volání déle než jeden vzorek, jakmile je přehrávač pozadu (cesta
s přeskakováním), a už to nedožene. ROM běží ze slotu cartridge (na R800 pomalejší než kód hry
v RAM).

Jádro v simulaci (`machine_boot_tb`, R800 speed Real) dává totéž: zátěž 0 přeskočeno 0,
25834 volání; 1 blok přeskočeno 1127, 13894 volání.
