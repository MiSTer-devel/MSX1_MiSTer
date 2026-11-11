#!/bin/bash
# Cartridge ROM without a database entry (memory_upload, Verilator --timing).
# Usage: wsl.exe -- bash rtl/tb/run_cart_rom.sh <Philips_VG_8020-00.msx> <CART_FW_EN.msx>
#   machine: cd tools/CreateMSXpack; python createComp.py ...; FW pack: python createDev.py
#   OLD=<git rev or file>: memory_upload.sv of that revision (a file for a git worktree, whose
#                          gitdir WSL may not read)
#   ALT=<file>: another memory_upload.sv with the ports of the current one
set -e
PACK=$(realpath "$1"); FW=$(realpath "$2")
[ -f "$OLD" ] && OLD=$(realpath "$OLD")
[ -n "$ALT" ] && ALT=$(realpath "$ALT")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
MU=${ALT:-../memory_upload.sv}
if [ -f "$OLD" ]; then MU="$OLD"
elif [ -n "$OLD" ]; then git -C .. show "$OLD:rtl/memory_upload.sv" > "$OUT/memory_upload.sv"; MU="$OUT/memory_upload.sv"; fi
DEF=""; [ -n "$OLD" ] && DEF="+define+OLD_MU"     # OLD: a revision with the tables as arrays
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style $DEF \
    --top-module cart_rom_tb -Mdir "$OUT" \
    ../package.sv "$MU" ../peripheral/ddram.sv ../lib/crc32.sv cart_rom_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
"$OUT/Vcart_rom_tb" +pack="$PACK" +fw="$FW" | grep -E "^(ok|FAIL|PASS|FAILED|NOT FIND|NO CRC|FIND)"
rm -rf "$OUT"
