# CreateKeyMap: tabulky kláves

[English](README.md) | **Česky**

Zpět na [nástroje](../README.cs.md) | [hlavní Readme](../../Readme.md).

## Účel

Jádro překládá klávesnici PS/2 (tak, jak ji doručí MiSTer) na klávesnicovou matici MSX pomocí
512bajtové tabulky. Tento nástroj tyto tabulky staví z čitelných souborů JSON. Je to nástroj pro
vývojáře: uživatel ho nepotřebuje, protože tabulky jsou už zabalené v balíčcích strojů.

Tabulka se indexuje kódem klávesy z MiSTeru `ps2_key[8:0]` (bit 8 = klávesa s prefixem E0).
Hodnota je jeden bajt: horní půlbajt je řádek matice MSX, dolní půlbajt je číslo bitu sloupce.
`0xFF` znamená žádná klávesa.

## Požadavky

- Python 3, jen standardní knihovna (`createKeyMap.py`).
- Spouštěj z této složky (`tools/CreateKeyMap`): `map/` a `keyboard/` čte relativní cestou
  a soubory `.bin` zapisuje do aktuálního adresáře.

## Použití

```
cd tools/CreateKeyMap
python createKeyMap.py
```

Nemá žádné volby. Pro každý `map/**/*.json` zapíše `key_map_<name>.bin` (512 bajtů, předvyplněno
`FF`). Vždy přepíše všechny; při opakovaném spuštění nad nezměněnými vstupy vyjdou soubory
bajt po bajtu stejné.

Hlášky:

| Hláška | Význam |
|---|---|
| `<name>` | zpracovávaná mapa |
| `Nenalezen <key>` („nenalezen“) | klávesa přiřazená v mapě není v `keyboard/ps2.json`; ignoruje se |
| `Klavesa nema scancode <key>` | klávesa v `ps2.json` je, ale má prázdný scancode |

## Soubory

| Soubor | Role |
|---|---|
| `createKeyMap.py` | generátor |
| `keyboard/ps2.json` | jméno klávesy → řetězec se scancodem PS/2 set 2, `"0xNN"`. Klávesy s prefixem E0 jsou `0x1NN` (například GRAPH = pravý Alt `0x111`, STOP `0x17c`, HOME `0x16c`, kurzory `0x16b`/`0x175`/`0x172`/`0x174`, INS `0x170`, DEL `0x171`). CODE = F10 (`0x09`), SELECT = F11 (`0x78`). |
| `map/eu.json`, `map/us.json`, `map/International.json` | blok komentářů s maticí a objekt `"assign"`: jméno klávesy → `"0xRC"` (řádek R, bit sloupce C) nebo `null` |
| `key_map_eu.bin`, `key_map_us.bin`, `key_map_International.bin` | vygenerované tabulky |
| `matrix.yaml` | nepoužívá ho žádný skript |
| `ps2map.py` | pomůcka, viz níže |
| `scancode_debugger.py` | pomůcka, viz níže |

`map/eu.json` popisuje standardní mezinárodní matici MSX (řádky 0–10). Jeho blok komentářů je
referenční tabulka matice.

## Jak se mapy dostanou do balíčků strojů

1. `createKeyMap.py` zapíše `key_map_<name>.bin`.
2. `.bin` se zakóduje jako base64 a vloží do prvku `<kbd_layout>` v XML stroje
   (`tools/CreateMSXpack/Computer/<Vendor>/<Machine>.xml`).
3. `createComp.py` ho dekóduje a zapíše do balíčku stroje jako záznam KEYBOARD_LAYOUT
   (hlavička záznamu a za ní 512 bajtů).
4. Při nahrání balíčku jádro tabulku zkopíruje do RAM klávesnice.

Soubory `.bin` se tedy **na SD kartu nekopírují**. Všechna XML strojů dnes obsahují
`key_map_eu.bin`. Po změně tabulky musíš aktualizovat `<kbd_layout>` a znovu postavit balíčky.

## Přidání nového rozložení klávesnice

1. Zkopíruj `map/eu.json` do `map/<name>.json`.
2. Uprav objekt `"assign"`. Jméno klávesy (levá strana) je klávesa PC z `keyboard/ps2.json`,
   hodnota je pozice v matici `"0xRC"` z tabulky v komentáři (R = řádek, C = číslo bitu sloupce).
   Na stejnou pozici matice může mířit víc kláves PC. Jedna klávesa PC dává právě jednu pozici:
   tabulka nezná stav Shiftu, takže nejde udělat, aby jedna klávesa PC dávala podle Shiftu různé
   klávesy MSX.
3. Není-li klávesa, kterou přiřazuješ, v `keyboard/ps2.json`, přidej ji tam (`"NAME": "0xNN"`,
   nebo `"0x1NN"` pro klávesu s prefixem E0). Klávesy chybějící v `ps2.json` se přeskočí
   s hláškou `Nenalezen <key>`.
4. Spusť `python createKeyMap.py`. Vznikne nový soubor `key_map_<name>.bin` (stávající se
   přepíšou také).
5. Zakóduj ho do base64 na jeden řádek, například `base64 -w0 key_map_<name>.bin`, nebo
   v Pythonu `base64.b64encode(open("key_map_<name>.bin", "rb").read()).decode()`.
6. Výsledek vlož do `<kbd_layout>` v XML stroje a znovu postav balíček pomocí `createComp.py`
   (viz [../CreateMSXpack](../CreateMSXpack/README.cs.md)).
7. Vyzkoušej na stroji; zkontroluj hlavně Shift, Ctrl, Graph, Code, kurzory a funkční klávesy.

## Pomocné skripty

- `ps2map.py`: jen definuje slovník `ps2set2` se scancody PS/2 set 2 a příznaky modifikátorů
  z MiSTeru. Nic ho neimportuje; je to podklad.
- `scancode_debugger.py`: interaktivní pomůcka, která vypisuje scancody PC stisknutých kláves.
  Potřebuje pip balíček `keyboard`. Má chyby (po shodě odkazuje na nedefinovanou proměnnou
  `scancode` a po prvním prvku slovníku skončí), takže ho ber jako zkušební nástroj, ne jako něco,
  na co se dá spolehnout.

## Známá omezení

- **Mapy `us` a `International` nemají klávesu SHIFT.** Jejich `assign` používá jméno `SHIFT`,
  ale `ps2.json` má jen `SHIFT_L` a `SHIFT_R`, takže se záznamy zahodí (scancody Shiftu zůstanou
  `FF`). `International` navíc ztratí `~ ^ : @` a `us` ztratí `~`. Tyto dvě mapy popisují jinou
  matici než `eu`; odkud pochází, nebylo ověřeno.
- **Numerická klávesnice (klávesy `NUM_*`) není namapovaná v žádné ze tří tabulek.**
- **Všechny stroje používají mapu `eu`.** Zbylé dvě nepoužívá žádné XML stroje.
- Jedna klávesa PC dává jednu pozici matice; překlad závislý na Shiftu neexistuje.
- `matrix.yaml` je nepoužitý (žádný skript YAML nečte) a má nestandardní seznam řádků; nepoužívej
  ho jako referenci, vezmi blok komentářů v `map/eu.json`.
