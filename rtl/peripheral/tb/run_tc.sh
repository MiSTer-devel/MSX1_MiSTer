#!/bin/bash
# TC8566AF testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_tc.sh
#   OLD_GLUE=1  dev_TC8566AF with the bugs of the TurboFDC2 glue: MOTORn not inverted, bit cell
#               80 clk, sysclk = sysCLK / 1000 (shows that the test catches them)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
OUT=$(mktemp -d)
GLUE="$ROOT/rtl/msx/devices/tc8566af.sv"
if [ -n "$OLD_GLUE" ]; then
    sed -e 's|assign FDD_bus.MOTORn = !(!sel\[1\] \&\& ctl0\[{2.b10, sel\[0\]}\]);   \/\/ bit 4 \/ 5|assign FDD_bus.MOTORn = sel[1] ? 1'"'"'b1 : ctl0[{2'"'"'b10, sel[0]}];|' \
        -e 's|localparam int BITLEN = 2 \* (sysCLK / 500_000);|localparam int BITLEN = 80;|' \
        -e 's|tc8566af #(.sysclk(sysCLK / 1_000_000)) fdc|tc8566af #(.sysclk(sysCLK / 1000)) fdc|' \
        "$GLUE" > "$OUT/tc8566af_glue.sv"
    grep -c "BITLEN = 80\|sysCLK / 1000)\|? 1'b1 : ctl0" "$OUT/tc8566af_glue.sv" | sed 's/^/old glue substitutions: /'
    GLUE="$OUT/tc8566af_glue.sv"
fi
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module tc8566af_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" "$ROOT"/rtl/peripheral/FDD/*.sv "$ROOT"/rtl/peripheral/FDC/modem/*.sv \
    "$ROOT"/rtl/peripheral/FDC/TC8566AF/*.sv "$ROOT/rtl/blockDevMux.sv" "$GLUE" \
    "$ROOT/rtl/tb/dpram_stub.sv" tc8566af_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vtc8566af_tb" | grep -v "^Command \|^LOAD Track\|^Load Track"
rm -rf "$OUT"
