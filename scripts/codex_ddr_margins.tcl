open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set m [lindex [get_hw_migs -quiet] 0]
puts "MIG: $m"

puts "\n---- Calibration status / errors ----"
foreach p {CAL_STATUS CAL_ERROR_CODE CAL_ERROR_MSG CAL_MAP_VERSION CAL_VERSION_RTL CAL_STOP_MARGIN} {
    if {[catch {set v [get_property $p $m]} err]} {
        puts "  $p : <no such property: $err>"
    } else {
        puts "  $p = $v"
    }
}

puts "\n---- Per-rank0 byte read eye margin (left/right edge, size) ----"
puts [format "%-6s %-12s %-12s %-10s" "byte" "left_edge" "right_edge" "eye_size"]
for {set b 0} {$b < 8} {incr b} {
    if {[catch {
        set left  [get_property CAL_EYE_LEFT_EDGE_RANK0_BYTE$b $m]
        set right [get_property CAL_EYE_RIGHT_EDGE_RANK0_BYTE$b $m]
        set size  [get_property CAL_EYE_SIZE_RANK0_BYTE$b $m]
        puts [format "%-6s %-12s %-12s %-10s" "byte$b" $left $right $size]
    } err]} {
        puts "  byte$b : <error: $err>"
    }
}

puts "\n---- Per-rank0 byte VREF calibration (coarse / final) ----"
puts [format "%-6s %-14s %-14s" "byte" "vref_coarse" "vref_final"]
for {set b 0} {$b < 8} {incr b} {
    if {[catch {
        set c [get_property CAL_VREF_COARSE_VALUE_RANK0_BYTE$b $m]
        set f [get_property CAL_VREF_FINAL_VALUE_RANK0_BYTE$b $m]
        puts [format "%-6s %-14s %-14s" "byte$b" $c $f]
    } err]} {
        puts "  byte$b : <error: $err>"
    }
}

puts "\n---- CAL_STATUS_RANK0_* stage codes ----"
for {set i 0} {$i < 8} {incr i} {
    if {[catch {set v [get_property CAL_STATUS_RANK0_$i $m]} err]} {
        continue
    }
    puts "  CAL_STATUS_RANK0_$i = $v"
}

close_hw_manager
puts "MARGIN_CHECK_DONE"
exit
