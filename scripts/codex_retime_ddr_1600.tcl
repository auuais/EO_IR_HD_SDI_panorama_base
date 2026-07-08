set_param general.maxThreads 8

# Regenerates ip/ddr4_sub64 at the DDR4_TimePeriod configured in
# create_ddr4_sub64_ip.tcl (plan section 20: retimed 833ps/DDR4-2400 ->
# 1250ps/DDR4-1600 to test the DQS-gate one-clock-misalignment theory).
# This purges and recreates the IP from scratch, so synth/impl must be
# reset afterward -- stale netlist caches from the 2400 build must not
# be reused. update_project.tcl opens the project itself.
source E:/Xylinx/EO_IR_HD_SDI_panorama_base/scripts/update_project.tcl

reset_run synth_1
launch_runs synth_1 -jobs 12
wait_on_run synth_1
close_project
