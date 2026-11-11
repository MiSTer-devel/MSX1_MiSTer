#!/bin/bash
# opl4_wave.sv against the reference model opl4_wave_gold.py (Verilator --timing).
# Usage: wsl.exe -- bash rtl/peripheral/SOUND/opl4/tb/run_opl4_wave.sh [seed [frames]]
#   DUT=<file>: another opl4_wave.sv (a mutant must fail)
#   ARGS="+free +slow=<n> +max_late=<n>": free running sample clock, memory answers after n clk,
#        at most max_late tone samples computed with old data
#   SCEN=chord: 24 tones at once (load on the sample memory) instead of the random music
set -e
cd "$(dirname "$0")"
DUT=$(realpath "${DUT:-../opl4_wave.sv}")
OUT=$(mktemp -d)
python3 opl4_wave_gold.py "$OUT" "${1:-1}" "${2:-60000}" $SCEN
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module opl4_wave_tb -Mdir "$OUT/obj" ../opl3.sv "$DUT" opl4_wave_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -20; exit 1; }
"$OUT/obj/Vopl4_wave_tb" +dir="$OUT" $ARGS | grep -E "FAIL|PASS|samples"
rm -rf "$OUT"
