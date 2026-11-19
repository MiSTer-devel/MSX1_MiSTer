#!/bin/bash
# mapper_kuc + flash testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_kuc.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module kuc_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers/kuc.sv ../../../peripheral/flash.sv kuc_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vkuc_tb"
rm -rf "$OUT"
