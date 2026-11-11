# MSX1/MSX2 for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

> [!CAUTION]
> **WIP Notice**: This core is currently in **WIP (Work in Progress)** status. Some components are still under development and may include debug outputs or experimental features. Certain functionalities may not yet work 100% as intended.

## MSX1 Core Overview
The MSX1 core is not a direct synthesis of a specific MSX computer model. Instead, it provides a **dynamically configurable hardware environment** based on a selected definition and configuration file. Each MSX model definition includes not only the hardware setup but also the corresponding **ROM binary content.**

For full functionality, the core also relies on an **extension module configuration,** which includes additional ROM binaries. This configuration is **independent of any specific MSX model**, allowing support for:
- Multiple language variants (via localized ROMs)
- Easy future expansion with new hardware extensions

The final configuration file is a **CRC32-based ROM database**, which maps known ROM checksums to their correct mapper types. This allows the core to automatically select the appropriate ROM mapper for each loaded image.

## Supported MSX Models
[The following MSX computer models are currently supported by the MSX1 core through configuration definitions](https://github.com/MiSTer-devel/MSX1_MiSTer/blob/main/ComputersModel.md)

## Supported Hardware Components
The MSX1 core includes support for the following hardware modules:
- `PPI` – [Programmable Peripheral Interface](https://www.msx.org/wiki/Programmable_Peripheral_Interface)
- `RTC` – [Real-Time Clock](https://www.msx.org/wiki/Programmable_Peripheral_Interface)
- `PSG` – [Programmable Sound Generator](https://www.msx.org/wiki/Category:PSG)
- `VDP` – [Video Display Processor (TMS family)](https://www.msx.org/wiki/Texas_Instruments_TMS9918)
- `VDP` – Yamaha [V9938](https://www.msx.org/wiki/Yamaha_V9938) / [V9939](https://www.msx.org/wiki/Yamaha_V9939)
- `KANJI` – [Kanji Display Support](https://www.msx.org/wiki/Kanji_display)
- `FDD` – Floppy Disk Drive
- `WD2793` – Floppy Disk Controller (read-only support)
- `OPM` – [FM Operator Type-M (YM2151)](https://www.msx.org/wiki/Category:OPM)
- `OPLL` – [FM Operator Type-LL (YM2413)](https://www.msx.org/wiki/Category:OPLL)
- `SCC` – [Konami Sound Custom Chip](https://www.msx.org/wiki/Konami_SCC)
- `SCC+` – [Konami 052539 Enhanced SCC](https://www.msx.org/wiki/Konami_052539)
- `OPL4` – [Yamaha YMF278B](https://www.msx.org/wiki/MoonSound) (MoonSound: OPL3 FM and 24 channel wave table synthesis)
- `MIDI IN` – YM2148 MIDI Interface
- `SFG01` - [YAMAHA SFG01](https://www.msx.org/wiki/Yamaha_SFG-01) 
- `SFG05` - [YAMAGA SFG05](https://www.msx.org/wiki/Yamaha_SFG-05)

## Supported ROM Mappers
The MSX1 core supports the following ROM mapping types:
- `ASCII8` – ASCII 8KB mapper
- `ASCII16` – ASCII 16KB mapper
- `ASCII16-X` – [ASCII16-X](https://www.grauw.nl/projects/ascii-x/ascii16-x/) mapper with an 8 MB flash ROM (changes are not saved)
- `RTYPE` – R-Type mapper
- `CrossBlaim` – Cross Blaim specific mapper
- `generic8k` – Generic 8KB ROM mapper
- `generic16k` – Generic 16KB ROM mapper
- `harryFox` – Harry Fox specific mapper
- `konami` – Standard Konami mapper
- `konami_scc` – Konami SCC mapper
- `national` – National mapper
- `zemina80` – Zemina 80KB mapper
- `zemina90` – Zemina 90KB mapper
These mappers ensure compatibility with a wide range of MSX ROMs, including commercial games, utilities, and homebrew software.

## Supported Expansion Cartridges
The MSX1 core also supports the following types of expansion cartridges:
- `ROM` – Standard ROM cartridge support
- `Floppy` – Floppy disk interface cartridges
- `SCC` – Konami SCC sound cartridges
- `SCC+` – Enhanced SCC+ cartridges
- `FM-PAC` – FM-PAC sound module cartridges
- `MEGARAM` – MegaRAM memory expansion
- `Mega Flash ROM SCC SD` – Flash ROM cartridge with SCC and SD card support
- `Game Master 2` – Konami Game Master 2
- `MoonSound` – OPL4 sound cartridge with 2 MB of sample RAM (the FW pack must contain `yrw801.rom`)

## MiSTerFPGA Platform Support
The MSX1 core integrates with MiSTerFPGA and supports the following features provided by the platform:
- `Joystick input` – Direct support for MiSTer-compatible joysticks
- `Keyboard input` – Customizable key mappings through model-specific configuration definitions
- `Cassette emulation or analog input` – Support for tape loading via audio input or digital emulation
- `SDRAM support` – Utilizes external SDRAM for extended memory requirements


## Creating Configurations for Computer Models and Expansion Modules
To generate configurations for MSX models and expansion modules, follow these steps:
1. Ensure **Python 3** is installed on your system.
2. Navigate to the tools/CreateMSXpack directory in this project.
3. Prepare a directory containing the required ROM binary files. By default, this directory is named ROM.
4. To create a configuration for MSX computers, run: ```python3 createComp.py```  
Use `python3 createComp.py --help` to see options for specifying custom paths.
5. To create a configuration for expansion modules, run: ```python3 createDev.py```  
6. Place the resulting .MSX configuration files into your MiSTer at: `/media/fat/games/MSX1/`

## License
This core is licensed under the GNU General Public License, version 3 or later
(see `LICENSE`, `SPDX-License-Identifier: GPL-3.0-or-later` in the source headers).
Parts taken from other projects keep their own licenses, as stated in their file headers
(e.g. the MiSTer framework in `sys/`, the X68000_MiSTer FDC modules under GPL-3.0, the
ESE / OCM-PLD derived files, the T80 / TV80 CPU and VDP cores).
