#!/bin/bash
# fdd testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_fdd.sh
#   OLD=<git rev>   FDD, blockDevMux and dev_WD2793 of that revision (shows the old behaviour)
#   PREV=<git rev>  the same for a revision with the current fdd interface (e.g. HEAD)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
OUT=$(mktemp -d)
CHANGED="rtl/peripheral/FDD rtl/blockDevMux.sv rtl/msx/devices/wd2793.sv"
SRC="$ROOT/rtl/peripheral/FDD/*.sv $ROOT/rtl/blockDevMux.sv $ROOT/rtl/msx/devices/wd2793.sv"
DEF=""
REV=${OLD:-$PREV}
if [ -n "$REV" ]; then
    mkdir -p "$OUT/old"
    for f in $(git -C "$ROOT" ls-tree -r --name-only "$REV" $CHANGED | grep '\.sv$'); do
        git -C "$ROOT" show "$REV:$f" > "$OUT/old/$(basename $f)"
    done
    SRC="$OUT/old/*.sv"
    [ -n "$OLD" ] && DEF="+define+OLD"
fi
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN $DEF \
    --top-module fdd_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" $SRC "$ROOT"/rtl/peripheral/FDC/WD279x/*.sv \
    "$ROOT/rtl/tb/dpram_stub.sv" fdd_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vfdd_tb" | grep -v "^Command \|^LOAD Track\|^Load Track"
rm -rf "$OUT"
