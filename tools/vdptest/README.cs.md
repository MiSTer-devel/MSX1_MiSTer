# VDPTEST pro MSX

[English](README.md) | **Česky**

Testovací ROM pro VDP: TMS9918A/28A/29A (jádro `VDP18`), V9938 a V9958 (jádro ESE VDP).
Spouští se na FPGA jádru a v openMSX a výsledky se porovnávají. Měří hlavně
**časování**:
- kdy se nastaví příznaky ve stavových registrech (F, 5S, C, VR, FH, CE);
- kdy přichází přerušení a jak dlouho trvají příkazy VDP.

Na jedné stránce jsou i pruhy z přerušení k vizuálnímu porovnání.

Vychází ze stejnojmenného testu pro Sord M5 (`SordM5_MiSTer_verilog/tools/vdptest`).
Program je ale napsaný znovu pro MSX: porty 98h–9Bh, klávesnice přes PPI a přerušení IM2.

## Překlad

```
sh tools/vdptest/build.sh
```

| Soubor | Obsah |
|---|---|
| `vdptest.rom` | 16 kB cartridge na 4000h. **Mezerník** = další stránka, **Enter** = předchozí. |
| `vdptest_auto.rom` | Stránkuje sám (asi po 0,6 s), pro simulaci. |
| `cmdbench.rom` | Doby příkazů VDP ve 14 konfiguracích (MSX2), viz kapitola CMDBENCH. |

Assembler je `pasmo.exe` 0.6.0 (zkopírovaný z projektu Sord M5). Volba
`--equ STARTPG=n` začne stránkou n+1 (ladění jedné stránky v simulaci).

**Pravidla pro ROM** (jádro ji spustí bez záznamu v databázi mapperů):
- na offsetu 0 hlavička `AB` + INIT ve stránce 4000h–7FFFh, tím se ROM umístí na 4000h;
- velikost nejvýš 48 kB;
- délka se nemusí zarovnávat.

## Spuštění

**FPGA:** v OSD nahrát `vdptest.rom` do slotu A (Cartridge = ROM).
- Musí být nahraný FW pack (`CART_FW_EN.msx`).
- Databáze mapperů nahraná být nemusí: ROM, kterou v ní jádro nenajde, spustí jako plain
  ROM podle hlavičky (viz [Podporované ROM mappery](../../Readme.cs.md#podporované-rom-mappery)).
- Pokud databáze nahraná je, vdptest v ní být nesmí, jinak by se použil záznam z ní.
- Vyžaduje jádro s commitem `e5dc75c` (větev `ROM_no_db`). Starší jádro spustí jen ROM se
  záznamem v databázi: CRC32 + mapper „0x4000“ (21), formát v `tools/CreateCRC/createDB.py`.

**openMSX** (stroj podle typu VDP):

```
openmsx -machine Philips_VG_8020 -cart vdptest.rom      # TMS9929A (PAL)
openmsx -machine Philips_NMS_8245 -cart vdptest.rom     # V9938
openmsx -machine Panasonic_FS-A1WX -cart vdptest.rom    # V9958
```

**Simulace celého stroje** (`rtl/tb/machine_boot_tb`, stránky jdou do logu jako text):

```
wsl.exe -- bash rtl/tb/run_machine_boot.sh <stroj.msx> none \
   (SIMARGS="+run_ms=20000 +fw=<CART_FW_EN.msx> +rom=tools/vdptest/vdptest_auto.rom")
```

## Jak program měří

- **Typ VDP:** zapíše R#15 = 1 a čte port 99h.
  - V99x8 pak vrací S#1: bit 7 (FL) zůstane 0, ID je v bitech 5–1 (V9938 = 0, V9958 = 2).
  - TMS99xx R#15 nemá, zápis skončí v R#7 (ten se pak přepíše) a čte se dál S#0, ve kterém se do snímku nastaví F.
  - Stránky jen pro V99x8 se na TMS přeskočí.
- **Turbo R** se přepne na Z80 (BIOS `CHGCPU`), aby smyčky počítaly takty Z80.
- **Měří se s DI** čtecí smyčkou v RAM:
  `IN A,(99h) / AND m / JR cc / INC HL / LD A,H / INC A / JP NZ`.
  Na MSX (jeden M1 wait na každý načtený opkód) má **56 T na iteraci**. Řádek má 228 T, tedy
  **4,07 iterace na řádek**.
- **Časový limit** je 65 280 iterací (asi 1 s), vypíše se jako `-----`.
- **Výsledky** jsou počty iterací. Porovnává se FPGA s openMSX. Řádek `MODEL` je výpočet
  podle modelu openMSX (`VDP.cc`), ne měření. Mezi dvěma měřeními se ztratí pár iterací
  na režii.

## Stránky

| # | Stránka | VDP | Co měří | MODEL |
|---|---|---|---|---|
| 1 | INFO | vše | Typ VDP, bajt verze MSX, ID V99x8. Délka snímku: iterace mezi dvěma F (5×). | NTSC 1066, PAL 1274 |
| 2 | IRQ BARS | vše | **Vizuální.** VBLANK přerušení přebarví okraj na 3 řádky **bíle**. Na V99x8 přerušení řádku (R#19 = 96) **žlutě**. Pruh začíná v okamžiku přerušení plus latence obsluhy (asi 0,3 řádku). | Bílý pruh hned pod obrazem. Žlutý od pravého okraje řádku 96. |
| 3 | S#2 VR | V99x8 | Od F do VR = 0, doba VR = 0, a zda je F nastavené hned po VR = 1. 4 řádky měření. | NTSC 281 / 786 / 1, PAL 489 / 786 / 1 |
| 4 | LINE INTERRUPT | V99x8 | S IE1 a DI: od F do FH v S#1 pro R#19 = 0, 100, 191. | NTSC 288 / 695 / 1066, PAL 496 / 903 / 1288 |
| 5 | S#1 FH | V99x8 | a) FH (R#19 = 190, IE1) přečtené 40 řádků po F; b) bez IE1: od F do FH = 1, doba FH = 1, FH přečtené na řádku 110; c) IE1 zapnuté až po shodě. | a) 1111; b) ~695 / 0–1 / 0; c) 0000 |
| 6 | 5S AND C TIMING | vše | Graphic 1, sprity na řádku 100: od F do 5S (5 spritů vedle sebe) a do C (2 překryté). | asi 690 |
| 7 | SPRITE COLLISION WINDOW | vše | C za celý snímek (všechna čtení S#0 sečtená), sprity Y = 99, 191, 209, 230 (32 spritů), 252. TMS v Graphic 1, V99x8 v SCREEN 5. | V99x8 11001 |
| 8 | VDP COMMAND TIME | V99x8 | SCREEN 5, obraz zapnutý, sprity vypnuté: HMMV, LMMV, YMMM, HMMM, LMMM, LINE 255×100, LINE 255×255 a HMMV s vypnutým obrazem. Od startu příkazu do CE = 0. | — (porovnat s openMSX) |

**Poznámky ke stránkám:**
- **Stránka 4, R#19 = 191:** shoda nastane ještě před F, proto se FH po F nejdřív smaže a
  měří se až další snímek.
- **Stránka 7, Y = 191** (sprite na řádcích 192–199):
  - openMSX kontroluje sprity V99x8 i na řádku 192, takže hlásí C;
  - TMS9929A změřený na Sord M5 kolizi na řádku 192 nehlásí.

## Výsledky

**Simulace** celého stroje (`machine_boot_tb`, 2026-11-10, větev `VDP_fork` s opravami
VDP). Sloupec openMSX: Philips NMS 8245 (V9938 PAL), 2026-11-10. Sloupec FPGA: NMS 8245 na MiSTeru, 2026-11-10.

| Stránka | NMS 8245, V9938 PAL (sim.) | VG-8020, TMS (sim.) | FPGA | openMSX |
|---|---|---|---|---|
| 1 snímek | 1268–1271 | 1268–1272 (po opravě PAL, dřív 1060–1064) | 1268–1272 | 1268–1272 |
| 3 VR | 485 / 780 / 1 | — | 484–485 / 780–781 / 1 | 485 / 780 / 1 |
| 4 FH, R#19 = 0/100/191 | 492 / 899 / 1269 | — | 491–492 / 899 / 1269 | 491–492 / 899 / 1269 |
| 5 FH | a) 1111; b) 899 / 0 / 0; c) 0000 | — | a) 1111; b) 899 / 0 / 0; c) 0000 | a) 1111; b) 899 / 0 / 0; c) 0000 |
| 6 5S / C | 890 / 894 | 686 / 691–692 | 890 / 894 | 894 / 895 |
| 7 kolize | 11001 | 10001 | 11001 | 11001 |
| 8 HMMV / LMMV / YMMM / HMMM / LMMM | 4553 / 18689 / 5675 / 5579 / 21737 | — | 4553 / 18648 / 5717 / 5537 / 21737 | 4561 / 18226 / 5495 / 7715 / 21280 |
| 8 LINE 255,100 / 255,255 / HMMV vyp. | 77 / 77 / 3262 | — | 77 / 77 / 3262 | 103 / 121 / 3996 |

**Poznámky:**
- **VG-8020 (PAL)** běžel s TMS v NTSC: `deviceParams.json` kóduje PAL = 0, NTSC = 1 a
  `dev_tms` posílal `param[0]` přímo do `is_pal_i`. Opraveno v `9de13dc`.
- **FPGA = simulace:** stránky 1–7 shodně (±1 iterace), příkazy do 0,8 %.
- **V9938 FPGA vs openMSX:** stránky 1, 3, 4, 5 a 7 se shodují.
- **5S (stránka 6)** přijde v ESE o 4 iterace (~1 řádek) dřív, C o 1 iteraci.
  - openMSX kontroluje sprity celého řádku najednou na jeho konci (komentář v
    `SpriteChecker.hh`, `checkUntil`); ESE prohledává Y během řádku před ním a
    podle téhož komentáře to tak nejspíš dělá i čip.
  - Pro okamžik 5S proto openMSX není přesná reference.
- **Příkazy VDP (stránka 8)**, ESE proti openMSX:
  - HMMV −0,2 %, LMMV +2,5 %, YMMM +3,3 %, LMMM +2,1 %: shoda;
  - HMMM o 28 % rychlejší (7715 → 5579);
  - HMMV s vypnutým obrazem o 18 % rychlejší (3996 → 3262);
  - LINE o 25–36 % rychlejší a nezávislý na vedlejší ose (openMSX 103 / 121, ESE 77 / 77).
  - Dřívější závěr „logické příkazy 3× pomalejší“ byl chybný: srovnával s čísly z forku
    (tamní openMSX HMMV 722 řádků, tady 1120), naměřená tedy s jinými parametry.

## CMDBENCH (doby příkazů V9938/V9958)

`cmdbench.rom` měří osm příkazů (HMMV, LMMV, SRCH, YMMM, HMMM, LMMM, LINE 255×100 a 255×255)
ve 14 konfiguracích:
- SCREEN 5: NTSC a PAL, 212 a 192 řádků, sprity zapnuté a vypnuté, vypnutý obraz;
- SCREEN 6, 7 a 8 (NTSC, 212 řádků, sprity zapnuté) a SCREEN 8 se sprity vypnutými.

Každý příkaz startuje, když VR přejde na 0 (řádek před displejem). Výsledek je počet
iterací smyčky 56 T do CE = 0, jako na stránce 8 vdptestu. Po měření ROM vypíše tabulku
v 80 sloupcích, jeden řádek na konfiguraci. Výsledky jsou i v RAM od C000h (14 × 8 slov),
C0FEh = A5h znamená hotovo.

**openMSX bez okna** (výsledky do souboru, skript `cmdbench.tcl`):

```
OPENMSX_USER_DATA=<adresář s systemroms> CMDBENCH_OUT=vysledek.txt   openmsx -machine Philips_NMS_8245 -cart cmdbench.rom -script cmdbench.tcl
```

Výstup openMSX 18.0 je referencí testu `rtl/peripheral/VIDEO/VDP/tb/run_vdp_cmd.sh`
(`cmdbench_openmsx.txt`).
