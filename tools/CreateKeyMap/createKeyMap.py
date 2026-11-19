# CreateKeyMap: PS/2 -> MSX keyboard matrix tables from the JSON maps
#
# Copyright (c) 2024-2026 Molekula
# SPDX-License-Identifier: GPL-3.0-or-later

import os
import json

DIR_MAPS = 'map'
DIR_KEYB = 'keyboard'

def convert_hex_to_int(num: str) -> int:
    if num.startswith("0x") or num.startswith("0X"):
        value = int(num, 16)
        return value

def find_maps(dir) :
    json_files = []
    for root, _, files in os.walk(dir):
      for file in files:
           if file.endswith(".json"):
                file_name = os.path.splitext(file)[0]
                path = os.path.relpath(root, dir)
                json_files.append((file_name, path))
    return json_files

def create_table(assign, scancodes):
    table = [0xFF] * 512
    for key in assign:
        if assign[key] :
            if key in scancodes : 
                if scancodes[key] :
                    pos = convert_hex_to_int(scancodes[key])
                    if assign[key] :
                        #port = convert_hex_to_int(assign[key])
                        #print(f'key: {key} value: {assign[key]} pos: {pos} port: {port} scancode: {scancodes[key]}')
                        table[pos] = convert_hex_to_int(assign[key])
                    else :
                        print(f'Klavesa neni prirazena {key}')
                else:
                    print(f'Klavesa nema scancode {key}')
            else :
                print(f'Nenalezen {key}')
    return table

def create_map(file_name, path, scan_codes):
    print(file_name)
    with open(DIR_MAPS + "/" + path + '/' + file_name + ".json", 'r') as file:
        maps = json.load(file)
        table = create_table(maps["assign"], scan_codes)

        with open("key_map_" + file_name + ".bin", "wb") as f:
            f.write(bytes(table))
            f.close()


maps = find_maps(DIR_MAPS)
 
with open(DIR_KEYB + '/ps2.json', 'r') as file:
    scan_codes = json.load(file)

for file_name, path in maps :
    create_map(file_name, path, scan_codes)
