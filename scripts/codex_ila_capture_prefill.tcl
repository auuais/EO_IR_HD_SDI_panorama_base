open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set ilas [get_hw_ilas -of_objects [current_hw_device]]
puts "ILAs: $ilas"

set ila1 ""
foreach cand $ilas {
    set matches [get_hw_probes -of_objects $cand -filter {NAME =~ "*dbg_starve_event"} -quiet]
    if {[llength $matches] > 0} {
        set ila1 $cand
        break
    }
}
puts "Using ILA: $ila1"

# Trigger directly on the "orange" condition itself: inside the display
# window, a committed frame exists (frame_valid_sync), but the renderer
# has not yet reached the pix_fifo prefill threshold (!stream_started).
# If this never fires within the wait timeout, that's evidence it's rare;
# if it fires immediately/repeatedly, that confirms frequent occurrence.
set trig_probe1 [get_hw_probes -of_objects $ila1 -filter {NAME =~ "*cur_inside_window"}]
set trig_probe2 [get_hw_probes -of_objects $ila1 -filter {NAME =~ "*frame_valid_sync"}]
set trig_probe3 [get_hw_probes -of_objects $ila1 -filter {NAME =~ "*stream_started"}]

set_property CONTROL.TRIGGER_POSITION 500 $ila1
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe1
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe2
set_property TRIGGER_COMPARE_VALUE eq1'b0 $trig_probe3

run_hw_ila $ila1
puts "Armed on (cur_inside_window && frame_valid_sync && !stream_started)..."
if {[catch {
    wait_on_hw_ila -timeout 15 $ila1
} err]} {
    puts "WAIT_TIMEOUT_OR_ERROR: $err"
}
puts "ILA_WAIT_DONE"

upload_hw_ila_data $ila1
set dataset [get_hw_ila_data -of_objects $ila1]
puts "DATASET: $dataset"
write_hw_ila_data -csv_file -force {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_prefill.csv} $dataset

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
