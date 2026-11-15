#!/bin/sh
# Builds the MIDI test ROM (Git Bash or WSL): gen_data.py -> data.inc, pasmo -> miditest.rom
set -e
cd "$(dirname "$0")"
PY=$(command -v python3 || command -v python || command -v py)
"$PY" gen_data.py
PASMO=../vdptest/pasmo.exe
[ -x "$PASMO" ] || PASMO=pasmo
"$PASMO" --bin miditest.asm miditest.rom
