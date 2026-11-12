#!/bin/bash
# SD window of the MFRSD with spi_divmmc (Verilator --timing), see mfrsd_sd_tb.sv.
#   wsl.exe -- bash rtl/msx/msx_slots/tb/run_mfrsd_sd.sh
#   OLD=<git rev>: mfrsd.sv of that revision (without sd_wait)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../../.. && pwd)
OUT=$(mktemp -d)
MF="$ROOT/rtl/msx/msx_slots/mappers/mfrsd.sv"
DEF=""
if [ -n "$OLD" ]; then
    git -C "$ROOT" show "$OLD:rtl/msx/msx_slots/mappers/mfrsd.sv" > "$OUT/mfrsd.sv"
    MF="$OUT/mfrsd.sv"
    DEF="+define+OLD"
fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module mfrsd_sd_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" "$MF" "$ROOT/rtl/spi_divmmc.sv" mfrsd_sd_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vmfrsd_sd_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
