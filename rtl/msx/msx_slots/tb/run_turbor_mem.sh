#!/bin/bash
# Turbo R main RAM users: mapper_dram, mapper_msx2_ram (PANASONIC_RAM). Verilator --timing.
# Usage: wsl.exe -- bash rtl/msx/msx_slots/tb/run_turbor_mem.sh
#        PREV=<git ref>: msx2_ram.sv from that ref, mapper_dram replaced by an idle stub if missing
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
SRC="../mappers/dram.sv ../mappers/msx2_ram.sv"
if [ -n "$PREV" ]; then
    git show "$PREV:rtl/msx/msx_slots/mappers/msx2_ram.sv" > "$OUT/msx2_ram_prev.sv"
    if git show "$PREV:rtl/msx/msx_slots/mappers/dram.sv" > "$OUT/dram_prev.sv" 2>/dev/null; then :; else
        printf '%s\n' 'module mapper_dram (cpu_bus_if.device_mp cpu_bus, input MSX::block_info_t block_info, output MSX::mapper_out_t out);' \
            '    assign out = MSX::MAPPER_OUT_IDLE;' 'endmodule' > "$OUT/dram_prev.sv"
    fi
    SRC="$OUT/dram_prev.sv $OUT/msx2_ram_prev.sv"
fi
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module turbor_mem_tb -Mdir "$OUT" \
    ../../../package.sv $SRC turbor_mem_tb.sv > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vturbor_mem_tb"
rm -rf "$OUT"
