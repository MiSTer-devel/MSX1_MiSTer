"""createDev.py: the FW pack carries a name table for the HPS (header bytes 8-11 = its offset).

Run from tools/CreateMSXpack:  py -m unittest discover tests
"""
import os
import shutil
import struct
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
sys.path.insert(0, TOOL_DIR)


def read_names(pack: bytes):
    """Parse the name table as Main_MiSTer does: (mappers, devices, FW configurations) or None."""
    offset = struct.unpack_from('<I', pack, 8)[0]
    if offset == 0 or pack[offset:offset + 4] != b'NAM1':
        return None
    pos = offset + 4
    lists = []
    for _ in range(3):
        count = struct.unpack_from('<H', pack, pos)[0]
        pos += 2
        names = []
        for _ in range(count):
            end = pack.index(b'\0', pos)
            names.append(pack[pos:end].decode('ascii'))
            pos = end + 1
        lists.append(names)
    return tuple(lists)


class CreateDevNamesTest(unittest.TestCase):
    def setUp(self):
        self.cwd = os.getcwd()
        self.tmp = tempfile.mkdtemp()
        os.chdir(TOOL_DIR)                      # JSON tables by relative name
        import createDev
        from tools import load_constants
        self.createDev = createDev
        self.constants = load_constants()

    def tearDown(self):
        os.chdir(self.cwd)
        shutil.rmtree(self.tmp)

    def build_pack(self, config):
        """FW pack of config with one 16 kB ROM, written into the temporary folder."""
        cd = self.createDev
        rom = bytes(range(256)) * 64
        roms = {'0#16384#x': {'start': 0, 'blocks': 1, 'id': 0}}
        table, data, rom_start = cd.create_fw_config(config, self.constants, roms)
        old_save = cd.DIR_SAVE
        os.chdir(self.tmp)
        try:
            with open('ROM.bin', 'wb') as f:
                f.write(rom)
            cd.DIR_SAVE = os.path.join(self.tmp, 'out')
            cd.save_fw_config(config, 'T', '', {}, self.constants, roms, table, data, rom_start)
        finally:
            cd.DIR_SAVE = old_save
            os.chdir(TOOL_DIR)
        with open(os.path.join(self.tmp, 'out', 'T.msx'), 'rb') as f:
            return f.read(), table, data, rom_start, rom

    def test_names(self):
        pack = self.build_pack({})[0]
        names = read_names(pack)
        self.assertIsNotNone(names, 'no name table')
        mappers, devices, fws = names
        for name, number in self.constants['mapper'].items():
            self.assertEqual(mappers[number], name)
        for name, number in self.constants['device'].items():
            self.assertEqual(devices[number], name)
        self.assertEqual(len(fws), 256)
        for name, number in self.constants['cart_dev'].items():
            self.assertEqual(fws[number], name)
        self.assertEqual(mappers[43], 'MSXDOS2')
        self.assertEqual(devices[3], 'WD2793')
        self.assertEqual(fws[21], '0x4000')
        self.assertEqual(fws[10], '')           # free FW ID

    def test_core_part_unchanged(self):
        """What the core reads (header 0-7, table, configurations, ROMs) stays as before."""
        pack, table, data, rom_start, rom = self.build_pack({})
        self.assertEqual(pack[:4], b'MsX\0')
        self.assertEqual(struct.unpack_from('<I', pack, 4)[0], rom_start)
        self.assertEqual(pack[12:16], b'\0' * 4)
        self.assertEqual(pack[16:16 + len(table)], bytes(table))
        body = 16 + len(table) + len(data)
        self.assertEqual(pack[16 + len(table):body], bytes(data))
        rom_addr = struct.unpack_from('<I', pack, rom_start)[0]
        self.assertEqual(pack[rom_addr:rom_addr + len(rom)], rom)
        self.assertEqual(struct.unpack_from('<I', pack, 8)[0], rom_addr + len(rom))


if __name__ == '__main__':
    unittest.main()
