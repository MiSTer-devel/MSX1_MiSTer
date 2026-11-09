#!/bin/bash
# Turbo R I/O testbenches (Verilator --timing): dev_s1990 + dev_turbor_pause, dev_turbor_pcm.
# Usage: wsl.exe -- bash rtl/msx/devices/tb/run_turbor_io.sh
set -e
cd "$(dirname "$0")"
for T in "turbor_io_tb ../s1990.sv ../turbor_pause.sv" "turbor_pcm_tb ../turbor_pcm.sv"; do
    set -- $T
    TOP=$1; shift
    OUT=$(mktemp -d)
    verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
        --top-module $TOP -Mdir "$OUT" \
        ../../../package.sv "$@" $TOP.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
    grep -E '%Error' "$OUT/build.log" || true
    "$OUT/V$TOP" | grep -E "PASS|FAIL"
    rm -rf "$OUT"
done
