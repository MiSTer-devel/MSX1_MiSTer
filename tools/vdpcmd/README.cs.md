# VDPCMD jako ROM

[English](README.md) | **Česky**

Cartridge ROM, která spustí [vdpcmd](https://github.com/bengalack/vdpcmd) od bengalacka bez
MSX-DOS. vdpcmd měří, kolik pixelů zvládne příkazový engine V9938/V9958 za jeden snímek, a
porovnává to s hodnotami naměřenými na skutečných strojích (sloupec `REAL`). Popis testů a jak
číst výsledky je v README originálu.

ROM obsahuje originální `vdpcmd.com` beze změny, takže měření běží stejným kódem jako pod DOSem.

## Překlad

```
sh tools/vdpcmd/build.sh
```

| Soubor | Obsah |
|---|---|
| `vdpcmd.rom` | 16 kB cartridge na 4000h |
| `vdpcmd.asm` | zavaděč a náhrada prostředí MSX-DOS |
| `upstream/vdpcmd.com` | originální program (bengalack/vdpcmd, commit `ddcc203`) |
| `upstream/LICENSE` | licence originálu (MIT) |

Assembler je `pasmo.exe` z `tools/vdptest`. ROM se spustí bez záznamu v databázi mapperů
(hlavička `AB` na offsetu 0, viz [vdptest](../vdptest/README.cs.md)).

## Spuštění

Libovolný stroj MSX2, MSX2+ nebo turbo R: `vdpcmd.rom` do slotu A (Cartridge = ROM). Program se
spustí hned po startu, několik sekund měří (obraz se střídá mezi SCREEN 8 a vypnutým obrazem)
a pak vypíše tabulku v 80 sloupcích. Mezerník pustí měření znovu.

Na FS-A1ST/GT musí být přepínač firmwaru vypnutý, jinak se místo cartridge spustí firmware.

Měří se ve frekvenci, kterou má stroj nastavenou (50 nebo 60 Hz), a podle ní se vybírají i
hodnoty `REAL`. Na turbo R a s turbem Panasonic se vdpcmd sám přepne na Z80 3,5 MHz.

**openMSX:**

```
openmsx -machine Philips_NMS_8245 -cart vdpcmd.rom
```

## Jak ROM nahrazuje DOS

vdpcmd počítá s tím, co mu dává MSX-DOS:
- RAM ve všech čtyřech stránkách, program na 0100h, jeho data sahají až do 4817h;
- na 0038h je `JP`, vdpcmd přepisuje adresu na 0039h na vlastní obsluhu přerušení (ta ukončuje
  příkaz VDP v přerušení snímku);
- BIOS volá přes `CALSLT` (001Ch) a `RDSLT` (000Ch), konec ohlásí přes BDOS (0005h).

ROM to připraví takto:
1. Rezidentní část zkopíruje do RAM na E000h, zásobník je pod F000h.
2. Stránky 0 a 1 přepne na slot RAM stránky 3 (primární i sekundární slot), tam nahraje
   `vdpcmd.com` na 0100h a vynuluje zbytek RAM až po E000h.
3. Na 0038h dá `JP` na obsluhu, která zavolá přerušení BIOSu, na 000Ch a 001Ch `JP` na
   `RDSLT` / `CALSLT` a na 0000h a 0005h `JP` na konec programu.
4. `CALSLT` a `RDSLT` přepnou stránku 0 na hlavní BIOS, zavolají ho a vrátí RAM. `CALSLT` umí
   jen hlavní BIOS (vdpcmd jiný slot nevolá); obě se vracejí se zakázaným
   přerušením.
5. Volání BDOS vrátí sloty do stavu při startu cartridge, vypíše `SPACE: run again` a čeká na
   mezerník.

Vlastní testy (každý mezi dvěma přerušeními snímku) nic z toho nevolají, takže časování je
stejné jako pod DOSem.
