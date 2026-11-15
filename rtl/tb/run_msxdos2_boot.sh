#!/bin/bash
# MSX-DOS2 cartridge in slot A boots its kernel ("Disk BASIC version 2.00") on an MSX2 with a disk drive.
# Usage: wsl.exe -- bash rtl/tb/run_msxdos2_boot.sh <MSX2 pack with FDC, e.g. Philips_NMS_8245.msx>
#            <CART_FW_EN.msx> <msxdos2-asc8-mapper.rom> [vampier.db]
# Two runs: the ROM rebuilt for the MSXDOS2 mapper (msxdos2_rom.py) and the ASCII8 patched ROM as is.
# The configuration report must name the DB configuration of slot A (MSXDOS2 60, ASCII8 50).
set -e
PACK=$(realpath "$1"); FW=$(realpath "$2"); ROM=$(realpath "$3")
cd "$(dirname "$0")"
DB=$(realpath "${4:-../../tools/CreateCRC/vampier.db}")
TMP=$(mktemp -d)
python3 msxdos2_rom.py "$ROM" "$DB" "$TMP"
RC=0
for v in "MSXDOS2:60:$TMP/dos2_msxdos2.rom" "ASCII8:50:$ROM"; do
    NAME=${v%%:*}; REST=${v#*:}; FWID=${REST%%:*}; FILE=${REST#*:}
    echo "=== mapper $NAME"
    LOG=$(VDEFS="+define+MSX_CFG_REPORT" SIMARGS="+fw=$FW +db=$TMP/mappers.db +rom=$FILE +run_ms=${RUN_MS:-15000}" \
          bash run_machine_boot.sh "$PACK" none "Disk BASIC version 2.00" 2>&1) || true
    echo "$LOG" | grep -E "PASS|FAIL|error=|on the screen|^REPORT" || echo "$LOG" | tail -20
    echo "$LOG" | grep -q "^PASS machine_boot_tb" || RC=1
    # cart_src_t 2 = DB
    echo "$LOG" | grep -qE "^REPORT MSXR valid 1 gen [0-9]+ error 0 A 2/$FWID " || { echo "FAIL report: slot A not DB / $FWID"; RC=1; }
done
rm -rf "$TMP"
[ $RC = 0 ] && echo "PASS run_msxdos2_boot" || echo "FAILED run_msxdos2_boot"
exit $RC
