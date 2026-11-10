#!/bin/sh
# Builds the VDP test ROM (Git Bash or WSL):
#   vdptest.rom        interactive (SPACE / RETURN)
#   vdptest_auto.rom   pages through the tests by itself (simulation)
#   cmdbench.rom       VDP command duration (openMSX reference: cmdbench.tcl)
set -e
cd "$(dirname "$0")"
PASMO=./pasmo.exe
[ -x "$PASMO" ] || PASMO=pasmo
"$PASMO" --bin vdptest.asm vdptest.rom
"$PASMO" --equ AUTO=1 --bin vdptest.asm vdptest_auto.rom
"$PASMO" --bin cmdbench.asm cmdbench.rom
