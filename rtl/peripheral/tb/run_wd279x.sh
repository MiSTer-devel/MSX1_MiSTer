#!/bin/bash
# wd279x testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_wd279x.sh
#   PREV=<git rev>  WD279x, modem and clockEnabler of that revision (shows the old behaviour)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
OUT=$(mktemp -d)
SRC="$ROOT/rtl/peripheral/FDC/WD279x/*.sv $ROOT/rtl/peripheral/FDC/modem/*.sv $ROOT/rtl/peripheral/FDD/clockEnabler.sv"
if [ -n "$PREV" ]; then
    mkdir -p "$OUT/prev"
    for f in $(git -C "$ROOT" ls-tree -r --name-only "$PREV" rtl/peripheral/FDC/WD279x rtl/peripheral/FDC/modem \
               rtl/peripheral/FDD/clockEnabler.sv | grep '\.sv$'); do
        git -C "$ROOT" show "$PREV:$f" > "$OUT/prev/$(basename $f)"
    done
    SRC="$OUT/prev/*.sv"
fi
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module wd279x_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" "$ROOT/rtl/peripheral/FDC/package.sv" $SRC wd279x_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
"$OUT/Vwd279x_tb" | grep -v "^Command "
rm -rf "$OUT"
