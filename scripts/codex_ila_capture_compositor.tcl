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

puts "---- hw_ilas ----"
set ilas [get_hw_ilas -of_objects [current_hw_device]]
puts "ILAs: $ilas"

set ila2 ""
foreach cand $ilas {
    set matches [get_hw_probes -of_objects $cand -filter {NAME =~ "*col_group"} -quiet]
    if {[llength $matches] > 0} {
        set ila2 $cand
        break
    }
}
if {$ila2 eq ""} {
    puts "ERROR: could not find an ILA with a col_group probe among: $ilas"
}
puts "Using ILA: $ila2"

set all_probes [get_hw_probes -of_objects $ila2]
puts "ALL_PROBES: $all_probes"

set trig_probe [get_hw_probes -of_objects $ila2 -filter {NAME =~ "*copy_issue"}]
puts "TRIGGER_PROBE: $trig_probe"

set_property CONTROL.TRIGGER_POSITION 10 $ila2
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe

run_hw_ila $ila2
puts "Armed on copy_issue==1. Waiting for trigger..."
wait_on_hw_ila $ila2
puts "ILA_WAIT_DONE"

upload_hw_ila_data $ila2
set dataset [get_hw_ila_data -of_objects $ila2]
puts "DATASET: $dataset"
write_hw_ila_data -csv_file -force {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_compositor.csv} $dataset

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
