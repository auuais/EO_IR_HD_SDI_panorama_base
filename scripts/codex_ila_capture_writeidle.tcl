open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

# NOTE: does not reprogram -- meant to be run against a device already
# programmed (in the same session) by an earlier capture script, so this
# experiment runs against the identical bitstream without a redundant
# reprogram+recalibration cycle in between. Each hw_manager session is
# independent, though, so PROBES.FILE still has to be (re)associated here.

puts "---- hw_ilas ----"
set ilas [get_hw_ilas -of_objects [current_hw_device]]
puts "ILAs: $ilas"

set ila0 ""
foreach cand $ilas {
    set matches [get_hw_probes -of_objects $cand -filter {NAME =~ "*copy_active"} -quiet]
    if {[llength $matches] > 0} {
        set ila0 $cand
        break
    }
}
if {$ila0 eq ""} {
    puts "ERROR: could not find an ILA with a copy_active probe among: $ilas"
}
puts "Using ILA: $ila0"

set all_probes [get_hw_probes -of_objects $ila0]
puts "ALL_PROBES: $all_probes"

set trig_probe [get_hw_probes -of_objects $ila0 -filter {NAME =~ "*copy_active"}]
puts "TRIGGER_PROBE: $trig_probe"

# Trigger on the write engine going idle -- captures a window of read
# activity with (mostly) no concurrent write, to test whether the
# first-64-bit-chunk-of-every-read-burst corruption persists with the
# write engine idle (plan section 18 / handoff section 4.1).
set_property CONTROL.TRIGGER_POSITION 500 $ila0
set_property TRIGGER_COMPARE_VALUE eq1'b0 $trig_probe

run_hw_ila $ila0
puts "Armed on copy_active==0. Waiting for trigger..."
wait_on_hw_ila $ila0
puts "ILA_WAIT_DONE"

upload_hw_ila_data $ila0
set dataset [get_hw_ila_data -of_objects $ila0]
puts "DATASET: $dataset"
write_hw_ila_data -csv_file -force {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_writeidle.csv} $dataset

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
