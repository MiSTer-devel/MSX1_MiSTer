#!/bin/bash
# flash testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_flash.sh [old_dir]
#   old_dir: directory with flash.sv and package.sv before the rewrite (no area bounds, no
#            reset); runs the checks both versions have in common
set -e
[ -n "$1" ] && OLD=$(realpath "$1")
cd "$(dirname "$0")"
PKG=../../package.sv; DUT=../flash.sv; DEFS=""
[ -n "$OLD" ] && { PKG="$OLD/package.sv"; DUT="$OLD/flash.sv"; DEFS="+define+OLD_FLASH"; }
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEFS \
    --top-module flash_tb -Mdir "$OUT" \
    "$PKG" "$DUT" flash_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vflash_tb"
rm -rf "$OUT"
