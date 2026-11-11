import os
import zlib
import argparse

class InvalidFileSizeException(Exception):
    pass

def calculate_crc32(file_path):
    buf_size = 65536
    crc32 = 0

    with open(file_path, 'rb') as f:
        while chunk := f.read(buf_size):
            crc32 = zlib.crc32(chunk, crc32)

    return crc32 & 0xFFFFFFFF

def find_files(root_dir, extensions):
    for dirpath, _, filenames in os.walk(root_dir):
        for file in filenames:
            if any(file.endswith(ext) for ext in extensions):
                yield os.path.join(dirpath, file)

def analyze_rom(rom, offset, pages):
    if offset + 1 < len(rom) and (rom[offset] == ord('A') and rom[offset + 1] == ord('B')):
        offset += 2
        
        for i in range(4):
            if offset + 2 * i + 1 < len(rom):
                addr = rom[offset + 2 * i] + rom[offset + 2 * i + 1] * 256
                if addr:
                    page = (addr >> 14) - (offset >> 14)
                    if 0 <= page <= 2:
                        pages[page] += 1
    

def is_inside(address, window_base, window_size):
    return window_base <= address < window_base + window_size

def process_rom(file_name):
    with open(file_name, 'rb') as f:
        rom = bytearray(f.read())

    pages = [0, 0, 0]

    if len(rom) >= 0x0010:
        analyze_rom(rom, 0x0000, pages)
    if len(rom) >= 0x4010:
        analyze_rom(rom, 0x4000, pages)

    window_base = 0x0000
    window_size = 0x10000
    if not is_inside(0x0000, window_base, window_size):
        pages[0] = 0
    if not is_inside(0x4000, window_base, window_size):
        pages[1] = 0
    if not is_inside(0x8000, window_base, window_size):
        pages[2] = 0

    if pages[1] and (pages[1] >= pages[0]) and (pages[1] >= pages[2]):
        return 0x4000
    elif pages[0] and pages[0] >= pages[2]:
        return 0x0000
    elif pages[2]:
        return 0x8000

    return window_base

def get_mapper(file_path):
    file_size = os.path.getsize(file_path)

    # ASCII16-X ROMs carry their mapper name in the header (offset 16)
    with open(file_path, 'rb') as f:
        if f.read(24)[16:24] == b'ASCII16X':
            return "ASCII16-X"
    
    blocks = file_size // 16384
    if file_size % 16384 :
        blocks = blocks + 1 
    if file_size > 0x10000 :
        raise InvalidFileSizeException(f"Velikost souboru {file_size} je příliš velká pro mapper")
    
    start = process_rom(file_path)

    if start == 0x0000:
        return "0x0000"
    if start == 0x4000:
        return "0x4000"
    if start == 0x8000:
        return "0x8000"
        
    raise InvalidFileSizeException(f"Mapper neurcen. Velikost souboru {file_size} ")

def process_files(root_dir):
    file_extensions = ['.ROM', '.rom', '.BIN', '.bin']
    file_data = []

    for file_path in find_files(root_dir, file_extensions):
        file_name = os.path.basename(file_path)

        crc32_checksum = calculate_crc32(file_path)
        file_data.append((file_path, file_name, crc32_checksum))

    
    mappers = []
    for file_path, file_name, crc32_checksum in file_data:
        try:
            mapper_name = get_mapper(file_path)           
            if mapper_name :
                mappers.append(f"{crc32_checksum:08X}\t{mapper_name}\n")
            
        except InvalidFileSizeException as e:
                print(f"Chyba při zpracování souboru {file_name}: {e}")

    return mappers

def write_mappers_file(output_path, lines):
    
    unique_lines = list(set(lines))
    
    with open(output_path, 'w') as f:
        f.writelines(unique_lines)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Process ROM auto, Mirrored, Normal mappers and detect start")
    parser.add_argument('--rom-dir', type=str, default="c:/Project/_OBSAH/ROMS""",
                        help='Path to the ROM files directory (default: %(default)s)')
    parser.add_argument('--output', type=str, default="mappersOverride.txt",
                        help='Path to the output file (default: %(default)s)')

    args = parser.parse_args()

    lines = process_files(args.rom_dir)
    write_mappers_file(args.output, lines)
  
    print(f"Zpracování dokončeno. Seznam zapsán do {args.output}.")
