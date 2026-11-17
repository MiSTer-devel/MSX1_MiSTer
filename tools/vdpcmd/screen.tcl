# openMSX script: the text screen (80 x 24 from VRAM 0) to a file after TEND seconds.
#   OUTTXT=result.txt TEND=25 openmsx -machine <machine> -cart vdpcmd.rom -script screen.tcl
set renderer none
set mute on
set throttle off
proc dumptxt {} {
  set f [open $::env(OUTTXT) w]
  for {set r 0} {$r < 24} {incr r} { puts $f [debug read_block VRAM [expr {$r * 80}] 80] }
  close $f
}
after time $::env(TEND) "dumptxt; exit"
