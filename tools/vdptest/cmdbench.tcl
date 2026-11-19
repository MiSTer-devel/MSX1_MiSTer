# openMSX script for cmdbench.rom: writes the 112 results (words at C000h) to a file and exits.
#   openmsx -machine Philips_NMS_8245 -cart cmdbench.rom -script cmdbench.tcl
# Output file: env CMDBENCH_OUT, default cmdbench_openmsx.txt in the current directory.
set renderer none
set mute on
set throttle off
proc cmdbench_check {} {
    if {[peek 0xC0FE] != 0xA5} { after time 1 cmdbench_check; return }
    set out cmdbench_openmsx.txt
    if {[info exists ::env(CMDBENCH_OUT)]} { set out $::env(CMDBENCH_OUT) }
    set f [open $out w]
    for {set c 0} {$c < 14} {incr c} {
        set row {}
        for {set i 0} {$i < 8} {incr i} {
            set a [expr {0xC000 + ($c * 8 + $i) * 2}]
            lappend row [expr {[peek $a] + 256 * [peek [expr {$a + 1}]]}]
        }
        puts $f [join $row " "]
    }
    close $f
    exit
}
after time 5 cmdbench_check
