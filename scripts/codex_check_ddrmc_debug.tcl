open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit} [current_hw_device]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]
after 5000
refresh_hw_device [current_hw_device]

puts "---- hw_migs ----"
set migs [get_hw_migs -quiet]
puts "MIGs: $migs"
if {[llength $migs] > 0} {
    foreach m $migs {
        puts "  MIG: $m"
        puts "  properties: [list_property $m]"
        puts "  CAL_STATUS: [get_property CAL_STATUS $m]"
    }
} else {
    puts "No MIGs found via get_hw_migs."
}

puts "---- hw_ddrmcs (Versal-style, expected empty for classic MIG) ----"
puts "DDRMCs: [get_hw_ddrmcs -quiet]"

close_hw_manager
puts "CHECK_DONE"
exit
