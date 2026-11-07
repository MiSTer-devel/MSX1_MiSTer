#!/bin/bash
# mappers equivalence: working tree vs git ref (default HEAD). Usage:
#   wsl.exe -- bash rtl/msx/msx_slots/tb/run_mappers_eq.sh [git-ref]
# Reference modules are renamed with suffix _old so both versions elaborate together.
set -e
cd "$(dirname "$0")"
REF=${1:-HEAD}

# Every mapper must drive each output field exactly once (neutral value when unused);
# simulation alone would not see an undriven field (2-state 0).
LINT=$(verilator --lint-only -Wall -Wno-fatal --top-module mappers \
       ../../../package.sv ../mappers.sv ../mappers/*.sv 2>&1 \
       | grep -E '^%Warning-(UNDRIVEN|MULTIDRIVEN)' | grep -v 'package.sv' || true)
if [ -n "$LINT" ]; then echo "$LINT"; echo "FAILED mappers lint"; exit 1; fi

ROOT=$(cd ../../../.. && pwd)
OUT=$(mktemp -d)
mkdir "$OUT/old"
FILES="rtl/msx/msx_slots/mappers.sv $(cd "$ROOT" && git ls-tree --name-only "$REF" rtl/msx/msx_slots/mappers/ | grep '\.sv$')"
for f in $FILES; do git -C "$ROOT" show "$REF:$f" > "$OUT/old/$(basename "$f")"; done
SED=()
for m in $(grep -ohE '^\s*module\s+\w+' "$OUT"/old/*.sv | awk '{print $2}' | sort -u); do
    SED+=(-e "s/\<$m\>/${m}_old/g")
done
sed -i "${SED[@]}" "$OUT"/old/*.sv
verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style \
    --top-module mappers_eq_tb -Mdir "$OUT" \
    ../../../package.sv ../mappers.sv ../mappers/*.sv "$OUT"/old/*.sv mappers_eq_tb.sv \
    > "$OUT/build.log" 2>&1 || { cat "$OUT/build.log"; exit 1; }
grep -E '%Error' "$OUT/build.log" || true
"$OUT/Vmappers_eq_tb"
rm -rf "$OUT"
