#!/bin/bash
# R800 timing of msx_cpu (Verilator --timing): 7.16 MHz, no M1 wait, VDP I/O spacing, T9769 wait.
#   wsl.exe -- bash rtl/tb/run_r800_timing.sh            turbor = 1 and 0
#   wsl.exe -- bash rtl/tb/run_r800_timing.sh +v         single verbose run
# ALT=<dir> takes tv80.sv, tv80a.sv, tv80_reg.sv and msx_cpu.sv from <dir> and builds the tb
# without the turbo R ports (OLD_CPU): the core before the R800 timing must fail.
set -e
cd "$(dirname "$0")"
CPU=../peripheral/CPU
DEF=""
[ -n "$ALT" ] && DEF="+define+OLD_CPU"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 $DEF \
    --top-module r800_timing_tb -Mdir "$OUT" \
    ../package.sv ../clock.sv $CPU/tv80_alu.sv $CPU/tv80_mcode.sv "${ALT:-$CPU}/tv80_reg.sv" \
    "${ALT:-$CPU}/tv80.sv" "${ALT:-$CPU}/tv80a.sv" "${ALT:-..}/msx_cpu.sv" r800_timing_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true

if [ $# -gt 0 ]; then
    "$OUT/Vr800_timing_tb" "$@" | grep -E "PASS|FAIL|NOP|active"
else
    for t in 1 0; do
        "$OUT/Vr800_timing_tb" +turbor=$t | grep -E "PASS|FAIL"
    done
fi
rm -rf "$OUT"
