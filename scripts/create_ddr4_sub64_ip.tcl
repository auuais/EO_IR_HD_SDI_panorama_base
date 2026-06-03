set project_root [file normalize "E:/Xylinx/EO_IR_HD_SDI_panorama_base"]
set ip_name ddr4_sub64
set ip_dir  [file join $project_root ip]
set ip_xci  [file join $ip_dir $ip_name "${ip_name}.xci"]

proc patch_ddr_clock_xdc {ip_xci} {
    set xdc_path [file normalize [file join [file dirname $ip_xci] ".." ".." "EO_IR_HD_SDI_panorama_base.gen" "sources_1" "ip" "ddr4_sub64" "par" "ddr4_sub64.xdc"]]
    if {![file exists $xdc_path]} {
        return
    }
    set fh [open $xdc_path r]
    set text [read $fh]
    close $fh
    set text [regsub {create_clock -period [0-9.]+ \[get_ports c0_sys_clk_p\]} $text {create_clock -period 4.998 [get_ports c0_sys_clk_p]}]
    set fh [open $xdc_path w]
    puts -nonewline $fh $text
    close $fh
}

if {[llength [get_files -quiet $ip_xci]]} {
    remove_files [get_files -quiet $ip_xci]
}
if {[file exists [file join $ip_dir $ip_name]]} {
    file delete -force [file join $ip_dir $ip_name]
}

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
    CONFIG.C0.DDR4_InputClockPeriod {4998} \
    CONFIG.C0.DDR4_TimePeriod {833} \
    CONFIG.C0.DDR4_AxiSelection {false} \
    CONFIG.Phy_Only {Complete_Memory_Controller} \
    CONFIG.Debug_Signal {Disable} \
] $p

generate_target all $p
export_ip_user_files -of_objects $p -no_script -sync -force -quiet
patch_ddr_clock_xdc $ip_xci
update_compile_order -fileset sources_1
