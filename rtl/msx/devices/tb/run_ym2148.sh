#!/bin/bash
# YM2148 MIDI out testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/devices/tb/run_ym2148.sh
#   ALT=<file>: another ym2148.sv (old version)
set -e
cd "$(dirname "$0")"
SRC="../ym2148.sv"
[ -n "$ALT" ] && SRC="$ALT"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module ym2148_tb -Mdir "$OUT" \
    ../../../package.sv $SRC ym2148_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error|%Warning-(WIDTH|CASEINCOMPLETE|MULTIDRIVEN|LATCH)' "$OUT/build.log" || true
"$OUT/Vym2148_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
