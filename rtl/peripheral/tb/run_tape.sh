#!/bin/bash
# tape (CAS player) testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_tape.sh
# Optional $1 = alternative tape.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../tape.sv}
OUT=$(mktemp -d)
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module tape_tb -Mdir "$OUT" \
    ../../package.sv "$DUT" ../ddram.sv tape_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vtape_tb"
rm -rf "$OUT"
