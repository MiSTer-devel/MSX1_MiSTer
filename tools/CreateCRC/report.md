# Mapper database report

Source: `https://romdb.vampier.net/Archive/sql-msxromdb.zip`  
Records in `vampier.db`: **8096** (previous file: 8074; added 22, removed 0, changed 0)  
Mirrored/Normal start address: 3765 from the header, 480 guessed (no header at 0, placed at 0000h like the core does without a record)  
Overrides: 53 lines, 0 give the same as the dump (`--prune` removes them)

## Supported

| FW configuration | ID | ROMs | of them override | DB types |
|---|---|---|---|---|
| Mirror_0x4000 | 27 | 3259 | 13 | Mirrored, Mirrored4000 |
| KonamiSCC | 56 | 1349 |  | KonamiSCC |
| ASCII8 | 50 | 767 |  | ASCII8 |
| ASCII16 | 51 | 691 |  | ASCII16 |
| Mirror_0x0000 | 26 | 487 | 1 | Mirrored |
| Mirror_0x8000 | 28 | 461 | 4 | Mirrored, Normal |
| KONAMI | 52 | 402 |  | Konami, konami |
| 0x8000 | 22 | 302 |  | 0x8000, Normal, Page2 |
| 0x4000 | 21 | 91 | 13 | 0x4000, Mirrored, Normal, Page12 |
| Generic8kB | 25 | 67 |  | 8kB |
| ASCII16X | 57 | 49 |  | ASCII16-X |
| 0x0000 | 20 | 29 | 22 | 0x0000, Mirrored |
| 16kb | 23 | 25 |  | 16kb |
| KOEI | 54 | 24 |  | KoeiSRAM32 |
| ASCII8SRAM8 | 36 | 16 |  | ASCII8SRAM8 |
| NEO8 | 58 | 13 |  | NEO-8 |
| ASCII16SRAM2 | 33 | 10 |  | ASCII16SRAM2 |
| NEO16 | 59 | 9 |  | NEO-16 |
| RTYPE | 49 | 8 |  | R-Type |
| Synthesizer | 41 | 8 |  | Synthesizer |
| ASCII16SRAM8 | 34 | 5 |  | ASCII16SRAM8 |
| ASCII8SRAM2 | 35 | 5 |  | ASCII8SRAM2 |
| Zemina80 | 31 | 5 |  | Zemina80in1 |
| Zemina90 | 32 | 3 |  | Zemina90in1 |
| CrossBlaim | 29 | 2 |  | CrossBlaim |
| GM2_ROM | 55 | 2 |  | GameMaster2 |
| HarryFox | 30 | 2 |  | HarryFox |
| SuperSwangi | 40 | 2 |  | SuperSwangi |
| WIZARDRY | 53 | 2 |  | Wizardry |
| MSXWrite | 42 | 1 |  | MSXWrite |

## Not supported

ROM types of the dump without a FW configuration. They are not in the database: a ROM up to 64 kB then runs as plain ROM (may work), a bigger one stops with "Not find CRC32 in DB". The column "over 64 kB" counts the ROMs that cannot run at all without the mapper.

| DB type | ROMs | games | over 64 kB | max kB | examples |
|---|---|---|---|---|---|
| YAMANOOTO | 12 | 4 | 12 | 8192 | Konami Neo-Ultimate Collection, Nightstalker, Tech Demo - Xenon 2 Megablast, ... |
| MatraCompilation | 6 | 5 | 6 | 512 | Cardwork Orange, Casio GPM-Compilation Volumen 1, Casio GPM-Compilation Volumen 2, ... |
| Namco | 6 | 6 | 0 | 16 | Bosconian, Dig Dug, Galaga, ... |
| manbow2 | 6 | 2 | 6 | 512 | Lotus F3, Manbow 2 |
| KonamiUltimateCollection | 5 | 2 | 5 | 5120 | Konami ultimate collection, Pampas and Selene |
| Manbow2_2 | 4 | 1 | 4 | 512 | Manbow 2 |
| AlAlamiah30-in-1 | 3 | 3 | 3 | 1024 | 30-in-1 Group A, 30-in-1 Group B, 30-in-1 Group C |
| Majutsushi | 3 | 1 | 3 | 128 | Hai no Majutsushi - Mahjong 2 |
| Halnote | 2 | 1 | 2 | 1024 | Halnote |
| ReproCartridgeV1 | 2 | 2 | 2 | 8192 | Metal Gear, Metal Gear 2 - Solid Snake |
| RetroHardMultiCart31in1 | 2 | 2 | 2 | 1024 | Multicart 31 in 1 - SHMUPS - Jogos de tiro, Multicart 31 in 1 - Volume 1 |
| SuperLodeRunner | 2 | 1 | 2 | 128 | Super Lode Runner |
| WonderKid | 2 | 2 | 2 | 128 | Aliens 2, Wonder Kid |
| Zemina126in1 | 2 | 1 | 2 | 2048 | Super Game World - 126 Games |
| Zemina25in1 | 2 | 1 | 2 | 512 | Super Game 25 |
| AlQuranDecoded | 1 | 1 | 1 | 1024 | Holy Quaran |
| Arc | 1 | 1 | 0 | 32 | ARC |
| ColecoMegaCart | 1 | 1 | 1 | 128 | The Pink Panther |
| HamarajaNight | 1 | 1 | 1 | 512 | Best of Hamaraja Night |
| Korean128in1 | 1 | 1 | 1 | 1024 | 128-in-1 |
| MatraInk | 1 | 1 | 0 | 48 | INK - Exxon Surfing |
| NettouYakyuu | 1 | 1 | 1 | 256 | Moero!! Nettou Yakyuu '88 |
| Playball | 1 | 1 | 0 | 32 | Playball |
| RBSC_Flash_KonamiSCC | 1 | 1 | 1 | 2048 | Angelic Warrior Deva |
| dooly | 1 | 1 | 0 | 32 | Agigongnyong Dooly (Baby Dinosaur Dooly) |
| keyboardmaster | 1 | 1 | 0 | 16 | Keyboard Master |
| playball | 1 | 1 | 0 | 32 | Playball |

## Left out of the dump

| Reason | ROMs |
|---|---|
| platform ColecoVision | 1341 |
| type System | 1234 |
| platform SG-1000 | 341 |
| type auto | 33 |
| over 16 MB | 13 |
| platform SVI | 11 |
