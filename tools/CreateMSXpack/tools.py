import os
import hashlib
import json
from typing import Union

def calculate_sha1(file_path):
    """
    Calculates the SHA1 hash for a given file.

    :param file_path: Path to the file to calculate the hash for.
    :return: SHA1 hash as a hexadecimal string.
    """
    with open(file_path, 'rb') as f:
        return hashlib.sha1(f.read()).hexdigest()

def find_files_with_sha1(directory):
    """
    Recursively searches the given directory and its subdirectories, finds all files,
    and calculates the SHA1 hash for each file. Returns a dictionary with the hash as key and the file path as value.

    :param directory: Directory to search.
    :return: Dictionary with (SHA1 hash, file path).
    """
    files_with_sha1 = {}

    for root, _, files in os.walk(directory):
        for file in files:
            full_path = os.path.join(root, file)
            file_sha1 = calculate_sha1(full_path)
            files_with_sha1[file_sha1] = full_path

    return files_with_sha1

def load_constants():
    """
    Loads the constants from the specified JSON files.
    :return: Dictionary containing the loaded constants.
    """
    constants = {}
    with open('block.json', 'r') as file:
        constants['block'] = json.load(file)

    with open('conf.json', 'r') as file:
        constants['conf'] = json.load(file)

    with open('cart_device.json', 'r') as file:
        constants['cart_dev'] = json.load(file)
    
    with open('mapper.json', 'r') as file:
        constants['mapper'] = json.load(file)
    
    with open('device.json', 'r') as file:
        constants['device'] = json.load(file)
     
    with open('deviceParams.json', 'r') as file:
        constants['deviceParams'] = json.load(file)

    return constants

def find_xml_files(directory):
    """
    Recursively searches the given directory and its subdirectories, finds all XML files,
    and returns a list containing the file name (without extension) and the relative file path.

    :param directory: Directory to search.
    :return: List of tuples (file name, relative path).
    """
    xml_files = []

    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".xml"):
                file_name = os.path.splitext(file)[0]
                path = os.path.relpath(root, directory)
                xml_files.append((file_name, path))

    return xml_files

def convert_to_int_or_string(text):
    if text is None:
        return None
    try:
        return int(text)
    except ValueError:
        return text
    
def convert_to_int_old(text):
    if text is None:
        return None
    try:
        return int(text)
    except ValueError:
        return None

def get_int_or_string_value(element):
    if element.text and element.text.strip():
        return convert_to_int_or_string(element.text.strip())
    return None

def convert_to_8bit(num: str) -> int:
    if not isinstance(num, str):
        return None
    try:
        # Zkusíme nejprve převést jako celé číslo
        if num.isdigit():
            value = int(num)
            if 0 <= value <= 255:
                return value
            else:
                return None
        
        # Zkusíme převést jako hexadecimální číslo
        if num.startswith("0x") or num.startswith("0X"):
            value = int(num, 16)
            if 0 <= value <= 0xFF:
                return value
            else:
                return None
        
        # Pokud se nejedná o validní číslo ani hexadecimální formát
        return None
    
    except ValueError:
        # Pokud převod selže, vrátíme None
        return None
    
def convert_to_int(num: Union[str, int]) -> int:
    if isinstance(num, int):
        return num
    
    if not isinstance(num, str):
        print("Not a string")
        return None
    try:
        # Zkusíme nejprve převést jako celé číslo
        if num.isdigit():
            value = int(num)
            return value
        
        # Zkusíme převést jako hexadecimální číslo
        if num.startswith("0x") or num.startswith("0X"):
            value = int(num, 16)
            return value
        
        # Pokud se nejedná o validní číslo ani hexadecimální formát
        return None
    
    except ValueError:
        # Pokud převod selže, vrátíme None
        return None

def get_device_param(constants, device_name, attributes):
    """
    Returns the device parameters based on the device type and its attributes.
    
    :param device: Device type.
    :param parameters: Device attributes.
    :return: Tuple of device parameters.
    """
    params = constants['deviceParams'].get(device_name, {})
    if not params:
        value = convert_to_8bit(attributes.get('param', '0'))
        return value
    else:
        ret = 0
        for param_name, param_property in params.items():
            value = 0
            if param_name in attributes:
                value = attributes[param_name]
                if param_property['param_type'] == 'int':
                    value = convert_to_int(value)
                    if 'div' in param_property and param_property['div'] is not None:
                        value = value // param_property['div']
                    if param_property['min'] is not None and value < param_property['min']:
                        print(f"Device '{device_name}' parameter '{param_name}' value {value} is less than minimum {param_property['min']} setting to default value {param_property['default']}")
                        value = param_property['default']
                    if param_property['max'] is not None and value > param_property['max']:
                        print(f"Device '{device_name}' parameter '{param_name}' value {value} is greater than maximum {param_property['max']} setting to default value {param_property['default']}")
                        value = param_property['default']
                elif param_property['param_type'] == 'enum':
                    if value not in param_property['enums']:
                        print(f"Device '{device_name}' parameter '{param_name}' value {value} is not in enum list {param_property['enums']} setting to default value {param_property['enums'][param_property['default']]}")
                        value = param_property['default']
                    else:
                        value = param_property['enums'].index(value)
                if "value_offset" in param_property and param_property["value_offset"] is not None:
                    value = value << param_property["value_offset"]
                if "values" in param_property and param_property["values"] is not None:
                    value = param_property['values'][value]
                #print(f"Device '{device_name}' parameter '{param_name}' value is {value}")
            ret  = ret | value
        #print(f"Device '{device_name}' return 0x{ret:02X}")
        return ret