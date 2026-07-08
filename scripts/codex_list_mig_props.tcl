open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set m [lindex [get_hw_migs -quiet] 0]
puts "MIG: $m"
puts "---- ALL properties ----"
foreach p [lsort [list_property $m]] {
    if {[catch {set v [get_property $p $m]} err]} {
        continue
    }
    puts "$p = $v"
}

close_hw_manager
puts "PROP_LIST_DONE"
exit
