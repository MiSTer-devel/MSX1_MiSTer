#!/bin/bash
# MSX-MIDI testbench (Verilator --timing): dev_msx_midi with i8251 and i8254.
# Usage: wsl.exe -- bash rtl/msx/devices/tb/run_msx_midi.sh
#   ALT_DIR=<dir>: msx_midi.sv, i8251.sv, i8254.sv from that directory (old version)
set -e
cd "$(dirname "$0")"
SRC="../msx_midi.sv ../../../peripheral/UART/i8251.sv ../../../peripheral/UART/i8254.sv"
[ -n "$ALT_DIR" ] && SRC="$ALT_DIR/msx_midi.sv $ALT_DIR/i8251.sv $ALT_DIR/i8254.sv"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module msx_midi_tb -Mdir "$OUT" \
    ../../../package.sv $SRC msx_midi_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error|%Warning-(WIDTH|CASEINCOMPLETE|MULTIDRIVEN|LATCH)' "$OUT/build.log" || true
"$OUT/Vmsx_midi_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
