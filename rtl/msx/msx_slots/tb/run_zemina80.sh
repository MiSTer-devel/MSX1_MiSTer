#!/bin/bash
# mapper_zemina80 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_zemina80.sh
# Optional $1 = alternative zemina80.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/zemina80.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module zemina80_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" zemina80_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vzemina80_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
