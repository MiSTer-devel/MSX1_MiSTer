#!/bin/bash
# mapper_national testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_national.sh
# Optional $1 = alternative national.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/national.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module national_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" national_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vnational_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
