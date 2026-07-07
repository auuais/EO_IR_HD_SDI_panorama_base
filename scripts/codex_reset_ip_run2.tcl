open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
foreach r {dbg_ila_0_synth_1 dbg_ila_1_synth_1} {
    if {[llength [get_runs -quiet $r]] > 0} {
        reset_run $r
        puts "Reset $r"
    } else {
        puts "No $r run found"
    }
}
close_project
