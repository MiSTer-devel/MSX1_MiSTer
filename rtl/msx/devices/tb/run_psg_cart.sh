#!/bin/bash
# dev_psg: second PSG of a cartridge (Yamanooto), ECHO. Usage: wsl.exe -- bash rtl/msx/devices/tb/run_psg_cart.sh
set -e
cd "$(dirname "$0")"
JT=../../../peripheral/SOUND/jt49/hdl
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module psg_cart_tb -Mdir "$OUT" \
    ../../../package.sv ../../../clock.sv ../../../peripheral/ps2mouse.sv \
    $JT/jt49_bus.v $JT/jt49.v $JT/jt49_cen.v $JT/jt49_div.v $JT/jt49_eg.v $JT/jt49_exp.v $JT/jt49_noise.v \
    ../psg.sv psg_cart_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vpsg_cart_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
