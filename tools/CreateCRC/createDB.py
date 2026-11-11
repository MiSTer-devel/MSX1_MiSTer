#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build vampier.db (CRC32 -> FW pack configuration) from the romdb.vampier.net SQL dump."""
import argparse
import collections
import io
import json
import os
import re
import sqlite3
import struct
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
PACK = os.path.join(HERE, '..', 'CreateMSXpack')
DEFAULT_SOURCE = 'https://romdb.vampier.net/Archive/sql-msxromdb.zip'
MAX_KB = 16384                      # biggest ROM the core loads (16 MB)
PLAIN_KB = 64                       # without a DB record the core runs ROMs up to 64 kB as plain ROM


# ---------------------------------------------------------------- source

def read_source(src):
    if re.match(r'https?://', src):
        print(f'Downloading {src}')
        with urllib.request.urlopen(src) as r:
            data = r.read()
    else:
        with open(src, 'rb') as f:
            data = f.read()
    if data[:2] == b'PK':
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = [n for n in z.namelist() if n.lower().endswith('.sql')]
            if len(names) != 1:
                sys.exit(f'Error: expected one .sql file in the archive, found {names}')
            data = z.read(names[0])
    return data.decode('utf-8')


def load_dump(sql):
    db = sqlite3.connect(':memory:')
    allowed = {sqlite3.SQLITE_CREATE_TABLE, sqlite3.SQLITE_INSERT, sqlite3.SQLITE_TRANSACTION,
               sqlite3.SQLITE_SELECT, sqlite3.SQLITE_READ, sqlite3.SQLITE_UPDATE}
    loading = [True]
    # the dump is foreign data: while it loads, no ATTACH, PRAGMA, triggers, functions etc.
    db.set_authorizer(lambda action, *_: sqlite3.SQLITE_OK if not loading[0] or action in allowed
                      else sqlite3.SQLITE_DENY)
    db.executescript(sql)
    loading[0] = False
    return db.execute("""
        SELECT upper(d.CRC32), d.RomType, coalesce(d.FileSize, 0), coalesce(d.StartBytes, ''),
               coalesce(i.Platform, ''), coalesce(i.GameName, '')
        FROM msxdb_romdetails d LEFT JOIN msxdb_rominfo i ON i.GameID = d.GameID
        WHERE coalesce(d.CRC32, '') <> '' AND d.Active = '1'""").fetchall()


# ---------------------------------------------------------------- configuration

def fw_configs():
    """FW configurations that exist in the FW pack: name -> ID."""
    with open(os.path.join(PACK, 'cart_device.json'), encoding='utf-8') as f:
        ids = json.load(f)
    names = set()
    ext = os.path.join(PACK, 'Extension')
    for fn in os.listdir(ext):
        if fn.lower().endswith('.xml'):
            names |= {fw.get('name') for fw in ET.parse(os.path.join(ext, fn)).getroot().iter('fw')}
    return {n: i for n, i in ids.items() if n in names}


def read_overrides(path):
    ov = {}
    if os.path.exists(path):
        with open(path, encoding='utf-8') as f:
            for line in f:
                line = line.split('#', 1)[0].strip()
                if line:
                    crc, name = line.split(maxsplit=1)
                    ov[crc.upper()] = name.strip()
    return ov


# ---------------------------------------------------------------- header -> address

def header_page(head, kb):
    """Page (0, 1, 2) the ROM starts at, from the first bytes of the file; None = no header."""
    if len(head) >= 10 and head[:2] == b'AB':
        init = head[2] | head[3] << 8
        text = head[8] | head[9] << 8
        if 0x8000 <= init < 0xC000 or (init == 0 and text >= 0x8000):
            return 2
        if 0 < init < 0x4000:
            return 0
        return 1
    return None


def file_page(data):
    """Page from the whole ROM file (header at 0 or at 4000h)."""
    p = header_page(data[:16], len(data) // 1024)
    if p is not None:
        return p
    h = data[0x4000:0x4010]
    if len(h) >= 4 and h[:2] == b'AB':
        init = h[2] | h[3] << 8
        return 1 if 0x8000 <= init < 0xC000 else 0
    return None


def scan_roms(rom_dir, wanted):
    """CRC32 -> start page for ROM files whose CRC is in wanted."""
    found = {}
    sizes = {kb * 1024 for kb in wanted.values()}
    for root, _, files in os.walk(rom_dir):
        for fn in files:
            p = os.path.join(root, fn)
            if os.path.getsize(p) not in sizes:
                continue
            with open(p, 'rb') as f:
                data = f.read()
            crc = f'{zlib.crc32(data):08X}'
            if crc in wanted:
                found[crc] = file_page(data)
    return found


# ---------------------------------------------------------------- build

def resolve(name, kb, start, types, fw, page_of):
    """DB type name -> (FW name or None, how)."""
    t = types.get(name, name)
    if isinstance(t, dict):
        page = page_of(start, kb)
        how = 'header'
        if page is None:
            page, how = 0, 'guess'            # same as the core without a DB record
        return t['by_header'][page], how
    return (t if t in fw else None), 'type'


def mirror_equal(a, b, kb):
    """MIRROR repeats the ROM modulo its size: small ROMs look the same from any start."""
    if a == b:
        return True
    m = {'Mirror_0x0000': 0, 'Mirror_0x4000': 1, 'Mirror_0x8000': 2}
    if a in m and b in m:
        blocks = max(1, -(-kb // 8))                  # 8 kB blocks, address = (block + 2*page) % blocks
        return (2 * (m[a] - m[b])) % blocks == 0
    return False


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source', default=DEFAULT_SOURCE, help='URL, .zip or .sql of the ROM DB dump (default: %(default)s)')
    ap.add_argument('--output', default=os.path.join(HERE, 'vampier.db'), help='database for the core (default: vampier.db)')
    ap.add_argument('--report', default=os.path.join(HERE, 'report.md'), help='report file (default: report.md)')
    ap.add_argument('--list', help='also write every record as text (CRC, FW config, type, kB, platform, name)')
    ap.add_argument('--roms', help='folder with ROM files: exact start address of mirrored ROMs without a header at 0')
    ap.add_argument('--prune', action='store_true', help='remove override lines that the dump already gives')
    a = ap.parse_args()

    with open(os.path.join(HERE, 'romtypes.json'), encoding='utf-8') as f:
        cfg = json.load(f)
    types, platforms, ignore = cfg['types'], set(cfg['platforms']), set(cfg['ignore'])
    fw = fw_configs()
    for k, v in types.items():
        targets = v['by_header'] if isinstance(v, dict) else [v]
        for t in targets:
            if t not in fw:
                print(f'Warning: romtypes.json {k} -> {t}: no such FW configuration, ROMs of this type are left out')
    ov_path = os.path.join(HERE, 'mappersOverride.txt')
    ov = read_overrides(ov_path)
    rows = load_dump(read_source(a.source))

    skipped = collections.Counter()
    roms = {}                                         # CRC -> (type, kB, start, platform, name)
    for crc, t, kb, start, pf, name in rows:
        if pf not in platforms:
            skipped[f'platform {pf or "?"}'] += 1
        elif t in ignore:
            skipped[f'type {t}'] += 1
        elif kb > MAX_KB:
            skipped['over 16 MB'] += 1
        else:
            roms.setdefault(crc, (t, kb, start, pf, name))

    files = {}
    if a.roms:
        wanted = {c: r[1] for c, r in roms.items()
                  if isinstance(types.get(r[0]), dict) and header_page(bytes.fromhex(r[2]), r[1]) is None}
        files = scan_roms(a.roms, wanted)
        print(f'ROM folder: {len(files)} of {len(wanted)} ROMs without a header at 0 found')

    def page_of(start, kb, crc=None):
        if crc in files and files[crc] is not None:
            return files[crc]
        return header_page(bytes.fromhex(start), kb) if start else None

    out = {}                                          # CRC -> (FW name, source)
    unsupported = collections.defaultdict(list)
    how = collections.Counter()
    for crc, (t, kb, start, pf, name) in roms.items():
        f, h = resolve(t, kb, start, types, fw, lambda s, k: page_of(s, k, crc))
        if f is None:
            unsupported[t].append((kb, pf, name))
            continue
        out[crc] = (f, 'dump')
        if h != 'type':
            how[h] += 1

    redundant, bad = [], []
    for crc, n in ov.items():
        t, kb = (roms[crc][0], roms[crc][1]) if crc in roms else (None, 0)
        f = n if n in fw else types.get(n)
        if not isinstance(f, str) or f not in fw:
            bad.append((crc, n))
            continue
        if crc in out and mirror_equal(out[crc][0], f, kb):
            redundant.append(crc)
        out[crc] = (f, 'override')
    for crc, n in bad:
        print(f'Warning: mappersOverride.txt {crc} {n}: unknown type or FW configuration, line ignored')

    # vampier.db: 8-byte records CRC32 LE, FW ID, 3 x 0; sorted by CRC
    old = {}
    if os.path.exists(a.output):
        with open(a.output, 'rb') as f:
            b = f.read()
        old = {struct.unpack_from('<I', b, i)[0]: b[i + 4] for i in range(0, len(b) - 7, 8)}
    new = {int(c, 16): fw[f] for c, (f, _) in out.items()}
    with open(a.output, 'wb') as f:
        for c in sorted(new):
            f.write(struct.pack('<I4B', c, new[c], 0, 0, 0))

    if a.list:
        with open(a.list, 'w', encoding='utf-8') as f:
            for c in sorted(out):
                t, kb, _, pf, name = roms.get(c, ('', 0, '', '', ''))
                f.write(f'{c}\t{out[c][0]}\t{t}\t{kb}\t{pf}\t{name}\n')

    if a.prune and redundant:
        keep = set(ov) - set(redundant)
        with open(ov_path, encoding='utf-8') as f:
            lines = f.readlines()
        with open(ov_path, 'w', encoding='utf-8') as f:
            f.writelines(l for l in lines
                         if not l.split('#', 1)[0].strip() or l.split()[0].upper() in keep)

    # ------------------------------------------------------------ report
    sup = collections.defaultdict(lambda: [0, 0, set()])
    for crc, (f, src) in out.items():
        s = sup[f]
        s[0] += 1
        s[1] += src == 'override'
        if crc in roms:
            s[2].add(roms[crc][0])
    R = ['# Mapper database report', '',
         f'Source: `{a.source if re.match(r"https?://", a.source) else os.path.basename(a.source)}`  ',
         f'Records in `{os.path.basename(a.output)}`: **{len(new)}** (previous file: {len(old)}; '
         f'added {len(set(new) - set(old))}, removed {len(set(old) - set(new))}, '
         f'changed {sum(1 for c in set(new) & set(old) if new[c] != old[c])})  ',
         f'Mirrored/Normal start address: {how["header"]} from the header, {how["guess"]} guessed (no header at 0, '
         f'placed at 0000h like the core does without a record)  ',
         f'Overrides: {len(ov)} lines, {len(redundant)} give the same as the dump'
         + (' (removed)' if a.prune else ' (`--prune` removes them)'), '',
         '## Supported', '',
         '| FW configuration | ID | ROMs | of them override | DB types |', '|---|---|---|---|---|']
    for f, (n, o, ts) in sorted(sup.items(), key=lambda x: (-x[1][0], x[0])):
        R.append(f'| {f} | {fw[f]} | {n} | {o or ""} | {", ".join(sorted(ts))} |')
    R += ['', '## Not supported', '',
          'ROM types of the dump without a FW configuration. They are not in the database: a ROM up to '
          f'{PLAIN_KB} kB then runs as plain ROM (may work), a bigger one stops with "Not find CRC32 in DB". '
          'The column "over 64 kB" counts the ROMs that cannot run at all without the mapper.', '',
          '| DB type | ROMs | games | over 64 kB | max kB | examples |', '|---|---|---|---|---|---|']
    for t, lst in sorted(unsupported.items(), key=lambda x: (-len(x[1]), x[0])):
        games = sorted({n for _, _, n in lst})
        ex = ', '.join(games[:3]) + (', ...' if len(games) > 3 else '')
        R.append(f'| {t} | {len(lst)} | {len(games)} | {sum(1 for kb, _, _ in lst if kb > PLAIN_KB)} '
                 f'| {max(kb for kb, _, _ in lst)} | {ex.replace("|", "/")} |')
    R += ['', '## Left out of the dump', '', '| Reason | ROMs |', '|---|---|']
    R += [f'| {k} | {v} |' for k, v in skipped.most_common()]
    report = '\n'.join(R) + '\n'
    with open(a.report, 'w', encoding='utf-8') as f:
        f.write(report)
    print(report)


if __name__ == '__main__':
    main()
