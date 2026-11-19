#!/bin/bash
# system_memory + flash testbench (Verilator --timing).
#   wsl.exe -- bash rtl/tb/run_system_memory.sh
# ALT=<dir> takes system_memory.sv, flash.sv and package.sv from <dir>; OLD=1 = wiring before the fix.
set -e
cd "$(dirname "$0")"
PKG=${ALT:-..}/package.sv
SYSMEM=${ALT:-..}/system_memory.sv
FLASH=${ALT:-../peripheral}/flash.sv
DEFS=""; [ -n "$OLD" ] && DEFS="+define+OLD"
[ -n "$ALT" ] && DEFS="$DEFS +define+OLD_FLASH"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEFS \
    --top-module system_memory_tb -Mdir "$OUT" \
    "$PKG" dpram_stub.sv "$SYSMEM" "$FLASH" system_memory_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vsystem_memory_tb"
rm -rf "$OUT"
