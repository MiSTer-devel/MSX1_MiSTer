#!/bin/bash
# reset_status testbenches (Verilator --timing). Usage: wsl.exe -- bash rtl/msx/devices/tb/run.sh
# Optional $1 = alternative reset_status.sv (e.g. old version for comparison)
set -e
cd "$(dirname "$0")"
DUT=${1:-../reset_status.sv}
for TOP in reset_status_tb dev_reset_status_tb; do
    OUT=$(mktemp -d)
    verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
        --top-module $TOP -Mdir "$OUT" \
        ../../../package.sv "$DUT" $TOP.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
    grep -E '%Error' "$OUT/build.log" || true
    "$OUT/V$TOP" | grep -E "PASS|FAIL"
    rm -rf "$OUT"
done
