import os
import hashlib
import xml.etree.ElementTree as ET
import base64


ROM_DIR = 'ROM'
XML_DIR_COMP = 'Computer'
XML_DIR_FW = 'Extension'
EXTENSIONS  = ["NONE", "FDC", "FM_PAC", "SCC", "SCC2", "MEGA_FLASH_ROM_SCC_SD", "GM2", "EMPTY" ]

CONFIG_TYPES = ["NONE", "FDC", "SLOT_A", "SLOT_B", "KBD_LAYOUT", "CONFIG"]
MAPPER_TYPES = ["MAPPER_UNUSED", "MAPPER_AUTO", "MAPPER_NONE", "MAPPER_RAM"]
MSX_TYPES    = ["MSX1", "MSX2"]

BLOCK_TYPES = {"NONE"       : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_UNUSED", "CONFIG" : "NONE"       },
               "RAM"        : {"FILL": True,  "RO": False, "MAPPER" : "MAPPER_NONE",   "CONFIG" : "NONE"       },
               "RAM MAPPER" : {"FILL": True,  "RO": False, "MAPPER" : "MAPPER_RAM",    "CONFIG" : "NONE"       },
               "ROM"        : {"FILL": True,  "RO": True,  "MAPPER" : "MAPPER_NONE",   "CONFIG" : "NONE"       },
               "FDC"        : {"FILL": True,  "RO": True,  "MAPPER" : "MAPPER_NONE",   "CONFIG" : "FDC"        },
               "SLOT A"     : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_UNUSED", "CONFIG" : "SLOT_A"     },
               "SLOT B"     : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_UNUSED", "CONFIG" : "SLOT_B"     },
               "KBD LAYOUT" : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_UNUSED", "CONFIG" : "KBD_LAYOUT" },
               "ROM_MIRROR" : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_NONE",   "CONFIG" : "NONE"       },
               "IO_MIRROR"  : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_UNUSED", "CONFIG" : "NONE"       },
               "MIRROR"     : {"FILL": False, "RO": False, "MAPPER" : "MAPPER_NONE",   "CONFIG" : "NONE"       },
               }

def file_hash(filename):
    """Return the SHA1 hash of the file at `filename`."""
    with open(filename, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()

def get_msx_type_id(typ):
    """Return the index of the given MSX type."""
    return MSX_TYPES.index(typ)


def create_MSX_block(primary, secondary, values):
    slotSubslot = ((int(primary) & 3) << 4) | ((int(secondary) & 3) << 2)
    
    head = bytearray()
    head.extend('MSX'.encode('ascii'))
    
    config = BLOCK_TYPES[values["type"]]
    value =  0x80 if config["FILL"] else 0
    value |= 0x40 if config["RO"] else 0
    value |= MAPPER_TYPES.index(config["MAPPER"])
    head.append(value)

    if values["type"] in ["IO_MIRROR", "MIRROR"] :
        head.append(CONFIG_TYPES.index(BLOCK_TYPES[values["ref"]["type"]]["CONFIG"]))
    else :
        head.append(CONFIG_TYPES.index(config["CONFIG"]))
    
    head.append((values['count'] >> 8) & 255)
    head.append(values['count'] & 255)
    if values["type"] in ["KBD LAYOUT"] :
        None
 
    if values["type"] in ["RAM", "ROM", "FDC", "IO_MIRROR"] :
        for i in range(0,values['count']):
            head.append(0x80 | slotSubslot | ((values["start"]+i) & 3))
            head.append(i)

    if values["type"] in ["MIRROR", "ROM_MIRROR"] :
        for i in range(0,values['count']):
            head.append(0x40 | slotSubslot | ((values["start"]+i) & 3))
            head.append(slotSubslot | (values['ref']['start'] + i) & 3) 
            

    if values["type"] in ["RAM MAPPER", "SLOT A", "SLOT B"] :
        head.append(0x80 | slotSubslot)
        head.append(0)
        head.append(0x80 | slotSubslot+1)
        head.append(0)
        head.append(0x80 | slotSubslot+2)
        head.append(0)
        head.append(0x80 | slotSubslot+3)
        head.append(0)
    for i in range(len(head),16) :
        head.append(0)
    return head

def create_MSX_config(config) :
    
    head = bytearray()
    head.extend('MSX'.encode('ascii'))
    head.append(MAPPER_TYPES.index("MAPPER_UNUSED"))
    head.append(CONFIG_TYPES.index("CONFIG"))
    head.append(config)
    for i in range(len(head),16) :
        head.append(0)
    return head

def create_FW_block(type, size):
    """Create and return a bytearray representing a block."""
    head = bytearray()
    head.extend('MSX'.encode('ascii'))
    head.append(0)
    head.append(type)
    head.append(size >> 8)
    head.append(size & 255)
    head.extend(bytearray(b'\x00\x00\x00\x00\x00\x00\x00\x00\x00'))
    return head

def createFWpack(root, fileHandle) :
    try :
        for fw in root.findall("./fw"):
            fw_name = fw.attrib["name"]
            fw_filename = fw.find('filename').text if fw.find('filename') is not None else None
            fw_SHA1 = fw.find('SHA1').text if fw.find('SHA1') is not None else None
            fw_size = int(fw.find('size').text) if fw.find('size') is not None else None
            if fw_name in EXTENSIONS :
                typ = EXTENSIONS.index(fw_name)
                if fw_SHA1 is not None :
                    if fw_SHA1 in rom_hashes.keys() :                    
                        inFileName = rom_hashes[fw_SHA1]
                        fileSize = os.path.getsize(inFileName)
                        size = fw_size if fw_size is not None else fileSize
                        head = create_FW_block(typ, size  >> 14)
                        fileHandle.write(head)
                        infile = open(inFileName, "rb")
                        fileHandle.write(infile.read())
                        print(size)
                        print(fileSize)
                        if size > fileSize :
                            fileHandle.write(bytes([0xFF] * (size - fileSize)))
                    else :
                        fileHandle.close()
                        raise Exception(f"Skip: {filename} Not found ROM {fw_filename} SHA1:{fw_SHA1}")
        fileHandle.close()
        return False
    except Exception as e:
        print(e)
        return True

def getRefereced(secondary, reference) :
    block = secondary.find((f'.//block[@start="{reference}"]'))
    return getValues(block, None)

def getValues(block, secondary) :
    values = {}
    values['start']    = int(block.attrib["start"]) & 3
    values['type']     = block.find('type').text if block.find('type') is not None else None
    values['count']    = int(block.find('block_count').text) if block.find('block_count') is not None else 0
    values['filename'] = block.find('filename').text if block.find('filename') is not None else None
    values['SHA1']     = block.find('SHA1').text if block.find('SHA1') is not None else None  
    
    if secondary is not None and block.find('ref') is not None :
        values['ref'] = getRefereced(secondary, block.find('ref').text)

    return (values)

def createMSXpack(root, fileHandle) :
    config = 0x00
    try :
        heads = []
        msx_type_value = None
        msx_type = root.find('type')
        if msx_type is not None:
            msx_type_value = msx_type.text
        for primary in root.findall("./primary"):
            primary_slot = primary.attrib["slot"]
            for secondary in primary.findall("./secondary"):
                secondary_slot = secondary.attrib["slot"]
                for block in secondary.findall("./block"):
                    block_ref = block.find('ref').text if block.find('ref') is not None else None
                    values = getValues(block, secondary)
                    head = create_MSX_block(primary_slot, secondary_slot, values) 
                    print(' '.join([f'{byte:02X}' for byte in head[3:15]]) + " {0}/{1} ".format(primary_slot, secondary_slot) + str(values))
                    if block_ref is None :
                        fileHandle.write(head)                      
                        if values["SHA1"] is not None :
                            if values["SHA1"] in rom_hashes.keys() :
                                infile = open(rom_hashes[values["SHA1"]], "rb")
                                fileHandle.write(infile.read())
                            else :
                                fileHandle.close()
                                raise Exception(f"Skip: {filename} Not found ROM {0} SHA1:{1}",values["filename"],values["SHA1"])
                    else :
                        heads.append(head)
                if int(secondary_slot) > 0 :
                    config = config | (0x1 << int(primary_slot))            
        for head in heads :             
            fileHandle.write(head)
        
        kbd_layout = root.find('kbd_layout')
        if kbd_layout is not None:
            values = {'type':"KBD LAYOUT", 'count':0}           
            head = create_MSX_block(0,0,values) 
            print(' '.join([f'{byte:02X}' for byte in head[3:15]]))
            fileHandle.write(head)
            fileHandle.write(base64.b64decode(kbd_layout.text))
        
        config = config | ((get_msx_type_id(msx_type_value) & 0x3) << 4)
        head = create_MSX_config(config)
        print(' '.join([f'{byte:02X}' for byte in head[3:15]]))
        fileHandle.write(head)
        fileHandle.close()
        return False
    except Exception as e:
        print(e)
        return True

# Traverse the XML directory and create blocks for each XML file
def parseDir(dir) :
    for dirpath, dirnames, filenames in os.walk(dir):
        for filename in filenames:
            if filename.endswith('.xml'):
                filepath = os.path.join(dirpath, filename)
                filename_without_extension, extension = os.path.splitext(filename)
                dir_save = "MSX" + dirpath[len(dir):]
                output_filename = os.path.join(dir_save, filename_without_extension) + ".MSX"
                if not os.path.exists(dir_save):
                    os.makedirs(dir_save)

                tree = ET.parse(filepath)
                root = tree.getroot()
                outfile = open(output_filename, "wb")               
                print(output_filename)
                error = True
                if root.tag == "msxConfig" :
                    error = createMSXpack(root, outfile)
                if root.tag == "fwConfig" :
                    error = createFWpack(root, outfile)
                if error :
                    outfile.close()
                    os.remove(output_filename)


# Traverse the ROM directory and save the hashes of the files in a dictionary
rom_hashes = {}
for dirpath, dirnames, filenames in os.walk(ROM_DIR):
    for filename in filenames:
        filepath = os.path.join(dirpath, filename)
        rom_hashes[file_hash(filepath)] = filepath


parseDir(XML_DIR_COMP)
parseDir(XML_DIR_FW)

            

                
