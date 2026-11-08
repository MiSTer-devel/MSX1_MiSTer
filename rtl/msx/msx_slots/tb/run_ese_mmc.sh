#!/bin/bash
# ESE-RAM MegaSD window + spi_divmmc testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_ese_mmc.sh
#        OLD=<git rev> ... runs it against package.sv, eseRam.sv, spi_divmmc.sv of that revision
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../../.. && pwd)
OUT=$(mktemp -d)
SRC="$ROOT/rtl/package.sv $ROOT/rtl/msx/msx_slots/mappers/eseRam.sv $ROOT/rtl/spi_divmmc.sv"
DEF=""
if [ -n "$OLD" ]; then
    for f in rtl/package.sv rtl/msx/msx_slots/mappers/eseRam.sv rtl/spi_divmmc.sv; do
        git -C "$ROOT" show "$OLD:$f" > "$OUT/$(basename $f)"
    done
    SRC="$OUT/package.sv $OUT/eseRam.sv $OUT/spi_divmmc.sv"
    DEF="+define+OLD"
fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module ese_mmc_tb -Mdir "$OUT" $SRC ese_mmc_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vese_mmc_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
