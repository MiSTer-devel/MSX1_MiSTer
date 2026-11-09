#!/bin/bash
# mapper_panasonic testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_panasonic.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module panasonic_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers/panasonic.sv panasonic_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vpanasonic_tb"
rm -rf "$OUT"
