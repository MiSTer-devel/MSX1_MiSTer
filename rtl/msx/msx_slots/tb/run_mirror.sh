#!/bin/bash
# mapper_mirror testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_mirror.sh
# Optional $1 = alternative mirror.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/mirror.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module mirror_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" mirror_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmirror_tb"
rm -rf "$OUT"
