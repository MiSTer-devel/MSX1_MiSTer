#!/bin/bash
# dev_opm testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_opm.sh
# Optional $1 = alternative opm.sv, JT51_QIP=<qip> alternative jt51 file list. The default is
# the synthesis list jt51_custom/jt51.qip: jt51.v and jt51_timers.v from jt51_custom, the rest
# from the jt51 submodule.
set -e
cd "$(dirname "$0")"
DUT=${1:-../opm.sv}
QIP=${JT51_QIP:-../../../peripheral/SOUND/jt51_custom/jt51.qip}
JT=$(sed -n 's/.*qip_path) *\([^ ]*\) *\].*/\1/p' "$QIP" | tr -d '\r' | sed "s|^|$(dirname "$QIP")/|")
OUT=$(mktemp -d)
verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style \
    --top-module opm_tb -Mdir "$OUT" \
    ../../../package.sv ../../../clock.sv $JT \
    "$DUT" opm_tb.sv > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vopm_tb" | grep -E "PASS|FAIL|ok |timer B"
rm -rf "$OUT"
