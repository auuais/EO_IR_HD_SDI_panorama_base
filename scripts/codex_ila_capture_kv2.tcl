open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set ilas [get_hw_ilas -of_objects [current_hw_device]]
puts "ILAs: $ilas"

set ila ""
foreach cand $ilas {
    set matches [get_hw_probes -of_objects $cand -filter {NAME =~ "*write_retiring"} -quiet]
    if {[llength $matches] > 0} {
        set ila $cand
        break
    }
}
puts "ILA_CORE: $ila"

set trig_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*write_retiring"}]
puts "TRIGGER_PROBE: $trig_probe"

set_property CONTROL.TRIGGER_POSITION 200 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe

for {set i 1} {$i <= 10} {incr i} {
    run_hw_ila $ila
    wait_on_hw_ila $ila
    puts "ILA_WAIT_DONE $i"

    upload_hw_ila_data $ila
    set dataset [get_hw_ila_data -of_objects $ila]
    puts "DATASET: $dataset"
    write_hw_ila_data -csv_file -force [format {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_kv2_%02d.csv} $i] $dataset
}

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
