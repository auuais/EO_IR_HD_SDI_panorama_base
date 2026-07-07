open_hw_manager
connect_hw_server
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE {E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit} [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager
exit
