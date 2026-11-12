#!/bin/bash
# mapper_fm_pac testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_fm_pac.sh
# Optional $1 = alternative fm_pac.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/fm_pac.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module fm_pac_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" fm_pac_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vfm_pac_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
