#!/bin/bash
# keyboard testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_keyboard.sh [keyboard.sv]
# Optional $1 = alternative keyboard.sv (e.g. an old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../keyboard.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module keyboard_tb -Mdir "$OUT" \
    ../../package.sv ../../tb/spram_stub.sv "$DUT" keyboard_tb.sv > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vkeyboard_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
