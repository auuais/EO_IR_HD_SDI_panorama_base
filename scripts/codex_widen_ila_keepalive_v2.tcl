open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr

# Widen dbg_ila_0 for the keepalive-read v2 mechanism
# (docs/DDR_READ_CADENCE_VT_TRACKING_FIX_PLAN.md phase 0): adds probe25-27
# for read_gap_counter/keepalive_want/keepalive_launch/cmd_is_keepalive/
# rd_return_is_keepalive/rd_tag_count/rd_tag_overflow/rd_tag_underflow/
# frame_valid, on top of the existing 25-probe write/read datapath coverage.
# Existing probe0-24 widths are unchanged; only C_NUM_OF_PROBES grows and
# the three new probe widths are added.
set_property -dict [list \
    CONFIG.C_PROBE5_WIDTH  {32} \
    CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE19_WIDTH {64} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE21_WIDTH {64} \
    CONFIG.C_PROBE22_WIDTH {64} \
    CONFIG.C_PROBE23_WIDTH {64} \
    CONFIG.C_PROBE24_WIDTH {64} \
    CONFIG.C_PROBE25_WIDTH {7} \
    CONFIG.C_PROBE26_WIDTH {10} \
    CONFIG.C_PROBE27_WIDTH {6} \
    CONFIG.C_NUM_OF_PROBES {28} \
] [get_ips dbg_ila_0]

generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci] -no_script -sync -force -quiet }

if {[llength [get_runs -quiet dbg_ila_0_synth_1]] > 0} {
    reset_run dbg_ila_0_synth_1
    puts "Reset dbg_ila_0_synth_1"
} else {
    puts "No dbg_ila_0_synth_1 run found"
}

update_compile_order -fileset sources_1
close_project
