open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
if {[llength [get_runs -quiet dbg_ila_0_synth_1]] > 0} {
    reset_run dbg_ila_0_synth_1
    puts "Reset dbg_ila_0_synth_1"
} else {
    puts "No dbg_ila_0_synth_1 run found"
}
close_project
