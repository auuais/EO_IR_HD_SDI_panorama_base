open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1
close_project
