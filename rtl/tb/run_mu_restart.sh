#!/bin/bash
# memory_upload: load requests during a running upload (Verilator --timing), see mu_restart_tb.sv.
#   wsl.exe -- bash rtl/tb/run_mu_restart.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
#   OLD=<git rev | file>  memory_upload.sv of that revision (fe7ca9e: before the fix, must fail)
#   ARGS="+dense=<n> +stride=<n>"  every stride-th clock, and every clock of the last n
set -e
PACK=$(realpath "$1"); FW=$(realpath "$2")
[ -f "$OLD" ] && OLD=$(realpath "$OLD")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
MU=../memory_upload.sv
if [ -f "$OLD" ]; then MU="$OLD"
elif [ -n "$OLD" ]; then git -C .. show "$OLD:rtl/memory_upload.sv" > "$OUT/memory_upload.sv"; MU="$OUT/memory_upload.sv"; fi
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module mu_restart_tb -Mdir "$OUT" \
    ../package.sv "$MU" ../peripheral/ddram.sv ../lib/crc32.sv mu_restart_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vmu_restart_tb" +pack="$PACK" +fw="$FW" $ARGS | grep -E "^(reference|FAIL|PASS|     block)"
rm -rf "$OUT"
