#!/bin/bash
# Cartridge ROM without a database entry (memory_upload, Verilator --timing).
# Usage: wsl.exe -- bash rtl/tb/run_cart_rom.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
#   machine: cd tools/CreateMSXpack; python createComp.py ...; FW pack: python createDev.py
#   OLD=<git rev or file>: memory_upload.sv of that revision (a file for a git worktree, whose
#                          gitdir WSL may not read)
#   ALT=<file>: another memory_upload.sv with the ports of the current one
#   EXTRA="+realrom=<file> +realdb=<vampier.db>": report how a real ROM is found and mapped
#   TOP=<git rev>: OSD load addresses from MSX1.sv of that revision (default: working tree)
set -e
PACK=$(realpath "$1"); FW=$(realpath "$2")
[ -f "$OLD" ] && OLD=$(realpath "$OLD")
[ -n "$ALT" ] && ALT=$(realpath "$ALT")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
# DDR3 load addresses of the OSD files (CONF_STR), offset from 0x30000000
if [ -n "$TOP" ]; then git -C .. show "$TOP:MSX1.sv" > "$OUT/MSX1.sv"; else cp ../../MSX1.sv "$OUT/MSX1.sv"; fi
osd_addr() { sed -n "s/.*$1,3\([0-9A-Fa-f]\{7\}\);.*/\1/p" "$OUT/MSX1.sv" | head -1; }
ADDRS="+fwaddr=$(osd_addr 'FC2,MSX,Load FW  PACK') +rom_a=$(osd_addr 'FS3,ROM,Load') +rom_b=$(osd_addr 'F4,ROM,Load') +db=$(osd_addr 'FC6,DB,Load DB MAPPERS')"
echo "$ADDRS" | grep -qE 'fwaddr=[0-9A-Fa-f]{7} .*rom_a=[0-9A-Fa-f]{7} .*rom_b=[0-9A-Fa-f]{7} .*db=[0-9A-Fa-f]{7}' || { echo "OSD addresses not found: $ADDRS"; exit 1; }
MU=${ALT:-../memory_upload.sv}
if [ -f "$OLD" ]; then MU="$OLD"
elif [ -n "$OLD" ]; then git -C .. show "$OLD:rtl/memory_upload.sv" > "$OUT/memory_upload.sv"; MU="$OUT/memory_upload.sv"; fi
DEF=""; [ -n "$OLD" ] && DEF="+define+OLD_MU"     # OLD: a revision with the tables as arrays
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module cart_rom_tb -Mdir "$OUT" \
    ../package.sv "$MU" ../peripheral/ddram.sv ../lib/crc32.sv cart_rom_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vcart_rom_tb" +pack="$PACK" +fw="$FW" $ADDRS $EXTRA | grep -E "^(ok|FAIL|PASS|FAILED|NOT FIND|NO CRC|FIND|DDR3|REAL|real)"
rm -rf "$OUT"
