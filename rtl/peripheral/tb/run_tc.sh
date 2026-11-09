#!/bin/bash
# TC8566AF testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_tc.sh
#   OLD_GLUE=1  dev_TC8566AF with the bugs of the TurboFDC2 glue: MOTORn not inverted, bit cell
#               80 clk, sysclk = sysCLK / 1000 (shows that the test catches them)
#   PREV=<rev>  core (rtl/peripheral/FDC/TC8566AF) and glue of that git revision, +define+PREV_CORE
#               (skips probes of signals the old core does not have)
#   NO_WRITE_GLUE=1  glue with WREN / WRBIT of the core left unconnected (before the write path)
set -e
cd "$(dirname "$0")"
ROOT=$(cd ../../.. && pwd)
OUT=$(mktemp -d)
GLUE="$ROOT/rtl/msx/devices/tc8566af.sv"
CORE=("$ROOT"/rtl/peripheral/FDC/TC8566AF/*.sv)
DEFS=""
if [ -n "$PREV" ]; then
    mkdir -p "$OUT/prev"
    CORE=()
    for f in $(git -C "$ROOT" ls-tree --name-only "$PREV" rtl/peripheral/FDC/TC8566AF/ | grep '\.sv$'); do
        git -C "$ROOT" show "$PREV:$f" > "$OUT/prev/$(basename "$f")"
        CORE+=("$OUT/prev/$(basename "$f")")
    done
    git -C "$ROOT" show "$PREV:rtl/msx/devices/tc8566af.sv" > "$OUT/prev_glue.sv"
    GLUE="$OUT/prev_glue.sv"
    DEFS="+define+PREV_CORE"
    echo "core and glue of $PREV: ${#CORE[@]} files"
fi
if [ -n "$OLD_GLUE" ]; then
    sed -e 's|assign FDD_bus.MOTORn = !(!sel\[1\] \&\& ctl0\[{2.b10, sel\[0\]}\]);   \/\/ bit 4 \/ 5|assign FDD_bus.MOTORn = sel[1] ? 1'"'"'b1 : ctl0[{2'"'"'b10, sel[0]}];|' \
        -e 's|localparam int BITLEN = 2 \* (sysCLK / 500_000);|localparam int BITLEN = 80;|' \
        -e 's|.sysclk(sysCLK / 1_000_000)|.sysclk(sysCLK / 1000)|' \
        "$GLUE" > "$OUT/tc8566af_glue.sv"
    grep -c "BITLEN = 80\|sysCLK / 1000)\|? 1'b1 : ctl0" "$OUT/tc8566af_glue.sv" | sed 's/^/old glue substitutions: /'
    GLUE="$OUT/tc8566af_glue.sv"
fi
if [ -n "$NO_WRITE_GLUE" ]; then
    sed -e 's|\.WREN(FDD_bus.WRITE_GATEn),.*|.WREN(),|' -e 's|\.WRBIT(FDD_bus.WRITE_DATAn),|.WRBIT(),|' \
        -e 's|^endmodule|assign FDD_bus.WRITE_GATEn = 1'"'"'b1; assign FDD_bus.WRITE_DATAn = 1'"'"'b1;\nendmodule|' \
        "$GLUE" > "$OUT/tc8566af_nowrite.sv"
    grep -c "WREN()\|WRBIT()" "$OUT/tc8566af_nowrite.sv" | sed 's/^/no write glue substitutions: /'
    GLUE="$OUT/tc8566af_nowrite.sv"
fi
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN $DEFS \
    --top-module tc8566af_tb -Mdir "$OUT" \
    "$ROOT/rtl/package.sv" "$ROOT/rtl/peripheral/FDC/package.sv" \
    "$ROOT"/rtl/peripheral/FDD/*.sv "$ROOT"/rtl/peripheral/FDC/modem/*.sv \
    "${CORE[@]}" "$ROOT/rtl/blockDevMux.sv" "$GLUE" \
    "$ROOT/rtl/tb/dpram_stub.sv" tc8566af_tb.sv > "$OUT/build.log" 2>&1 \
    || { grep -E "%Error" "$OUT/build.log" | head -30; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vtc8566af_tb" | grep -v "^Command \|^LOAD Track\|^Load Track"
rm -rf "$OUT"
