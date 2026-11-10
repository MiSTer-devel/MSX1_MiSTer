#!/bin/bash
# V9938 / V9958 vertical timing against openMSX (Verilator --timing).
#   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_timing.sh
# ALT=<dir> takes the VDP sources from <dir> (the old code must fail).
# +cmd: also prints the duration of VDP commands (SCREEN 5, informational), +pal in PAL.
set -e
cd "$(dirname "$0")"
V=$(cd "${ALT:-..}" && pwd)
# command timing: vdp_access_slots (now) or vdp_wait_control (older sources)
CMDT=$V/vdp_access_slots.sv; [ -f "$CMDT" ] || CMDT=$V/vdp_wait_control.sv
OUT=$(mktemp -d)
verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module vdp_timing_tb -Mdir "$OUT" \
    $V/vdp_package.sv $V/vdp_ram.sv $V/vdp_spinforam.sv $V/vdp_hvcounter.sv $V/vdp_ssg.sv \
    $V/vdp_interrupt.sv $V/vdp_register.sv $V/vdp_command.sv $CMDT \
    $V/vdp_colordec.sv $V/vdp_graphic123m.sv $V/vdp_graphic4567.sv $V/vdp_text12.sv \
    $V/vdp_sprite.sv $V/vdp_ntsc_pal.sv $V/vdp.sv vdp_timing_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -30; exit 1; }
"$OUT/Vvdp_timing_tb" "$@"
rc=$?
rm -rf "$OUT"
exit $rc
