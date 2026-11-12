#!/bin/bash
# mapper_offset testbench (Verilator --timing). Usage:
#   wsl.exe -- bash rtl/msx/msx_slots/tb/run_offset.sh [offset.sv]
# Optional $1 = alternative offset.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/offset.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module offset_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" offset_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Voffset_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
