#!/bin/bash
# fdd testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_fdd.sh
#   OLD=<git rev>   FDD, blockDevMux and dev_WD2793 of that revision (shows the old behaviour)
#   PREV=<git rev>  the same for a revision with the current fdd interface (e.g. HEAD)
#   NO_MOTOR_OFF=1  fdd without the motor_off_ms input (revisions before 2026-11-09)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
OUT=$(mktemp -d)
CHANGED="rtl/peripheral/FDD rtl/peripheral/FDC/WD279x rtl/peripheral/FDC/modem rtl/blockDevMux.sv rtl/msx/devices/wd2793.sv"
SRC="$ROOT/rtl/peripheral/FDD/*.sv $ROOT/rtl/peripheral/FDC/WD279x/*.sv $ROOT/rtl/peripheral/FDC/modem/*.sv"
SRC="$SRC $ROOT/rtl/blockDevMux.sv $ROOT/rtl/msx/devices/wd2793.sv"
DEF=""
REV=${OLD:-$PREV}
if [ -n "$REV" ]; then
    mkdir -p "$OUT/old"
    for f in $(git -C "$ROOT" ls-tree -r --name-only "$REV" $CHANGED | grep '\.sv$'); do
        git -C "$ROOT" show "$REV:$f" > "$OUT/old/$(basename $f)"
    done
    SRC="$OUT/old/*.sv"
    [ -n "$OLD" ] && DEF="+define+OLD"
    # before the shared modem library: demodulators were wd279x_*dem in WD279x
    [ -z "$(git -C "$ROOT" ls-tree "$REV" rtl/peripheral/FDC/modem)" ] && DEF="$DEF +define+MODEM_OLD"
    # before the density input of dev_WD2793 (FDD_if.MFM from the controller)
    git -C "$ROOT" show "$REV:rtl/msx/devices/wd2793.sv" | grep -q density || DEF="$DEF +define+NO_DENSITY"
fi
[ -n "$NO_MOTOR_OFF" ] && DEF="$DEF +define+NO_MOTOR_OFF"
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN $DEF \
    --top-module fdd_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" "$ROOT/rtl/peripheral/FDC/package.sv" $SRC \
    "$ROOT/rtl/tb/dpram_stub.sv" fdd_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vfdd_tb" | grep -v "^Command \|^LOAD Track\|^Load Track"
rm -rf "$OUT"
