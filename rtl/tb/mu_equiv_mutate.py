"""Mutated machine packs for run_mu_equiv.sh: paths that real packs do not reach.

usage: mu_equiv_mutate.py <output dir> <pack.msx>...

For each pack (header 8 bytes 'MSx', then 8-byte records; a ROM block, a device with its
own memory and the keyboard layout are followed by their data):
  _devx4   every device record four times        (no free copy: ERR_MISSING_SOURCE)
  _blkx4   every block device record four times  (ERR_DEVICE_MISSING)
  _sig     wrong signature                       (ERR_BAD_MSX_CONF)
  _conf    unsupported record type in the middle (ERR_NOT_SUPPORTED_CONF)
  _block   unsupported block type in the middle  (ERR_NOT_SUPPORTED_BLOCK)
  _fuzzN   random slot addresses, device types and parameters of records without data
"""
import os
import random
import sys

CONF_BLOCK, CONF_DEVICE, CONF_LAYOUT = 0, 1, 2
BLOCK_RAM, BLOCK_ROM, BLOCK_SRAM, BLOCK_DEVICE, BLOCK_MAPPER, BLOCK_CART = 0, 1, 2, 3, 4, 5


def parse(d):
    """-> header, [(record, data)]"""
    recs, p = [], 8
    while p + 8 <= len(d):
        r = bytearray(d[p:p + 8]); p += 8
        n = 0
        t = r[0] & 7
        if t == CONF_BLOCK and r[2] == BLOCK_ROM:
            n = r[3] * 16384
        elif t == CONF_DEVICE and r[5] != 0 and not r[6] & 0x80:
            n = r[5] * 16384
        elif t == CONF_LAYOUT:
            n = 512
        recs.append((r, d[p:p + n])); p += n
    assert p == len(d), 'pack does not parse'
    return bytearray(d[:8]), recs


def build(hdr, recs):
    out = bytearray(hdr)
    for r, data in recs:
        out += r + data
    return out


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
n = 0
for path in sys.argv[2:]:
    d = open(path, 'rb').read()
    hdr, recs = parse(d)
    base = os.path.splitext(os.path.basename(path))[0]
    rnd = random.Random(base)
    var = {}

    var['devx4'] = build(hdr, [x for r in recs for x in ([r] * 4 if r[0][0] & 7 == CONF_DEVICE and not r[1] else [r])])
    var['blkx4'] = build(hdr, [x for r in recs for x in ([r] * 4 if r[0][0] & 7 == CONF_BLOCK and r[0][2] == BLOCK_DEVICE else [r])])
    h = bytearray(hdr); h[2] = ord('y')
    var['sig'] = build(h, recs)
    mid = len(recs) // 2
    var['conf'] = build(hdr, recs[:mid] + [(bytearray([3, 0, 0, 0, 0, 0, 0, 0]), b'')] + recs[mid:])
    var['block'] = build(hdr, recs[:mid] + [(bytearray([0, 0x40, 13, 0, 0, 0, 0, 0]), b'')] + recs[mid:])
    for k in range(3):
        rs = [(bytearray(r), data) for r, data in recs]
        for r, data in rs:
            if data or rnd.random() > 0.25:
                continue
            t = r[0] & 7
            if t == CONF_DEVICE:
                r[rnd.choice([1, 2, 3, 4])] = rnd.randrange(256) if rnd.random() < 0.5 else rnd.randrange(32)
            elif t == CONF_BLOCK and r[2] not in (BLOCK_RAM, BLOCK_ROM, BLOCK_SRAM, BLOCK_CART):
                r[rnd.choice([1, 3, 4, 5, 6, 7])] = rnd.randrange(256)
            elif t == CONF_BLOCK:
                r[1] = rnd.randrange(256)               # slot / subslot / block / size only
        var[f'fuzz{k}'] = build(hdr, rs)
    for name, data in var.items():
        open(os.path.join(out, f'{base}_{name}.msx'), 'wb').write(data)
        n += 1
print(f'{n} mutated packs in {out}')
