#!/bin/bash
# dev_systimer testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_systimer.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module systimer_tb -Mdir "$OUT" \
    ../../../package.sv ../systimer.sv systimer_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vsystimer_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
