open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
set p [get_ips ddr4_sub64]
if {[llength $p]} {
  report_property $p
}
close_project
