#!/bin/sh
# Builds z80_memptr.hex (for z80_undoc_tb) from z80_memptr.asm (Git Bash or WSL, pasmo).
set -e
cd "$(dirname "$0")"
PASMO=../../tools/vdptest/pasmo.exe
[ -x "$PASMO" ] || PASMO=pasmo
"$PASMO" --bin z80_memptr.asm z80_memptr.bin
PY=$(command -v python3 || command -v python)
"$PY" -c "import sys; d=open('z80_memptr.bin','rb').read(); open('z80_memptr.hex','w', newline='\n').write(''.join('%02x\n' % b for b in d))"
rm -f z80_memptr.bin
