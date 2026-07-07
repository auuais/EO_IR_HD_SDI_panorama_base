open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
set stale [get_files -quiet *dbg_ila_0.xci]
puts "STALE_FILES: $stale"
if {[llength $stale] > 0} {
    remove_files -quiet $stale
}
set stale_ip [get_ips -quiet dbg_ila_0]
puts "STALE_IP: $stale_ip"
close_project
