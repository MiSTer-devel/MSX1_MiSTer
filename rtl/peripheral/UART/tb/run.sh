#!/bin/bash
# uart_rx testbench (Verilator --timing). Usage: wsl.exe -- bash rtl/peripheral/UART/tb/run.sh
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
verilator --binary --timing -Wno-fatal -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    --top-module uart_rx_tb -Mdir "$OUT" \
    ../uart_rx.sv uart_rx_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Warning|%Error' "$OUT/build.log" || true
"$OUT/Vuart_rx_tb"
rm -rf "$OUT"
