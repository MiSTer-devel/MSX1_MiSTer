#!/bin/bash
# mapper_ascii16 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ascii16.sh
# Optional $1 = alternative ascii16.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/ascii16.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module ascii16_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" ascii16_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vascii16_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
