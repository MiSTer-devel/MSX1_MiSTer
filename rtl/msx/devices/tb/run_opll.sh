#!/bin/bash
# dev_opll testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_opll.sh
# Optional $1 = alternative opll.sv (e.g. old version for comparison); NO_WAIT=1 for a version
# without the enawait / wait_rq ports
set -e
cd "$(dirname "$0")"
DUT=${1:-../opll.sv}
IKA=../../../peripheral/SOUND/ikaopll/src
DEF=""
[ -n "$NO_WAIT" ] && DEF="+define+NO_WAIT"
OUT=$(mktemp -d)
verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module opll_tb -Mdir "$OUT" \
    ../../../package.sv ../../../clock.sv "$IKA"/IKAOPLL.v "$IKA"/IKAOPLL_modules/IKAOPLL_*.v \
    "$DUT" opll_tb.sv > "$OUT/build.log" 2>&1 || { grep -E "%Error" "$OUT/build.log" | head -20; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vopll_tb" | grep -E "PASS|FAIL|OPLL:"
rm -rf "$OUT"
