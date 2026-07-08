set project_root [file normalize "E:/Xylinx/EO_IR_HD_SDI_panorama_base"]
set ip_name ddr4_sub64
set ip_dir  [file join $project_root ip]
set ip_path [file join $ip_dir $ip_name]
set ip_xci  [file join $ip_dir $ip_name "${ip_name}.xci"]
set desired_clock_period_ns 4.999

proc patch_clock_period {path desired_clock_period_ns} {
    if {![file exists $path]} {
        return 0
    }
    set fh [open $path r]
    set text [read $fh]
    close $fh
    set replacement [format {create_clock -period %.3f [get_ports c0_sys_clk_p]} $desired_clock_period_ns]
    set updated [regsub -all {create_clock -period [0-9.]+ \[get_ports c0_sys_clk_p\]} $text $replacement text]
    if {!$updated} {
        return 0
    }
    set fh [open $path w]
    puts -nonewline $fh $text
    close $fh
    return 1
}

proc patch_ddr_clock_xdcs {project_root ip_name desired_clock_period_ns} {
    set candidates [list \
        [file join $project_root ip $ip_name par "${ip_name}.xdc"] \
        [file join $project_root EO_IR_HD_SDI_panorama_base.gen sources_1 ip $ip_name par "${ip_name}.xdc"] \
        [file join $project_root ip_build_tmp tmpq.gen sources_1 ip $ip_name par "${ip_name}.xdc"] \
        [file join $project_root ip_build_tmp2 tmpq.gen sources_1 ip $ip_name par "${ip_name}.xdc"] \
    ]
    foreach xdc_path $candidates {
        patch_clock_period [file normalize $xdc_path] $desired_clock_period_ns
    }
}

proc delete_path_if_exists {path} {
    if {[file exists $path]} {
        file delete -force $path
    }
}

proc purge_ddr_ip_artifacts {project_root ip_name} {
    foreach path [list \
        [file join $project_root ip $ip_name] \
        [file join $project_root EO_IR_HD_SDI_panorama_base.ip_user_files ip $ip_name] \
        [file join $project_root ip_build_tmp] \
        [file join $project_root ip_build_tmp2] \
    ] {
        delete_path_if_exists [file normalize $path]
    }
}

if {[llength [get_files -quiet $ip_xci]]} {
    remove_files [get_files -quiet $ip_xci]
}
purge_ddr_ip_artifacts $project_root $ip_name

create_ip -name ddr4 -vendor xilinx.com -library ip -module_name $ip_name -dir $ip_dir
set p [get_ips $ip_name]

if {![llength [get_files -quiet $ip_xci]]} {
    add_files -norecurse $ip_xci
}

set_property -dict [list \
    CONFIG.Reference_Clock {Differential} \
    CONFIG.System_Clock {Differential} \
    CONFIG.C0_CLOCK_BOARD_INTERFACE {Custom} \
    CONFIG.C0.DDR4_DataWidth {64} \
    CONFIG.C0.DDR4_MemoryPart {MT40A512M16TB-062E} \
    CONFIG.C0.DDR4_MemoryType {Components} \
    CONFIG.C0.DDR4_DataMask {DM_NO_DBI} \
    CONFIG.C0.DDR4_InputClockPeriod {4999} \
    CONFIG.C0.DDR4_TimePeriod {1071} \
    CONFIG.C0.DDR4_AxiSelection {false} \
    CONFIG.Phy_Only {Complete_Memory_Controller} \
    CONFIG.Debug_Signal {Disable} \
] $p

reset_target all $p
generate_target all $p
export_ip_user_files -of_objects $p -no_script -sync -force -quiet
patch_ddr_clock_xdcs $project_root $ip_name $desired_clock_period_ns
update_compile_order -fileset sources_1
