open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
set_property CONFIG.Debug_Signal {Enable} [get_ips ddr4_sub64]
generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/ddr4_sub64/ddr4_sub64.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/ddr4_sub64/ddr4_sub64.xci] -no_script -sync -force -quiet }
if {[llength [get_runs -quiet ddr4_sub64_synth_1]] > 0} {
    reset_run ddr4_sub64_synth_1
}
update_compile_order -fileset sources_1
close_project
exit
