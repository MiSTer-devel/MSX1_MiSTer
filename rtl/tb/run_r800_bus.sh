#!/bin/bash
# R800 single phase bus of msx_cpu against the two phase one (Verilator --timing).
#   wsl.exe -- bash rtl/tb/run_r800_bus.sh            memory latency 2 (as the SDRAM) and 0
#   wsl.exe -- bash rtl/tb/run_r800_bus.sh +lat=3     must fail: the data would come one clk late
cd "$(dirname "$0")"
CPU=../peripheral/CPU
OUT=$(mktemp -d)
python3 z80_timing_prog.py "$OUT" > "$OUT/gen.log"
for lvl in 1 2; do
    verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 -GFAST_LEVEL=$lvl         --top-module r800_bus_tb -Mdir "$OUT/$lvl" -I"$OUT"         ../package.sv ../clock.sv $CPU/tv80_alu.sv $CPU/tv80_mcode.sv $CPU/tv80_reg.sv         $CPU/tv80.sv $CPU/tv80a.sv ../msx_cpu.sv r800_bus_tb.sv         > "$OUT/build$lvl.log" 2>&1 || { grep -A6 "%Error" "$OUT/build$lvl.log" | head -40; exit 1; }
    grep -E '%Error' "$OUT/build$lvl.log" || true
    if [ $# -gt 0 ]; then
        "$OUT/$lvl/Vr800_bus_tb" +hex="$OUT/z80_timing.hex" "$@" | grep -E "PASS|FAIL" | head -12
    else
        for a in "+lat=2" "+lat=0"; do
            "$OUT/$lvl/Vr800_bus_tb" +hex="$OUT/z80_timing.hex" $a | grep -E "PASS|FAIL" | head -12
        done
    fi
done
rm -rf "$OUT"
