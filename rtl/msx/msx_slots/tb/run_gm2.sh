#!/bin/bash
# mapper_gamemaster2 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_gm2.sh
# Optional $1 = alternative gm2.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/gamemaster2.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module gm2_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" gm2_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vgm2_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
