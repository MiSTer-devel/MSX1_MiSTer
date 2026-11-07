#!/bin/bash
# dev_dac testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_dac.sh
# Optional $1 = alternative dac.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../dac.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module dac_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" dac_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vdac_tb"
rm -rf "$OUT"
