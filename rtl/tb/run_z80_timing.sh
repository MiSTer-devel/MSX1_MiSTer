#!/bin/bash
# Z80 instruction timing of msx_cpu (Verilator --timing): every opcode against the Zilog
# T states plus the MSX M1 wait state.
#   wsl.exe -- bash rtl/tb/run_z80_timing.sh            M1 wait 1 and 0, 3.58 and 5.37 MHz
#   wsl.exe -- bash rtl/tb/run_z80_timing.sh +wait=1 +v single verbose run
# ALT=<dir> takes tv80*.sv and msx_cpu.sv from <dir> when present there.
set -e
cd "$(dirname "$0")"
CPU=../peripheral/CPU
pick() { if [ -n "$ALT" ] && [ -f "$ALT/$(basename "$1")" ]; then echo "$ALT/$(basename "$1")"; else echo "$1"; fi; }
OUT=$(mktemp -d)
python3 z80_timing_prog.py "$OUT" > "$OUT/gen.log"
DEF=""
grep -q "input  *turbor" "$(pick ../msx_cpu.sv)" && DEF="+define+CPU_HAS_TURBOR"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 $DEF \
    --top-module z80_timing_tb -Mdir "$OUT" -I"$OUT" \
    ../package.sv ../clock.sv "$(pick $CPU/tv80_alu.sv)" "$(pick $CPU/tv80_mcode.sv)" "$(pick $CPU/tv80_reg.sv)" \
    "$(pick $CPU/tv80.sv)" "$(pick $CPU/tv80a.sv)" "$(pick ../msx_cpu.sv)" z80_timing_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true

if [ $# -gt 0 ]; then
    "$OUT/Vz80_timing_tb" +hex="$OUT/z80_timing.hex" "$@" | grep -E "PASS|FAIL|ok "
else
    for a in "+wait=1" "+wait=0" "+wait=1 +sel=2"; do
        "$OUT/Vz80_timing_tb" +hex="$OUT/z80_timing.hex" $a | grep -E "PASS|FAIL" | head -60
    done
fi
rm -rf "$OUT"
