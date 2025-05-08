# MSX1/MSX2 for [MiSTer Board](https://github.com/MiSTer-devel/Main_MiSTer/wiki)

# Features MSX1
- Reference HW Philips VG8020/00
- RAM 64kB in slot 3
- Sound YM2149(PSG)
- Support two cartridges
- Automatic detect cartridge mapper. (Konami, Konami SCC, ASCII8, ASCII16, Linear64k) 
- Manual select mapper (R-TYPE)
- Joystick.
- FDD support (VY0010). Use DSK image
- Cassette support. Analog or CAS emulation
- PAL/NTSC mode
- Load bios for experiments

## Memory limitations
- No SDRAM 
  - Slot 1 ROM image max size 128kB
  - Slot 2 ROM image max size  64kB
  - Slot 3 64Kb RAM
- 32MB SDRAM
  - Slot 1 ROM image max size 1MB
  - Slot 2 ROM image max size 2MB
  - Slot 3 64Kb RAM
- 64MB SDRAM
  - Slot 1 ROM image max size 2MB
  - Slot 2 ROM image max size 4MB
  - Slot 3 64Kb RAM
- 128MB SDRAM
  - Slot 1 ROM image max size 4MB
  - Slot 2 ROM image max size 4MB
  - Slot 3 64Kb RAM

## ROM BIOS
Load them manually from the menu

# Features MSX2
- Reference HW Philips VG8240/00
- RAM in slot 3/2
- Sound YM2149(PSG)
- Video V9938
- Support two cartridges
- Cartridge emulation (ROM, SCC, SCC+, FM-PAC, Gamemaster2)
- Automatic detect cartridge mapper. (Konami, Konami SCC, ASCII8, ASCII16, Linear64k) 
- Manual select mapper (R-TYPE)
- Joystick.
- FDD support.
- RTC support
- Cassette support. Analog or CAS emulation
- PAL/NTSC mode
- Load bios for experiments

## Memory limitations
- No SDRAM 
  - Slot 1 ROM image max size 128kB
  - Slot 2 ROM image max size  64kB
  - Slot 3/2 64Kb RAM
- 32MB SDRAM
  - Slot 1 ROM image max size 1MB
  - Slot 2 ROM image max size 2MB
  - Slot 3/2 512Kb RAM
- 64MB SDRAM
  - Slot 1 ROM image max size 2MB
  - Slot 2 ROM image max size 4MB
  - Slot 3/2 512Kb RAM
- 128MB SDRAM
  - Slot 1 ROM image max size 4MB
  - Slot 2 ROM image max size 4MB
  - Slot 3/2 512Kb RAM

## ROM BIOS
Copy bios files to Games/MSX1 folder or load them manually from the menu
- BIOS files use the `.MSX` file extension.
- Use the script `tools/CreateMSXPack/createMSXpack.py` to generate them.
- Refer to the XML files in the `Computer` and `Extension` directories to determine which BIOS ROM files are needed.
- Copy the required ROM files into the `tools/CreateMSXPack/ROM` directory.
- Then, run the `createMSXpack.py` script.
- The generated `.MSX` files will be located in the `tools/CreateMSXPack/MSX` directory.
