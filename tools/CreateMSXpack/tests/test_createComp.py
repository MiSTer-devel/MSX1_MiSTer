"""createComp.py: a pack with a missing ROM must not be written; the report lists the result.

Run from tools/CreateMSXpack:  py -m unittest discover tests
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL_DIR = os.path.dirname(HERE)
CBIOS_XML = os.path.join(TOOL_DIR, 'Computer', 'C-BIOS', 'MSX - C-BIOS.xml')
CBIOS_ROMS = ('cbios_main_msx1.rom', 'cbios_logo_msx1.rom')
LOGO_SHA1 = '9fbbe400dbaf186aeba42e170d9424b032412c42'

# Machine XML with a device ROM (ROM_SHA1) that no ROM folder has
DEVICE_ROM_XML = """<?xml version="1.0" ?>
<msxConfig>
  <device mask="0xFE" port="0x98" MODE="PAL">TMS99xx</device>
  <device port="0xD8" mask="0xFE" ROM_SHA1="0000000000000000000000000000000000000000">KANJI</device>
  <primary slot="0">
    <block start="0" count="2">
      <memory SHA1="2f997e8a57528518c82ab3693fdae243dbbcc508" filename="cbios_main_msx1.rom">ROM</memory>
    </block>
  </primary>
</msxConfig>
"""


class CreateCompTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.xml = os.path.join(self.tmp, 'xml', 'Test')
        self.rom = os.path.join(self.tmp, 'rom')
        self.out = os.path.join(self.tmp, 'out')
        os.makedirs(self.xml)
        os.makedirs(self.rom)

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def add_roms(self, names):
        for n in names:
            shutil.copy(os.path.join(TOOL_DIR, 'ROM', 'cbios', n), self.rom)

    def add_xml(self, name, text=None):
        dst = os.path.join(self.xml, name + '.xml')
        if text is None:
            shutil.copy(CBIOS_XML, dst)
        else:
            with open(dst, 'w') as f:
                f.write(text)

    def run_tool(self):
        r = subprocess.run([sys.executable, 'createComp.py', '--xml-dir', os.path.dirname(self.xml),
                            '--rom-dir', self.rom, '--output-dir', self.out],
                           cwd=TOOL_DIR, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def pack(self, name):
        return os.path.join(self.out, 'Test', name + '.msx')

    def report(self):
        with open(os.path.join(self.out, 'createComp_report.txt'), encoding='utf-8') as f:
            return f.read()

    def test_all_roms_present(self):
        self.add_roms(CBIOS_ROMS)
        self.add_xml('Good')
        self.run_tool()
        self.assertTrue(os.path.isfile(self.pack('Good')))
        rep = self.report()
        self.assertIn('Created: 1', rep)
        self.assertIn('Not created: 0', rep)
        self.assertIn('Test/Good', rep)
        self.assertNotIn('|', rep)

    def test_missing_block_rom(self):
        self.add_roms(CBIOS_ROMS[:1])
        self.add_xml('NoLogo')
        self.run_tool()
        self.assertFalse(os.path.exists(self.pack('NoLogo')), 'pack written without its ROM')
        rep = self.report()
        self.assertIn('Not created: 1', rep)
        self.assertIn('Test/NoLogo', rep)
        self.assertIn(LOGO_SHA1, rep)
        self.assertIn('cbios_logo_msx1.rom', rep)

    def test_stale_pack_removed(self):
        # A pack left from an earlier run must not survive a run that fails
        os.makedirs(os.path.dirname(self.pack('NoLogo')))
        with open(self.pack('NoLogo'), 'wb') as f:
            f.write(b'old')
        self.add_roms(CBIOS_ROMS[:1])
        self.add_xml('NoLogo')
        self.run_tool()
        self.assertFalse(os.path.exists(self.pack('NoLogo')))

    def test_missing_device_rom(self):
        self.add_roms(CBIOS_ROMS)
        self.add_xml('NoKanji', DEVICE_ROM_XML)
        self.run_tool()
        self.assertFalse(os.path.exists(self.pack('NoKanji')))
        self.assertIn('0000000000000000000000000000000000000000', self.report())

    def test_mixed(self):
        self.add_roms(CBIOS_ROMS[:1])
        self.add_xml('NoLogo')
        self.add_xml('NoKanji', DEVICE_ROM_XML)
        self.run_tool()
        rep = self.report()
        self.assertIn('Created: 0', rep)
        self.assertIn('Not created: 2', rep)


if __name__ == '__main__':
    unittest.main()
