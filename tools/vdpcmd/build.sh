#!/bin/sh
# Builds the vdpcmd ROM (Git Bash or WSL): pasmo -> vdpcmd.rom
set -e
cd "$(dirname "$0")"
PASMO=../vdptest/pasmo.exe
[ -x "$PASMO" ] || PASMO=pasmo
"$PASMO" --bin vdpcmd.asm vdpcmd.rom
