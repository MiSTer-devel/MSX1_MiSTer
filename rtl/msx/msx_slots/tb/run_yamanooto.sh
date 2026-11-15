#!/bin/bash
# mapper_yamanooto + flash testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_yamanooto.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module yamanooto_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers/yamanooto.sv ../../../peripheral/flash.sv yamanooto_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vyamanooto_tb"
rm -rf "$OUT"
