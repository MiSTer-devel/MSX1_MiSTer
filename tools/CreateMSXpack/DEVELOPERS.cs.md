# CreateMSXpack: příručka pro vývojáře

[English](DEVELOPERS.md) | **Česky**

Jak přidat model počítače, rozšiřující cartridge nebo nový mapper či zařízení. Pokyny pro uživatele (spuštění nástrojů, příprava ROM) jsou v [README.cs.md](README.cs.md). Zpět na [readme projektu](../../Readme.md).

Související: rozložení klávesnice [../CreateKeyMap/README.md](../CreateKeyMap/README.md), databáze mapperů [../CreateCRC/README.md](../CreateCRC/README.md).

## 1. Přehled a tok dat

```
Computer/**/*.xml  ─┐
ROM/ (by SHA1)      ├─ createComp.py ─> MSX/<Vendor>/<Machine>.msx   (header "MSx")  ─ Load ROM PACK ─┐
*.json tables      ─┘                                                                                 │
Extension/*.xml    ─┐                                                                                 ├─> rtl/memory_upload.sv
ROM/ (by SHA1)      ├─ createDev.py  ─> MSX/CART_FW_EN.msx / _JP.msx (header "MsX")  ─ Load FW PACK ──┤   (builds the slot map
*.json tables      ─┘                                                                                 │    and device config)
CreateCRC: vampier.db (CRC32 -> FW ID)                                          ─ Load DB MAPPERS ────┘
```

- `createComp.py` převádí XML počítače (`<msxConfig>`) na binární seznam 8bajtových záznamů (bloky, zařízení, rozložení klávesnice) následovaný daty ROM. Zavaděč jádra `memory_upload.sv` ho přečte a naplní své tabulky slotů, paměti a zařízení.
- `createDev.py` převádí `Extension/*.xml` (`<fwConfig>`) na tabulku konfigurací cartridgí indexovanou ID („FW ID“). Při naplnění slotu cartridge zavaděč vyhledá konfiguraci zvolené cartridge. U souboru ROM se vyhledá CRC32 v databázi mapperů a DB vrátí FW ID.
- `tools.py` obsahuje sdílené pomocné funkce: prohledání složky ROM podle SHA1, čtení čísel, načítání JSON a kódování parametrů zařízení.
- Tabulky JSON obsahují číselná ID. **Musí přesně odpovídat výčtům (enum) v RTL.**

| Tabulka JSON | Výčet v RTL (`rtl/package.sv`) | Obsah |
|---|---|---|
| `conf.json` | `conf_t` | typy záznamů (BLOCK 0, DEVICE 1, KEYBOARD_LAYOUT 2, CARTRIGE 3, END 7) |
| `block.json` | `block_t` | typy bloků 0-11 |
| `device.json` | `device_t` (5 bitů) | názvy zařízení 0-22 (MEM_MAPPER = `DEV_MSX2_RAM`, TMS99xx = `DEV_VDP_TMS`, V99xx = `DEV_VDP_V99xx`) |
| `mapper.json` | `mapper_typ_t` (6 bitů) | názvy mapperů 0-40 (psaní `GENRIC_16KB`/`GENRIC_8KB` je shodné s RTL) |
| `cart_device.json` | `cart_typ_t` | FW ID: 0-13 cartridge z nabídky, 20-57 mappery ROM vybírané podle DB |
| `deviceParams.json` | použití `io_device.param` v modulu každého zařízení | pojmenované parametry zařízení, viz oddíl 2.6 |

Všechny nástroje spouštějte zevnitř `tools/CreateMSXpack`: tabulky JSON a `ROM` (není-li `--rom-dir`), `Extension`, `MSX` se otevírají relativním názvem (`createDev.py` navíc používá dočasný `ROM.bin` v aktuální složce).

## 2. XML počítače (`Computer/<Vendor>/<Machine>.xml`)

Kořenový prvek `<msxConfig>`. Čísla mohou být desítková nebo hexadecimální s `0x` (jen v XML počítače; výjimku viz XML rozšíření).

### 2.1 Potomci kořene

| Prvek | Obsah | Význam |
|---|---|---|
| `<cpu>` | `Z80` nebo `R800` | bity 7:6 hlavičky. Počítače turbo R stále uvádějí `Z80`; R800 se za běhu přepíná zařízením S1990 |
| `<wait_count>` | 0-7 | čekací stavy M1 (bity 5:3 hlavičky). Všechny počítače používají `1` |
| `<cpu_frequency>` | 0, 1, 2 | 0 = 3,58, 1 = 5,39, 2 = 10,7 MHz. Všechny počítače používají `0` |
| `<device>` | název zařízení | I/O zařízení nejvyšší úrovně, viz 2.2 |
| `<kbd_layout>` | base64 | 512bajtová mapa kláves z [../CreateKeyMap/README.md](../CreateKeyMap/README.md), stane se záznamem KEYBOARD_LAYOUT. Každý současný počítač vkládá `key_map_eu.bin` |
| `<primary slot="0..3">` | strom slotů | primární slot, viz 2.3 |

Ostatní textové prvky v kořeni se uloží a ignorují (komentáře v XML zmiňují `type` a `video_standard`; nemají žádný účinek).

### 2.2 `<device>` nejvyšší úrovně

Text prvku je název z `device.json`; neznámý název vypíše `Device '<x>' nenalezeno` a záznam se přeskočí. Atributy:

| Atribut | Význam |
|---|---|
| `port`, `mask` | každý 8 bitů. Zařízení reaguje na přístup, když `(addr & mask) == port` |
| pojmenované parametry | kódují se přes `deviceParams.json` (oddíl 2.6): `MODE` (TMS99xx: PAL/NTSC), `VDP_ID` (V99xx: V9938/V9958), `system` (PSG: true = PSG počítače s porty pro joystick/klávesnici), `OCM` (PPI), `inverted` (RESET_STATUS) |
| `param` | surový 8bitový parametr pro zařízení **bez** záznamu v `deviceParams.json` (například KANJI: bit 0 = hangul, bit 1 = lascom) |
| `ROM_SHA1`, `rom_skip`, `rom_size` | vlastní ROM zařízení, připojená k záznamu (font KANJI). Když ROM chybí, celý počítač se přeskočí a jeho `.msx` se smaže |
| `shared_slot`, `shared_subslot`, `shared_block`, `shared_size` (všechny povinné společně), `shared_offset` (výchozí 0) | paměť zařízení je okno do existujícího bloku (KANJI v 1chipMSX používá blok ESE-RAM) |

Zařízení nejvyšší úrovně bez `shared_slot` se zapisují první, zařízení se `shared_slot` až za strom slotů. Zařízení se `shared_slot` proto smí odkazovat jen na bloky vytvořené stromem slotů.

### 2.3 Strom slotů

```xml
<primary slot="P" [expander="0|1"] [expander_wo="0|1"] [expander_init="0xNN"]>
   <secondary slot="S"> <block ...>...</block> ... </secondary>   <!-- S = 0..3 -->
   <!-- or directly: -->
   <block ...>...</block>
</primary>
```

- Nerozšířený slot má buď `<block>` přímo pod `<primary>`, nebo jeden `<secondary slot="0">`. Obojí dává podslot 0.
- **Expander (registr podslotů FFFFh) se zapne automaticky**, když je některý `<secondary slot>` větší než 0, nebo ho vynutí `expander="1"`. `expander_init` je hodnota FFFFh po resetu (1chipMSX používá `0x2B`). `expander_wo` se uloží, ale RTL ho zatím ignoruje.
- **Nemíchejte `<block>` a `<secondary>` v jednom `<primary>`**: zapíšou se jen přímé bloky.
- Sloty se zapisují v pořadí v XML. Externí sloty (`<cart>`) patří nakonec: blok `FLASH` (oddíl 3.2) rozšiřuje paměť přidělenou jako poslední a tou musí být ROM cartridge.
- Limity jádra: nejvýše 64 bloků (4 sloty x 4 podsloty x 4 stránky), 16 paměťových záznamů, 8 záznamů zařízení mapovaných do paměti.

### 2.4 `<block>`

Atributy: `start` (první 16kB stránka 0-3, výchozí 0) a `count` (počet stránek, výchozí 4, ořízne se na `4 - start`). Přijímá se i potomek `<count>`, ale žádný soubor ho nepoužívá; neuvádějte obojí.

Potomci, každý nejvýše jednou na blok (kromě `<device>`, který se smí opakovat, např. OPM + YM2148 v jednom bloku). Zapisují se v tomto pořadí: memory, shared_memory, mapper, cart, device, ref.

| Potomek | Atributy a obsah | Účinek |
|---|---|---|
| `<memory>ROM</memory>` | `SHA1` (malá hexadecimální písmena, povinný), `filename` (informativní, vypíše se ve zprávě „not found“), `skip` a `size` (bajty, desítkově nebo hexadecimálně, vyříznou úsek z dumpu), `exactFilename` (cesta, obchází hledání podle SHA1; podporováno, nepoužito) | blok ROM. V packu je doplněn FF na násobek 16 kB (ceil(size/16 kB) musí být nejvýše 255) |
| `<memory>RAM</memory>` | `size` (bajty, výchozí = stránky x 16 kB), `pattern` (výplň, výchozí 1) | blok RAM. 4 MB se kóduje jako 0. Vzory výplně: 1 = FF, 2 = 00, 3/4/5 = pruhy jako po zapnutí DRAM (0 = „data z DDR“, pro RAM nepoužívat). Počítače používají 1, 2, 3, 4 |
| `<shared_memory>` | text `ROM` = jen pro čtení, cokoli jiného čtení/zápis; `slot`, `subslot`, `block` (zdroj), `offset`, `size` (bajty) | okno do paměti jiného bloku. Zdrojový blok už musí v packu existovat. K `offset` viz úskalí v oddíle 6 |
| `<mapper>NAME</mapper>` | název z `mapper.json`; volitelný `param` 0-3 | záznam MAPPER. `param` používá jen `DRAM` (která 16kB stránka horních 64 kB RAM). Blok ROM bez mapperu je v jádře lineární (`MAPPER_OFFSET`) |
| `<cart>A</cart>` | `A`/`a`/`0` nebo `B`/`b`/`1` | označí blok jako slot cartridge A nebo B (záznam SLOT). Obvykle `<block start="0">` (všechny 4 stránky) |
| `<device>NAME</device>` | `port` + `mask` (přidá záznam IO_DEVICE; maska je FF, když je zadán jen `port`), pojmenované parametry nebo surový `param` | zařízení vázané na tento blok (zařízení mapované do paměti nebo zařízení s mapperem): `MEM_MAPPER`, `WD2793`, `TC8566AF`, `OPM`, `YM2148`, `SCC`, ... |
| `<ref to_block="n">DEVICE</ref>` nebo `MEMORY` | `to_block` 0-3 | `DEVICE`: tento blok také vybírá zařízení bloku `n` (registry FDC viditelné i ve stránce 2). `MEMORY`: zkopíruje paměť, mapper, parametr mapperu a offset bloku `n` |

`REF_*` odkazují na blok ve **stejném slotu a podslotu** a odkazovaný blok musí být první.

XML počítače nemůže deklarovat SRAM s baterií; `<sram>` se respektuje jen ve FW packu.

### 2.5 Pravidla pro FDC

- Jádro má **jednu pozici FDC** (a jeden TC8566AF). Druhý FDC na obsazené pozici vyvolá chybu OSD `FDC already in machine`.
- **Vnitřní FDC má přednost před FDC cartridge.** Má-li počítač FDC a uživatel zvolí FDC cartridge ve slotu A, zavaděč tiše zopakuje načtení bez cartridge A. Není to chyba.
- FDC jako cartridge ve slotu (`VY0010`) je možné **jen ve slotu A a s 1 mechanikou**. Ve slotu B, nebo když pozice FDC není v jádře sestavena, je chyba `Device not in this core build`.
- Limity počtu kopií zařízení (`MSX::N_*` v `rtl/package.sv`, počítá se přes počítač i obě cartridge): OPLL 2, OPM 1, SCC 2, PSG 1, DAC 2, LATCH_PORT 2, MEM_MAPPER 2, RESET_STATUS 1, OPL4 1, pozice FDC 1, TC8566AF 1; ostatní 1. Překročení limitu dá `Device not in this core build`.

### 2.6 Kódování parametrů zařízení (`deviceParams.json`)

U zařízení se záznamem každý pojmenovaný atribut přispívá bity a výsledky se sčítají operací OR. Parametr je buď `int` (hodnota, volitelně dělená `div`, kontrolovaná proti `min`/`max`, převedená přes `values`, posunutá o `value_offset`), nebo `enum` (index v `enums`). Hodnota mimo rozsah nebo neznámá vypíše varování a použije se `default`.

**Atribut, který chybí, přispívá 0, ne svou hodnotou `default`.**

| Zařízení | Parametr | Kódování | Používá |
|---|---|---|---|
| WD2793 | `fdd_count` 1/2 | bity 3:2 = 01 / 11 | povolení mechaniky |
| | `style` Philips/National/Sony | bity 1:0 = 0/1/2 | model FDC |
| | `single_sided` false/true | bit 4 | |
| | `density` MFM/FM | bit 5 | |
| TC8566AF | `fdd_count` | bity 3:2 | |
| | `ioRegs` ""/7FF2/7FF8 | bity 1:0 = 0/1/2 | model registrů |
| | `single_sided` | bit 4 | |
| MEM_MAPPER | `size` v bajtech, děleno 16384, 1..255 | počet segmentů; chybí = 0 = 256 segmentů (4 MB) | `msx2_ram.sv` |
| V99xx | `VDP_ID` V9938/V9958/UNKNOWN | hodnoty 0/2/1 | `v99.sv` |
| TMS99xx | `MODE` PAL/NTSC | 0/1 | `tms.sv` |
| PSG | `system` | bit 0 | `psg.sv` |
| PPI | `OCM` | bit 0 | `ppi.sv` |
| RESET_STATUS | `inverted` | bit 0 | `reset_status.sv` |
| OPL4 | `sampleram` v bajtech, děleno 131072, 0..16 | bity 4:0 | `opl4.sv` |
| YM2148 | `variant` SFG-01/SFG-05 | bit 0 | `ym2148.sv` |

Zařízení bez záznamu berou surový atribut `param` (8 bitů, výchozí 0).

### 2.7 Komentovaný minimální příklad

Odvozeno z `Computer/Philips/Philips_NMS_8245.xml`.

```xml
<?xml version="1.0" ?>
<msxConfig>
  <cpu>Z80</cpu>                         <!-- Z80 | R800 -->
  <wait_count>1</wait_count>             <!-- M1 wait states -->
  <cpu_frequency>0</cpu_frequency>       <!-- 0=3.58 1=5.39 2=10.7 MHz -->
  <!-- I/O devices of the machine: decoded when (port & mask) == port -->
  <device mask="0xFC" port="0x98" VDP_ID="V9938">V99xx</device>   <!-- MSX1: <device mask="0xFE" port="0x98" MODE="PAL">TMS99xx</device> -->
  <device mask="0xF8" port="0xA0" system="true">PSG</device>
  <device mask="0xF8" port="0xA8">PPI</device>
  <device mask="0xFE" port="0xB4">RTC</device>
  <kbd_layout>BASE64 OF key_map_eu.bin (684 chars)</kbd_layout>
  <primary slot="0">                     <!-- not expanded: one secondary slot 0 -->
    <secondary slot="0">
      <block start="0" count="2">        <!-- pages 0-1 = 0000h-7FFFh -->
        <memory SHA1="6103b39f1e38d1aa2d84b1c3219c44f1abb5436e" filename="nms8245_basic-bios2.rom">ROM</memory>
      </block>
    </secondary>
  </primary>
  <primary slot="3">                     <!-- secondaries > 0 => expander on -->
    <secondary slot="0">
      <block start="0" count="1">
        <memory SHA1="e7905d16d2ccd57a013c122dc432106cd59ef52c" filename="nms8245_msx2sub.rom">ROM</memory>
      </block>
    </secondary>
    <secondary slot="2">
      <block start="0">                  <!-- count defaults to 4 -->
        <memory size="131072" pattern="4">RAM</memory>
        <mapper>MSX2_RAM</mapper>
        <device mask="0xFC" port="0xFC" size="131072">MEM_MAPPER</device>
      </block>
    </secondary>
    <secondary slot="3">
      <block start="1" count="1">        <!-- disk ROM at 4000h + memory-mapped FDC -->
        <memory SHA1="c3f3ca454d66a0bc791f1d4b60e6857b44eb8755" filename="nms8245_disk.rom">ROM</memory>
        <device style="Philips" fdd_count="1">WD2793</device>
      </block>
      <block start="2" count="1">        <!-- FDC registers also in page 2 -->
        <ref to_block="1">DEVICE</ref>
      </block>
    </secondary>
  </primary>
  <!-- external slots last -->
  <primary slot="1"><secondary slot="0"><block start="0"><cart>A</cart></block></secondary></primary>
  <primary slot="2"><secondary slot="0"><block start="0"><cart>B</cart></block></secondary></primary>
</msxConfig>
```

Referenční soubory pro zvláštní funkce:

| Funkce | Soubor |
|---|---|
| přímý `<block>` pod `<primary>` + `expander="1"` | `Computer/Philips/Philips_VG_8020-19.xml` |
| výřezy ROM (`skip`/`size`), `param` mapperu `DRAM`, `PANASONIC`, `TURBO_R_FDC`, TC8566AF, KANJI přes `ROM_SHA1`, zařízení turbo R | `Computer/Panasonic/Panasonic_FS-A1ST.xml` |
| `shared_memory`, zařízení se `shared_*`, `expander_init`, zařízení OCM, mapper 4 MB | `Computer/OCM/1chipMSX.xml` |
| dvě zařízení v jednom bloku (OPM + YM2148) | `Computer/Yamaha/Yamaha_CX5MII_128.xml` |
| `ref MEMORY`, mapper `NATIONAL` | `Computer/National/National_FS-4600F.xml` |

## 3. XML rozšíření (`Extension/CART_FW_EN.xml`, `CART_FW_JP.xml`)

Kořen `<fwConfig>`, potomci `<fw name="X">`. `X` musí být klíčem v `cart_device.json`, jinak se přeskočí (`FW name: X SKIP. Not in cart_device.json`). Oba soubory se liší jen SHA1 ROM FM-PAC, takže **každá změna se dělá v obou souborech**.

### 3.1 Potomci `<fw>`

| Potomek | Význam |
|---|---|
| `<block [start] [count] [offset] [fix_offset]>` | konfigurace podslotu 0. `start` výchozí 0, `count` výchozí 4. `offset` 0-3 dá jako parametr mapperu `0x80\|offset` (pro mapper `OFFSET`: `0x0000`, `0x4000`, `0x8000`, `Synthesizer`). `fix_offset` 0-3 dá `0xC0\|n` (pro `MIRROR`) |
| `<secondary slot="n"><block>...</block></secondary>` | podslot n cartridge (MegaFlashROM SCC+ SD používá 0-3) |
| `<expander>` | záznam expanderu pro slot cartridge; text `expander_wo` nastaví příznak jen pro zápis |
| `<io_device>` | přijímá se a ignoruje |

**V XML rozšíření se čísla čtou funkcí `int()`: hexadecimální hodnoty se nepřijímají.**

### 3.2 Potomci `<block>`

| Potomek | Význam |
|---|---|
| `<SHA1 [skip] [size]>sha1</SHA1>` | ROM bloku ze složky ROM (skip/size desítkově) |
| `<filename>` | informativní |
| `<mapper>` | název z `mapper.json` |
| `<device [port] [mask] [param] [named params] [memory="block"]>NAME</device>` | zařízení. Pojmenované parametry se kódují přes `deviceParams.json`. `memory="block"` znamená, že zařízení používá paměť bloku (vlnová ROM/RAM OPL4). Chybějící paměť bloku dá v jádře `NOT FW CONF` |
| `<ram>bytes</ram>` | RAM, vzor FF |
| `<sram>bytes</sram>` | SRAM s baterií, ukládá se v jednotkách 1 kB (sloty A a B mají oddělené oblasti SRAM) |
| `<flash>bytes</flash>` | paměť je flash čip této velikosti: načtená ROM, zbytek FF (ASCII16-X, 8 MB) |
| `<extend>bytes</extend>` | stejný záznam, s významem „RAM za ROM“ (MoonSound: 2 MB ROM + 2 MB sample RAM = 4 MB) |
| `<device_param>` | načte se, ale nepoužije |

Neznámé značky se zalogují a přeskočí. Záznamy se pro blok generují v pořadí: ROM, FLASH, RAM, MAPPER, DEVICE (+ IO_DEVICE při `port`), SRAM. Velikost `<flash>`/`<extend>` musí být pod 0x2000 x 16 kB. `FLASH` rozšiřuje jen paměť alokovanou jako poslední (ROM cartridge).

### 3.3 Jak se cartridge z nabídky mapují na FW ID

Hodnota položky OSD se převede na `cart_typ_t` v `rtl/msx_config.sv` a zavaděč načte FW konfiguraci, jejíž číslo je tato hodnota výčtu. **U cartridgí z nabídky se FW ID rovná hodnotě `cart_typ_t`** (`rtl/package.sv`).

| Nabídka slotu A | Nabídka slotu B | `cart_typ_t` = FW ID | Název v `cart_device.json` |
|---|---|---|---|
| ROM | ROM | 11 `CART_TYP_ROM` | žádný (přes DB, ID 20-57) |
| FDC | není k dispozici | 5 | `VY0010` |
| SCC | SCC | 0 | `SCC` |
| SCC+ | SCC+ | 1 | `SCC+` |
| FM-PAC | FM-PAC | 2 | `FM_PAC` |
| MegaSCC+ 1MB | není k dispozici | 6 | `MEGASCC1` |
| MegaFlashROM SCC+ SD | není k dispozici | 3 | `MEGA_FLASH_ROM` |
| GameMaster2 | není k dispozici | 4 | `GM2` |
| není k dispozici | MegaSCC+ 2MB | 7 | `MEGASCC2` |
| není k dispozici | MegaRAM ASCII-8K 1MB | 8 | `MEGAASCII8` |
| není k dispozici | MegaRAM ASCII-16K 2MB | 9 | `MEGAASCII16` |
| Empty | Empty | 12 | žádný (prázdná konfigurace) |
| MoonSound | MoonSound | 13 | `MOONSOUND` |
| není v nabídce | není v nabídce | 10 | `MEGARAM` (žádná položka nabídky ho nepoužívá; 1chipMSX používá mapper MEGARAM přímo ve svém XML) |

- `CART_TYP_ROM` (11) je zvláštní: zavaděč spočítá CRC32 načtené ROM a zeptá se DB. Záznam DB dá FW ID (20-57). ROM o velikosti nejvýše 64 kB, která v DB není, běží jako prostá ROM s FW ID 20/21/22 zvoleným podle hlavičky `AB`.
- `CART_TYP_EMPTY` (12) nemá záznam `<fw>`; jeho položka v tabulce míří na prázdnou konfiguraci. Proto i prázdný slot potřebuje FW pack.
- **Volná FW ID**: 14 a 15 pro nové cartridge z nabídky (`cart_typ_t` i pole stavu mají 4 bity). Pro mappery z DB: 24, 37-48 kromě 40-42 a 58 výše.
- Text nabídky: `CONF_STR_SLOT_A` / `CONF_STR_SLOT_B` v `rtl/msx_config.sv`.

## 4. Postupy

### 4.1 Nový model počítače (bez nového hardwaru)

1. Zkopírujte nejbližší XML v `Computer/<Vendor>/`. Referencí, kterou stávající soubory sledují, je openMSX `share/machines/<name>.xml`.
2. Vyplňte zařízení, strom slotů a SHA1 ROM (`sha1sum` dumpů). Do `<kbd_layout>` vložte mapu kláves (base64 souboru `.bin` z CreateKeyMap).
3. Dodržte limity jádra z 2.3 a 2.5.
4. Sestavte jen tento počítač a sledujte konzoli:
   ```
   python createComp.py --xml-dir Computer/<Vendor> --output-dir <dir> --debug
   ```
   Nesmí se objevit žádný řádek `ROM SHA1 not found`. `--debug` vypíše každý záznam (`DEVIC:`, `BLOCK:` se slotem/podslotem/stránkou).
5. Otestujte (oddíl 8).

### 4.2 Nová cartridge v nabídce

1. `cart_device.json`: přidejte název s ID 14 nebo 15 (musí se rovnat nové hodnotě `cart_typ_t`).
2. Přidejte `<fw name="...">` do **obou** souborů `CART_FW_EN.xml` a `CART_FW_JP.xml`.
3. RTL: přidejte hodnotu do `cart_typ_t` (`rtl/package.sv`) na tu pozici. V `rtl/msx_config.sv` přidejte text nabídky do `CONF_STR_SLOT_A` / `_B` a řádky `case`. Pole stavu mají 4 bity: nejvýše 16 položek.
4. Znovu sestavte FW pack (`python createDev.py`) a zkopírujte ho na SD kartu.
5. Pokud cartridge potřebuje nový mapper, zařízení nebo typ bloku, viz 4.4.

### 4.3 Nový mapper ROM vybíraný podle DB

1. Dejte FW konfiguraci volné ID (24, 37-48 kromě 40-42, 58+) v `cart_device.json` a přidejte `<fw>` do obou XML rozšíření.
2. V `../CreateCRC/romtypes.json` přidejte do `types` jeden řádek `"TypROM": "název fw"`. `TypROM` je název z tabulky „Not supported“ v `../CreateCRC/report.md`; FW ID se vezme z `cart_device.json`.
3. Znovu sestavte FW pack a `vampier.db` (viz [../CreateCRC/README.cs.md](../CreateCRC/README.cs.md)).
4. Pokud je samotný mapper nový hardware, viz 4.4.

`createDB.py` zapisuje jen typy, jejichž konfigurace FW existuje, takže ROM nikdy nedostane prázdnou konfiguraci. Jeho report vypíše nepodporované typy s počty, z nichž je vidět, který mapper stojí za to přidat.

### 4.4 Nové zařízení, mapper nebo typ bloku (místa v RTL)

- **Zařízení**: přidejte název do `device.json` a do `device_t` (`rtl/package.sv`, na stejnou pozici, 5 bitů, nejvýše 31); volitelně záznam v `deviceParams.json`; modul v `rtl/msx/devices/` (uvedený v jeho `files.qip`); instanci v `rtl/msx/devices.sv` s `io_device[DEV_X]` (příkladem je OPL4). U zařízení, které může existovat ve více kopiích, přidejte `N_X` a větev `dev_slots()` v `rtl/package.sv`. Zvuková zařízení je nutné přidat i do zvukového mixu.
- **Mapper**: přidejte do `mapper.json` a do `mapper_typ_t` (vložit před `MAPPER_UNUSED` a držet číslování shodné s JSON); modul v `rtl/msx/msx_slots/mappers/` a jeho `files.qip`; instanci v `rtl/msx/msx_slots/mappers.sv` vybíranou podle `block_info.typ == MAPPER_X` (viz `ascii16x.sv`).
- **Typ bloku nebo záznamu**: přidejte do `block.json` / `conf.json` a do `block_t` / `conf_t` a ošetřete ho v `memory_upload.sv` (`STATE_PROCESS_BLOCK` / `STATE_LOAD_CONF`). Jinak jádro ohlásí `NOT SUPPORTED BLOCK` / `NOT SUPPORTED CONF`.
- Kód musí projít Quartusem 17 (pozor na 32bitové literály v typovaných výrazech, přiřazení zabaleného pole do nezabaleného a size casty).

## 5. Binární formát packů (stručně)

### 5.1 Pack počítače (`MSx`)

- Hlavička, 8 bajtů: `'M' 'S' 'x' conf 0 0 0 0`, kde `conf = cpu<<6 | (wait_count & 7)<<3 | (cpu_frequency & 7)`.
- Záznamy mají 8 bajtů, první bajt je typ záznamu. Pořadí: zařízení nejvyšší úrovně bez `shared_slot`, všechny sloty `<primary>` v pořadí v XML, zařízení nejvyšší úrovně se `shared_slot`, rozložení klávesnice. Záznam END neexistuje: pack končí koncem souboru.
- Záznam BLOCK: `00 addr type p0 p1 p2 p3 p4`, kde `addr = slot<<6 | subslot<<4 | start_page<<2 | (count-1)`.
- Záznam DEVICE (nejvyšší úroveň): `01 dev_id port mask param size16k shared_ref shared_off`. Pokud je `size16k` > 0 a není `shared_ref`, následují data ROM. `shared_ref = 0x80 | slot<<4 | subslot<<2 | block`.
- KEYBOARD_LAYOUT: `02 00 00 00 00 00 00 00` následovaný 512bajtovou tabulkou.

| Typ bloku | Název | Parametry (createComp) |
|---|---|---|
| 0 | RAM | p0 = velikost/16 kB (0 = 256 = 4 MB), p1 = vzor výplně |
| 1 | ROM | p0 = ceil(velikost/16 kB); následují data |
| 2 | SRAM | jen FW pack |
| 3 | DEVICE | p0 = id zařízení, p1 = param |
| 4 | MAPPER | p0 = id mapperu, p1 = (param&3)<<2 |
| 5 | SLOT (cartridge) | p0 = 0 (A) / 1 (B) |
| 6 | REF_MEM | p0 = to_block |
| 7 | REF_DEV | p0 = to_block |
| 8 | IO_DEVICE | p0 = port, p1 = mask, p2 = param |
| 9 | EXPANDER | addr = pouze slot<<6; p0 = wo<<1 \| enable, p1 = počáteční hodnota FFFFh |
| 10 | SHARED_MEM | p0 = slot<<4\|subslot<<2\|block, p1 = offset/16 kB, p2 = velikost/16 kB, p3 = ro |
| 11 | FLASH | jen FW pack; rozšíří poslední paměť na N x 16 kB |

### 5.2 FW pack (`MsX`)

- 16bajtová hlavička: `'M' 's' 'X' 00`, uint32 LE s offsetem tabulky ROM v souboru, 8 nulových bajtů.
- Na 0x10: 256 x uint32 LE offset konfigurace N v souboru (N = FW ID). Nepoužitá ID míří na prázdnou konfiguraci (jediný záznam END).
- Konfigurace je seznam 6bajtových záznamů `type addr block_type p1 p2 p3` zakončený `07 00 00 00 00 00`. Bity slotu v `addr` jsou 0, slot cartridge doplní jádro operací OR.
- Tabulka ROM je uint32 LE offset pro každou odlišnou ROM (deduplikace podle skip, size a SHA1), následují obrazy ROM doplněné FF na 16 kB.

## 6. Úskalí

1. **Chybějící pojmenovaný parametr se kóduje jako 0**, ne jako jeho `default` (např. WD2793 bez `fdd_count` nedá žádné bity povolení mechaniky).
2. **MEM_MAPPER `size` 4 MB: atribut vynechte.** `size="4194304"` dá 256 segmentů, což je nad maximem 255, takže se vypíše varování a použije se výchozí hodnota (1 segment, 16 kB). Chybějící znamená 256 segmentů.
3. **`shared_memory offset="0"` jádro dekóduje jako 4 MB.** Offset 0 nepoužívejte.
4. **Atribut `variant` u OPM nemá žádný účinek** (OPM nemá záznam v `deviceParams.json` a modul `param` ignoruje). `variant` u YM2148 (`SFG-01`/`SFG-05`) funguje.
5. **V XML rozšíření dostane zařízení s `port` surový `param`**, ne zakódované pojmenované parametry (záznam IO_DEVICE se zapíše se surovým atributem a v jádře přepíše param zařízení DEVICE). Spoléhá na to MegaFlashROM SCC+ SD: MEM_MAPPER `param="32"` = 32 x 16 kB = 512 kB. createComp naproti tomu zapisuje do IO_DEVICE zakódovanou hodnotu.
6. Hexadecimální čísla fungují v XML počítače, ale **ne v XML rozšíření**.
7. Nemíchejte `<block>` a `<secondary>` v jednom `<primary>`.
8. SHA1 v XML musí být malými hexadecimálními písmeny.
9. Pack se zapíše i při chybějících ROM; smaže se jen při chybějící ROM `ROM_SHA1` zařízení nejvyšší úrovně. Kontrolujte konzoli.
10. `<sram>` funguje jen ve FW konfiguracích; XML počítače nemůže deklarovat SRAM.
11. `expander_wo` se uloží, ale RTL ho ignoruje.
12. Nástroje spouštějte zevnitř `tools/CreateMSXpack` (tabulky JSON podle relativního názvu). Složka s ROM může být jinde: `--rom-dir` v obou nástrojích.
13. Obě XML rozšíření se musí upravovat společně.

## 7. Zprávy v konzoli

Úplná tabulka zpráv a chyb OSD s významem je v [README](README.cs.md#řešení-potíží). Doplňky důležité pro vývojáře:

| Zpráva | Kde | Význam |
|---|---|---|
| `Missing SHA1 for ROM in slot s/ss` | createComp | `<memory>ROM</memory>` bez `SHA1` i bez `exactFilename` |
| `Error, block contain multiple count` | createComp | zadán atribut `count` i potomek `<count>` |
| `Processing unknown element: <tag>` | createComp | neznámý potomek `<primary>` |
| `Error: missing attribut ... in shared_memory` | createComp | zbytek toho slotu se zahodí |
| `Device 'X' parameter 'p' value v ... setting to default` | tools.py | chybný pojmenovaný parametr, použit default |
| `Unknown mapper type`, `Unknown device type`, `Tag name: X SKIP` | createDev | název není v tabulkách JSON, nebo neznámá značka |

## 8. Testování

1. Sestavte a přečtěte konzoli (oddíl 4.1). Žádné `ROM SHA1 not found`.
2. Na MiSTeru: Load FW PACK, Load ROM PACK. Sledujte chyby OSD (README, „Chyby OSD v jádře“).
3. Simulace (Verilator běží ve WSL; cesty tam jsou `/mnt/c/...`):
   - Zavedení počítače: `wsl.exe -- bash rtl/tb/run_machine_boot.sh <machine.msx> <image.dsk|none> [expected text]`. Plusargs, předávané v `SIMARGS`: `+run_ms=`, `+fw=<FW pack>`, `+db=`, `+rom=<cart ROM>`, `+slota=`, `+slotb=`, `+key=`, `+vram_dump=`. Pomocník pro obraz disku: `rtl/tb/make_dsk_image.py`.
   - Regrese zavaděče: `rtl/tb/run_mu_equiv.sh <packs dir> <CART_FW.msx> <ROM set dir>`, `run_memory_upload.sh` (OCM), `run_cart_rom.sh <VG_8020 pack> <CART_FW_EN.msx>`, `run_mu_restart.sh`, `run_ocm_boot.sh`.
   - `run_mu_equiv.sh` porovnává zavaděč s referenční revizí; spusťte ho po každé změně `memory_upload.sv` nebo formátu packu.
4. Syntéza v Quartusu se spouští zvlášť; její výsledek nebyl součástí těchto nástrojů.
