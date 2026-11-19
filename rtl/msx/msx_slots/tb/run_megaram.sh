#!/bin/bash
# mapper_megaram testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_megaram.sh    (OLD=<git rev>: megaram.sv of that revision)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../../.. && pwd)
OUT=$(mktemp -d)
DUT="$ROOT/rtl/msx/msx_slots/mappers/megaram.sv"
if [ -n "$OLD" ]; then
    git -C "$ROOT" show "$OLD:rtl/msx/msx_slots/mappers/megaram.sv" > "$OUT/megaram.sv"
    DUT="$OUT/megaram.sv"
fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module megaram_tb -Mdir "$OUT" "$ROOT/rtl/package.sv" "$DUT" megaram_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmegaram_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
