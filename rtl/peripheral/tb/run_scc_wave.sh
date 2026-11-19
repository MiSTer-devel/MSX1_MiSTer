#!/bin/bash
# scc_wave testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_scc_wave.sh [scc_wave.sv]
# Optional $1 = alternative scc_wave.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../SOUND/scc_wave.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module scc_wave_tb -Mdir "$OUT" \
    "$DUT" scc_wave_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vscc_wave_tb" | grep -E "^(ok|PASS|FAIL)"
rm -rf "$OUT"
