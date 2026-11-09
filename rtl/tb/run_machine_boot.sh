#!/bin/bash
# Machine boot from a floppy image (Verilator): msx_system + blockDevMux + HPS / DDR3 / SDRAM models.
# Usage: wsl.exe -- bash rtl/tb/run_machine_boot.sh <machine.msx> <image.dsk | none> [expected text]
#   SIMARGS="+run_ms=20000"  more MSX time (default 15000 ms); "+key=171" Delete held at boot
#                            (Panasonic FS-A1F: skips the A1 Cockpit); "+vram_dump=<prefix>"
#   machine.msx: cd tools/CreateMSXpack; python createComp.py --xml-dir <dir> --rom-dir <dir> --output-dir <dir>
#   image.dsk:   python3 rtl/tb/make_dsk_image.py x.dsk --text 'AUTOEXEC.BAS=10 PRINT "DISK OK"'
set -e
PACK=$(realpath "$1"); DSK="$2"; [ "$DSK" = none ] || DSK=$(realpath "$DSK"); EXPECT="$3"
cd "$(dirname "$0")"
ROOT=$(cd ../.. && pwd)
OUT=$(mktemp -d)

# Synthesis file list from the qip tree (SystemVerilog/Verilog, no PLL); packages first
python3 - "$ROOT" > "$OUT/files.txt" <<'EOF'
import os, re, sys
root = sys.argv[1]
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
        elif k in ('SYSTEMVERILOG_FILE', 'VERILOG_FILE') and '/pll' not in p and os.path.exists(p):
            out.append(p)
walk(os.path.join(root, 'rtl/files.qip'))
pk = [p for p in out if re.search(r'^\s*package\s', open(p, encoding='latin-1').read(), re.M)]
print('\n'.join(pk + [p for p in out if p not in pk]))
EOF

verilator --binary --timing -O3 -j 4 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module machine_boot_tb -Mdir "$OUT" \
    $(cat "$OUT/files.txt") dpram_stub.sv spram_stub.sv altsyncram_stub.sv \
    machine_boot_tb.sv > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
ARGS=(+pack="$PACK" +dsk="$DSK")
[ -n "$EXPECT" ] && ARGS+=(+expect="$EXPECT")
stdbuf -oL "$OUT/Vmachine_boot_tb" "${ARGS[@]}" $SIMARGS |
    grep --line-buffered -v "^BLOCK\|^  BLOCK\|^DEVICE\|^LOAD\|^  LOAD\|^CONFIG\|^DO STATE\|^Command \|^LOAD Track\|^Load Track\|^Change FDD"
rm -rf "$OUT"
