#!/bin/bash
# reset_status testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run.sh
# Optional $1 = alternative reset_status.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../reset_status.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module reset_status_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" reset_status_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vreset_status_tb"
rm -rf "$OUT"
