#!/bin/bash
# memory_upload against a reference revision (Verilator --timing), see mu_equiv_tb.sv.
#   wsl.exe -- bash rtl/tb/run_mu_equiv.sh <packs dir> <CART_FW.msx> <ROM set dir> [seeds per pack]
#     packs dir:   machine packs (*.msx, searched recursively), built with createComp.py and ROMs
#     ROM set dir: python3 rtl/tb/mu_equiv_roms.py <dir>
#   REF=<git rev | file>   reference memory_upload.sv (default: the last revision with the
#                          tables in registers)
#   DUT=<file>             memory_upload.sv under test (a mutant must fail)
#   STRICT=1               compare the RAM lookup entry numbers too (module under test without
#                          the restart through the idle state: DUT=<fe7ca9e file>)
#   SEED0=<n> first seed, STEPS=<n> actions per run, JOBS=<n> parallel runs (4), ARGS="+v" verbose
set -e
PACKS=$(realpath "$1"); FW=$(realpath "$2"); SET=$(realpath "$3"); NSEED=${4:-2}
REF=${REF:-2451995}
[ -f "$REF" ] && REF=$(realpath "$REF")
[ -n "$DUT" ] && DUT=$(realpath "$DUT")
cd "$(dirname "$0")"
OUT=$(mktemp -d)
# reference: old copy limits (3, SCC 2), its FDC block device records for the tb, and the
# SRAM of a ROM cartridge in the entry of its slot (C9; it had entry 0 for slots A and B)
if [ -f "$REF" ]; then cat "$REF"; else git -C .. show "$REF:rtl/memory_upload.sv"; fi |
    sed "s/ref_sram                 <= 2'd0;/ref_sram                 <= conf[3][0] ? 2'd2 : 2'd1;/" |
    sed "s/conf\[3\]\[0\] ? 28'h1100000 : 28'hC00000;/conf[3][0] ? MSX::DDR3_ROM_B : MSX::DDR3_ROM_A;/" |
    sed "s/if ((ref_sram == 2'd0 \&\& lookup_SRAM\[ref_sram\].size == '0) || ref_sram != 2'd0) begin/if (ref_sram != 2'd0) begin/" |
    sed 's/^module memory_upload\r\?$/module memory_upload_ref/' |
    sed "s/MSX::dev_copies(device_t'(conf\[1\]))/(device_t'(conf[1]) == DEV_SCC ? 2'd2 : 2'd3)/g" |
    sed "/^endmodule/i\\    wire tb_fdc_rec = state == STATE_PROCESS_BLOCK \&\& block_t'(conf[2]) == BLOCK_DEVICE \&\& (device_t'(conf[3]) == DEV_WD2793 || device_t'(conf[3]) == DEV_TC8566AF);\n    wire tb_load_start = state == STATE_CLEAN;" \
    > "$OUT/memory_upload_ref.sv"
grep -q "^module memory_upload_ref" "$OUT/memory_upload_ref.sv" || { echo "reference module not found"; exit 1; }
grep -q "lookup_SRAM\[ref_sram\].size == '0" "$OUT/memory_upload_ref.sv" && { echo "reference C9 patch did not apply"; exit 1; }
grep -q "28'hC00000" "$OUT/memory_upload_ref.sv" && { echo "reference ROM address patch did not apply"; exit 1; }
verilator --binary --timing -O3 -Wno-fatal -Wno-lint -Wno-style \
    --top-module mu_equiv_tb -Mdir "$OUT" \
    ../package.sv "${DUT:-../memory_upload.sv}" "$OUT/memory_upload_ref.sv" ../peripheral/ddram.sv ../lib/crc32.sv mu_equiv_tb.sv \
    > "$OUT/build.log" 2>&1 || { grep -E '%Error' "$OUT/build.log" | head -20; exit 1; }
ARGSET=""
i=0; for f in "$SET"/rom*.rom; do ARGSET="$ARGSET +rom$i=$f"; i=$((i+1)); done
i=0; for f in "$SET"/db*.db;   do ARGSET="$ARGSET +db$i=$f";  i=$((i+1)); done
# one job per (pack, seed), JOBS in parallel
seed=${SEED0:-1}
while IFS= read -r pack; do
    for n in $(seq 1 "$NSEED"); do printf '%s\t%s\n' "$seed" "$pack"; seed=$((seed+1)); done
done < <(find "$PACKS" -name "*.msx" | sort) > "$OUT/jobs.txt"
[ -n "$STRICT" ] && ARGSET="$ARGSET +strict"
export OUT FW ARGSET ARGS STEPS LINES_MAX
run_one() {
    seed=${1%%$'\t'*}; pack=${1#*$'\t'}
    res=$("$OUT/Vmu_equiv_tb" +pack="$pack" +fw="$FW" $ARGSET +seed=$seed +steps=${STEPS:-12} $ARGS | grep -E "^(PASS|FAIL|FAILED|DIFF|\| )" || true)
    if echo "$res" | grep -q "^PASS"; then
        echo "$res" | grep "^PASS" > "$OUT/res.$seed.pass"
        [ -n "$ARGS" ] && { echo "$(basename "$pack"):"; echo "$res"; }
    else
        { echo "$(basename "$pack") seed $seed:"; echo "$res" | head -${LINES_MAX:-14}; } | tee "$OUT/res.$seed.fail"
    fi
    return 0
}
export -f run_one
tr '\n' '\0' < "$OUT/jobs.txt" | xargs -0 -P "${JOBS:-4}" -I{} bash -c 'run_one "$1"' _ {}
runs=$(wc -l < "$OUT/jobs.txt"); fail=$(ls "$OUT"/res.*.fail 2>/dev/null | wc -l)
cat "$OUT"/res.*.pass 2>/dev/null | awk '{c+=$5; for (i=11;i<=NF;i+=2) e[$i]+=substr($(i+1),2)} END {printf "compares %d; loads by error code:", c; for (k in e) printf " %s x%d", k, e[k]; print ""}'
rm -rf "$OUT"
echo "run_mu_equiv: $runs runs, $fail failed"
[ "$fail" = 0 ]
