#!/bin/bash
# mapper_konami testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_konami.sh
# Optional $1 = alternative konami.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../mappers/konami.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module konami_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" konami_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vkonami_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
