open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
set_param general.maxThreads 8
reset_run synth_1
launch_runs synth_1 -jobs 12
wait_on_run synth_1
close_project
