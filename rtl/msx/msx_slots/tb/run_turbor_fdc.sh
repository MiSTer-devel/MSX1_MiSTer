#!/bin/bash
# mapper_turbor_fdc testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_turbor_fdc.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module turbor_fdc_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers/turbor_fdc.sv turbor_fdc_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vturbor_fdc_tb"
rm -rf "$OUT"
