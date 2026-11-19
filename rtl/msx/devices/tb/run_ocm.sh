#!/bin/bash
# dev_ocm testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_ocm.sh
# Optional $1 = alternative ocm.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../ocm.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module ocm_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" ocm_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vocm_tb"
rm -rf "$OUT"
