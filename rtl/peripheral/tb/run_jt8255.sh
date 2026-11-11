#!/bin/bash
# jt8255 testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_jt8255.sh
# PREV=<git ref>: jt8255.v from that ref (wsl.exe -- env PREV=HEAD bash ...)
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
SRC=../jt8255.v
if [ -n "$PREV" ]; then SRC="$OUT/jt8255_prev.v"; git show "$PREV:rtl/peripheral/jt8255.v" > "$SRC"; fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module jt8255_tb -Mdir "$OUT" \
    "$SRC" jt8255_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vjt8255_tb"
rm -rf "$OUT"
