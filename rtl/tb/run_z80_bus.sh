#!/bin/bash
# Bus cycles inside an instruction, TV80a against the Z80 (Verilator --timing).
#   wsl.exe -- bash rtl/tb/run_z80_bus.sh
# ALT=<dir> takes tv80*.sv from <dir> when present there (the core before the fix must fail).
cd "$(dirname "$0")"
CPU=../peripheral/CPU
pick() { if [ -n "$ALT" ] && [ -f "$ALT/$(basename "$1")" ]; then echo "$ALT/$(basename "$1")"; else echo "$1"; fi; }
OUT=$(mktemp -d)
python3 z80_timing_prog.py "$OUT" > "$OUT/gen.log"
DEF=""
grep -q "input  *FAST" "$(pick $CPU/tv80a.sv)" && DEF="+define+TV80_FAST"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 $DEF \
    --top-module z80_bus_tb -Mdir "$OUT" -I"$OUT" \
    "$(pick $CPU/tv80_alu.sv)" "$(pick $CPU/tv80_mcode.sv)" "$(pick $CPU/tv80_reg.sv)" \
    "$(pick $CPU/tv80.sv)" "$(pick $CPU/tv80a.sv)" z80_bus_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vz80_bus_tb" +hex="$OUT/z80_timing.hex" | grep -E "PASS|FAIL"
rm -rf "$OUT"
