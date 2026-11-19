#!/bin/bash
# mapper_zemina90 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_zemina90.sh
# Optional $1 = alternative zemina90.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/zemina90.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module zemina90_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" zemina90_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vzemina90_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
