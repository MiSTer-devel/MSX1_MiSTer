#!/bin/bash
# SRAMs of the machine devices: power-on FFh, write / read back, sram_init (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/devices/tb/run_sram_init.sh
#   OLD=<dir>: rtc.sv, devices/rtc.sv and matsushita.sv from <dir> (modules without sram_init)
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
SRC="../../../peripheral/rtc.sv ../rtc.sv ../matsushita.sv ../s1985.sv"; DEF=""
if [ -n "$OLD" ]; then SRC="$OLD/peripheral_rtc.sv $OLD/rtc.sv $OLD/matsushita.sv"; DEF="+define+OLD"; fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module sram_init_tb -Mdir "$OUT" \
    ../../../package.sv $SRC sram_init_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error|%Warning-(WIDTH|CASEINCOMPLETE|MULTIDRIVEN|LATCH)' "$OUT/build.log" || true
"$OUT/Vsram_init_tb" | grep -E "^(ok|PASS|FAIL)" | head -40
rm -rf "$OUT"
