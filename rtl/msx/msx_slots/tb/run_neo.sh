#!/bin/bash
# mapper_neo (NEO-8, NEO-16) testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_neo.sh
# Optional $1 = alternative neo.sv (e.g. a broken variant)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/neo.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module neo_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" neo_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vneo_tb"
rm -rf "$OUT"
