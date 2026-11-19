#!/bin/bash
# Configuration report in the DDR3 (cfg_report + memory_upload + ddram, Verilator --timing).
# Usage: wsl.exe -- bash rtl/tb/run_cfg_report.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
#   EXTRA="+busy": DDR3 randomly busy
#   EXTRA="+fdcpack=<Philips_NMS_8245.msx>": FDC cartridge in a machine with its own FDC
set -e
PACK=$(realpath "$1"); FW=$(realpath "$2")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
# DDR3 load addresses of the OSD files (CONF_STR), offset from 0x30000000
osd_addr() { sed -n "s/.*$1,3\([0-9A-Fa-f]\{7\}\);.*/\1/p" ../../MSX.sv | head -1; }
ADDRS="+fwaddr=$(osd_addr 'FC2,MSX,Load FW  PACK') +rom_a=$(osd_addr 'FS3,ROM,Load') +rom_b=$(osd_addr 'F4,ROM,Load') +db=$(osd_addr 'FC6,DB,Load DB MAPPERS')"
echo "$ADDRS" | grep -qE 'fwaddr=[0-9A-Fa-f]{7} .*rom_a=[0-9A-Fa-f]{7} .*rom_b=[0-9A-Fa-f]{7} .*db=[0-9A-Fa-f]{7}' || { echo "OSD addresses not found: $ADDRS"; exit 1; }
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module cfg_report_tb -Mdir "$OUT" \
    ../package.sv ../memory_upload.sv ../cfg_report.sv ../peripheral/ddram.sv ../lib/crc32.sv cfg_report_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vcfg_report_tb" +pack="$PACK" +fw="$FW" $ADDRS $EXTRA | grep -E "^(ok|FAIL|PASS|FAILED)"
rm -rf "$OUT"
