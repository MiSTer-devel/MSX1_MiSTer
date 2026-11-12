#!/bin/bash
# dev_opm testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_opm.sh
# Optional $1 = alternative opm.sv, JT51=<dir> alternative jt51 hdl directory (old versions)
set -e
cd "$(dirname "$0")"
DUT=${1:-../opm.sv}
JT=${JT51:-../../../peripheral/SOUND/jt51/hdl}
OUT=$(mktemp -d)
verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style \
    --top-module opm_tb -Mdir "$OUT" -I"$JT" \
    ../../../package.sv ../../../clock.sv $(ls "$JT"/jt51*.v) \
    "$DUT" opm_tb.sv > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vopm_tb" | grep -E "PASS|FAIL|ok |timer B"
rm -rf "$OUT"
