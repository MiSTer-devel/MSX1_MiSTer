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

Potřebujete pack počítače a prakticky vždy i FW pack: používá ho každá volba cartridge v OSD, včetně **Empty** a obyčejné ROM. Bez něj se obejde jen slot ROM, do kterého není nahraná žádná ROM.

## Požadavky

- Python 3 (ověřeno s 3.10).
- Žádné balíčky k instalaci: nástroje používají jen standardní knihovnu Pythonu (žádné `pip install`).

## Příprava dumpů ROM

1. Dumpy ROM vložte do `tools/CreateMSXpack/ROM/`, nebo je mějte kdekoli jinde a složku předejte volbou `--rom-dir` (oba nástroje, viz [Sestavení packů](#sestavení-packů)). Podsložky jsou v pořádku, složka se prohledává rekurzivně.
2. Názvy souborů ani přípony nejsou důležité. **ROM se rozpoznávají podle SHA1 celého souboru.** Potřebujete přesně ten dump, který nástroj očekává (stejné dumpy, jaké používá openMSX jako systémové ROM).
3. Které ROM jsou potřeba pro který počítač, je v [příloze A](#appendix-a-rom-images-per-machine) a v [tabulce firmwarových ROM](#firmware-roms-for-the-fw-pack) níže. Počítač s chybějící ROM pack nedostane, viz [Řešení potíží](#řešení-potíží).

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

Názvy jsou ty, které používá openMSX. 31 počítačů potřebuje navíc ROM s fontem KANJI (označeno „KANJI font ROM“). 287 obrazů ROM pro 227 počítačů.

| SHA1 | Název(y) souboru v XML | Počítače |
|---|---|---|
| `829c00c3114f25b3dae5157c0a238b52a3ac37db` | HX22IIC2.BIN, avt_dpc-200_basic-bios1.rom, fc-200_basic-bios1.rom, hx-20E_basic-bios.rom, hx51-basic-bios.rom, vg8020_basic-bios1.rom | AVT_DPC-200, Goldstar_FC-200, Philips_VG_8020-00, Toshiba_HX-20E, Toshiba_HX-22I, Toshiba_HX-51I |
| `5e094fca95ab8e91873ee372a3f1239b9a48a48d` | ax170_basic-bios1.rom | Al_Alamiah_AX170 |
| `0287b2ec897b9196788cd9f10c99e1487d7adbbb` | ax170_arabic.rom | Al_Alamiah_AX170 |
| `0340707c5de2310dcf5e569b7db4c6a6a5590cb7` | IC125.BIN | Al_Alamiah_AX230 |
| `620a209bdfdb65a22380031fce654bd1df61def2` | IC127.BIN | Al_Alamiah_AX230 |
| `35195ab67c289a0b470883464df66bc6ea5b00d3` | ax350ii_basic-bios2.rom, ax370_basic-bios2.rom | Al_Alamiah_AX370, Yamaha_AX350II |
| `0c08e799a7cf130ae2b9bc93f28bd4959cee6fdc` | ax370_rom01.rom | Al_Alamiah_AX370 |
| `4b4508131dca6d811694ae6379f41364c477de58` | ax370_swp.rom | Al_Alamiah_AX370 |
| `8167117a003824220c36775682acbb36b3733c5e` | ax370_sb.rom | Al_Alamiah_AX370 |
| `ee9c6a073766bef2220a57372f5c0dbfc6e55c8c` | ax370_msx2sub.rom | Al_Alamiah_AX370 |
| `9efa744be8355675e7bfdd3976bbbfaf85d62e1d` | ax370_disk.rom, phc-70fd2_disk.rom | Al_Alamiah_AX370, Sanyo_PHC-70FD2 |
| `1c9a5867d39f6f02a0a4ef291904623e2521c2c5` | ax370_painter.rom | Al_Alamiah_AX370 |
| `e998f0c441f4f1800ef44e42cd1659150206cf79` | perfect_msx1_basic-bios1.rom, vg8020-20_basic-bios1.rom | Bawareth_Perfect_MSX1, Philips_VG_8020-20 |
| `29a9169b605b5881e4a15fcfd65209a4e8679285` | perfect_msx1_arabic.rom | Bawareth_Perfect_MSX1 |
| `2f997e8a57528518c82ab3693fdae243dbbcc508` | cbios_main_msx1.rom | MSX - C-BIOS |
| `9fbbe400dbaf186aeba42e170d9424b032412c42` | cbios_logo_msx1.rom | MSX - C-BIOS |
| `f929bd1d720b0ef7092c9add8accd0d56fc9c8a3` | cbios_main_msx2.rom | MSX2 - C-BIOS |
| `d4e5b98ce23573669fb44447582d656e390791c0` | cbios_logo_msx2.rom | MSX2 - C-BIOS |
| `2fcb40413e7d373f0f2dbdc815ce18746ddf3684` | cbios_sub.rom | MSX2 - C-BIOS |
| `c5bfa85f7315fb11928b27a721a908c93b7d3fbf` | 2+FM cks-B414h.ROM | CIEL_Expert-Turbo |
| `302afb5d8be26c758309ca3df611ae69cced2821` | HX22-IC2.BIN, cf-2000_basic-bios1.rom, cx11_basic-bios1.rom, cx5f_basic-bios1.rom, fm-x_basic-bios1.rom, hb-101_basic-bios1.rom, hb-10_basic-bios1.rom, hb-701_basic-bios1.rom, hb-75_basic-bios1.rom, hc-7_basic-bios1.rom, hx-10d_basic-bios1.rom, mb-h1_basic-bios1.rom, mb-h21_basic-bios1.rom, mb-h50_basic-bios1.rom, mbh2bios.rom, ml-8000_basic-bios1.rom, ml-f110_basic-bios1.rom, ml-f120_basic-bios1.rom, mpc-10_basic-bios1.rom, mpc-10mkii_basic-bios1.rom, mpc-6_basic-bios1.rom, mpc1_basic-bios1.rom, mpc3_basic-bios1.rom, mx-10_basic-bios1.rom, pct-55_basic-bios1.rom, phc-30n_basic-bios1.rom, pv-16_basic-bios1.rom, pv-7_basic-bios1.rom, px-7_basic-bios1.rom, px-v60_basic-bios1.rom, sony_hb201_basic-bios1.rom, v-10_basic-bios1.rom, v-20jp_basic-bios1.rom, v20bios.rom, yis-503_basic-bios1.rom | Canon V-20, Canon_V-10, Canon_V-20_JP, Casio_MX-10, Casio_PV-16, Casio_PV-7, Fujitsu_FM-X, General_Paxon_PCT-55, Hitachi MB-H2, Hitachi_MB-H1, Hitachi_MB-H21, Hitachi_MB-H50, Mitsubishi_ML-8000, Mitsubishi_ML-F110, Mitsubishi_ML-F120, National_CF-2000, Pioneer_PX-7, Pioneer_PX-V60, Sanyo_MPC-1, Sanyo_MPC-10, Sanyo_MPC-10mkII, Sanyo_MPC-3, Sanyo_MPC-6, Sanyo_PHC-30N, Sony_HB-10, Sony_HB-101, Sony_HB-201, Sony_HB-701, Sony_HB-701FD, Sony_HB-75, Toshiba_HX-10D, Toshiba_HX-22, Victor_HC-7, Yamaha_CX11, Yamaha_CX5F, Yamaha_YIS-503 |
| `8963fc041975f31dc2ab1019cfdd4967999de53e` | cx5m_basic-bios1.rom, hb-55p_basic-bios1.rom, hb-75p_basic-bios1.rom, hc-7gb_basic-bios1.rom, ml-f80_basic-bios1.rom, mpc100_basic-bios1.rom, px-7uk_basic-bios1.rom, spc-800_basic-bios1.rom, v20ebios.u20, yc-64_basic-bios1.rom, yis-503f_basic-bios1.rom | Canon V-20E, Fenner_SPC-800, JVC_HC-7GB, Mitsubishi_ML-F80, Pioneer_PX-7UK, Sanyo_MPC-100, Sony_HB-55P, Sony_HB-75P, Yamaha_CX5M, Yamaha_YIS-503F, Yashica_YC-64 |
| `d99eebded5db5fce1e072d08e642c0909bc7efdd` | v20fbios.rom | Canon V-20F |
| `d67be6d7d56d7229418f4e122f2ec27990db7d19` | v20gbios.rom | Canon V-20G |
| `9fb289ea5c11d497ee00703f64e82575d1c59923` | v20sbios.rom | Canon V-20S |
| `0081ea0d25bc5cd8d70b60ad8cfdc7307812c0fd` | Toshiba_HX-23F_IC2_basicbios.bin, cx7-128_basic_bios2.rom, fs-4500_basic-bios2.rom, fs-4600f_basic-bios2.rom, fs-4700f_basic-bios2.rom, fs-a1_basic-bios2.rom, fs-a1mk2_basic-bios2.rom, hb-f1_basic-bios2.rom, hb-f1ii_basic-bios2.rom, hb-f500-2_basic-bios2.rom, hb-f500_basic-bios2.rom, hb-f5_basic-bios2.rom, hb-f900_basic-bios2.rom, hb-t600_basic-bios2.rom, hc-80_basic-bios2.rom, mb-h3_basic-bios2.rom, mpc-25fd_basic-bios2.rom, mpc-25fs_basic-bios2.rom, v-25_basic-bios2.rom, yis604-128_basic_bios2.rom | Canon_V-25, Hitachi_MB-H3, National_FS-4500, National_FS-4600F, National_FS-4700F, Panasonic_FS-A1, Panasonic_FS-A1MK2, Sanyo_MPC-25FD, Sanyo_MPC-25FS, Sony_HB-F1, Sony_HB-F1II, Sony_HB-F5, Sony_HB-F500, Sony_HB-F500_v2, Sony_HB-F900, Sony_HB-T600, Toshiba_HX-23, Toshiba_HX-23F, Victor_HC-80, Yamaha_CX7-128, Yamaha_CX7M-128, Yamaha_YIS-604-128 |
| `b8e30d604d319d511cbfbc61e5d8c38fbb9c5a33` | cx7-128_msx2sub.rom, f5_msx2sub.rom, fs-4500_msx2sub.rom, fs-4700f_msx2sub.rom, hb-f1_msx2sub.rom, hb-f500-2_msx2sub.rom, hb-f500_msx2sub.rom, hc-80_msx2sub.rom, mb-h3_msx2sub.rom, ml-g10_msx2sub.rom, ml-g30m1_msx2sub.rom, ml-g30m2_msx2sub.rom, mpc-25fd_msx2sub.rom, mpc-25fs_msx2sub.rom, v-25_msx2sub.rom, yis604-128_msx2sub.rom | Canon_V-25, Hitachi_MB-H3, Mitsubishi_ML-G10, Mitsubishi_ML-G30_model_1, Mitsubishi_ML-G30_model_2, National_FS-4500, National_FS-4700F, Sanyo_MPC-25FD, Sanyo_MPC-25FS, Sony_HB-F1, Sony_HB-F5, Sony_HB-F500, Sony_HB-F500_v2, Victor_HC-80, Yamaha_CX7-128, Yamaha_CX7M-128, Yamaha_YIS-604-128 |
| `97f9a0b45ee4b34d87ca3f163df32e1f48b0f09c` | v-8_basic-bios1.rom | Canon_V-8 |
| `a7ed5fd940f4e3a33e676840c0a83ac7ee54d972` | mx-15_basic-bios1.rom | Casio_MX-15 |
| `affa3c5cd8db79a1450ad8a7f405a425b251653d` | cpc-300_basic-bios2.rom, cpc-300e_basic-bios2.rom | Daewoo_CPC-300, Daewoo_CPC-300E |
| `47a9d9a24e4fc6f9467c6e7d61a02d45f5a753ef` | cpc-300_hangul.rom, cpc-300e_hangul.rom | Daewoo_CPC-300, Daewoo_CPC-300E |
| `fb51c505adfbc174df94289fa894ef969f5357bc` | cpc-300_msx2sub.rom | Daewoo_CPC-300 |
| `09f7d788698a23aa7eec140237e907d4c37cbfe0` | cpc-300e_msx2sub.rom | Daewoo_CPC-300E |
| `22d5f4e522250dc5eb17e15b68f4a51bb752cba1` | (KANJI font ROM, bez názvu souboru v XML) | Daewoo_CPC-400S |
| `75f5f0a5a2e8f0935f33bb3cf07b83dd3e5f3347` | CPC-40038, CPC-400S.U38 | Daewoo_CPC-400S |
| `6b640c1d8cbeda6ca7d6facd16a206b62e059eee` | CPC-400S.U44 | Daewoo_CPC-400S |
| `a08a940aa87313509e00bc5ac7494d53d8e03492` | cpc-51_basic-bios.rom | Daewoo_CPC-51_Zemix V |
| `dd3c39c8cfa06ec69f54c95c3b2291e3da7bd4f2` | CPC64122.ROM | Daewoo_CPC-61_Zemmix_Super_V |
| `171b587bd5a947a13f3114120b6e7baca3b57d78` | 800bios.rom, dpc-100_basic-bios1.rom, dpc-180_basic-bios1.rom, dpc-200_basic-bios1.rom, fc80bios.rom, fc80ubios.rom | Daewoo_DPC-100, Daewoo_DPC-180, Daewoo_DPC-200, Goldstar_FC-80, Goldstar_FC-80U, Goldstar_GFC-1080A, Samsung_SPC-800 |
| `4421fa2504cbce18f7c84b5ea97f04e017007f07` | dpc-100_hangul.rom, dpc-200_hangul.rom | Daewoo_DPC-100, Daewoo_DPC-180, Daewoo_DPC-200 |
| `d3af963e2529662eae63f04a2530454685a1989f` | daewoo_dpc-200fr_basic-bios1.rom, olympia_phc-2_basic-bios1.rom, phc-28l_basic-bios1.rom, yeno_dpc-64_basic-bios1.rom | Daewoo_DPC-200E(FR), Olympia_PHC-2, Sanyo_PHC-28L, Yeno_DPC-64 |
| `7f8c94cb8913db32a696dec80ffc78e46693f1b7` | uk1msx048.ic37 | Eurohard_Dragon_MSX |
| `05fedd4b9bfcf4949020c79d32c4c3f03a54fb62` | uk2msx058.ic6 | Eurohard_Dragon_MSX |
| `3abca440cba16ac5e162b602557d30169f77adab` | bruc100_1_basic-bios1.rom | Frael_Bruc_100_1 |
| `88611b54cdbb79aa5380570f3dfef8b3a1cc2057` | bruc100_2_basic-bios1.rom | Frael_Bruc_100_2 |
| `8e28899175aadf3bbd8c9ba63d3b82c2caa74709` | fc80han.rom | Goldstar_FC-80 |
| `58dbe73ae80c2c409e766c3ace730ecd7bec89d0` | fc80uhan.rom | Goldstar_FC-80U, Goldstar_GFC-1080A |
| `6b0be712b9c95c1e912252ab5703e1c0bc457d9e` | gfc1080bios.rom | Goldstar_GFC-1080 |
| `141b44212ba28e7d03e0b54126fedd9e0807dc42` | gfc1080han.rom | Goldstar_GFC-1080 |
| `a5581fa3ce10f90f15ba3dc53d57b02d6e4af172` | gfc1080pasocalc.rom | Goldstar_GFC-1080 |
| `d6720845928ee848cfa88a86accb067397685f02` | expert_ddplus_basic-bios1.rom | Gradiente_Expert_DD_Plus, Gradiente_Expert_GPC-1, Gradiente_Expert_Plus |
| `f1525de4e0b60a6687156c2a96f8a8b2044b6c56` | cf-3300_disk.rom, expert_ddplus_disk.rom | Gradiente_Expert_DD_Plus, National_CF-3300 |
| `d4cea8c815f3eeabe0c6a1c845f902ec4318bf6b` | expert_plus_demo.rom | Gradiente_Expert_Plus |
| `ef3e010eb57e4476700a3bbff9d2119ab3acdf62` | expert_1.0_basic-bios1.rom | Gradiente_Expert_XP-800 |
| `e2140fa2e8e59090ecccf55b62323ea9dcc66d0b` | mbh2firm.rom | Hitachi MB-H2 |
| `3e005832138ffde8b1c36025754f81c2112b236d` | mb-h1_firmware.rom | Hitachi_MB-H1 |
| `a2665c7c4b95171ace72c66d9bae4309329eb0ac` | mb-h21_firmware.rom | Hitachi_MB-H21 |
| `74ee82cc09ffcf78f6e9a3f0d993f8f80d81444c` | mb-h3_firmware.rom | Hitachi_MB-H3 |
| `db03211b7db46899df41db2b1dfbec972109a967` | (KANJI font ROM, bez názvu souboru v XML) | Hitachi_MB-H70, Mitsubishi_ML-G30_model_1, Mitsubishi_ML-G30_model_2, Pioneer_UC-V102, Toshiba_HX-32, Toshiba_HX-33, Yamaha_YIS-805-256 |
| `a8ccbe66c05d5a8f68e1163a88e07f2d82bf241b` | mb-h70_basic-bios2.rom | Hitachi_MB-H70 |
| `0fbd45ef3dd7bb82d4c31f1947884f411f1ca344` | fs-4600f_msx2sub.rom, fs-5000f2_msx2sub.rom, fs-a1_msx2sub.rom, fs-a1mk2_msx2sub.rom, hb-f1ii_msx2sub.rom, hb-f1xd_msx2sub.rom, hb-f1xdmk2_msx2sub.rom, hb-f900_msx2sub.rom, hb-t600_msx2sub.rom, mb-h70_msx2sub.rom, uc-v102_msx2sub.rom | Hitachi_MB-H70, National_FS-4600F, National_FS-5000F2, Panasonic_FS-A1, Panasonic_FS-A1MK2, Pioneer_UC-V102, Sony_HB-F1II, Sony_HB-F1XD, Sony_HB-F1XDmk2, Sony_HB-F900, Sony_HB-T600 |
| `6608250065bfb43b309147a81711b77cb3067a02` | mb-h70_disk.rom | Hitachi_MB-H70 |
| `21a9f60cb6370d0617ce54c42bb7d8e40a4ab560` | ml-f120_firmware.rom | Mitsubishi_ML-F120 |
| `0cbe0df4af45e8f531e9c761403ac9e71808f20c` | ml-fx1_basic-bios1.rom | Mitsubishi_ML-FX1 |
| `c1e46c00f1e38fc9e0ab487bf0513bd93ce61f3f` | ml-g10_basic-bios2.rom, ml-g30m1_basic-bios2.rom, ml-g30m2_basic-bios2.rom, uc-v102_basic-bios2.rom | Mitsubishi_ML-G10, Mitsubishi_ML-G30_model_1, Mitsubishi_ML-G30_model_2, Pioneer_UC-V102 |
| `789bb6cdb2d1ed0348f36336da11b149d74e4d9f` | ml-g10_firmware.rom | Mitsubishi_ML-G10 |
| `e4fdf518a8b9c8ab4290c21b83be2c347965fc24` | ml-g1_es_basic-bios2.rom, ml-g3_es_basic-bios2.rom | Mitsubishi_ML-G1_ES, Mitsubishi_ML-G3_ES |
| `1e9a955943aeea9b1807ddf1250ba6436d8dd276` | hb-f700s_msx2sub.rom, ml-g1_es_msx2sub.rom, ml-g3_es_msx2sub.rom | Mitsubishi_ML-G1_ES, Mitsubishi_ML-G3_ES, Sony_HB-F700S |
| `5cf0abca6dbcf940bc33c433ecb4e4ada02fbfe6` | ml-g1_paint.rom | Mitsubishi_ML-G1_ES |
| `f7c3ac138918a493eb91628ed88cf37999059579` | ml-g30m1_disk.rom, uc-v102_disk.rom | Mitsubishi_ML-G30_model_1, Pioneer_UC-V102 |
| `6069d63c68b03fa56de040fb5f52eeadbffe2a2c` | ml-g30m2_disk.rom | Mitsubishi_ML-G30_model_2 |
| `30ba1144c872a0bb1c91768e75a2c28ab1f4e3c6` | ml-g3_es_disk.rom | Mitsubishi_ML-G3_ES |
| `c7a2c5baee6a9f0e1c6ee7d76944c0ab1886796c` | cf-1200_basic-bios1.rom, cf-2700_basic-bios1.rom, cf-3000_basic-bios1.rom, cf-3300_basic-bios1.rom, fs-1300_basic-bios1.rom | National_CF-1200, National_CF-2700, National_CF-3000, National_CF-3300, National_FS-1300 |
| `9ed3ab6d893632b9246e91b412cd5db519e7586b` | (KANJI font ROM, bez názvu souboru v XML) | National_FS-4000, National_FS-4500, National_FS-4700F, National_FS-5500F1, National_FS-5500F2 |
| `df48902f5f12af8867ae1a87f255145f0e5e0774` | fs-4000_basic-bios1.rom | National_FS-4000 |
| `931d6318774bd495a32ec3dabf8d0edfc9913324` | fs-4000_msxword.rom | National_FS-4000 |
| `77bd67d5d10d459d343e79eafcd8e17eb0f209dd` | fs-4000_kanjibasic.rom | National_FS-4000 |
| `3ce8e35790eb4689b21e14c7ecdd4b63943ee158` | fs-4500_wordfont.rom, fs-4700f_wordfont.rom | National_FS-4500, National_FS-4700F |
| `6442c1c5cece64c6dae90cc6ae3675f070d93e06` | fs-4500_msxjusho.rom, fs-4700f_msxjusho.rom | National_FS-4500, National_FS-4700F |
| `3f047469b62d93904005a0ea29092e892724ce0b` | fs-4500_msxword1.rom | National_FS-4500 |
| `df07e89fa0b1c7874f9cdf184c136f964fea4ff4` | fs-4500_kanjibasic1.rom, fs-4700f_kanjibasic1.rom | National_FS-4500, National_FS-4700F |
| `4c8ea05c09b40c41888fa18db065575a317fda16` | fs-4500_msxword2.rom, fs-4700f_msxword2.rom | National_FS-4500, National_FS-4700F |
| `c63db26660da96af56f8a7d3ea18544b9ae5a37c` | fs-4500_kanjibasic2.rom, fs-4700f_kanjibasic2.rom | National_FS-4500, National_FS-4700F |
| `5e872d5853698731a0ed22fb72dbcdfd59cd19c3` | (KANJI font ROM, bez názvu souboru v XML) | National_FS-4600F, National_FS-5000F2, Panasonic_FS-A1F |
| `31292b9ca9fe7d1d8833530f44c0a5671bfefe4e` | fs-4600f_wordfont1.rom | National_FS-4600F |
| `3a9a942ed888dd641cddf8deada1879c454df3c6` | fs-4600f_kanjibasic.rom, fs-5000f2_kanjibasic.rom, fs-5500_kanjibasic.rom | National_FS-4600F, National_FS-5000F2, National_FS-5500F1, National_FS-5500F2 |
| `02155fc25c9bd23e1654fe81c74486351e1ecc28` | fs-4600f_wordfont2.rom | National_FS-4600F |
| `005794c10a4237de3907ba4a44d436078d3c06c2` | fs-4600f_msxword.rom | National_FS-4600F |
| `073feb8bb645d935e099afaf61e6f04f52adee42` | fs-4600f_disk.rom, fs-5000f2_disk.rom | National_FS-4600F, National_FS-5000F2 |
| `f5af1d2a8bcf247f78847e1a9d995e581df87e8e` | fs-4700f_msxword1.rom | National_FS-4700F |
| `78cd7f847e77fd8cd51a647efb2725ba93f4c471` | fs-4700f_disk.rom, fs-5500_disk.rom | National_FS-4700F, National_FS-5500F1, National_FS-5500F2 |
| `59967765d6e9328909dee4dac1cbe4cf9d47d315` | fs-5000f2_basic-bios2.rom | National_FS-5000F2 |
| `98bbfa3ab07b7a5cad55d7ddf7cbd9440caa2a86` | fs-5000f2_setuprtc.rom | National_FS-5000F2 |
| `44e0dd215b2a9f0770dd76fb49187c05b083eed9` | fs-5500_basic-bios2.rom | National_FS-5500F1, National_FS-5500F2 |
| `4be8371f3b03e70ddaca495958345f3c4f8e2d36` | fs-5500_msx2sub.rom | National_FS-5500F1, National_FS-5500F2 |
| `b677a861b67e8763a11d5dcf52416b42493ade57` | fs-5500_superimp.rom | National_FS-5500F1, National_FS-5500F2 |
| `54ffdd9daaf5f9ae90adb627186a405dffd999f6` | pc-70100_basic-bios1.rom | Nikko_PC-70100 |
| `81966a221b25c2cf61fc1e5e65a0d76f1b2f8553` | ocm_iplrom.rom | 1chipMSX |
| `69bf27b610e11437dad1f7a1c37a63179a293d12` | cf-2700_basic-bios1_german.rom | Panasonic_CF-2700_DE |
| `5e6b1306a30bbb46af61487d1a3cc1b0a69004c3` | cf-2700_basic-bios1_gb.rom | Panasonic_CF-2700_GB |
| `63098f27beac9eca6b39d837d2a552395df33fe1` | fs-a1_deskpac1.rom | Panasonic_FS-A1 |
| `7f5b76605e3d898cc4b5aacf1d7682b82fe84353` | fs-a1_deskpac2.rom | Panasonic_FS-A1 |
| `9a62d7a5ccda974261f7c0600476d85e10deb99b` | DA1024D0365R.rom | Panasonic_FS-A1F |
| `e0e99cd91e88ce2676445663f832c835d74d6fd4` | (KANJI font ROM, bez názvu souboru v XML) | Panasonic_FS-A1FX |
| `623cbca109b6410df08ee7062150a6bda4b5d5d4` | fs-a1fx_IC16.rom | Panasonic_FS-A1FX |
| `5aff2d9b6efc723bc395b0f96f0adfa83cc54a49` | (KANJI font ROM, bez názvu souboru v XML) | Panasonic_FS-A1GT, Panasonic_FS-A1ST, Panasonic_FS-A1WSX, Panasonic_FS-A1WX |
| `e779c338eb91a7dea3ff75f3fde76b8af22c4a3a` | fs-a1gt_firmware.rom | Panasonic_FS-A1GT |
| `2752cd89754c05abdf7c23cba132d38e3ef0f27d` | fs-a1mk2_cockpit1.rom | Panasonic_FS-A1MK2 |
| `e194d290ebfa4595ce0349ea2fc15442508485b0` | fs-a1mk2_cockpit2.rom | Panasonic_FS-A1MK2 |
| `a3f4e2e4934074925d775afe30ac72f150ede543` | fs-a1mk2_cockpit3.rom | Panasonic_FS-A1MK2 |
| `c212b11fda13f83dafed688c54d098e7e47ab225` | fs-a1st_firmware.rom | Panasonic_FS-A1ST |
| `f4433752d3bf876bfefb363c749d4d2e08a218b6` | fs-a1wsx_basic-bios2p.rom, phc-35j_basic-bios2p.rom | Panasonic_FS-A1WSX, Sanyo_PHC-35J |
| `aad42ba4289b33d8eed225d42cea930b7fc5c228` | fs-a1wsx_fmbasic.rom, fs-a1wx_fmbasic.rom, phc-70fd2_fmbasic.rom | Panasonic_FS-A1WSX, Panasonic_FS-A1WX, Sanyo_PHC-70FD2 |
| `fe0254cbfc11405b79e7c86c7769bd6322b04995` | fs-a1wsx_msx2psub.rom, fs-a1wx_msx2psub.rom, phc-35j_msx2psub.rom, phc-70fd2_msx2psub.rom | Panasonic_FS-A1WSX, Panasonic_FS-A1WX, Sanyo_PHC-35J, Sanyo_PHC-70FD2 |
| `dcc3a67732aa01c4f2ee8d1ad886444a4dbafe06` | fs-a1wsx_kanjibasic.rom, phc-35j_kanjibasic.rom | Panasonic_FS-A1WSX, Sanyo_PHC-35J |
| `7ed7c55e0359737ac5e68d38cb6903f9e5d7c2b6` | fs-a1wsx_disk.rom | Panasonic_FS-A1WSX |
| `3330d9b6b76e3c4ccb7cf252496ed15d08b95d3f` | fs-a1wsx_firmware.rom | Panasonic_FS-A1WSX |
| `e90f80a61d94c617850c415e12ad70ac41e66bb7` | fs-a1wx_basic-bios2p.rom, phc-70fd2_basic-bios2p.rom | Panasonic_FS-A1WX, Sanyo_PHC-70FD2 |
| `1ef3956f7f918873fb9b031339bba45d1e5e5878` | fs-a1wx_kanjibasic.rom, phc-70fd2_kanjibasic.rom | Panasonic_FS-A1WX, Sanyo_PHC-70FD2 |
| `bb59c849898d46a23fdbd0cc04ab35088e74a18d` | fs-a1wx_disk.rom | Panasonic_FS-A1WX |
| `d37ab4bd2bfddd8c97476cbe7347ae581a6f2972` | fs-a1wx_firmware.rom | Panasonic_FS-A1WX |
| `21329398c0f350e330b353f45f21aa7ba338fc8d` | nms801_basic-bios1.rom | Philips_NMS_801 |
| `e761e7081c613ad4893a664334ce105841d0e80e` | NMS8220SystemROM.bin | Philips_NMS_8220 |
| `5df95d033ae70b107697b69470126ce1b7ae9eb5` | nms8220_designer.rom | Philips_NMS_8220 |
| `ee0d8ccfc247368078d27183c34b3a5c0f4ae0f1` | nms8245_16_basic-bios2.rom, nms8250-16_basic-bios2.rom | Philips_NMS_8245-16, Philips_NMS_8250-16 |
| `b83770cca8453a153d7e260070a3a3c059d64ed3` | nms8245_16_msx2sub.rom, nms8250-16_msx2sub.rom | Philips_NMS_8245-16, Philips_NMS_8250-16 |
| `58ba1887e8fd21c912b6859cae6514bd874ffcca` | nms8245_16_disk.rom | Philips_NMS_8245-16 |
| `b034764e6a8978db60b1d652917f5e24a66a7925` | 8280fbios.rom, ax350iif_basic-bios2.rom, nms8245_19_basic-bios2.rom | Philips_NMS_8245-19, Philips_VG_8235-39, Yamaha_AX350IIF |
| `fd4bcc81a8160a1dea06036c5f79d200f948f4d6` | nms8245_19_msx2sub.rom, nms8250-19_msx2sub.rom | Philips_NMS_8245-19, Philips_NMS_8250-19, Philips_VG_8235-39 |
| `48f92795133fec19c555bbb95c9696a56f7a585b` | nms8245_19_disk.rom | Philips_NMS_8245-19 |
| `6103b39f1e38d1aa2d84b1c3219c44f1abb5436e` | nms8220_basic-bios2.rom, nms8245_basic-bios2.rom, nms8250_basic-bios2.rom | Philips_NMS_8245, Philips_NMS_8250, Philips_NMS_8255, Philips_VG_8235-20 |
| `e7905d16d2ccd57a013c122dc432106cd59ef52c` | nms8245_msx2sub.rom | Philips_NMS_8245 |
| `c3f3ca454d66a0bc791f1d4b60e6857b44eb8755` | nms8245_disk.rom | Philips_NMS_8245 |
| `c3efedda7ab947a06d9345f7b8261076fa7ceeef` | nms8250_disk.rom | Philips_NMS_8250-16, Philips_NMS_8250-19 |
| `d18694e9e7040b2851fe985cefb89766868a2fd3` | nms8250-19_basic-bios2.rom | Philips_NMS_8250-19 |
| `5c1f9c7fb655e43d38e5dd1fcc6b942b2ff68b02` | nms8250_msx2sub, nms8250_msx2sub.rom | Philips_NMS_8250, Philips_NMS_8255, Philips_VG_8235-20 |
| `dab3e6f36843392665b71b04178aadd8762c6589` | nms8250_1.08_disk.rom | Philips_NMS_8250, Philips_NMS_8255 |
| `42252cf87deeb58181a7bfec7c874190a1351779` | vg8000_basic-bios1.rom, vg8010_basic-bios1.rom | Philips_VG_8000-00, Philips_VG_8010-00 |
| `898630ad1497dc9a329580c682ee55c4bcb9c30c` | vg8010-19_basic-bios1.rom | Philips_VG_8010-19 |
| `ae4a6632d4456ef44603e72f5acd5bbcd6c0d124` | vg8020-19_basic-bios1.rom | Philips_VG_8020-19 |
| `0de3c802057560560a03d7965fcc4cff69f8575c` | hb-f500p_basic-bios2.rom, hb-f700p_basic-bios2.rom, hb-f9p_basic-bios2.rom, hb-g900ap_basic-bios2.rom, hb-g900p_basic-bios2.rom, vg8230_basic-bios2.rom | Philips_VG_8230, Sony_HB-F500P, Sony_HB-F700P, Sony_HB-F9P, Sony_HB-G900AP, Sony_HB-G900P |
| `3288894e1be6af705871499b23c85732dbc40993` | hb-f500p_msx2sub.rom, hb-f700d_msx2sub.rom, hb-g900ap_msx2sub.rom, hb-g900p_msx2sub.rom, vg8230_msx2sub.rom | Philips_VG_8230, Sony_HB-F500P, Sony_HB-F700D, Sony_HB-G900AP, Sony_HB-G900P |
| `0f5798850d11b316a4254b222ca08cc4ad6d4da2` | nvg8230_disk.rom | Philips_VG_8230 |
| `5e1a4bd6826b29302a1eb88c340477e7cbd0b50a` | vg8235_basic-bios2.rom | Philips_VG_8235-00 |
| `c289dad246364e2dd716c457ca5eecf98e76c9ab` | VG8235-ROM2 - Basic2.0.bin | Philips_VG_8235-00 |
| `7ce255ab63ba79f81d8b83d66f1108062d0b61f1` | vg8235-00_disk.rom | Philips_VG_8235-00 |
| `cef16eb95502ba6ab2265fcafcedde470a101541` | hb-f700d_basic-bios2.rom, hb-g900d_basic-bios2.rom, vg8235-02_basic-bios2.rom | Philips_VG_8235-02, Sony_HB-F700D, Sony_HB-G900D |
| `7b4a96402847decfc110ff9eda713bdcd218bd83` | hb-f9p_msx2sub.rom, hb-g900d_msx2sub.rom, vg8235-02_msx2sub.rom | Philips_VG_8235-02, Sony_HB-F9P, Sony_HB-G900D |
| `17997ca299dbcb21dbfa6bf82099a380f7f75bfe` | vg8235-02_disk.rom | Philips_VG_8235-02 |
| `3926cdd91fa89657a811463e48cfbdb350676e51` | hb-f700f_basic-bios2.rom, vg8235-19_basic-bios2.rom | Philips_VG_8235-19, Sony_HB-F700F |
| `792e6b2814ab783d06c7576c1e3ccd6a9bbac34a` | hb-f700f_msx2sub.rom, vg8235-19_msx2sub.rom | Philips_VG_8235-19, Sony_HB-F700F |
| `742375e636b6819b454246ea5c6a552588cb7a7e` | vg8235-19_disk.rom | Philips_VG_8235-19 |
| `1ee2abc68a81ae7e39548985021b6532f31171b2` | vg8235_disk_nms2.2_DE.rom | Philips_VG_8235-20 |
| `959060445e92eb980ddd9df3ef9cfefcae2de1d0` | vg8235-39_disk.rom | Philips_VG_8235-39 |
| `421ac0dbfdf35b35fe5adba5d528efba28edcecb` | vg8240_basic-bios2.rom | Philips_VG_8240 |
| `b003a5a12920facb30aa3e526a71fb557c669309` | vg8240_msx2sub.rom | Philips_VG_8240 |
| `24f3bea9f47a4d9f89be1ae1040facbfd0dba1bd` | vg8240_disk.rom | Philips_VG_8240 |
| `abd6a1574cc533ed0165f1351c1a3b560bd2dc6b` | 800han.rom | Samsung_SPC-800 |
| `c3a47480c9dd2235f40f9a53dab68e3c48adca01` | mpc-10mkii_firmware.rom | Sanyo_MPC-10mkII |
| `20218b02c893f30369d1fb4b66b6f37ffce83ed6` | mpc-11_basic-bios1.rom | Sanyo_MPC-11 |
| `4d0c37ad722366ac7aa3d64291c3db72884deb2d` | mpc2_basic-bios1.rom, phc-33_basic-bios1.rom, phc-spc_basic-bios1.rom, sx-100_basic-bios1.rom, yis503ii_basic_bios1.rom | Sanyo_MPC-2, Sanyo_PHC-33, Sanyo_PHC-SPC, Yamaha_SX-100, Yamaha_YIS-503II |
| `7850264dead5b05dd07fc79c1b7357940b92565e` | mpc-2300_basic-bios2.rom | Sanyo_MPC-2300 |
| `99990f4b262c6c6e0682041bf30d1ed24dc7dda5` | mpc-2300_msx2sub.rom | Sanyo_MPC-2300 |
| `bdbc75aacba4ea0f359694f304ae436914733460` | mpc-25fd_disk.rom | Sanyo_MPC-25FD |
| `50f4098a77e7af7093e29cc8683d2b34b2d07b13` | mpc-25fs_disk.rom | Sanyo_MPC-25FS |
| `38a645febd0e0fe86d594f27c2d14be995acc730` | hb-75d_basic-bios1.rom, mpc-64_basic-bios1.rom, phc-28p_basic-bios1.rom | Sanyo_MPC-64, Sanyo_PHC-28P, Sony_HB-75D |
| `4ce41fcc1a603411ec4e99556409c442078f0ecf` | hb-f1xd_basic-bios2.rom, hb-f1xdmk2_basic-bios2, phc-23_basic-bios2.rom, phc-23j_basic-bios2.rom, phc-23jb_basic-bios2.rom | Sanyo_PHC-23, Sanyo_PHC-23J, Sanyo_PHC-23JB, Sony_HB-F1XD, Sony_HB-F1XDmk2 |
| `fd9fa78bac25aa3c0792425b21d14e364cf7eea4` | phc-23j_msx2sub.rom, phc-23jb_msx2sub.rom | Sanyo_PHC-23, Sanyo_PHC-23J, Sanyo_PHC-23JB |
| `b1cce60ef61c058f5e42ef7ac635018d1a431168` | phc-28s_basic-bios1.rom | Sanyo_PHC-28S |
| `84a645becec0a25d3ab7a909cde1b242699a8662` | (KANJI font ROM, bez názvu souboru v XML) | Sanyo_PHC-35J, Sanyo_PHC-70FD |
| `b6f2ca2e8a18d6c7cd326cb8d1a1d7d747f23059` | Sanyo_PHC-70FD.rom | Sanyo_PHC-70FD |
| `bcdb4dae303dfe5234f372d70a5e0271d3202c36` | (KANJI font ROM, bez názvu souboru v XML) | Sanyo_PHC-70FD2 |
| `22b3191d865010264001b9d896186a9818478a6b` | phc-70fd2_basickun.rom | Sanyo_PHC-70FD2 |
| `663f8c512d04d213fa616b0db5eefe3774012a4b` | hotbit_1.1_basic-bios1.rom | Sharp_HB-8000_1.1 |
| `9425815446d468058705bae545ffa13646744a87` | hotbit_1.2_basic-bios1.rom | Sharp_HB-8000_1.2 |
| `64adb7fcf9b86f59d8658badb02f58e61bb15712` | hb-101_firmware.rom | Sony_HB-101 |
| `5e7c8eab238712d1e18b0219c0f4d4dae180420d` | hb-101p_basic-bios1.rom, hb-10p_basic-bios1.rom, hb-201p_basic-bios1.rom, hb-501p_basic-bios1.rom | Sony_HB-101P, Sony_HB-10P, Sony_HB-201P, Sony_HB-501P |
| `8ffc24677fd9d2606a79718764261cdf02434f0a` | hb-101p_firmware.rom | Sony_HB-101P |
| `6acaf2eeb57f65f7408235d5e07b7563229de799` | (KANJI font ROM, bez názvu souboru v XML) | Sony_HB-11, Sony_HB-F500, Sony_HB-F500_v2, Sony_HB-F900, Sony_HB-T600 |
| `6716404cf248f92d672fa4c54c9c07f47990b011` | hb-11_basic-bios1.rom | Sony_HB-11 |
| `21baaf52bc5355417d810dd479679482bb9a45a0` | hb-11_firmware_1.rom | Sony_HB-11 |
| `4ee80ca1645c1f3c01fd04c3ceb6f78d44fc13c0` | hb-11_firmware_2.rom | Sony_HB-11 |
| `8a827cf0cddce2c98c6c6cdd830e7791eb9a28cf` | hb-11_firmware_3.rom | Sony_HB-11 |
| `0f4f09f1a6ef7535b243afabfb44a3a0eb0498d9` | sony_hb201_note-bios1.rom | Sony_HB-201 |
| `e84d3ec7a595ee36b50e979683c84105c1871857` | hb-201p_firmware.rom | Sony_HB-201P |
| `63050d2d21214a721cc55f152c22b7be8061ac33` | hb-20p_basic-bios1.rom | Sony_HB-20P |
| `b262aedc71b445303f84efe5e865cbb71fd7d952` | hb-55p_firmware.rom, hb-75p_firmware.rom | Sony_HB-55P, Sony_HB-75P |
| `2520e55987ea3084a5bfd75452dc6215b9a1aac4` | hb-701_firmware.rom | Sony_HB-701, Sony_HB-701FD |
| `be86a0c2004142f2e8b7d65bf03733cc3d041ec1` | hb-701fd_disk.rom | Sony_HB-701FD |
| `5f26319aec3354a94e2a98e07b2c70046bc45417` | hb-75_firmware.rom | Sony_HB-75 |
| `97ce59892573cac3c440efff6d74c8a1c29a5ad3` | hb-75d_firmware.rom | Sony_HB-75D |
| `9db72bb78792595a12499c821048504dc96ef848` | hb-f1_firmware1.rom | Sony_HB-F1 |
| `aa78fc9bcd2343f84cf790310a768ee47f90c841` | hb-f1_firmware2.rom | Sony_HB-F1 |
| `58accf41a90693874b86ce98d8d43c27beb8b6dc` | hb-f1_firmware3.rom | Sony_HB-F1 |
| `30d914cda2180889a40a3328e0a0c1327f4eaa10` | hb-f1ii_firmware1.rom | Sony_HB-F1II |
| `ed2fea5c2a3c2e58d4f69f9d636e08574486a2b1` | hb-f1ii_firmware2.rom | Sony_HB-F1II |
| `917d1c079e03c4a44de864f123d03c4e32c8daae` | hb-f1ii_firmware3.rom | Sony_HB-F1II |
| `12f2cc79b3d09723840bae774be48c0d721ec1c6` | hb-f1xd_disk.rom, hb-f1xdmk2_disk.rom, hb-f700d_disk.rom, hb-f700f_disk.rom, hb-g900ap_disk.rom, hb-g900d_disk.rom, hb-g900p_disk.rom, hb-t600_disk.rom | Sony_HB-F1XD, Sony_HB-F1XDmk2, Sony_HB-F700D, Sony_HB-F700F, Sony_HB-G900AP, Sony_HB-G900D, Sony_HB-G900P, Sony_HB-T600 |
| `218d91eb6df2823c924d3774a9f455492a10aecb` | (KANJI font ROM, bez názvu souboru v XML) | Sony_HB-F1XDJ, Sony_HB-F1XV |
| `f2a1d326d72d4c70ea214d7883838de8847a82b7` | Sony_HB-F1XDJ_main.rom, Sony_HB-F1XV.rom | Sony_HB-F1XDJ, Sony_HB-F1XV |
| `ade0c5ba5574f8114d7079050317099b4519e88f` | hb-f1xdj.rom, hb-f1xv.rom | Sony_HB-F1XDJ, Sony_HB-F1XV |
| `06ba91d6732ee8a2ecd5dcc38b0ce42403d86708` | hb-f5_firmware.rom | Sony_HB-F5 |
| `e93b8da1e8dddbb3742292b0e5e58731b90e9313` | hb-f500-2_disk.rom, hb-f500_disk.rom | Sony_HB-F500, Sony_HB-F500_v2 |
| `1566532146fcfc28c707753777c66585dc12418a` | hb-f500p_disk.rom | Sony_HB-F500P |
| `24624c5fa3a8069b1d865cdea8a029f15c1955ea` | hb-f700p_msx2sub.rom | Sony_HB-F700P |
| `3376cf9dd2b1ac9b41bf6bf6598b33136e86f9d5` | hb-f700p_disk.rom, hb-f700s_disk.rom | Sony_HB-F700P, Sony_HB-F700S |
| `4811956f878c3e03da46317f787cdc4bebc86f47` | hb-f700s_basic-bios2.rom, hb-f9s_IC11.rom | Sony_HB-F700S, Sony_HB-F9S |
| `fc760d1d7b16370abc7eea39955f230b95b37df6` | hb-f900_disk.rom | Sony_HB-F900 |
| `558b7383544542cf7333700ff90c3efbf93ba2a3` | hb-f900_video-utility.rom | Sony_HB-F900 |
| `8cc1f7ceeef745bb34e80253971e137213671486` | hb-f9p_firmware2.rom | Sony_HB-F9P |
| `2d1880d1f5a6944fcb1b198b997a3d90ecd1903d` | hb-f9p_firmware.rom | Sony_HB-F9P |
| `7f440ec7295d889b097e1b66bf9bc5ce086f59aa` | hb-f9p_russian_basic-bios2.rom | Sony_HB-F9P_Russian |
| `a6d7b1fd4ee896ca7513d02c033fc9a8aa065235` | hb-f9p_russian_msx2sub.rom | Sony_HB-F9P_Russian |
| `1166a93d7185ba024bdf2bfa9a30e1c447fb6db1` | hb-f9s_IC12.rom | Sony_HB-F9S |
| `7efac54dd8f580f3b7809ab35db4ae58f0eb84d1` | hb-f9s_IC13.rom | Sony_HB-F9S |
| `6bb18cd2d69f124ad0c7c23a13eb0d2139037696` | hb-g900ap_video-utility.rom | Sony_HB-G900AP |
| `852c3d6ce3787f4fca986e173a4f9eed9f344576` | hb-g900d_video-utility.rom | Sony_HB-G900D |
| `8779b004e7605a3c419825f0373a5d8fa84e1d5b` | hb-g900p_video-utility.rom | Sony_HB-G900P |
| `6d2a659b65feeccce57cf47ef9ea567794b6d5ce` | hb-t600_firmware.rom | Sony_HB-T600 |
| `ea6a82cf8c6e65eb30b98755c8577cde8d9186c0` | svi-728_basic-bios1.rom | Spectravideo_SVI-728 |
| `1c89e63aed92906426f63fa760392b87f1f660bb` | svi-728_dk_basic-bios1.rom | Spectravideo_SVI-728_DK |
| `82415ee031721d1954bfa42e1c6dd79d71c692d6` | svi-728es_basic-bios1.rom | Spectravideo_SVI-728_ES |
| `87f4d0fa58cfe9cef818a3185df2735e6da6168c` | svi-728_se_basic-bios1.rom, svi-738_se_basic-bios1.rom | Spectravideo_SVI-728_SE, Spectravideo_SVI-738_SE |
| `c53b3f2c00f31683914f7452f3f4d94ae2929c0d` | svi-738_basic-bios1.rom | Spectravideo_SVI-738 |
| `99a40266bc296cef1d432cb0caa8df1a7e570be4` | svi-738_disk.rom | Spectravideo_SVI-738, Spectravideo_SVI-738_DE, Spectravideo_SVI-738_DK, Spectravideo_SVI-738_PL, Spectravideo_SVI-738_SE |
| `fc3a4872f27dd8ce7c801d4816aab483d5050e31` | svi-738_de_basic-bios1.rom | Spectravideo_SVI-738_DE |
| `1bda5af20cb86565bdc1ebd1e59a691fed7f9256` | svi-738_dk_basic-bios1.rom | Spectravideo_SVI-738_DK |
| `c90077ed84133a947841e07856e71133ba779da6` | svi-738_pl_basic-bios1.rom | Spectravideo_SVI-738_PL |
| `d5bf4814ea694481c8badbb8de8d56a08ee03cc0` | talent_dpc-200_basic-bios1.rom | Talent_DPC-200 |
| `7bba23669b7abfb6a142f9e1735b847d6e4e8267` | tpc-310_basic-bios2.rom | Talent_TPC-310 |
| `39dfc46260f99b670916b1e55f67a5d4136e6e54` | tpc-310_msx2sub.rom | Talent_TPC-310 |
| `181bf58da7184e128cd419da3109b93344a543cf` | tpc-310_turbo.rom | Talent_TPC-310 |
| `cdeb0ed8adecaaadb78d5a5364fd603238591685` | tpc-310_accessories.rom | Talent_TPC-310 |
| `7a69e9b9595f3b0060155f4b419c915d4d9d8ca1` | fs-tm1_basic-bios2.rom | Toshiba_FS-TM1 |
| `a4bdbdb20bf9fd3c492a890fbf541bf092eaa8e1` | fs-tm1_msx2sub.rom | Toshiba_FS-TM1 |
| `30737040d90c136d34dd409fe579bc4cca11c469` | fs-tm1_utility1.rom | Toshiba_FS-TM1 |
| `ff6e07d3976b0874164fae680ae028d598752049` | fs-tm1_utility2.rom | Toshiba_FS-TM1 |
| `4dad9de7c28b452351cc12910849b51bd9a37ab3` | hx-10_basic-bios1.rom | Toshiba_HX-10 |
| `9f7cfa932bd7dfd0d9ecaadc51655fb557c2e125` | hx-20E_wordprocessor.rom | Toshiba_HX-20E |
| `01600d06d83072d4e757b29728555efde2c79705` | HX21-IC2.BIN, HX32-IC3.BIN | Toshiba_HX-21, Toshiba_HX-32 |
| `4e2ec9c0294a18a3ab463f182f9333d2af68cdca` | HX21-IC3.BIN, HX22-IC3.BIN | Toshiba_HX-21, Toshiba_HX-22 |
| `3289336b2c12161fd926a7e5ce865770ae7038af` | HX22IIC3.BIN | Toshiba_HX-22I |
| `6ecf73a1dd55b363c2e68cc6245ece979aec1fc5` | Toshiba_HX-23F_IC52_subrom-jwp.bin | Toshiba_HX-23, Toshiba_HX-23F |
| `0958361ac9b19782cf7017b2e762b416e0203f37` | Toshiba_HX-23F_IC3_rs232-jwp.bin | Toshiba_HX-23, Toshiba_HX-23F |
| `ed589da7f359a4e139a23cd82d9a6a6fa3d70db0` | HX32-IC2.BIN | Toshiba_HX-32 |
| `5e057526fe39d79e88e7ff1ce02ed669bd38929e` | HX33_IC7.BIN | Toshiba_HX-33 |
| `e211534064ea6f436f2e7458ded35c398f17b761` | hc-7_firmware.rom | Victor_HC-7 |
| `7f498db2f431b9c0b42dac1c7ca46a236b780228` | hc-80_firmware.rom | Victor_HC-80 |
| `afd6b92cc7c4b7aea960f6c15cde38381ad357b9` | ax-150_basic-bios.rom | Yamaha_AX150 |
| `786091b8744e78b9201e302f798469c8ace2ab95` | ax-150_arabic.rom | Yamaha_AX150 |
| `079c018739c37485f3d64ef2145a0267fce6e20e` | ax200_basic-bios1.rom | Yamaha_AX200 |
| `7574cc5655805ea316011a8123b064917f06f83c` | ax200_arabic.rom | Yamaha_AX200 |
| `fcc385b90c65575e29fc009aa00b5120fc4c251a` | sfg-05.rom | Yamaha_AX200 |
| `f8cd4c05083decfc098cff077e055a4ae1e91a73` | ax350ii_arabic.rom | Yamaha_AX350II |
| `3a74e73b94d066b0187feb743c5eceddf0c61c2b` | ax350ii_swp.rom | Yamaha_AX350II |
| `688c1e790034205c36489ee90f2e9099bf6316ef` | ax350ii_sakhrfilespart.rom | Yamaha_AX350II |
| `ace202e87337fbc54fea21e22c0b3af0abe6f4ae` | ax350ii_painter.rom, ax350iif_painter.rom | Yamaha_AX350II, Yamaha_AX350IIF |
| `ebb76f9061e875365023523607db610f2eda1d26` | ax350ii_msx2sub.rom | Yamaha_AX350II |
| `358e69f427390041b5aa28018550a88f996bddb6` | ax350ii_disk.rom | Yamaha_AX350II |
| `5077b9c86ce1dc0a22c71782dac7fb3ca2a467e0` | ax350iif_arabic.rom | Yamaha_AX350IIF |
| `54ff13b58868018fcd43c916b8d7c7200ebdcabe` | ax350iif_swp.rom | Yamaha_AX350IIF |
| `4cbceba8f37f08272b612b6fc212eeaf379da9c3` | ax350iif_msx2sub.rom | Yamaha_AX350IIF |
| `bd0ad648d728c691fcee08eaaaa95e15e29c0d0d` | ax350iif_disk.rom | Yamaha_AX350IIF |
| `dd1b577ea3ea69de84a68d311261392881f9eac3` | ax500_basic-bios2.rom | Yamaha_AX500 |
| `92bac0b2995f54f0eebf167cd447361a6a4923eb` | ax500_arabic.rom | Yamaha_AX500 |
| `8674d000a52ec01fd80c8cb7cbaa66d4c3ca5cf7` | ax500_swp.rom | Yamaha_AX500 |
| `8e889999ecec302f05d3bd0a0f127b489fcf3739` | ax500_sakhr_files.rom | Yamaha_AX500 |
| `80872d997d18e1a633e70b9da35a0d28113073e5` | ax500_painter.rom | Yamaha_AX500 |
| `7f86af13e81259a0db8f70d8a7e026fb918ee652` | ax500_msx2sub.rom | Yamaha_AX500 |
| `a953bef071b603d6280bdf7ab6249c2e6f1a4cd8` | ax500_disk.rom | Yamaha_AX500 |
| `434651305f92aa770a89e40b81125fb22d91603d` | sfg-01.rom | Yamaha_CX11, Yamaha_CX5F, Yamaha_CX5M, Yamaha_CX5MU |
| `0dde59e8d98fa524961cd37b0e100dbfb42cf576` | cx5mii_basic-bios1.rom | Yamaha_CX5MII |
| `0ce800666c0d66bc2aa0b73a16f228289b9198be` | cx5mii_sub.rom | Yamaha_CX5MII |
| `7b1798561ee1844a7d6432924fbee9b4fc591c19` | cx5mii_fmvoicingprogramii.rom | Yamaha_CX5MII |
| `6680d7118d85418813f1db9449bf3e20942b16da` | sfg-05.rom | Yamaha_CX5MII, Yamaha_CX5MII_128, Yamaha_CX7M-128 |
| `ea4a723cf098be7d7b40f23a7ab831cf5e2190d7` | cx5mii-128_basic-bios1.rom | Yamaha_CX5MII_128 |
| `c2340313bfda751181e8a5287d60f77bc6a2f3e6` | cx5mii-128_sub.rom | Yamaha_CX5MII_128 |
| `30747a56f45389be76362f7fc55d673f1bff8312` | cx5mii-128_fmvoicingprogramii.rom, cx7m-128_fmvoicingprogramii.rom | Yamaha_CX5MII_128, Yamaha_CX7M-128 |
| `706dd67036baeec7127e4ccd8c8db8f6ce7d0e4c` | cx5m_basic-bios1.rom | Yamaha_CX5MU |
| `0f851ee7a1cf79819f61cc89e9948ee72a413802` | yis-503iiir_basic-bios2.rom, yis805-128r2_basic-bios2.rom | Yamaha_YIS-503IIIR, Yamaha_YIS-805-128R2 |
| `03bf6d2ac86f5c9ab618e155442787c700f99fed` | yis-503iiir_msx2sub.rom, yis805-128r2_msx2sub.rom | Yamaha_YIS-503IIIR, Yamaha_YIS-805-128R2 |
| `f4f7a54cdf5a9dd6c59f7cb219c2c5eb0a00fa8a` | yis-503iiir_cpm.rom | Yamaha_YIS-503IIIR |
| `807a823d4cac527c9f3758ed412aa2584c7f6d37` | yis-503iir_basic-bios.rom | Yamaha_YIS-503IIR |
| `41e056e33ee4f548f6af30257717bc40e3cf8238` | yis805-128r2_painter.rom, yis805-256_painter.rom | Yamaha_YIS-805-128R2, Yamaha_YIS-805-256 |
| `3a481c7b7e4f0406a55952bc5b9f8cf9d699376c` | yis805-128r2_disk.rom | Yamaha_YIS-805-128R2 |
| `609dbcbd2add28137e5c459d34cdb8012c8a1535` | yis805-256_basic-bios2.rom | Yamaha_YIS-805-256 |
| `5d04cfc0ee49aa012068a7050c4d912f402c08a7` | yis805-256_IC328.rom | Yamaha_YIS-805-256 |

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
                     [--output-dir OUTPUT_DIR] [--report REPORT] [--debug]

Process ROM and XML files

options:
  -h, --help            show this help message and exit
  --rom-dir ROM_DIR     Path to the ROM files directory (default: ROM)
  --xml-dir XML_DIR     Path to the XML files directory (default: Computer)
  --output-dir OUTPUT_DIR
                        Path to the output directory (default: MSX)
  --report REPORT       Text report of created and skipped packs (default:
                        OUTPUT_DIR/createComp_report.txt)
  --debug               Debug output
```

Jen některé počítače sestavíte tak, že `--xml-dir` nasměrujete na podsložku, například:

```
python createComp.py --xml-dir Computer/Philips --output-dir MSX/Philips
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

Na MiSTeru kopírujte do `/media/fat/games/MSX/`:

- obsah `MSX/` (složky výrobců s packy počítačů `.msx`) a jeden ze souborů `CART_FW_EN.msx` / `CART_FW_JP.msx`,
- `tools/CreateCRC/vampier.db` (databáze mapperů, viz [../CreateCRC/README.md](../CreateCRC/README.md)).

| Položka OSD | Soubor |
|---|---|
| **Load ROM PACK** | pack počítače `<Machine>.msx` |
| **Load FW PACK** | `CART_FW_EN.msx` nebo `CART_FW_JP.msx` |
| **Load DB MAPPERS** | `vampier.db`. Potřebný pro ROM cartridge větší než 64 kB nebo s mapperem; menší prosté ROM běží i bez něj |

Načtěte FW pack a pack počítače (a DB, pokud používáte velké ROM cartridge). Jádro při každém (opětovném) načtení znovu přečte všechny načtené soubory. MiSTer si pamatuje naposledy načtený pack počítače, FW pack a DB a při startu jádra je načte znovu automaticky. ROM cartridge, obrazy disket a kazety se automaticky nenačítají.

## Řešení potíží

**createComp zapíše pack počítače, jen když našel všechny jeho ROM.** Počítač s chybějící ROM pack nedostane a jeho pack z dřívějšího běhu se smaže. Report `MSX/createComp_report.txt` vypíše vytvořené packy a u každého počítače bez packu chybějící ROM (název souboru a SHA1). createDev FW pack bez chybějící firmwarové ROM pořád zapíše, viz níže.

### Zprávy v konzoli

| Zpráva | Význam a oprava |
|---|---|
| `<machine name>` (samostatný řádek) | XML bylo přečteno a pack se sestavuje. Následující řádky patří tomuto počítači. |
| `ROM SHA1 not found: <sha1> (ROM name: <file>) in slot s/ss` | Ve složce ROM není soubor s tímto SHA1. Doplňte správný dump (viz příloha A). |
| `ROM SHA1 not found: <sha1> (device KANJI)` | Chybí ROM s fontem KANJI. Týká se 31 počítačů s ROM fontu KANJI v příloze A. |
| `<machine name>: pack NOT written` | Některá ROM počítače chybí (řádky nad tím) nebo je jeho XML chybné. Pack se nezapíše, starý se smaže. |
| `Created N, not created M. Report: <soubor>` | Konec běhu. V reportu je seznam chybějících ROM po počítačích. |
| `WARNING:__main__:Missing ROM '<soubor>' for cartridge <NAME>. SHA1: ...` (createDev) | Firmwarová ROM rozšíření nenalezena (název souboru a cartridge podle `Extension/*.xml`, viz [Firmwarové ROM](#firmwarové-rom-pro-fw-pack)). Cartridge se vygeneruje bez své ROM: FM-PAC, GM2 a FDC cartridge nemají firmware, MoonSound v jádře skončí chybou `NOT FW CONF`. |
| `INFO:__main__:NAME: KONAMI index: 34` (createDev) | Běžná informační zpráva. Index je v šestnáctkové soustavě. |
| `Error: unknown ...`, `Unknown block elements`, `FW name: X SKIP. Not in cart_device.json`, `Device '<x>' nenalezeno` | Problém v XML nebo v tabulkách JSON (jen když jste je upravovali). Viz [DEVELOPERS.cs.md](DEVELOPERS.cs.md). |

### Chyby OSD v jádře

Po kterékoli z těchto zpráv se stroj nespustí: jádro zůstane v resetu do dalšího načtení. Odstraňte příčinu a načtěte znovu.

| Text OSD | Význam a oprava |
|---|---|
| BAD MSX CONF | Soubor načtený jako ROM PACK není pack počítače (například je to FW pack). |
| NOT SUPPORTED CONF | Pack obsahuje neznámý záznam. Sestavte pack nástroji ze stejné verze, jako je jádro. |
| NOT SUPPORTED BLOCK | Pack obsahuje typ bloku, který toto jádro nezná (pack vytvořený novějšími nástroji než jádro). Aktualizujte jádro nebo pack sestavte znovu. |
| BAD MSX FW CONF | Soubor načtený jako FW PACK není FW pack. |
| NOT FW CONF | Slot cartridge potřebuje FW pack, ale žádný není načten (včetně volby **Empty** a obyčejné ROM), nebo při sestavení FW packu chyběla ROM MoonSoundu `yrw801.rom`. Načtěte nebo znovu sestavte FW pack. |
| DEVICE MISSING | Počítač spolu s cartridgemi používá víc kopií zařízení, než jádro obsahuje (např. FM-PAC v obou slotech na stroji s MSX-MUSIC, MoonSound v obou slotech). Změňte výběr cartridgí. |
| Device not in this core build | FDC cartridge ve slotu B nebo pozice FDC, kterou tento build jádra nemá. |
| SMALL MEMORY | Počítač s cartridgemi potřebuje víc paměti, než je k dispozici (256 kB bez modulu SDRAM, jinak velikost modulu). |
| No CRC32 DB | Byla načtena ROM cartridge větší než 64 kB a není načtena žádná DB. Načtěte `vampier.db`. |
| Not find CRC32 in DB | ROM je větší než 64 kB a v DB není. Viz [../CreateCRC/README.md](../CreateCRC/README.md). |
| FDC already in machine | Počítač už má na dané pozici řadič disků. |
| ROM too big | ROM cartridge je větší než 16 MB. |

Počítač s vlastním řadičem disků plus FDC cartridge ve slotu A není chyba: vyhraje řadič počítače a cartridge se ignoruje.

## Vlastní počítač nebo rozšíření

Viz [DEVELOPERS.cs.md](DEVELOPERS.cs.md). Rozložení klávesnice: [../CreateKeyMap/README.md](../CreateKeyMap/README.md).
