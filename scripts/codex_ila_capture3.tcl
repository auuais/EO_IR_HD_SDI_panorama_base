open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit} [current_hw_device]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
program_hw_devices [current_hw_device]
refresh_hw_device [current_hw_device]

# Let DDR4 calibration + a few frames of free-running operation settle before
# arming the trigger.
after 5000

set ila [lindex [get_hw_ilas -of_objects [current_hw_device]] 0]
puts "ILA_CORE: $ila"

set all_probes [get_hw_probes -of_objects $ila]
puts "ALL_PROBES: $all_probes"

set trig_probe [get_hw_probes -of_objects $ila -filter {NAME =~ "*write_retiring"}]
puts "TRIGGER_PROBE: $trig_probe"

set_property CONTROL.TRIGGER_POSITION 200 $ila
set_property TRIGGER_COMPARE_VALUE eq1'b1 $trig_probe

run_hw_ila $ila
wait_on_hw_ila $ila
puts "ILA_WAIT_DONE"

upload_hw_ila_data $ila
set dataset [current_hw_ila_data]
puts "DATASET: $dataset"
write_hw_ila_data -csv_file -force {E:/Xylinx/EO_IR_HD_SDI_panorama_base/ila_capture_3.csv} $dataset

close_hw_manager
puts "ILA_CAPTURE_DONE"
exit
