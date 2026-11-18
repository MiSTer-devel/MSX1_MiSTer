#!/bin/bash
# RP5C01 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_rtc.sh [rtc.sv]
# Optional $1 = alternative rtc.sv (e.g. the old one, which must fail)
set -e
cd "$(dirname "$0")"
DUT=${1:-../rtc.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module rtc_tb -Mdir "$OUT" "$DUT" rtc_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
"$OUT/Vrtc_tb"
rm -rf "$OUT"
