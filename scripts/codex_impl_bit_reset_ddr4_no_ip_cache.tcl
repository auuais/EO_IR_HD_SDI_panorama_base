open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
set_param general.maxThreads 8

# Force the DDR4 IP OOC run to resynthesize from the generated RTL sources.
# The ordinary flow can legally reuse the IP synthesis cache, which hides
# instrumentation-only edits made under ip/ddr4_sub64/rtl.
config_ip_cache -disable_cache

if {[llength [get_runs -quiet ddr4_sub64_synth_1]] > 0} {
    reset_run ddr4_sub64_synth_1
    launch_runs ddr4_sub64_synth_1 -jobs 12
    wait_on_run ddr4_sub64_synth_1
    puts "ddr4_sub64_synth_1 status: [get_property STATUS [get_runs ddr4_sub64_synth_1]]"
}

reset_run synth_1
launch_runs synth_1 -jobs 12
wait_on_run synth_1
puts "synth_1 status: [get_property STATUS [get_runs synth_1]]"

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 12
wait_on_run impl_1
puts "impl_1 status: [get_property STATUS [get_runs impl_1]]"

close_project
