#!/bin/bash
# mapper_generic8k / mapper_generic16k testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_generic.sh [generic8k.sv generic16k.sv]
set -e
cd "$(dirname "$0")"
G8=${1:-../mappers/generic8k.sv}
G16=${2:-../mappers/generic16k.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module generic_tb -Mdir "$OUT" \
    ../../../package.sv "$G8" "$G16" generic_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vgeneric_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
