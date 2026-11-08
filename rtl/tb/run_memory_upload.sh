#!/bin/bash
# memory_upload testbench (Verilator --timing): loads an MSX pack and checks the OCM layout.
# Usage: wsl.exe -- bash rtl/tb/run_memory_upload.sh <pack.msx> <ocm_iplrom.rom> [fw.msx cartb]
#   pack: python createComp.py --xml-dir Computer/OCM --output-dir <dir>  (OCM.msx)
#   fw:   python createDev.py (MSX/CART_FW_EN.msx), cartb: cart_typ_t of slot 2 (10 = MEGARAM)
set -e
PACK=$(realpath "$1"); IPL=$(realpath "$2")
EXTRA=""
[ -n "$3" ] && EXTRA="+fw=$(realpath "$3") +cartb=$4"
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module memory_upload_tb -Mdir "$OUT" \
    ../package.sv ../memory_upload.sv ../peripheral/ddram.sv ../lib/crc32.sv memory_upload_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmemory_upload_tb" +pack="$PACK" +ipl="$IPL" $EXTRA | grep -v "^BLOCK\|^DEVICE\|^CONFIG\|^DO STATE"
rm -rf "$OUT"
