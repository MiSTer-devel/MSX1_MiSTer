#!/bin/bash
# sound_mix testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/tb/run_sound_mix.sh
# Optional $1 = alternative sound_mix implementation (e.g. model of the old mixing)
set -e
cd "$(dirname "$0")"
DUT=${1:-../sound_mix.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module sound_mix_tb -Mdir "$OUT" \
    ../../package.sv "$DUT" sound_mix_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vsound_mix_tb"
rm -rf "$OUT"
