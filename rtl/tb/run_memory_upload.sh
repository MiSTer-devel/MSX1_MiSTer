#!/bin/bash
# memory_upload testbench (Verilator --timing): loads an MSX pack and checks the OCM layout.
# Usage: wsl.exe -- bash rtl/tb/run_memory_upload.sh <pack.msx> <ocm_iplrom.rom>
#   pack: python createComp.py --xml-dir Computer_rozpracovano --output-dir <dir>  (OCM/OCM.msx)
set -e
PACK=$(realpath "$1"); IPL=$(realpath "$2")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module memory_upload_tb -Mdir "$OUT" \
    ../package.sv ../memory_upload.sv ../peripheral/ddram.sv ../lib/crc32.sv memory_upload_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmemory_upload_tb" +pack="$PACK" +ipl="$IPL" | grep -v "^BLOCK\|^DEVICE\|^CONFIG\|^DO STATE"
rm -rf "$OUT"
