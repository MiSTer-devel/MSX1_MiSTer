#!/bin/bash
# Undocumented flags of msx_cpu / TV80 (Verilator --timing): MEMPTR (Z80), block I/O and BIT
# flags (Z80, R800).   wsl.exe -- bash rtl/tb/run_z80_undoc.sh
# ALT=<dir> takes tv80.sv and tv80_alu.sv from <dir> (the old code must fail).
# z80_memptr.hex is built from z80_memptr.asm by z80_memptr.sh.
set -e
cd "$(dirname "$0")"
CPU=../peripheral/CPU
A=${ALT:-$CPU}
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 \
    --top-module z80_undoc_tb -Mdir "$OUT" \
    ../package.sv ../clock.sv $A/tv80_alu.sv $CPU/tv80_mcode.sv $CPU/tv80_reg.sv \
    $A/tv80.sv $CPU/tv80a.sv ../msx_cpu.sv z80_undoc_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
for a in "+memptr" "" "+r800=1"; do
    "$OUT/Vz80_undoc_tb" $a | grep -E "PASS|FAIL|note"
done
rm -rf "$OUT"
