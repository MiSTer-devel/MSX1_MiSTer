#!/bin/bash
# sdram testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/tb/run_sdram.sh
# Optional $1 = alternative sdram.sv; OLD=1 for the version without core_phase port.
set -e
cd "$(dirname "$0")"
DUT=${1:-../sdram.sv}
DEFS=""; [ -n "$OLD" ] && DEFS="+define+OLD"
OUT=$(mktemp -d)
# Verilator workarounds on a copy (controller logic unchanged):
#  - no procedural tristate: SDRAM_DQ split into input (reads) and SDRAM_DQ_drv (writes)
#  - no initializer on a variable declared inside always (state = STATE_STARTUP = 0 anyway)
sed -e 's/inout  reg \[15:0\] SDRAM_DQ,/input [15:0] SDRAM_DQ, output reg [15:0] SDRAM_DQ_drv,/' \
    -e 's/SDRAM_DQ <= /SDRAM_DQ_drv <= /' -e "s/SDRAM_DQ_drv <= 16'bz/SDRAM_DQ_drv <= 16'h0/" \
    -e 's/reg  \[3:0\] state = STATE_STARTUP;/reg  [3:0] state;/' "$DUT" > "$OUT/sdram_dut.sv"
grep -q 'SDRAM_DQ_drv,' "$OUT/sdram_dut.sv" || { echo "DQ port split failed"; exit 1; }
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style $DEFS \
    --top-module sdram_tb -Mdir "$OUT" \
    ../../package.sv altddio_out_stub.sv "$OUT/sdram_dut.sv" sdram_tb.sv > "$OUT/build.log" 2>&1 \
    || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vsdram_tb"
rm -rf "$OUT"
