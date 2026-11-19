#!/bin/bash
# opl3.sv against Nuked OPL3 (tb/nuked, LGPL-2.1+), sample by sample; timers and status.
# Usage: wsl.exe -- bash rtl/peripheral/SOUND/opl4/tb/run_opl3.sh [seed [random samples]]
#   DUT=<file>: another opl3.sv (a mutant must fail)
set -e
cd "$(dirname "$0")"
DUT=$(realpath "${DUT:-../opl3.sv}")
OUT=$(mktemp -d)
gcc -O2 -c nuked/opl3.c -o "$OUT/nuked_opl3.o"
verilator --cc --exe --build -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module opl3 -Mdir "$OUT" -CFLAGS "-I$(pwd)/nuked" -LDFLAGS "$OUT/nuked_opl3.o" \
    "$DUT" "$(pwd)/opl3_tb.cpp" > "$OUT/build.log" 2>&1 || { grep -E "%Error|error" "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vopl3" "$@"
rm -rf "$OUT"
