import os
import xml.etree.ElementTree as ET
import struct
import base64
import argparse
from tools import load_constants, find_files_with_sha1, find_xml_files, convert_to_int_or_string, get_int_or_string_value, convert_to_int, convert_to_8bit, get_device_param

ROM_DIR = 'ROM'
XML_DIR_COMP = 'Computer'
DIR_SAVE = 'MSX'

def parse_msx_block(root):
    """
    Parses a 'block' element from the XML and returns a dictionary with its properties.
    
    :param root: XML element <block>
    :return: Dictionary with block details.
    """
    result = {}
    start = convert_to_int_or_string(root.attrib.get("start", 0))
    count = convert_to_int_or_string(root.attrib.get("count", None))
    
    for element in root:
        value = (get_int_or_string_value(element), element.attrib)

        if element.tag not in result:
            result[element.tag] = value
        else:
            if isinstance(result[element.tag], tuple):
                result[element.tag] = [result[element.tag], value]
            else:
                result[element.tag].append(value)
    
    # Adjust the count to not exceed the limit
    if 'count' in  result :
        if count is not None:
            print("Error, block contain multiple count")
        else :
            count = result['count']
    else :
        if count is None:
            count = 4

    if count > 4 - start:
        count = 4 - start

    result['block_start'] = start
    result['block_count'] = count
    return result

def parse_msx_secondary(root):
    """
    Parses a 'secondary' element from the XML and returns a dictionary with the parsed blocks.

    :param root: XML element <secondary>
    :return: Dictionary containing 'block' key with list of blocks.
    """
    blocks = [parse_msx_block(element) for element in root if element.tag == 'block']
    return {'block': blocks}

def parse_msx_primary(root):
    """
    Parses a 'primary' element from the XML and returns a dictionary with its sub-elements.

    :param root: XML element <primary>
    :return: Dictionary containing parsed blocks and secondary slots.
    """
    results = {}
    expander = 0
    for element in root:
        if element.tag == 'secondary':
            slot = convert_to_int_or_string(element.attrib["slot"])
            if slot > 0 : 
                expander = 1
            results.setdefault('secondary', {})[slot] = parse_msx_secondary(element)
        elif element.tag == 'block':
            results.setdefault('block', []).append(parse_msx_block(element))
        else:
            print(f"Processing unknown element: {element.tag}")
    
    if root.tag == 'primary':
        expander_en = convert_to_int(root.attrib.get("expander",'0'))
        expander_wo = convert_to_int(root.attrib.get("expander_wo",'0'))
        expander_init = convert_to_8bit(root.attrib.get("expander_init",'0'))
        if expander > 0:
            expander_en = 1
        if expander_en > 0:
            expander = expander_wo << 1 | expander_en
            if 'secondary' in results: 
                for slot, slot_data in results['secondary'].items():
                    if 'block' in slot_data :
                        slot_data['block'].append({'expander': (expander, expander_init)})
                        break
            else :
                results['block'].append({'expander': (expander, expander_init)})
            
    return results

def parse_msx_config(root):
    """
    Parses the entire <msxConfig> XML root element.

    :param root: Root XML element <msxConfig>.
    :return: Dictionary with parsed configuration.
    """
    results = {}
    devices = []
    for element in root:
        if element.tag == 'primary':
            slot = convert_to_int_or_string(element.attrib["slot"])
            results.setdefault('primary', {})[slot] = parse_msx_primary(element)
        else:
            value = get_int_or_string_value(element)
            if value:
                if element.tag == 'device' :
                    devices.append((value, element.attrib))
                else :
                    results[element.tag] = (value, element.attrib)

    if len(devices) > 0:
        results['devices'] = devices

    return results

def create_msx_config_header(config, outfile):
    #type, video_standard,
    """
    Writes the MSX configuration header to the output file.
    :param config: Config data
    :param outfile: Opened file object for writing.
    """
    
    #.get('type', ('MSX1',{})), config.get('video_standard', ('PAL',{}))
    cpu = config.get('cpu', ('Z80',{}))[0]
    wait_count = convert_to_int(config.get('wait_count', ('0',{}))[0])
    cpu_frequency = convert_to_int(config.get('cpu_frequency', ('0',{}))[0])
    conf = 0
    
    #CPU variants
    if cpu == 'Z80' :
        conf = conf | 0x00
    elif cpu == 'R800' :
        conf = conf | 0x40

    #Wait states
    conf = conf | (wait_count & 0x7) << 3
    
    #CPU frequency
    conf = conf | (cpu_frequency & 0x7)

    data = struct.pack('BBBBBBBB', ord('M'), ord('S'), ord('x'), conf, 0, 0, 0, 0)
    outfile.write(data)

def add_block_type_to_file(address, typ, params, outfile, constants):
    """
    Writes a one block configuration to the output file

    :param address: Block address {slot, subslo, block_start, block_count} 
    :param typ: Type of block.
    :param params: List parameters.
    :param outfile: Opened file object for writing.
    :param constants: Dictionary with configuration constants.
    """
    block_type = constants['block'][typ]
    data = struct.pack('BBBBBBBB', constants['conf']['BLOCK'], address, block_type, params[0], params[1], params[2], params[3], params[4])
    if debug_output:
        print(f"BLOCK: {constants['conf']['BLOCK']} {address:02X} {block_type:02X} {params[0]:02X} {params[1]:02X} {params[2]:02X} {params[3]:02X} {params[4]:02X} {address >> 6}/{(address >> 4) & 3}/{(address >> 2) & 3} block_count: {((address&3)+1)} {typ}({block_type})")
    outfile.write(data)
    
    for i in range(len(params)):
        params[i] = 0
    
def create_msx_config_block(slot, subslot, blocks, outfile, files_with_sha1, constants):
    """
    Writes a block configuration to the output file, including any ROM data if applicable.

    :param slot: Slot number.
    :param subslot: Subslot number.
    :param blocks: List of block configurations.
    :param outfile: Opened file object for writing.
    :param files_with_sha1: Dictionary of files with their SHA1 hashes.
    :param constants: Dictionary with configuration constants.
    """
    for block in blocks:
        params = [0] * 5

        if 'expander' in block:
            address = (slot & 3) << 6
            (params[0], params[1]) = block['expander']
            add_block_type_to_file(address, 'EXPANDER', params, outfile, constants)
            continue

        address = ((slot & 3) << 6) | ((subslot & 3) << 4) | ((block['block_start'] & 3) << 2) | ((block['block_count'] - 1) & 3)
        if 'memory' in block:
            (typ, attributes) = block.pop('memory', (None, None)) 
            if typ == 'ROM' :
                filename = None	
                if 'exactFilename' in attributes: 
                    filename = attributes['exactFilename']
                elif 'SHA1' not in attributes:
                    print(f"Missing SHA1 for ROM in slot {slot}/{subslot}")               
                elif attributes['SHA1'] not in files_with_sha1:
                    print(f"ROM SHA1 not found: {attributes['SHA1']} (ROM name: {attributes['filename']}) in slot {slot}/{subslot}")
                else :
                    filename = files_with_sha1[attributes['SHA1']]
                
                if filename:
                    file_size = os.path.getsize(filename)
                    file_skip_bytes = 0
                    if 'skip' in attributes:
                        file_skip_bytes = convert_to_int(attributes['skip'])
                    if 'size' in attributes:
                        file_size = convert_to_int(attributes['size'])
                    
                    params[0] = (file_size + 16383) // 16384
                    add_block_type_to_file(address, typ, params, outfile, constants)

                    with open(filename, 'rb') as source_file:
                        if file_skip_bytes > 0:
                            source_file.seek(file_skip_bytes)

                        data = source_file.read(file_size)
                        outfile.write(data)
                        current_size = len(data)
                        padding_needed = ((current_size + 16383) // 16384) * 16384 - current_size
                        if padding_needed > 0:
                            outfile.write(b'\xff' * padding_needed)

                    filename = None
            elif typ == 'RAM' :
                if "size" in attributes :
                    value = convert_to_int(attributes["size"])
                    if value :
                        params[0] = (value // 16384) & 0xFF
                    else :
                        print(f"RAM size not integer : {attributes['size']} in slot {slot}/{subslot}")
                else :
                    params[0] = block['block_count']

                pattern = 1
                if "pattern" in attributes :
                    value = convert_to_int(attributes["pattern"])
                    if value :
                        pattern = value
                        
                params[1] = pattern
                add_block_type_to_file(address, typ, params, outfile, constants)
            else :
                print(f"memory type {typ} unknown in slot {slot}/{subslot}") 
        
        if 'shared_memory' in block:
            (typ, attributes) = block.pop('shared_memory', (None, None))
            if typ == 'ROM' :
                ro = 1
            else:
                ro = 0

            if "offset" in attributes :
                offset = convert_to_int(attributes["offset"])
            else :
                offset = 0

            if "size" in attributes :
                size = convert_to_int(attributes["size"])
            else :
                print(f"Error: missing attribut 'size' in shared_memory '{typ}' in slot {slot}/{subslot}") 
                return
            
            ref = 0

            if "slot" in attributes :
                ref = (convert_to_int(attributes["slot"]) & 3) << 4
            else :
                print(f"Error: missing attribut 'slot' in shared_memory '{typ}' in slot {slot}/{subslot}") 
                return
            
            if "subslot" in attributes :
                ref = ref | ((convert_to_int(attributes["subslot"]) & 3) << 2)
            else :
                print(f"Error: missing attribut 'subslot' in shared_memory '{typ}' in slot {slot}/{subslot}") 
                return
            
            if "block" in attributes :
                ref = ref | (convert_to_int(attributes["block"]) & 3)
            else :
                print(f"Error: missing attribut 'block' in shared_memory  '{typ}' in slot {slot}/{subslot}") 
                return

            params[0] = ref
            params[1] = (offset // 16384) & 0xFF
            params[2] = (size // 16384) & 0xFF
            params[3] = ro
            add_block_type_to_file(address, "SHARED_MEM", params, outfile, constants)

        if 'mapper' in block:
            (typ, attributes) = block.pop('mapper', (None, None))
            if typ in constants['mapper'] :
                params[0] = constants['mapper'][typ]
                # mapper parameter (DRAM: first 16 KB page of the top 64 KB of the main RAM)
                if attributes and 'param' in attributes :
                    params[1] = (convert_to_int(attributes['param']) & 3) << 2
                add_block_type_to_file(address, "MAPPER", params, outfile, constants)
            else :
                print(f"Error: unknown mapper '{typ}' in slot {slot}/{subslot}")  
        
        if 'cart' in block:
            (typ, attributes) = block.pop('cart', (None, None))
            value = None
            if typ == 'A' or typ == 'a' or typ == '0':
                value = 0
            elif typ == 'B' or typ == 'b' or typ == '1' :
                value = 1
            else :
                print(f"Error: unknown identify CART '{typ}' in slot {slot}/{subslot}")

            if value is not None:
                params[0] = value
                add_block_type_to_file(address, "SLOT", params, outfile, constants)
        if 'device' in block:
            device = block.pop('device')
            if isinstance(device, tuple):
                device = [device]
            
            for (typ, attributes) in device:
                if typ in constants['device']:
                    
                    device_param = get_device_param(constants, typ, attributes)

                    params[0] = constants['device'][typ]
                    params[1] = device_param

                    add_block_type_to_file(address, "DEVICE", params, outfile, constants)

                    device_mask = None
                    device_port = None
                    if "mask" in attributes:
                        device_mask = convert_to_8bit(attributes['mask'])
                    if "port" in attributes:
                        device_port = convert_to_8bit(attributes['port'])
                        if device_mask is None:
                            device_mask = 0xFF  #Default value
                        params[0] = device_port
                        params[1] = device_mask
                        params[2] = device_param
                        add_block_type_to_file(address, "IO_DEVICE", params, outfile, constants)
                else :
                    print(f"Error: unknown device '{typ}' in slot {slot}/{subslot}") 
        
        if 'ref' in block:
            (typ, attributes) = block.pop('ref', (None, None))
            if typ == "DEVICE" :
                if "to_block" in attributes :
                    value = convert_to_int(attributes["to_block"])
                    if value is not None:
                        params[0] = value & 3
                        add_block_type_to_file(address, "REF_DEV", params, outfile, constants)
                    else :
                        print(f"Error: reference type '{typ}' value to_block is not integger in slot {slot}/{subslot}") 
                else :
                    print(f"Error: reference type '{typ}' missing value to_block in slot {slot}/{subslot}") 
            elif typ == "MEMORY" :
                if "to_block" in attributes :
                    value = convert_to_int(attributes["to_block"])
                    if value is not None:
                        params[0] = value & 3
                        add_block_type_to_file(address, "REF_MEM", params, outfile, constants)
                    else :
                        print(f"Error: reference type '{typ}' value to_block is not integger in slot {slot}/{subslot}") 
                else :
                    print(f"Error: reference type '{typ}' missing value to_block in slot {slot}/{subslot}") 

            else :
                print(f"Error: unknown reference type '{typ}' in slot {slot}/{subslot}") 
        
        
        del block['block_start']
        del block['block_count']
        if block:
            print (f"Unknown block elements {block}")
        
        
 

      #  elif block['type'] == 'REF_DEV':
      #      print(f"slot {slot}/{subslot}")
      #      print(block)
      #      params[0] = block.get('block_ref', None)
           
      #  else:
      #      print(f"Error: unknown type '{block['type']}' in slot {slot}/{subslot}")

      #  data = struct.pack('BBBBBBBB', constants['conf']['BLOCK'], address, block_type, params[0], params[1], params[2], params[3], params[4])
      #  print(f"BLOCK: {constants['conf']['BLOCK']} {address:02X} {block_type:02X} {params[0]:02X} {params[1]:02X} {params[2]:02X} {params[3]:02X} {params[4]:02X} {block['type']} block_count: {block['count']}")
      #  outfile.write(data)

      #  if filename:
      #      with open(filename, 'rb') as source_file:
      #          data = source_file.read()
      #          outfile.write(data)
      #          current_size = len(data)
      #          padding_needed = ((current_size + 16383) // 16384) * 16384 - current_size
      #          if padding_needed > 0:
      #              outfile.write(b'\xff' * padding_needed)

def create_msx_config_subslot(slot, secondary, outfile, files_with_sha1, constants):
    """
    Writes the configuration for a subslot to the output file.

    :param slot: Slot number.
    :param secondary: Secondary slot configuration.
    :param outfile: Opened file object for writing.
    :param files_with_sha1: Dictionary of files with their SHA1 hashes.
    :param constants: Dictionary with configuration constants.
    """
    for subslot, subslot_data in secondary.items():
        if 'block' in subslot_data:
            create_msx_config_block(slot, subslot, subslot_data['block'], outfile, files_with_sha1, constants)

def create_msx_config_primary(primary, outfile, files_with_sha1, constants):
    """
    Writes the configuration for the primary slots to the output file.

    :param primary: Primary slot configuration.
    :param outfile: Opened file object for writing.
    :param files_with_sha1: Dictionary of files with their SHA1 hashes.
    :param constants: Dictionary with configuration constants.
    """
    for slot, slot_data in primary.items():
        if 'block' in slot_data:
            create_msx_config_block(slot, 0, slot_data['block'], outfile, files_with_sha1, constants)
        elif 'secondary' in slot_data:
            create_msx_config_subslot(slot, slot_data['secondary'], outfile, files_with_sha1, constants)

def create_msx_config_kbd_layout(layout, outfile, constants):
    """
    Writes the configuration for the kezboard layout to the output file.

    :param layout: Base64 encoded layout
    :param outfile: Opened file object for writing.
    :param constants: Dictionary with configuration constants.
    """
    if layout and layout[0]:
        data = struct.pack('BBBBBBBB', constants['conf']['KEYBOARD_LAYOUT'], 0, 0, 0, 0, 0, 0, 0)
        outfile.write(data)
        outfile.write(base64.b64decode(layout[0]))

def create_msx_config_device(device, outfile, files_with_sha1, constants):
    for (device, parameters) in device :
        port = 0
        port_mask = 0
        rom_data = 0
        rom_size = 0
        rom_skip = 0
        param = 0
        filename = None
        
        if 'ROM_SHA1' in parameters : 
            if parameters['ROM_SHA1'] not in files_with_sha1 :
                raise Exception(f"ROM missing! SHA1 {parameters['ROM_SHA1']} not find. Computer SKIP")

            filename = files_with_sha1[parameters['ROM_SHA1']]
            if filename:
                if 'rom_skip' in parameters : rom_skip  = convert_to_int(parameters['rom_skip'])
                rom_size = os.path.getsize(filename) - rom_skip
                if 'rom_size' in parameters : rom_size  = convert_to_int(parameters['rom_size'])

        # Device memory as a window into an existing block (shared_slot/subslot/block/offset/size):
        # byte 6 = 0x80 | slot<<4 | subslot<<2 | block, byte 7 = offset, byte 5 = size (16 kB units)
        shared_ref = 0
        shared_offset = 0
        if 'shared_slot' in parameters :
            for attr in ('shared_subslot', 'shared_block', 'shared_size') :
                if attr not in parameters :
                    raise Exception(f"Device '{device}': missing attribute '{attr}'")
            shared_ref = (0x80
                          | ((convert_to_int(parameters['shared_slot']) & 3) << 4)
                          | ((convert_to_int(parameters['shared_subslot']) & 3) << 2)
                          | (convert_to_int(parameters['shared_block']) & 3))
            shared_offset = convert_to_int(parameters.get('shared_offset', '0')) // 16384
            rom_size = convert_to_int(parameters['shared_size'])

        if 'mask'     in parameters : port_mask = convert_to_8bit(parameters['mask'])
        if 'port'     in parameters : port      = convert_to_8bit(parameters['port'])
        #if 'param'    in parameters : param     = convert_to_8bit(parameters['param'])
        
        param = get_device_param(constants, device, parameters)
        size = (rom_size + 16383) // 16384
        
        if device not in constants['device'] :
            print(f"Device '{device}' nenalezeno. Zkontroluj device.json")
            continue       
        
        data = struct.pack('BBBBBBBB', constants['conf']['DEVICE'], constants['device'][device], port, port_mask, param, size, shared_ref, shared_offset & 0xFF)
        if debug_output:
            print(f"DEVIC: {constants['conf']['DEVICE']} {constants['device'][device]:02X} {port:02X} {port_mask:02X} {param:02X} {size:02X} {shared_ref:02X} {shared_offset & 0xFF:02X}")
        outfile.write(data)

        if filename:
            with open(filename, 'rb') as source_file:
                if rom_skip > 0:
                    source_file.seek(rom_skip)

                data = source_file.read(rom_size)
                outfile.write(data)
                current_size = len(data)
                padding_needed = ((current_size + 16383) // 16384) * 16384 - current_size
                if padding_needed > 0:
                    outfile.write(b'\xff' * padding_needed)
        

def create_msx_config(config, file_name, path, files_with_sha1, constants, outpt_dir):
    """
    Creates the MSX configuration file based on the parsed configuration data.

    :param config: Parsed MSX configuration.
    :param file_name: Output file name.
    :param path: Output file path.
    :param files_with_sha1: Dictionary of files with their SHA1 hashes.
    :param constants: Dictionary with configuration constants.
    """
    file_path = os.path.join(outpt_dir, path)
    os.makedirs(file_path, exist_ok=True)
    file_path = os.path.join(file_path, file_name + '.msx')
    
    try:
        with open(file_path, "wb") as outfile:
            #create_msx_config_header(config.get('type', ('MSX1',{})), config.get('video_standard', ('PAL',{})), outfile)
            create_msx_config_header(config, outfile)
            # Devices with memory in a shared block go after the slots: the block must exist first
            devices = config.get('devices', [])
            create_msx_config_device([d for d in devices if 'shared_slot' not in d[1]], outfile, files_with_sha1, constants)
            create_msx_config_primary(config.get('primary', {}), outfile, files_with_sha1, constants)
            create_msx_config_device([d for d in devices if 'shared_slot' in d[1]], outfile, files_with_sha1, constants)
            create_msx_config_kbd_layout(config.get('kbd_layout', None), outfile, constants) 
    except Exception as e:
        print(e)
        os.remove(file_path)
    
             
def create_msx_conf(file_name, path, files_with_sha1, constants, outpt_dir, root_dir):
    """
    Parses the XML configuration file and creates the corresponding MSX configuration file.

    :param file_name: Input XML file name (without extension).
    :param path: Relative path to the XML file.
    :param files_with_sha1: Dictionary of files with their SHA1 hashes.
    :param constants: Dictionary with configuration constants.
    """
    file_path = os.path.join(root_dir, path, file_name + '.xml')
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        if root.tag != "msxConfig":
            print(f"File {file_path} is not a valid msxConfig XML. Skipping.")
            return
        
        config = parse_msx_config(root)
        print(file_name)
        create_msx_config(config, file_name, path, files_with_sha1, constants, outpt_dir)

    except (ET.ParseError, FileNotFoundError) as e:
        print(f"Error processing file {file_path}: {e}")


debug_output = False

if __name__ == '__main__':   
    parser = argparse.ArgumentParser(description="Process ROM and XML files")
    parser.add_argument('--rom-dir', type=str, default=ROM_DIR,
                        help='Path to the ROM files directory (default: %(default)s)')
    parser.add_argument('--xml-dir', type=str, default=XML_DIR_COMP,
                        help='Path to the XML files directory (default: %(default)s)')
    parser.add_argument('--output-dir', type=str, default=DIR_SAVE,
                        help='Path to the output directory (default: %(default)s)')
    parser.add_argument('--debug', action='store_true', help='Debug output')

    args = parser.parse_args()
    
    if args.debug:
        debug_output = True
        
    files_with_sha1 = find_files_with_sha1(args.rom_dir)
    constants = load_constants()

    xml_files = find_xml_files(args.xml_dir)
    
    outpt_dir = args.output_dir

    for file_name, path in xml_files:
        create_msx_conf(file_name, path, files_with_sha1, constants, outpt_dir, args.xml_dir)
