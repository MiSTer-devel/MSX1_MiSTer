#!/bin/bash
# reset_sync testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/lib/tb/run.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module reset_sync_tb -Mdir "$OUT" \
    ../reset_sync.sv reset_sync_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vreset_sync_tb"
rm -rf "$OUT"
