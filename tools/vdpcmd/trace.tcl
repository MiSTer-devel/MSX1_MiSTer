# openMSX script: trace of vdpcmd.rom for rtl/peripheral/VIDEO/VDP/tb/vdp_vdpcmd_tb.sv.
#   TRACE_OUT=trace.txt TEND=22 openmsx -machine <machine> -cart vdpcmd.rom -script trace.tcl
# Lines: 'I frame cycle' VBLANK interrupt, 'P frame cycle value' write to port 99h,
# 'B frame cycle R#17 value' write to port 9Bh (R#17 after its increment), 'D frame cycle' write
# to port 98h. Then: python mkdata.py trace.txt <cycles per frame> vdpcmd_<m>.txt
set renderer none
set mute on
set throttle off
set ::lf [open $::env(TRACE_OUT) w]
proc pos {} { return "[machine_info VDP_frame_count] [machine_info VDP_cycle_in_frame]" }
proc irq {} { if {[debug probe read VDP.IRQvertical]} { puts $::lf "I [pos]" } }
proc w99 {} { puts $::lf "P [pos] [format %02X $::wp_last_value]" }
proc w9b {} { puts $::lf "B [pos] [expr {[debug read {VDP regs} 17] & 0x3F}] [format %02X $::wp_last_value]" }
proc w98 {} { puts $::lf "D [pos]" }
debug probe set_bp VDP.IRQvertical {} irq
debug set_watchpoint write_io 0x99 {} w99
debug set_watchpoint write_io 0x9B {} w9b
debug set_watchpoint write_io 0x98 {} w98
proc fin {} { close $::lf; exit }
after time $::env(TEND) fin
