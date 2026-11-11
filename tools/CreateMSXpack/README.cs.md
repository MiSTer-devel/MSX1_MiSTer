# CreateMSXpack

[English](README.md) | **Česky**

Nástroje, které vytvářejí konfigurační soubory („packy“) potřebné ke spuštění jádra MSX. Zpět na [readme projektu](../../Readme.md).

## Co vytváří a proč

Jádro nemá vestavěný žádný počítač ani firmware cartridgí. Vše se za běhu načítá ze souborů na SD kartě:

| Nástroj | Výstup | Co to je | Položka OSD |
|---|---|---|---|
| `createComp.py` | `MSX/<Vendor>/<Machine>.msx` (jeden na počítač) | **Pack počítače**: rozložení slotů, RAM, I/O zařízení, rozložení klávesnice a BIOS ROM daného počítače | **Load ROM PACK** |
| `createDev.py` | `MSX/CART_FW_EN.msx` a `MSX/CART_FW_JP.msx` | **FW pack (rozšíření)**: konfigurace všech cartridgí z nabídky OSD (SCC, SCC+, FM-PAC, FDC, MegaFlashROM SCC+ SD, MoonSound, ...) a každého typu mapperu ROM, plus firmwarové ROM, které potřebují | **Load FW PACK** |

BIOS ROM jsou chráněné autorským právem a **nejsou součástí repozitáře**. Vlastní dumpy dodáte vy, nástroje je zabalí do výše uvedených souborů. Bez dalšího fungují jen open-source počítače C-BIOS a zaváděcí ROM 1chipMSX.

Potřebujete pack počítače a prakticky vždy i FW pack (potřebuje ho i prázdný slot cartridge).

## Požadavky

- Python 3 (ověřeno s 3.10).
- Žádné balíčky k instalaci: nástroje používají jen standardní knihovnu Pythonu (žádné `pip install`).

## Příprava dumpů ROM

1. Dumpy ROM vložte do `tools/CreateMSXpack/ROM/`, nebo je mějte kdekoli jinde a složku předejte volbou `--rom-dir` (oba nástroje, viz [Sestavení packů](#sestavení-packů)). Podsložky jsou v pořádku, složka se prohledává rekurzivně.
2. Názvy souborů ani přípony nejsou důležité. **ROM se rozpoznávají podle SHA1 celého souboru.** Potřebujete přesně ten dump, který nástroj očekává (stejné dumpy, jaké používá openMSX jako systémové ROM).
3. Které ROM jsou potřeba pro který počítač, je v [příloze A](#appendix-a-rom-images-per-machine) a v [tabulce firmwarových ROM](#firmware-roms-for-the-fw-pack) níže. Chybějící ROM se jen oznámí, viz [Řešení potíží](#řešení-potíží).

Už přiložené jsou: ROM C-BIOS (`ROM/cbios/`) a IPL ROM pro 1chipMSX (`ROM/ocm/`). Počítač 1chipMSX (OCM) načítá svůj BIOS (`OCM-BIOS.DAT`) za běhu z SD karty, ne z packu.

Velká složka s ROM nástroje zpomaluje: každý soubor v ní se celý přečte a spočítá se jeho hash.

### Firmwarové ROM pro FW pack

Všechny jsou volitelné. Chybějící ROM vypne nebo rozbije jen příslušnou cartridge.

| Cartridge | Název souboru v XML | SHA1 |
|---|---|---|
| FM-PAC (`CART_FW_EN`) | FM_PAC_EN.ROM | `6996489fcec52934b8beed87643cc33d02ecc301` |
| FM-PAC (`CART_FW_JP`) | FM_PAC_EN.ROM | `9d789166e3caf28e4742fe933d962e99618c633d` |
| GameMaster2 | GM2.ROM | `5c00f9e3a48411e08fac89b1dfdd2a6e95853919` |
| FDC cartridge (VY0010) | VY0010.ROM | `8924e3e11eb1c8c1edcb7efa63c26d2bdc142473` |
| MoonSound | yrw801.rom | `32760893ce06dbe3930627755ba065cc3d8ec6ca` |
| MegaFlashROM SCC+ SD | mfrsd.ROM | `1621f623b834dc57cb2983f30b36bcc3ac56cafd` |

`CART_FW_EN.msx` a `CART_FW_JP.msx` se liší jen ROM FM-PAC. Použijte ten, který odpovídá vašemu dumpu FM-PAC.

<details>
<summary>Příloha A: obrazy ROM podle počítačů (seznam SHA1)</summary>

<a id="appendix-a-rom-images-per-machine"></a>

Názvy jsou ty, které používá openMSX. Čtyři počítače potřebují navíc ROM s fontem KANJI (označeno „KANJI font ROM“).

| SHA1 | Název(y) souboru v XML | Počítače |
|---|---|---|
| `829c00c3114f25b3dae5157c0a238b52a3ac37db` | avt_dpc-200_basic-bios1.rom, fc-200_basic-bios1.rom, vg8020_basic-bios1.rom | AVT_DPC-200, Goldstar_FC-200, Philips_VG_8020-00 |
| `5e094fca95ab8e91873ee372a3f1239b9a48a48d` | ax170_basic-bios1.rom | Al_Alamiah_AX170 |
| `0287b2ec897b9196788cd9f10c99e1487d7adbbb` | ax170_arabic.rom | Al_Alamiah_AX170 |
| `0340707c5de2310dcf5e569b7db4c6a6a5590cb7` | IC125.BIN | Al_Alamiah_AX230 |
| `620a209bdfdb65a22380031fce654bd1df61def2` | IC127.BIN | Al_Alamiah_AX230 |
| `2f997e8a57528518c82ab3693fdae243dbbcc508` | cbios_main_msx1.rom | MSX - C-BIOS |
| `9fbbe400dbaf186aeba42e170d9424b032412c42` | cbios_logo_msx1.rom | MSX - C-BIOS |
| `f929bd1d720b0ef7092c9add8accd0d56fc9c8a3` | cbios_main_msx2.rom | MSX2 - C-BIOS |
| `d4e5b98ce23573669fb44447582d656e390791c0` | cbios_logo_msx2.rom | MSX2 - C-BIOS |
| `2fcb40413e7d373f0f2dbdc815ce18746ddf3684` | cbios_sub.rom | MSX2 - C-BIOS |
| `302afb5d8be26c758309ca3df611ae69cced2821` | cx11_basic-bios1.rom, cx5f_basic-bios1.rom, mbh2bios.rom, mx-10_basic-bios1.rom, pv-16_basic-bios1.rom, pv-7_basic-bios1.rom, sony_hb201_basic-bios1.rom, v20bios.rom | Canon V-20, Casio_MX-10, Casio_PV-16, Casio_PV-7, Hitachi MB-H2, Sony_HB-201, Yamaha_CX11, Yamaha_CX5F |
| `8963fc041975f31dc2ab1019cfdd4967999de53e` | cx5m_basic-bios1.rom, v20ebios.u20 | Canon V-20E, Yamaha_CX5M |
| `d99eebded5db5fce1e072d08e642c0909bc7efdd` | v20fbios.rom | Canon V-20F |
| `d67be6d7d56d7229418f4e122f2ec27990db7d19` | v20gbios.rom | Canon V-20G |
| `9fb289ea5c11d497ee00703f64e82575d1c59923` | v20sbios.rom | Canon V-20S |
| `a7ed5fd940f4e3a33e676840c0a83ac7ee54d972` | mx-15_basic-bios1.rom | Casio_MX-15 |
| `affa3c5cd8db79a1450ad8a7f405a425b251653d` | cpc-300_basic-bios2.rom | Daewoo_CPC-300 |
| `47a9d9a24e4fc6f9467c6e7d61a02d45f5a753ef` | cpc-300_hangul.rom | Daewoo_CPC-300 |
| `fb51c505adfbc174df94289fa894ef969f5357bc` | cpc-300_msx2sub.rom | Daewoo_CPC-300 |
| `22d5f4e522250dc5eb17e15b68f4a51bb752cba1` | (KANJI font ROM, bez názvu souboru v XML) | Daewoo_CPC-400S |
| `75f5f0a5a2e8f0935f33bb3cf07b83dd3e5f3347` | CPC-40038, CPC-400S.U38 | Daewoo_CPC-400S |
| `6b640c1d8cbeda6ca7d6facd16a206b62e059eee` | CPC-400S.U44 | Daewoo_CPC-400S |
| `a08a940aa87313509e00bc5ac7494d53d8e03492` | cpc-51_basic-bios.rom | Daewoo_CPC-51_Zemix V |
| `171b587bd5a947a13f3114120b6e7baca3b57d78` | 800bios.rom, dpc-100_basic-bios1.rom, dpc-180_basic-bios1.rom, dpc-200_basic-bios1.rom, fc80bios.rom, fc80ubios.rom | Daewoo_DPC-100, Daewoo_DPC-180, Daewoo_DPC-200, Goldstar_FC-80, Goldstar_FC-80U, Goldstar_GFC-1080A, Samsung_SPC-800 |
| `4421fa2504cbce18f7c84b5ea97f04e017007f07` | dpc-100_hangul.rom, dpc-200_hangul.rom | Daewoo_DPC-100, Daewoo_DPC-180, Daewoo_DPC-200 |
| `d3af963e2529662eae63f04a2530454685a1989f` | daewoo_dpc-200fr_basic-bios1.rom | Daewoo_DPC-200E(FR) |
| `8e28899175aadf3bbd8c9ba63d3b82c2caa74709` | fc80han.rom | Goldstar_FC-80 |
| `58dbe73ae80c2c409e766c3ace730ecd7bec89d0` | fc80uhan.rom | Goldstar_FC-80U, Goldstar_GFC-1080A |
| `6b0be712b9c95c1e912252ab5703e1c0bc457d9e` | gfc1080bios.rom | Goldstar_GFC-1080 |
| `141b44212ba28e7d03e0b54126fedd9e0807dc42` | gfc1080han.rom | Goldstar_GFC-1080 |
| `a5581fa3ce10f90f15ba3dc53d57b02d6e4af172` | gfc1080pasocalc.rom | Goldstar_GFC-1080 |
| `d6720845928ee848cfa88a86accb067397685f02` | expert_ddplus_basic-bios1.rom | Gradiente_Expert_DD_Plus, Gradiente_Expert_GPC-1, Gradiente_Expert_Plus |
| `f1525de4e0b60a6687156c2a96f8a8b2044b6c56` | expert_ddplus_disk.rom | Gradiente_Expert_DD_Plus |
| `d4cea8c815f3eeabe0c6a1c845f902ec4318bf6b` | expert_plus_demo.rom | Gradiente_Expert_Plus |
| `ef3e010eb57e4476700a3bbff9d2119ab3acdf62` | expert_1.0_basic-bios1.rom | Gradiente_Expert_XP-800 |
| `e2140fa2e8e59090ecccf55b62323ea9dcc66d0b` | mbh2firm.rom | Hitachi MB-H2 |
| `5e872d5853698731a0ed22fb72dbcdfd59cd19c3` | (KANJI font ROM, bez názvu souboru v XML) | National_FS-4600F, Panasonic_FS-A1F |
| `0081ea0d25bc5cd8d70b60ad8cfdc7307812c0fd` | fs-4600f_basic-bios2.rom, fs-a1_basic-bios2.rom, hb-f1_basic-bios2.rom, hb-f5_basic-bios2.rom | National_FS-4600F, Panasonic_FS-A1, Sony_HB-F1, Sony_HB-F5 |
| `0fbd45ef3dd7bb82d4c31f1947884f411f1ca344` | fs-4600f_msx2sub.rom, fs-a1_msx2sub.rom, hb-f1xdmk2_msx2sub.rom | National_FS-4600F, Panasonic_FS-A1, Sony_HB-F1XDmk2 |
| `31292b9ca9fe7d1d8833530f44c0a5671bfefe4e` | fs-4600f_wordfont1.rom | National_FS-4600F |
| `3a9a942ed888dd641cddf8deada1879c454df3c6` | fs-4600f_kanjibasic.rom | National_FS-4600F |
| `02155fc25c9bd23e1654fe81c74486351e1ecc28` | fs-4600f_wordfont2.rom | National_FS-4600F |
| `005794c10a4237de3907ba4a44d436078d3c06c2` | fs-4600f_msxword.rom | National_FS-4600F |
| `073feb8bb645d935e099afaf61e6f04f52adee42` | fs-4600f_disk.rom | National_FS-4600F |
| `81966a221b25c2cf61fc1e5e65a0d76f1b2f8553` | ocm_iplrom.rom | 1chipMSX |
| `63098f27beac9eca6b39d837d2a552395df33fe1` | fs-a1_deskpac1.rom | Panasonic_FS-A1 |
| `7f5b76605e3d898cc4b5aacf1d7682b82fe84353` | fs-a1_deskpac2.rom | Panasonic_FS-A1 |
| `9a62d7a5ccda974261f7c0600476d85e10deb99b` | DA1024D0365R.rom | Panasonic_FS-A1F |
| `5aff2d9b6efc723bc395b0f96f0adfa83cc54a49` | (KANJI font ROM, bez názvu souboru v XML) | Panasonic_FS-A1ST |
| `c212b11fda13f83dafed688c54d098e7e47ab225` | fs-a1st_firmware.rom | Panasonic_FS-A1ST |
| `21329398c0f350e330b353f45f21aa7ba338fc8d` | nms801_basic-bios1.rom | Philips_NMS_801 |
| `e761e7081c613ad4893a664334ce105841d0e80e` | NMS8220SystemROM.bin | Philips_NMS_8220 |
| `5df95d033ae70b107697b69470126ce1b7ae9eb5` | nms8220_designer.rom | Philips_NMS_8220 |
| `6103b39f1e38d1aa2d84b1c3219c44f1abb5436e` | nms8220_basic-bios2.rom, nms8245_basic-bios2.rom, nms8250_basic-bios2.rom | Philips_NMS_8245, Philips_NMS_8250, Philips_NMS_8255, Philips_VG_8235-20 |
| `e7905d16d2ccd57a013c122dc432106cd59ef52c` | nms8245_msx2sub.rom | Philips_NMS_8245 |
| `c3f3ca454d66a0bc791f1d4b60e6857b44eb8755` | nms8245_disk.rom | Philips_NMS_8245 |
| `ee0d8ccfc247368078d27183c34b3a5c0f4ae0f1` | nms8250-16_basic-bios2.rom | Philips_NMS_8250-16 |
| `b83770cca8453a153d7e260070a3a3c059d64ed3` | nms8250-16_msx2sub.rom | Philips_NMS_8250-16 |
| `c3efedda7ab947a06d9345f7b8261076fa7ceeef` | nms8250_disk.rom | Philips_NMS_8250-16, Philips_NMS_8250-19 |
| `d18694e9e7040b2851fe985cefb89766868a2fd3` | nms8250-19_basic-bios2.rom | Philips_NMS_8250-19 |
| `fd4bcc81a8160a1dea06036c5f79d200f948f4d6` | nms8250-19_msx2sub.rom | Philips_NMS_8250-19, Philips_VG_8235-39 |
| `5c1f9c7fb655e43d38e5dd1fcc6b942b2ff68b02` | nms8250_msx2sub, nms8250_msx2sub.rom | Philips_NMS_8250, Philips_NMS_8255, Philips_VG_8235-20 |
| `dab3e6f36843392665b71b04178aadd8762c6589` | nms8250_1.08_disk.rom | Philips_NMS_8250, Philips_NMS_8255 |
| `42252cf87deeb58181a7bfec7c874190a1351779` | vg8000_basic-bios1.rom, vg8010_basic-bios1.rom | Philips_VG_8000-00, Philips_VG_8010-00 |
| `898630ad1497dc9a329580c682ee55c4bcb9c30c` | vg8010-19_basic-bios1.rom | Philips_VG_8010-19 |
| `ae4a6632d4456ef44603e72f5acd5bbcd6c0d124` | vg8020-19_basic-bios1.rom | Philips_VG_8020-19 |
| `e998f0c441f4f1800ef44e42cd1659150206cf79` | vg8020-20_basic-bios1.rom | Philips_VG_8020-20 |
| `0de3c802057560560a03d7965fcc4cff69f8575c` | vg8230_basic-bios2.rom | Philips_VG_8230 |
| `3288894e1be6af705871499b23c85732dbc40993` | vg8230_msx2sub.rom | Philips_VG_8230 |
| `0f5798850d11b316a4254b222ca08cc4ad6d4da2` | nvg8230_disk.rom | Philips_VG_8230 |
| `5e1a4bd6826b29302a1eb88c340477e7cbd0b50a` | vg8235_basic-bios2.rom | Philips_VG_8235-00 |
| `c289dad246364e2dd716c457ca5eecf98e76c9ab` | VG8235-ROM2 - Basic2.0.bin | Philips_VG_8235-00 |
| `7ce255ab63ba79f81d8b83d66f1108062d0b61f1` | vg8235-00_disk.rom | Philips_VG_8235-00 |
| `1ee2abc68a81ae7e39548985021b6532f31171b2` | vg8235_disk_nms2.2_DE.rom | Philips_VG_8235-20 |
| `b034764e6a8978db60b1d652917f5e24a66a7925` | 8280fbios.rom, ax350iif_basic-bios2.rom | Philips_VG_8235-39, Yamaha_AX350IIF |
| `959060445e92eb980ddd9df3ef9cfefcae2de1d0` | vg8235-39_disk.rom | Philips_VG_8235-39 |
| `421ac0dbfdf35b35fe5adba5d528efba28edcecb` | vg8240_basic-bios2.rom | Philips_VG_8240 |
| `b003a5a12920facb30aa3e526a71fb557c669309` | vg8240_msx2sub.rom | Philips_VG_8240 |
| `24f3bea9f47a4d9f89be1ae1040facbfd0dba1bd` | vg8240_disk.rom | Philips_VG_8240 |
| `abd6a1574cc533ed0165f1351c1a3b560bd2dc6b` | 800han.rom | Samsung_SPC-800 |
| `0f4f09f1a6ef7535b243afabfb44a3a0eb0498d9` | sony_hb201_note-bios1.rom | Sony_HB-201 |
| `b8e30d604d319d511cbfbc61e5d8c38fbb9c5a33` | f5_msx2sub.rom, hb-f1_msx2sub.rom | Sony_HB-F1, Sony_HB-F5 |
| `9db72bb78792595a12499c821048504dc96ef848` | hb-f1_firmware1.rom | Sony_HB-F1 |
| `aa78fc9bcd2343f84cf790310a768ee47f90c841` | hb-f1_firmware2.rom | Sony_HB-F1 |
| `58accf41a90693874b86ce98d8d43c27beb8b6dc` | hb-f1_firmware3.rom | Sony_HB-F1 |
| `4ce41fcc1a603411ec4e99556409c442078f0ecf` | hb-f1xdmk2_basic-bios2 | Sony_HB-F1XDmk2 |
| `12f2cc79b3d09723840bae774be48c0d721ec1c6` | hb-f1xdmk2_disk.rom | Sony_HB-F1XDmk2 |
| `06ba91d6732ee8a2ecd5dcc38b0ce42403d86708` | hb-f5_firmware.rom | Sony_HB-F5 |
| `5077b9c86ce1dc0a22c71782dac7fb3ca2a467e0` | ax350iif_arabic.rom | Yamaha_AX350IIF |
| `54ff13b58868018fcd43c916b8d7c7200ebdcabe` | ax350iif_swp.rom | Yamaha_AX350IIF |
| `ace202e87337fbc54fea21e22c0b3af0abe6f4ae` | ax350iif_painter.rom | Yamaha_AX350IIF |
| `4cbceba8f37f08272b612b6fc212eeaf379da9c3` | ax350iif_msx2sub.rom | Yamaha_AX350IIF |
| `bd0ad648d728c691fcee08eaaaa95e15e29c0d0d` | ax350iif_disk.rom | Yamaha_AX350IIF |
| `434651305f92aa770a89e40b81125fb22d91603d` | sfg-01.rom | Yamaha_CX11, Yamaha_CX5F, Yamaha_CX5M, Yamaha_CX5MU |
| `0dde59e8d98fa524961cd37b0e100dbfb42cf576` | cx5mii_basic-bios1.rom | Yamaha_CX5MII |
| `0ce800666c0d66bc2aa0b73a16f228289b9198be` | cx5mii_sub.rom | Yamaha_CX5MII |
| `7b1798561ee1844a7d6432924fbee9b4fc591c19` | cx5mii_fmvoicingprogramii.rom | Yamaha_CX5MII |
| `6680d7118d85418813f1db9449bf3e20942b16da` | sfg-05.rom | Yamaha_CX5MII, Yamaha_CX5MII_128 |
| `ea4a723cf098be7d7b40f23a7ab831cf5e2190d7` | cx5mii-128_basic-bios1.rom | Yamaha_CX5MII_128 |
| `c2340313bfda751181e8a5287d60f77bc6a2f3e6` | cx5mii-128_sub.rom | Yamaha_CX5MII_128 |
| `30747a56f45389be76362f7fc55d673f1bff8312` | cx5mii-128_fmvoicingprogramii.rom | Yamaha_CX5MII_128 |
| `706dd67036baeec7127e4ccd8c8db8f6ce7d0e4c` | cx5m_basic-bios1.rom | Yamaha_CX5MU |

</details>

## Sestavení packů

**Příkazy vždy spouštějte zevnitř `tools/CreateMSXpack`** (nástroje čtou své tabulky JSON podle relativní cesty).

```
cd tools/CreateMSXpack
python createComp.py        # all machines -> MSX/<Vendor>/<Machine>.msx
python createDev.py         # -> MSX/CART_FW_EN.msx and MSX/CART_FW_JP.msx
```

V Linuxu/macOS použijte `python3`.

ROM uložené mimo složku nástroje (absolutní cesta, nebo relativní k aktuální složce):

```
python createComp.py --rom-dir D:/MSX/roms
python createDev.py  --rom-dir D:/MSX/roms
```

Oba nástroje vypíšou své volby s `--help`.

### Volby createComp.py

```
usage: createComp.py [-h] [--rom-dir ROM_DIR] [--xml-dir XML_DIR]
                     [--output-dir OUTPUT_DIR] [--debug]

Process ROM and XML files

options:
  -h, --help            show this help message and exit
  --rom-dir ROM_DIR     Path to the ROM files directory (default: ROM)
  --xml-dir XML_DIR     Path to the XML files directory (default: Computer)
  --output-dir OUTPUT_DIR
                        Path to the output directory (default: MSX)
  --debug               Debug output
```

Jen některé počítače sestavíte tak, že `--xml-dir` nasměrujete na podsložku, například:

```
python createComp.py --xml-dir Computer/Philips --output-dir MSX
```

### createDev.py

```
usage: createDev.py [-h] [--rom-dir ROM_DIR]

Build the cartridge FW packs: Extension/*.xml -> MSX/<name>.msx. Run from the
CreateMSXpack directory (JSON tables are read from the current directory).

options:
  -h, --help         show this help message and exit
  --rom-dir ROM_DIR  Path to the ROM files directory, searched recursively,
                     files matched by SHA1 (default: ROM)
```

Vždy čte `Extension/` a zapisuje do `MSX/`, měnit jde jen složka s ROM. Neexistující složka s ROM nástroj zastaví s chybou.

## Kopírování na SD kartu

Na MiSTeru kopírujte do `/media/fat/games/MSX1/`:

- obsah `MSX/` (složky výrobců s packy počítačů `.msx`) a jeden ze souborů `CART_FW_EN.msx` / `CART_FW_JP.msx`,
- `tools/CreateCRC/vampier.db` (databáze mapperů, viz [../CreateCRC/README.md](../CreateCRC/README.md)).

| Položka OSD | Soubor |
|---|---|
| **Load ROM PACK** | pack počítače `<Machine>.msx` |
| **Load FW PACK** | `CART_FW_EN.msx` nebo `CART_FW_JP.msx` |
| **Load DB MAPPERS** | `vampier.db`. Potřebný pro ROM cartridge větší než 64 kB nebo s mapperem; menší prosté ROM běží i bez něj |

Načtěte FW pack a pack počítače (a DB, pokud používáte velké ROM cartridge). Jádro při každém (opětovném) načtení znovu přečte všechny načtené soubory. MiSTer si pamatuje naposledy načtený pack počítače, FW pack a DB a při startu jádra je načte znovu automaticky. ROM cartridge, obrazy disket a kazety se automaticky nenačítají.

## Řešení potíží

**Pack se zapíše i při chybějících ROM a takový pack nenabootuje.** Vždy čtěte výpis nástrojů v konzoli.

### Zprávy v konzoli

| Zpráva | Význam a oprava |
|---|---|
| `<machine name>` (samostatný řádek) | XML bylo přečteno a pack se zapisuje. Následující řádky patří tomuto počítači. |
| `ROM SHA1 not found: <sha1> (ROM name: <file>) in slot s/ss` | Ve složce ROM není soubor s tímto SHA1. Pack se přesto zapíše, ale bez této ROM a nenabootuje. Doplňte správný dump (viz příloha A). |
| `ROM missing! SHA1 <sha1> not find. Computer SKIP` | Chybí ROM s fontem KANJI, pack tohoto počítače se **nezapíše** (je smazán). Týká se Daewoo_CPC-400S, National_FS-4600F, Panasonic_FS-A1F, Panasonic_FS-A1ST. |
| `WARNING:__main__:Missing ROM '<soubor>' for cartridge <NAME>. SHA1: ...` (createDev) | Firmwarová ROM rozšíření nenalezena (název souboru a cartridge podle `Extension/*.xml`, viz [Firmwarové ROM](#firmwarové-rom-pro-fw-pack)). Cartridge se vygeneruje bez své ROM: FM-PAC, GM2 a FDC cartridge nemají firmware, MoonSound v jádře skončí chybou `NOT FW CONF`. |
| `INFO:__main__:NAME: KONAMI index: 34` (createDev) | Běžná informační zpráva. Index je v šestnáctkové soustavě. |
| `Error: unknown ...`, `Unknown block elements`, `FW name: X SKIP. Not in cart_device.json`, `Device '<x>' nenalezeno` | Problém v XML nebo v tabulkách JSON (jen když jste je upravovali). Viz [DEVELOPERS.cs.md](DEVELOPERS.cs.md). |

### Chyby OSD v jádře

Když se jádro zastaví se zprávou na OSD, zůstane v resetu do dalšího načtení.

| Text OSD | Význam a oprava |
|---|---|
| BAD MSX CONF | Soubor načtený jako ROM PACK není pack počítače (například je to FW pack). |
| NOT SUPPORTED CONF | Pack obsahuje neznámý záznam. Sestavte pack nástroji ze stejné verze, jako je jádro. |
| NOT SUPPORTED BLOCK | Pack obsahuje typ bloku, který toto jádro nezná (pack vytvořený novějšími nástroji než jádro). Aktualizujte jádro nebo pack sestavte znovu. |
| BAD MSX FW CONF | Soubor načtený jako FW PACK není FW pack. |
| NOT FW CONF | Slot cartridge potřebuje FW pack, ale žádný není načten (týká se i prázdného slotu), nebo ROM cartridge nemá konfiguraci, nebo při sestavení FW packu chyběla ROM MoonSoundu `yrw801.rom`. Načtěte nebo znovu sestavte FW pack. |
| Device not in this core build | Počítač spolu s cartridgemi používá víc kopií zařízení, než jádro obsahuje. Například druhý FDC nebo FDC cartridge ve slotu B. Změňte výběr cartridgí. |
| No CRC32 DB | Byla načtena ROM cartridge větší než 64 kB a není načtena žádná DB. Načtěte `vampier.db`. |
| Not find CRC32 in DB | ROM je větší než 64 kB a v DB není. Viz [../CreateCRC/README.md](../CreateCRC/README.md). |
| FDC already in machine | Počítač už má na dané pozici řadič disků. |
| ROM too big | ROM cartridge je větší než 16 MB. |

Počítač s vlastním řadičem disků plus FDC cartridge ve slotu A není chyba: vyhraje řadič počítače a cartridge se ignoruje.

## Vlastní počítač nebo rozšíření

Viz [DEVELOPERS.cs.md](DEVELOPERS.cs.md). Rozložení klávesnice: [../CreateKeyMap/README.md](../CreateKeyMap/README.md).
