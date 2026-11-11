import os
import xml.etree.ElementTree as ET
import struct
import logging
import argparse
from tools import load_constants, find_files_with_sha1, find_xml_files, convert_to_int_or_string, get_int_or_string_value, convert_to_8bit, convert_to_int, get_device_param

# Nastavení logování
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ROM_DIR = 'ROM'
XML_DIR = 'Extension'
DIR_SAVE = 'MSX'

def create_block_entry(constants: dict, block_type: str, address: int, sha1: str = None, param1: int = 0, param2: int = 0, param3: int = 0, file_skip_bytes: int = 0, file_size: int = 0) -> dict:
    block_entry = {
        "typ": constants['conf']['BLOCK'],
        "address": address,
        "block_typ": constants['block'][block_type],
        "param1": param1,
        "param2": param2,
        "param3": param3
    }
    if sha1:
        block_entry['SHA1'] = sha1
        block_entry['file_size'] = file_size
        block_entry['file_skip_bytes'] = file_skip_bytes
        
    return block_entry

def parse_fw_block(root: ET.Element, subslot: int, files_with_sha1: dict, constants: dict, name: str = '') -> list:
    block = {}
    result = []
    start = int(root.attrib.get("start", 0))
    count = int(root.attrib.get("count", 4))
    offset = int(root.attrib.get("offset", -1))
    fix_offset = int(root.attrib.get("fix_offset", -1))

    dev_el = None
    for element in root:
        if element.tag in ['SHA1', 'filename', 'device', 'mapper', 'sram', 'ram', 'flash', 'extend', 'device_param']:
            block[element.tag] = get_int_or_string_value(element)
            if element.tag == 'ram' :
                pattern = 1;
            
            if element.tag == 'device' :
                dev_el = element
                device_port = convert_to_8bit(element.attrib.get('port'))
                device_mask = convert_to_8bit(element.attrib.get('mask'))
                device_param = convert_to_8bit(element.attrib.get('param','0'))

                if device_port is not None:
                    if device_mask is None:
                        device_mask = 0xFF             #Defaultni hodnota

            if element.tag == 'SHA1' :
                file_skip_bytes = convert_to_int(element.attrib.get('skip',0))
                file_size       = convert_to_int(element.attrib.get('size',0))

        else:
            logger.error(f"Tag name: {element.tag} SKIP. Not expected here")

    if count > 4 - start:
        count = 4 - start

    address = ((subslot & 3) << 4) | ((start & 3) << 2) | ((count - 1) & 3)

    if 'SHA1' in block:
        if block['SHA1'] in files_with_sha1:
            result.append(create_block_entry(constants, 'ROM', address, sha1=block['SHA1'], file_size=file_size, file_skip_bytes=file_skip_bytes))
        else:
            logger.warning(f"Missing ROM '{block.get('filename', '?')}' for cartridge {name}. SHA1: {block['SHA1']}")
    
    for tag in ('flash', 'extend'):
        # the memory loaded so far (cartridge ROM, ROM of the block) is extended to this size and the
        # rest filled with FF: a flash chip, or RAM behind a ROM (MoonSound sample memory)
        if tag in block:
            blocks = convert_to_int(block[tag]) // (1024 * 16)
            if 0 < blocks < 0x2000:
                result.append(create_block_entry(constants, 'FLASH', address, param1=blocks >> 8, param2=blocks & 0xFF))
            else:
                logger.warning("Flash / extend size not defined correctly")

    if 'ram' in block:
        size = convert_to_int(block['ram'])
        if size :
            result.append(create_block_entry(constants, 'RAM', address, param1=size//(1024 * 16), param2 = pattern)) # RAM v 16 kB blocích
        else :
            logger.warning("SRAM size not defined correctly")

    if 'mapper' in block:
        if block['mapper'] in constants['mapper']:
            param2 = 0
            if offset > -1 and offset < 4 :
                param2 = 0x80 + offset
            if fix_offset > -1 and fix_offset < 4 :
                param2 = 0x80 + 0x40 + fix_offset
            result.append(create_block_entry(constants, 'MAPPER', address, param1=constants['mapper'][block['mapper']], param2=param2))
        else:
            logger.warning(f"Unknown mapper type: {block['mapper']} see file mapper.json")

    if 'device' in block:
        if block['device'] in constants['device']:
            param_dev = block.get('device_param', 0)
            device_id = constants['device'][block['device']]
            param_dev = 0
            parameter = 0
            if dev_el is not None and dev_el.attrib:
                param_dev = get_device_param(constants, block['device'], dev_el.attrib)
                if dev_el.attrib.get('memory') == 'block':      # the device uses the memory of this block
                    parameter = 1

            result.append(create_block_entry(constants, 'DEVICE', address, param1=device_id, param2 = param_dev, param3=parameter))
            if device_port is not None:
                result.append(create_block_entry(constants, 'IO_DEVICE', address, param1=device_port, param2 = device_mask, param3 = device_param))
        else:
            logger.warning(f"Unknown device type: {block['device']}")
    
    if 'sram' in block:
        size = convert_to_int(block['sram'])
        if size :
            result.append(create_block_entry(constants, 'SRAM', address, param1=size//1024)) # SRAM v 1 kB
        else :
            logger.warning("SRAM size not defined correctly")

    return result

def parse_fw_secondary(root: ET.Element, subslot: int, files_with_sha1: dict, constants: dict, name: str = '') -> list:
    blocks = []
    for element in root:
        if element.tag == 'block':
            blocks.extend(parse_fw_block(element, subslot, files_with_sha1, constants, name))
    return blocks

def parse_fw(name: str, root: ET.Element, files_with_sha1: dict, constants: dict) -> list:
    results = []
    for element in root:
        if element.tag == 'secondary':
            slot = int(element.attrib["slot"])
            results.extend(parse_fw_secondary(element, slot, files_with_sha1, constants, name))
        elif element.tag == 'block':
            results.extend(parse_fw_block(element, 0, files_with_sha1, constants, name))
        elif element.tag == 'io_device':
            pass  # Placeholder for future extensions
        elif element.tag == 'expander':
            if element.text == 'expander_wo' :
                expander = 3
            else :
                expander = 1
            result = []
            result.append(create_block_entry(constants, 'EXPANDER', 0, param1=expander))
            results.extend(result)
        else:
            logger.warning(f"Tag name: {element.tag} SKIP. Not expected here")

    return results

def parse_fw_config(root: ET.Element, files_with_sha1: dict, constants: dict) -> dict:
    results = {}
    for element in root:
        if element.tag == 'fw':
            name = element.attrib["name"]
            if name not in constants['cart_dev']:
                logger.warning(f"FW name: {name} SKIP. Not in cart_device.json")
                continue
            results[name] = parse_fw(name, element, files_with_sha1, constants)
        else:
            logger.warning(f"Unknown tag: {element.tag} SKIP.")
            continue
    return results

def prepare_roms(config: dict, files_with_sha1: dict) -> dict:
    roms = {}
    start = 0
    id = 0
    try:
        with open('ROM.bin', 'wb') as rom_file:
            for key in config:
                for block in config[key]:
                    if 'SHA1' in block:
                        if block['SHA1'] not in roms:
                            filename = files_with_sha1[block['SHA1']]
                            file_size = block["file_size"]
                            file_skip_bytes = block["file_skip_bytes"]
                            
                            if file_size == 0 :
                                file_size = os.path.getsize(filename)
                            
                            file_blocks = (file_size + 16383) // 16384
                            with open(filename, 'rb') as source_file:
                                
                                if file_skip_bytes > 0:
                                    source_file.seek(file_skip_bytes)

                                data = source_file.read(file_size)

                                rom_file.write(data)
                                current_size = len(data)
                                padding_needed = ((current_size + 16383) // 16384) * 16384 - current_size
                                if padding_needed > 0:
                                    rom_file.write(b'\xff' * padding_needed)

                            rom_name = f'{block["file_skip_bytes"]}#{block["file_size"]}#' + block['SHA1']
                            roms[rom_name] = {"start": start, "blocks": file_blocks, "id": id}
                            id += 1
                            start += file_blocks * 16384
        return roms
    except IOError as e:
        logger.error(f"Error writing to ROM.bin: {e}")
        return {}

def set_address(address_array: bytearray, index: int, address: int):
    if index < 0 or index >= 256:
        raise ValueError("Index must be in the range 0 to 255.")
    
    start = index * 4
    address_array[start:start+4] = struct.pack('I', address)

def init_address(address_array: bytearray, addr: int):
    for i in range(256):
        set_address(address_array, i, addr)

def create_fw_config(config: dict, constants: dict, roms: dict) -> tuple:
    data = bytearray()
    address_array = bytearray(256 * 4)
    addr = 0x10 + len(address_array)
    init_address(address_array, addr)
    
    data += struct.pack('BBBBBB', constants['conf']['END'], 0, 0, 0, 0, 0)
    logger.info(f"CONF addr:{addr:04X} < {constants['conf']['END']:02X} 00 00 00 00 00") 
    addr += 6

    for key in config:
        logger.info(f"NAME: {key} index: {constants['cart_dev'][key]:02X}")
        set_address(address_array, constants['cart_dev'][key], addr)
        
        for conf in config[key]:
            conf['param1'] = conf.get('param1', 0)
            conf['param2'] = conf.get('param2', 0)
            conf['param3'] = conf.get('param3', 0)

            if conf['typ'] == constants['conf']['BLOCK'] and conf['block_typ'] == constants['block']['ROM']:
                if 'SHA1' in conf :
                    sha1_name = f'{conf["file_skip_bytes"]}#{conf["file_size"]}#' + conf['SHA1']
                    if sha1_name in roms:
                        conf['param1'] = roms[sha1_name]['id']
                        conf['param2'] = (roms[sha1_name]['blocks'] >> 8) & 0xff
                        conf['param3'] = roms[sha1_name]['blocks'] & 0xff
                    else:
                        logger.warning(f"Missing SHA1 in ROM configuration or SHA1 not found in ROMs: {conf}")
                        continue

            # Formátování číselných parametrů pro logování
            param1_str = f"{conf['param1']:02X}" if isinstance(conf['param1'], int) else str(conf['param1'])
            param2_str = f"{conf['param2']:02X}" if isinstance(conf['param2'], int) else str(conf['param2'])
            param3_str = f"{conf['param3']:02X}" if isinstance(conf['param3'], int) else str(conf['param3'])

            logger.info(f"CONF addr:{addr:04X} < {conf['typ']:02X} {conf['address']:02X} {conf['block_typ']:02X} {param1_str} {param2_str} {param3_str}") 
            data += struct.pack('BBBBBB', conf['typ'], conf['address'], conf['block_typ'], conf['param1'], conf['param2'], conf['param3'])
            addr += 6
        data += struct.pack('BBBBBB', constants['conf']['END'], 0, 0, 0, 0, 0)
        addr += 6
    
    return address_array, data, addr

def save_fw_config(config: dict, file_name: str, path: str, files_with_sha1: dict, constants: dict, roms: dict, table: bytearray, data: bytearray, rom_start_addr: int):
    file_path = os.path.join(DIR_SAVE, path)
    os.makedirs(file_path, exist_ok=True)
    file_path = os.path.join(file_path, file_name + '.msx')
    
    try:
        with open(file_path, "wb") as outfile:
            head = struct.pack('BBBBI', ord('M'), ord('s'), ord('X'), 0, rom_start_addr)
            outfile.write(head)
            outfile.write(b'\x00' * 8)
            outfile.write(table)
            outfile.write(data)
    
            addr_rom_start = rom_start_addr + 4 * len(roms)
            rom_table = bytearray()

            for rom in roms:
                rom_table += struct.pack('I', addr_rom_start + roms[rom]['start'])

            outfile.write(rom_table)
    
            with open('ROM.bin', 'rb') as rom_file:
                rom_content = rom_file.read()

            outfile.write(rom_content)
            os.remove('ROM.bin')
    except IOError as e:
        logger.error(f"Error saving MSX config to {file_path}: {e}")

def create_fw_conf(file_name: str, path: str, files_with_sha1: dict, constants: dict):
    file_path = os.path.join(XML_DIR, path, file_name + '.xml')
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        if root.tag != "fwConfig":
            logger.warning(f"File {file_path} is not a valid msxConfig XML. Skipping.")
            return
        
        config = parse_fw_config(root, files_with_sha1, constants)
        roms = prepare_roms(config, files_with_sha1)
        table, data, rom_start_addr = create_fw_config(config, constants, roms)
        save_fw_config(config, file_name, path, files_with_sha1, constants, roms, table, data, rom_start_addr)

    except (ET.ParseError, FileNotFoundError) as e:
        logger.error(f"Error processing file {file_path}: {e}")

if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description=f"Build the cartridge FW packs: {XML_DIR}/*.xml -> {DIR_SAVE}/<name>.msx. "
                    "Run from the CreateMSXpack directory (JSON tables are read from the current directory).")
    parser.add_argument('--rom-dir', type=str, default=ROM_DIR,
                        help='Path to the ROM files directory, searched recursively, files matched by SHA1 (default: %(default)s)')
    args = parser.parse_args()

    if not os.path.isdir(args.rom_dir):
        parser.error(f"ROM directory not found: {args.rom_dir}")

    files_with_sha1 = find_files_with_sha1(args.rom_dir)
    constants = load_constants()

    xml_files = find_xml_files(XML_DIR)

    for file_name, path in xml_files:
        print(f"NAME: {file_name}")
        create_fw_conf(file_name, path, files_with_sha1, constants)
