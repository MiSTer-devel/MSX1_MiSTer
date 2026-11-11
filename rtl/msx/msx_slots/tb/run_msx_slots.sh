#!/bin/bash
# msx_slots testbench (Verilator --timing). Usage:
#   wsl.exe -- bash rtl/msx/msx_slots/tb/run_msx_slots.sh [git-ref]
# With a git ref, msx_slots.sv and subslot.sv are taken from that ref (shows the old behaviour).
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
SLOTS=../../msx_slots.sv
SUBSLOT=../subslot.sv
if [ -n "$1" ]; then
    ROOT=$(cd ../../../.. && pwd)
    git -C "$ROOT" show "$1:rtl/msx/msx_slots.sv"         > "$OUT/msx_slots.sv"
    git -C "$ROOT" show "$1:rtl/msx/msx_slots/subslot.sv" > "$OUT/subslot.sv"
    SLOTS=$OUT/msx_slots.sv
    SUBSLOT=$OUT/subslot.sv
fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module msx_slots_tb -Mdir "$OUT" \
    ../../../package.sv "$SLOTS" "$SUBSLOT" ../mappers.sv ../mappers/*.sv msx_slots_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmsx_slots_tb"
rm -rf "$OUT"
