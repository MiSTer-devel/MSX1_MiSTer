# Nástroje

[English](README.md) | **Česky**

Pomocné nástroje jádra MSX pro MiSTer. Zpět na [hlavní Readme](../Readme.md).

| Nástroj | K čemu je | Kdo ho potřebuje |
|---|---|---|
| [CreateMSXpack](CreateMSXpack/README.cs.md) | Vyrobí balíčky strojů a FW pack | uživatelé i vývojáři |
| [CreateCRC](CreateCRC/README.cs.md) | Vyrobí databázi mapperů pro ROM cartridge | vývojáři (uživatelé si vezmou hotový `vampier.db`) |
| [CreateKeyMap](CreateKeyMap/README.cs.md) | Vyrobí tabulky PS/2 → klávesnicová matice MSX | vývojáři |
| [vdptest](vdptest/README.cs.md) | Testovací ROM pro časování VDP | vývojáři a testeři |

## Rychlý start pro uživatele

Na SD kartu do `/media/fat/games/MSX1/` zkopíruj tyto soubory:

| Soubor | Povinný? | Vyrobí | Položka OSD |
|---|---|---|---|
| balíček stroje `.msx` (jeden na stroj, např. `<Vendor>/<Machine>.msx`) | ano, aspoň jeden | `createComp.py` z [CreateMSXpack](CreateMSXpack/README.cs.md) | Load ROM PACK |
| FW pack `CART_FW_EN.msx` nebo `CART_FW_JP.msx` (liší se jen ROM FM-PAC) | prakticky ano: bez něj nefungují sloty pro cartridge, ani „Empty“ | `createDev.py` z [CreateMSXpack](CreateMSXpack/README.cs.md) | Load FW  PACK |
| databáze mapperů `vampier.db` | nepovinná; potřeba pro ROM cartridge větší než 64 kB | hotová v `CreateCRC/vampier.db`, nic se nestaví | Load DB MAPPERS |

Postup:
1. Nainstaluj Python 3.
2. Dumpy BIOS/firmware ROM dej do `tools/CreateMSXpack/ROM/` (musíš si je obstarat sám;
   v repozitáři jsou jen ROM C-BIOS).
3. V `tools/CreateMSXpack` spusť `python createComp.py` a `python createDev.py`; balíčky vzniknou
   v `MSX/`. Podrobnosti a význam hlášek na konzoli jsou v
   [README CreateMSXpack](CreateMSXpack/README.cs.md).
4. Obsah `MSX/` a `tools/CreateCRC/vampier.db` zkopíruj do `/media/fat/games/MSX1/`.
5. V OSD nahraj FW pack, databázi (nepovinně) a balíček stroje.

ROM her (`*.rom`) se nahrávají přímo z SD karty v OSD (slot 1/slot 2 = ROM); žádný nástroj je
nevyrábí. Tabulky kláves se na SD kartu nekopírují: jsou zabalené v balíčcích strojů.

## Nástroje

### CreateMSXpack

Převede definice strojů (`Computer/**/*.xml`) a tvoje obrazy BIOS ROM na balíčky strojů `.msx`
a definice cartridge (`Extension/*.xml`) na FW pack. ROM se hledají podle SHA1 obsahu souboru,
ne podle jména.

Spuštění (v `tools/CreateMSXpack`): `python createComp.py` a `python createDev.py`.
Dokumentace: [README](CreateMSXpack/README.cs.md) | [README (EN)](CreateMSXpack/README.md).

### CreateCRC

Vyrobí tabulku CRC32 → mapper (`vampier.db`), podle které jádro vybírá mapper ROM cartridge.
Uživatel ji stavět nemusí. Hodí se, když ROM v databázi chybí nebo potřebuje jiný mapper.

Spuštění (v `tools/CreateCRC`): `python createDB.py` (potřebuje internet).
Dokumentace: [README](CreateCRC/README.cs.md) | [README (EN)](CreateCRC/README.md).

### CreateKeyMap

Vyrobí 512bajtové tabulky, které překládají scancody PS/2 na klávesnicovou matici MSX. Vkládají
se do XML strojů; všechny stroje dnes používají tabulku `eu`.

Spuštění (v `tools/CreateKeyMap`): `python createKeyMap.py`.
Dokumentace: [README](CreateKeyMap/README.cs.md) | [README (EN)](CreateKeyMap/README.md).

### vdptest

Testovací ROM (`vdptest.rom`, `vdptest_auto.rom`, `cmdbench.rom`), které měří časování VDP:
stavové příznaky, přerušení a dobu příkazů na TMS9918A/28A/29A, V9938 a V9958. ROM jsou přeložené
a leží v repozitáři, stačí je nahrát jako ROM hry do slotu A.

Spuštění: `sh tools/vdptest/build.sh` (jen pro nový překlad).
Dokumentace: [README](vdptest/README.cs.md) | [README (EN)](vdptest/README.md).

## Pro vývojáře

- **Nový model stroje nebo rozšiřující cartridge:** viz
  [CreateMSXpack/DEVELOPERS.cs.md](CreateMSXpack/DEVELOPERS.cs.md)
  ([English](CreateMSXpack/DEVELOPERS.md)).
- **Nové rozložení klávesnice:** [CreateKeyMap](CreateKeyMap/README.cs.md).
- **Mapper konkrétní ROM (přepis) nebo nové jméno mapperu:** [CreateCRC](CreateCRC/README.cs.md).
- **Kontrola časování VDP:** [vdptest](vdptest/README.cs.md).

Pythonové skripty používají jen standardní knihovnu, kromě ladicí pomůcky
`CreateKeyMap/scancode_debugger.py` (potřebuje balíček `keyboard`). Skripty se musí spouštět
z vlastní složky, protože datové soubory otevírají relativním jménem.
