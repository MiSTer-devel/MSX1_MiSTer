#!/bin/bash
# ps2mouse testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_ps2mouse.sh
# Optional $1 = alternative ps2mouse (e.g. MSX_MiSTer rtl/peripheral/ps2mouse.v)
set -e
cd "$(dirname "$0")"
DUT=${1:-../ps2mouse.sv}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module ps2mouse_tb -Mdir "$OUT" "$DUT" ps2mouse_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vps2mouse_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
