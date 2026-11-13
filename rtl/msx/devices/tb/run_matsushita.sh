#!/bin/bash
# dev_matsushita / dev_ciel_turbo testbench (Verilator --timing).
# Usage: wsl.exe -- bash rtl/msx/devices/tb/run_matsushita.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module matsushita_tb -Mdir "$OUT" \
    ../../../package.sv ../matsushita.sv matsushita_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error|%Warning-(WIDTH|CASEINCOMPLETE|MULTIDRIVEN|LATCH)' "$OUT/build.log" || true
"$OUT/Vmatsushita_tb" | grep -E "PASS|FAIL"
rm -rf "$OUT"
