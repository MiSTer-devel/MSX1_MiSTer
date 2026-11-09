#!/bin/bash
# TV80 bus timing tests, taken from the Sord M5 core (doc/sordm5-opravy.md).
#   wsl.exe -- bash rtl/peripheral/CPU/tb/run_tv80.sh
#
# 1. tb_tv80 - interrupt acknowledge (IM0/IM1/IM2) and NMI lengths, I/O cycle shape
# 2. tb_wait - /WAIT against the Z80 rule in every phase of a loop, without and with IN,
#              for a short and a long /WAIT
#
# ALT=<dir> takes tv80.sv, tv80a.sv and tv80_mcode.sv from <dir> (old code must fail).
set -e
cd "$(dirname "$0")"
C=$(cd .. && pwd)
A=$(cd "${ALT:-..}" && pwd)
TB=$(pwd)
SRC="$C/tv80_alu.sv $A/tv80_mcode.sv $C/tv80_reg.sv $A/tv80.sv $A/tv80a.sv"
OUT=$(mktemp -d)

build() {   # obj top sources...
    obj=$OUT/$1; top=$2; shift 2
    mkdir -p "$obj"
    verilator -cc --exe --build -O2 -Wno-fatal -Wno-lint -Wno-style --Mdir "$obj" \
        -o tb --top-module "$top" "$@" >"$obj/build.log" 2>&1 \
        || { grep -E "Error|error" "$obj/build.log" | head -20; exit 1; }
}

build tv80 tb_tv80 $SRC $TB/tb_tv80.sv $TB/tb_tv80.cpp
build wait tb_wait $SRC $TB/tb_wait.sv $TB/tb_wait.cpp

rc=0
echo "##### tb_tv80"
"$OUT/tv80/tb" || rc=1
for w in 7 53; do
    for io in "" io; do
        echo; echo "##### tb_wait $w $io"
        "$OUT/wait/tb" $w $io | grep -E "OK|FAIL|PASS|average" || rc=1
    done
done
rm -rf "$OUT"
echo; echo "run_tv80: $([ $rc = 0 ] && echo PASS || echo FAIL)"
exit $rc
