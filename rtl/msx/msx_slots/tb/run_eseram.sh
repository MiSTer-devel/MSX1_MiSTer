#!/bin/bash
# mapper_eseRam testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_eseram.sh
# Optional $1 = alternative eseRam.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/eseRam.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module eseram_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" eseram_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Veseram_tb"
rm -rf "$OUT"
