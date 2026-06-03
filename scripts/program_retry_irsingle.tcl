open_hw_manager
connect_hw_server -allow_non_jtag
current_hw_target [lindex [get_hw_targets *] 0]
open_hw_target
set dev [lindex [get_hw_devices] 0]
current_hw_device $dev
refresh_hw_device $dev
set_property PROGRAM.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit} $dev
program_hw_devices $dev
refresh_hw_device $dev
close_hw_target
close_hw_manager