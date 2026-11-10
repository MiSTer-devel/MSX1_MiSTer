"""Writes the measured V9938 access slot tables of openMSX into vdp_access_slots.sv.

usage: gen_access_slots.py <openMSX src/video/VDPAccessSlots.cc> [vdp_access_slots.sv]

The block between "// BEGIN slot tables" and "// END slot tables" is replaced.
The tables (cycle numbers 0..1367 of a line at which the command engine may access VRAM)
come from openMSX VDPAccessSlots.cc, measured on a real V9938 with a logic analyser.
All slots are on even cycles, so a table is stored as 684 bits indexed by cycle / 2.
"""
import re
import sys

src = open(sys.argv[1], encoding='utf-8').read()
NAMES = [('ScreenOff', 'SLOT_OFF'), ('SpritesOn', 'SLOT_SPON'), ('SpritesOff', 'SLOT_SPOFF'),
         ('CharSpritesOn', 'SLOT_CSPON'), ('CharSpritesOff', 'SLOT_CSPOFF'), ('Text', 'SLOT_TEXT')]
out = ['    // BEGIN slot tables: gen_access_slots.py from openMSX VDPAccessSlots.cc, do not edit.',
       '    // Bit n = an access slot at line cycle 2n (openMSX cycle numbering).']
for name, sv in NAMES:
    m = re.search(r'slots' + name + r'\s*=\s*\{(.*?)\};', src, re.S)
    assert m, name
    body = re.sub(r'//[^\n]*', '', m.group(1))
    vals = [eval(v) for v in body.replace('\n', ' ').split(',') if v.strip()]
    slots = sorted(v for v in vals if v < 1368)
    assert all(v % 2 == 0 for v in slots), name
    bits = 0
    for v in slots:
        bits |= 1 << (v // 2)
    out.append(f'    // {name}: {len(slots)} slots')
    out.append(f'    localparam logic [683:0] {sv} =')
    out.append(f"        684'h{bits:0171x};")
out.append('    // END slot tables')

dst = sys.argv[2] if len(sys.argv) > 2 else 'vdp_access_slots.sv'
text = open(dst, encoding='utf-8').read()
a = text.index('    // BEGIN slot tables')
b = text.index('    // END slot tables\n') + len('    // END slot tables\n')
open(dst, 'w', encoding='utf-8', newline='\n').write(text[:a] + '\n'.join(out) + '\n' + text[b:])
print(f'{len(NAMES)} tables -> {dst}')
