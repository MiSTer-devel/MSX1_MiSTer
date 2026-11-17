#!/bin/bash
# vdpcmd (bengalack) in the VDP alone, against openMSX (vdp_vdpcmd_tb.sv, Verilator --timing).
#   wsl.exe -- bash rtl/peripheral/VIDEO/VDP/tb/run_vdp_vdpcmd.sh [gt|nms] [+k=<n>] [+only=<n>]
#   gt  = Panasonic FS-A1GT, 60 Hz, OUT every 78 cycles; nms = Philips NMS 8245, 50 Hz, 72 cycles
# ALT=<dir> takes the VDP sources from <dir>.
set -e
cd "$(dirname "$0")"
M=${1:-gt}; shift || true
V=$(cd "${ALT:-..}" && pwd)
OUT=$(mktemp -d)
verilator --binary --timing -O2 -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN \
    --top-module vdp_vdpcmd_tb -Mdir "$OUT" \
    $V/vdp_package.sv $V/vdp_ram.sv $V/vdp_spinforam.sv $V/vdp_hvcounter.sv $V/vdp_ssg.sv \
    $V/vdp_interrupt.sv $V/vdp_register.sv $V/vdp_command.sv $V/vdp_access_slots.sv \
    $V/vdp_colordec.sv $V/vdp_graphic123m.sv $V/vdp_graphic4567.sv $V/vdp_text12.sv \
    $V/vdp_sprite.sv $V/vdp_ntsc_pal.sv $V/vdp.sv vdp_vdpcmd_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -30; exit 1; }
"$OUT/Vvdp_vdpcmd_tb" +data="$(pwd)/vdpcmd_$M.txt" +ref="$(pwd)/vdpcmd_${M}_openmsx.txt" "$@"
rm -rf "$OUT"
