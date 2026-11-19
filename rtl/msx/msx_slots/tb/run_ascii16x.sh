#!/bin/bash
# mapper_ascii16x + flash testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ascii16x.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module ascii16x_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers/ascii16x.sv ../../../peripheral/flash.sv ascii16x_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vascii16x_tb"
rm -rf "$OUT"
