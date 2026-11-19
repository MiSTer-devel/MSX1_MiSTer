#!/bin/bash
# mapper_konami_scc testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_konami_scc.sh
# PREV=<git ref>: mapper from that ref (wsl.exe -- env PREV=HEAD bash ...)
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
SRC=../mappers/konami_scc.sv
if [ -n "$PREV" ]; then SRC="$OUT/konami_scc_prev.sv"; git show "$PREV:rtl/msx/msx_slots/mappers/konami_scc.sv" > "$SRC"; fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module konami_scc_tb -Mdir "$OUT" \
    ../../../package.sv "$SRC" konami_scc_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vkonami_scc_tb"
rm -rf "$OUT"
