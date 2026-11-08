#!/bin/bash
# OCM boot simulation (Verilator): msx_system + SD path + HPS/DDR3/SDRAM models.
# Usage: wsl.exe -- bash rtl/tb/run_ocm_boot.sh <1chipMSX.msx> <OCM-BIOS.rom>   (SIMARGS=+trace for a trace)
#   SDADD="--add NAME.EXT=<path> ..."  more files on the card (e.g. MSXDOS2.SYS, COMMAND2.COM,
#   AUTOEXEC.BAT for a DOS run with SIMARGS="+dos +fw=<CART_FW_EN.msx> +status=<hex>"; SofaROM:
#   AUTOEXEC.BAT "SROM /Q GAME.ROM", /Q skips the key prompt before the ROM is started)
#   1chipMSX.msx: cd tools/CreateMSXpack; python createComp.py --xml-dir Computer/OCM --output-dir <dir>
#   The SD image (MBR + FAT16, OCM-BIOS.DAT first) is built by make_sd_image.py; the IPL
#   needs a partition table (as made by sdcreate), a FAT16 volume without MBR is not booted.
set -e
PACK=$(realpath "$1"); BIOS=$(realpath "$2")
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
OUT=$(mktemp -d)

python3 make_sd_image.py "$BIOS" "$OUT/sd.img" --mbr $SDADD

# Synthesis file list from the qip tree (SystemVerilog/Verilog, no PLL); packages first
python3 - "$ROOT" "$OUT" > "$OUT/files.txt" <<'EOF'
import os, re, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]

def from_git(p):
    # a file missing in the working tree (e.g. broken submodule checkout) is taken from HEAD
    repo = os.path.dirname(p)
    while not os.path.exists(os.path.join(repo, '.git')): repo = os.path.dirname(repo)
    rel = os.path.relpath(p, repo)
    dst = os.path.join(tmp, 'from_git', rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, 'wb') as f:
        f.write(subprocess.check_output(['git', '-C', repo, 'show', 'HEAD:' + rel]))
    print(f'WARNING: {p} missing, using HEAD of {repo}', file=sys.stderr)
    return dst

rx = re.compile(r'-name\s+(\w+_FILE)\s+\[file join \$::quartus\(qip_path\)\s+"?([^"\]\s]+)"?\s*\]')
out = []
def walk(q):
    d = os.path.dirname(q)
    for line in open(q, encoding='latin-1'):
        if line.lstrip().startswith('#'): continue
        m = rx.search(line)
        if not m: continue
        k, rel = m.groups(); p = os.path.normpath(os.path.join(d, rel))
        if k == 'QIP_FILE': walk(p)
        elif k in ('SYSTEMVERILOG_FILE', 'VERILOG_FILE') and '/pll' not in p:
            out.append(p if os.path.exists(p) else from_git(p))
walk(os.path.join(root, 'rtl/files.qip'))
pk = [p for p in out if re.search(r'^\s*package\s', open(p, encoding='latin-1').read(), re.M)]
print('\n'.join(pk + [p for p in out if p not in pk]))
EOF

verilator --binary --timing -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module ocm_boot_tb -Mdir "$OUT" \
    $(cat "$OUT/files.txt") dpram_stub.sv spram_stub.sv altsyncram_stub.sv \
    "$ROOT/sys/sd_card.sv" ocm_boot_tb.sv > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
stdbuf -oL "$OUT/Vocm_boot_tb" +pack="$PACK" +img="$OUT/sd.img" +bios="$BIOS" $SIMARGS |
    grep --line-buffered -v "^BLOCK\|^  BLOCK\|^DEVICE\|^LOAD\|^  LOAD\|^CONFIG\|^DO STATE\|^SWIO\|SWIO WRITE\|^Command I"
rm -rf "$OUT"
