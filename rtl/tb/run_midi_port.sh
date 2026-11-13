#!/bin/bash
# midi_port testbench (Verilator --timing): user port modes, MT32-pi (real sys/mt32pi.sv against
# an I2C / I2S model of the Pi), MIDI in / out routing, audio mix, LCD overlay.
# Usage: wsl.exe -- bash rtl/tb/run_midi_port.sh
#   ALT=<file>  another midi_port.sv (mutants)
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
# Verilator takes "reg x = 0;" inside an always block as a blocking assignment (BLKANDNBLK):
# simulate a copy of the framework file without those initial values (all start at 0 anyway)
sed 's/^\(\s*reg .*\) = 0;/\1;/' ../../sys/mt32pi.sv > "$OUT/mt32pi.sv"
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
    --top-module midi_port_tb -Mdir "$OUT" \
    ../package.sv "$OUT/mt32pi.sv" ../peripheral/UART/uart_rx.sv "${ALT:-../midi_port.sv}" midi_port_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error|%Warning-(WIDTH|CASEINCOMPLETE|MULTIDRIVEN|LATCH)' "$OUT/build.log" || true
"$OUT/Vmidi_port_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
