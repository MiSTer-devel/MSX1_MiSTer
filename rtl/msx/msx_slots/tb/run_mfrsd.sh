#!/bin/bash
# mapper_mfrsd testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mfrsd.sh
# Optional $1 = alternative mfrsd.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/mfrsd.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module mfrsd_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" mfrsd_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmfrsd_tb"
rm -rf "$OUT"
