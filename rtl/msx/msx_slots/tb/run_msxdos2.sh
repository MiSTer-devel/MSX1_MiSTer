#!/bin/bash
# mapper_msxdos2 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_msxdos2.sh
# Optional $1 = alternative msxdos2.sv (e.g. a broken variant)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/msxdos2.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module msxdos2_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" msxdos2_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmsxdos2_tb"
rm -rf "$OUT"
