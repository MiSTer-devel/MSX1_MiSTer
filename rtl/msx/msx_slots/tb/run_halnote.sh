#!/bin/bash
# mapper_halnote testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_halnote.sh
# Optional $1 = alternative halnote.sv (e.g. a broken variant)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/halnote.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module halnote_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" halnote_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vhalnote_tb"
rm -rf "$OUT"
