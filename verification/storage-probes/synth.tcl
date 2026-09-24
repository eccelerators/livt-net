set root [pwd]
open_project $root/.livt/vendor/work/PacketStorageProbe.xpr
# Remove unused Livt.Lang overloads unsupported by Vivado's VHDL-2008 library.
proc preprocessLang {path} {
 set f [open $path r]
 set lines [split [read $f] "\n"]
 close $f
 set output {}
 set skip 0
 foreach line $lines {
  if {$skip} {
   if {[regexp {^\s*end function;} $line]} {set skip 0}
   continue
  }
  if {[regexp {^\s*function to_string\(value: (integer_vector|boolean_vector)\) return string is\s*$} $line]} {
   set skip 1
   continue
  }
  if {[regexp {^\s*function to_string\(value: (integer_vector|boolean_vector)\) return string;\s*$} $line]} {continue}
  lappend output $line
 }
 set f [open $path w]
 puts -nonewline $f [join $output "\n"]
 close $f
}
foreach f [get_files -all -filter {NAME =~ *Livt.Lang.Package.vhd}] {
 preprocessLang [get_property NAME $f]
}
set f [open $root/clock.xdc w]
puts $f {create_clock -period 10.000 [get_ports Clk]}
close $f
add_files -fileset constrs_1 $root/clock.xdc
set_param general.maxThreads 4
update_compile_order -fileset sources_1
synth_design -top packetstorageprobe_wrapper -part xc7a100tcsg324-1 -mode out_of_context
report_utilization -file $root/utilization.rpt
report_utilization -hierarchical -file $root/hierarchy.rpt
write_checkpoint -force $root/synth.dcp
close_project
