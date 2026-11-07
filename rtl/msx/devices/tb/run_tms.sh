#!/bin/bash
# dev_tms testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run_tms.sh
# Optional $1 = alternative tms.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../tms.sv}
V=../../../peripheral/VIDEO/VDP18
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module tms_tb -Mdir "$OUT" \
    ../../../package.sv ../../../clock.sv $V/vdp18_pack-p.sv $V/vdp18_col_pack-p.sv \
    $V/vdp18_core.sv $V/vdp18_clk_gen.sv $V/vdp18_hor_vert.sv $V/vdp18_ctrl.sv $V/vdp18_cpuio.sv \
    $V/vdp18_addr_mux.sv $V/vdp18_pattern.sv $V/vdp18_sprite.sv $V/vdp18_col_mux.sv \
    "$DUT" tms_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vtms_tb"
rm -rf "$OUT"
