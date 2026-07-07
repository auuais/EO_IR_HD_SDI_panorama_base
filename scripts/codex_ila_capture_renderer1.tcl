open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit} [current_hw_device]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

# Let DDR4 calibration + several frames of free-running operation settle.
after 5000
refresh_hw_device [current_hw_device]

puts "---- hw_ilas ----"
set ilas [get_hw_ilas -of_objects [current_hw_device]]
puts "ILAs: $ilas"

# Don't assume index/order -- pick whichever ILA actually has the renderer's
# starvation-event probe, since discovery order across two cores isn't
# guaranteed to match instantiation order.
set ila1 ""
foreach cand $ilas {
    set matches [get_hw_probes -of_objects $cand -filter {NAME =~ "*dbg_starve_event"} -quiet]
    if {[llength $matches] > 0} {
        set ila1 $cand
        break
    }
}
if {$ila1 eq ""} {
    puts "ERROR: could not find an ILA with a dbg_starve_event probe among: $ilas"
}
puts "Using ILA: $ila1"

set all_probes [get_hw_probes -of_objects $ila1]
puts "ALL_PROBES: $all_probes"

set trig_probe [get_hw_probes -of_objects $ila1 -filter {NAME =~ "*cur_active"}]
puts "TRIGGER_PROBE: $trig_probe"

# Changed from triggering on the (possibly rare/never) starvation event to
# triggering on cur_active==1, which is true during almost the entire
# active-video region and so fires almost immediately. This trades "wait
# indefinitely for a starvation event" for "capture a large window of
# ordinary operation and count starvation events directly in analysis" --
# a bounded, always-informative result either way.
set_property CONTROL.TRIGGER_POSITION 500 $ila1
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe

run_hw_ila $ila1
puts "Armed on cur_active==1 (fires almost immediately)..."
wait_on_hw_ila $ila1
puts "ILA_WAIT_DONE"

upload_hw_ila_data $ila1
set dataset [get_hw_ila_data -of_objects $ila1]
puts "DATASET: $dataset"
write_hw_ila_data -csv_file -force {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_renderer1.csv} $dataset

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
