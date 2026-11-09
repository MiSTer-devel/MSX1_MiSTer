#!/bin/bash
# msx_cpu testbench (Verilator --timing).
#   wsl.exe -- bash rtl/tb/run_msx_cpu.sh                 golden suite (all speeds / waits)
#   wsl.exe -- bash rtl/tb/run_msx_cpu.sh +sel=1 +lat=2   single run with plusargs
# ALT=<dir> replaces tv80.sv, tv80a.sv and msx_cpu.sv (and tv80_reg.sv if present) with versions
# from <dir>, built with OLD_CPU (msx_cpu without the Z80 / R800 switch ports).
set -e
cd "$(dirname "$0")"
CPU=../peripheral/CPU
SRC_TV80=${ALT:-$CPU}/tv80.sv
SRC_TV80A=${ALT:-$CPU}/tv80a.sv
SRC_MSXCPU=${ALT:-..}/msx_cpu.sv
SRC_REG=$CPU/tv80_reg.sv
DEF=""
if [ -n "$ALT" ]; then
    DEF="+define+OLD_CPU"
    [ -f "$ALT/tv80_reg.sv" ] && SRC_REG=$ALT/tv80_reg.sv
fi
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -O2 $DEF \
    --top-module msx_cpu_tb -Mdir "$OUT" -I. \
    ../package.sv ../clock.sv $CPU/tv80_alu.sv $CPU/tv80_mcode.sv "$SRC_REG" \
    "$SRC_TV80" "$SRC_TV80A" "$SRC_MSXCPU" msx_cpu_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true

if [ $# -gt 0 ]; then
    "$OUT/Vmsx_cpu_tb" "$@" | grep -E "RESULT|LEN|PASS|FAIL"
else
    # Golden hash (n=200000) from the derived-clock implementation before CE, identical for
    # every speed/wait. lat = memory read latency margin of the CE version: lat+1 fails.
    # (derived-clock version had margin +1: 11/12, 7/8, 3/4)
    # sel wait lat
    while read -r sel wait lat; do
        for l in 0 $lat; do
            "$OUT/Vmsx_cpu_tb" +sel=$sel +wait=$wait +lat=$l +golden=b6e812a5 | grep -E 'PASS|FAIL' \
                | sed "s/^/sel=$sel wait=$wait lat=$l: /"
        done
    done <<'EOF'
0 0 10
0 1 11
2 0 6
2 1 7
1 0 2
1 1 3
EOF
    # Run-time speed switching (OCM turbo) at the 10.7 MHz latency margin, with and
    # without memory / I/O wait states.
    for a in "+switch=40" "+switch=3" "+switch=200 +wait=1" "+switch=8 +wait=1 +mwait=2 +iowait=3"; do
        "$OUT/Vmsx_cpu_tb" $a +lat=2 +golden=b6e812a5 | grep -E 'PASS|FAIL' | sed "s/^/$a lat=2: /"
    done
    # Wait states: strobe length in CPU clocks at 10.7 MHz, M1 wait 1 (base M1 3, MRD 2,
    # MWR 1, IORD/IOWR 2): memory +2 (M1 max(1,2)), I/O +3
    "$OUT/Vmsx_cpu_tb" +sel=1 +wait=1 +mwait=2 +iowait=3 +n=20000 | grep LEN \
        | grep -q "LEN M1 4..4 MRD 4..4 MWR 3..3 IORD 5..5 IOWR 5..5" \
        && echo "mwait=2 iowait=3: PASS lengths" || echo "mwait=2 iowait=3: FAILED lengths"
    # R800 multiplier (OCM CPU type): MULUB / MULUW only with r800, NOPs on the Z80
    "$OUT/Vmsx_cpu_tb" +mul +r800 | grep -E 'PASS|FAIL'
    "$OUT/Vmsx_cpu_tb" +mul       | grep -E 'PASS|FAIL'
fi
rm -rf "$OUT"
