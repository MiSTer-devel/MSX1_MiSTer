#!/bin/bash
# NMOS / CMOS Z80 and R800 differences of msx_cpu (Verilator --timing): SCF / CCF flags, OUT (C),0.
#   wsl.exe -- bash rtl/tb/run_z80_cmos.sh
# ALT=<dir> takes tv80.sv from <dir> (needs the CMOS port; an older tv80.sv does not build).
set -e
cd "$(dirname "$0")"
CPU=../peripheral/CPU
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 \
    --top-module z80_cmos_tb -Mdir "$OUT" \
    ../package.sv ../clock.sv $CPU/tv80_alu.sv $CPU/tv80_mcode.sv $CPU/tv80_reg.sv \
    "${ALT:-$CPU}/tv80.sv" $CPU/tv80a.sv ../msx_cpu.sv z80_cmos_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
for a in "+cmos=0" "+cmos=1" "+cmos=0 +r800=1" "+cmos=1 +r800=1"; do
    "$OUT/Vz80_cmos_tb" $a | grep -E "PASS|FAIL"
done
rm -rf "$OUT"
