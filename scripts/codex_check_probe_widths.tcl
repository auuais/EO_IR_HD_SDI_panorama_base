open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROBES.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.ltx} [current_hw_device]
refresh_hw_device [current_hw_device]

set ila [lindex [get_hw_ilas -of_objects [current_hw_device]] 0]
set p [lindex [get_hw_probes -of_objects $ila -filter {NAME =~ "*wdf_data_q*"}] 0]
puts "Probe object: $p"
report_property $p

close_hw_manager
puts "PROBE_WIDTH_CHECK_DONE"
exit
