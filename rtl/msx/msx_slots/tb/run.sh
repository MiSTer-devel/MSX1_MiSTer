#!/bin/bash
# subslot testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run.sh
# Optional $1 = alternative subslot.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../subslot.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module subslot_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" subslot_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vsubslot_tb"
rm -rf "$OUT"
