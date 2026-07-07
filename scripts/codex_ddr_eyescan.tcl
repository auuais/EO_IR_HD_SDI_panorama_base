open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set m [lindex [get_hw_migs -quiet] 0]
puts "MIG: $m"

puts "Before: 2D_EYE_SCAN_START=[get_property 2D_EYE_SCAN_START $m] 2D_EYE_SCAN_END=[get_property 2D_EYE_SCAN_END $m]"

if {[catch {
    set_property 2D_EYE_SCAN_START 001 $m
    refresh_hw_mig $m
} err]} {
    puts "Trigger attempt error: $err"
} else {
    puts "Triggered OK, polling for completion..."
    for {set i 0} {$i < 20} {incr i} {
        after 2000
        refresh_hw_mig $m
        set endv [get_property 2D_EYE_SCAN_END $m]
        puts "  poll $i: 2D_EYE_SCAN_END=$endv"
        if {$endv != "000"} {
            puts "Scan appears complete."
            break
        }
    }
}

puts "\n==== Full property dump after scan attempt ===="
report_property $m

close_hw_manager
puts "EYESCAN_DONE"
exit
