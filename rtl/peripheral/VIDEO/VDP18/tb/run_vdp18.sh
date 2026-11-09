#!/bin/bash
# VDP18 (TMS9918A/28A/29A) tests, taken from the Sord M5 core (doc/sordm5-opravy.md).
#   wsl.exe -- bash rtl/peripheral/VIDEO/VDP18/tb/run_vdp18.sh
#
# 1. tb_vdp_addr   - VRAM addresses of vdp18_addr_mux in all modes against a C++ model
# 2. tb_vdp_frame  - whole frames against a reference renderer (failing scenes leave
#                    <scene>_got.ppm / _exp.ppm in the build directory)
# 3. tb_vdp_timing - vertical frame timing (NTSC, PAL) measured on the outputs
# 4. tb_vdp_status - status flags C, 5S and the sprite number, read through the CPU port
#
# ALT=<dir> takes the VDP18 sources from <dir> (old code must fail); OLD_VDP=1 builds
# tb_vdp_addr without the bitmap_i port of the undocumented modes.
set -e
cd "$(dirname "$0")"
R=$(cd "${ALT:-..}" && pwd)
TB=$(pwd)
DEF=""
[ -n "$OLD_VDP" ] && DEF="+define+OLD_VDP"
VDP="$R/vdp18_pack-p.sv $R/vdp18_col_pack-p.sv $R/vdp18_core.sv $R/vdp18_clk_gen.sv \
     $R/vdp18_hor_vert.sv $R/vdp18_ctrl.sv $R/vdp18_cpuio.sv $R/vdp18_addr_mux.sv \
     $R/vdp18_pattern.sv $R/vdp18_sprite.sv $R/vdp18_col_mux.sv"
OUT=$(mktemp -d)

build() {   # obj top sources...
    obj=$OUT/$1; top=$2; shift 2
    mkdir -p "$obj"
    verilator -cc --exe --build -O2 -Wno-fatal -Wno-lint -Wno-style $DEF -I"$R" --Mdir "$obj" \
        -o tb --top-module "$top" "$@" >"$obj/build.log" 2>&1 \
        || { grep -E "Error|error" "$obj/build.log" | head -20; exit 1; }
}

build addr   tb_vdp_addr  $R/vdp18_pack-p.sv $R/vdp18_addr_mux.sv $TB/tb_vdp_addr.sv $TB/tb_vdp_addr.cpp
build frame  tb_vdp_frame $VDP $TB/tb_vdp_frame.sv $TB/tb_vdp_frame.cpp
build timing tb_vdp_frame $VDP $TB/tb_vdp_frame.sv $TB/tb_vdp_timing.cpp
build status tb_vdp_frame $VDP $TB/tb_vdp_frame.sv $TB/tb_vdp_status.cpp

rc=0
for t in addr frame timing status; do
    echo "##### tb_vdp_$t"
    (cd "$OUT/$t" && ./tb) || rc=1
    echo
done
[ -n "$KEEP" ] && echo "build kept in $OUT" || rm -rf "$OUT"
echo "run_vdp18: $([ $rc = 0 ] && echo PASS || echo FAIL)"
exit $rc
