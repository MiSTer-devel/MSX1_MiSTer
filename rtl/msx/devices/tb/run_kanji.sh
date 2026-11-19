#!/bin/bash
# dev_kanji testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_kanji.sh
# Optional $1 = alternative kanji.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../kanji.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module kanji_tb -Mdir "$OUT" \
    ../../../package.sv "$DUT" kanji_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vkanji_tb"
rm -rf "$OUT"
