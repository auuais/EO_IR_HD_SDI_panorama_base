set project_root [file normalize "E:/Xylinx/EO_IR_HD_SDI_panorama_base"]
source [file join $project_root scripts update_project.tcl]

reset_run synth_1
reset_run impl_1

launch_runs synth_1
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "synth_1 status: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "synth_1 did not complete successfully"
}

launch_runs impl_1 -to_step write_bitstream
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "impl_1 status: $impl_status"
if {![string match "*write_bitstream Complete*" $impl_status]} {
    error "impl_1 did not reach write_bitstream successfully"
}

puts "Stage B build completed successfully"
