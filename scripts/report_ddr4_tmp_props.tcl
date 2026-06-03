open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip_build_tmp/tmpq.xpr
set p [get_ips ddr4_sub64]
puts "IP=[llength $p]"
if {[llength $p]} {
  foreach k [lsort [report_property -return_string $p]] { }
  report_property $p
}
close_project
