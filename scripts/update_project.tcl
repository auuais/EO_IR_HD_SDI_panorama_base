set project_root [file normalize "E:/Xylinx/EO_IR_HD_SDI_panorama_base"]
set project_xpr  [file join $project_root EO_IR_HD_SDI_panorama_base.xpr]

proc add_if_missing {path {fileset sources_1}} {
    set norm [file normalize $path]
    if {![llength [get_files -quiet $norm]]} {
        if {$fileset eq "sources_1"} {
            add_files -norecurse $norm
        } else {
            add_files -fileset $fileset -norecurse $norm
        }
    }
}

proc ensure_xci_in_xpr {project_xpr} {
    set xci_marker {$PPRDIR/ip/ddr4_sub64/ddr4_sub64.xci}
    set src_marker  {$PPRDIR/src/KintexTop_0cam_ch1_0108.v}
    set fh [open $project_xpr r]
    set text [read $fh]
    close $fh
    if {[string first $xci_marker $text] >= 0} {
        return
    }
    set file_block "      <File Path=\"$xci_marker\">\n        <FileInfo>\n          <Attr Name=\"UsedIn\" Val=\"synthesis\"/>\n          <Attr Name=\"UsedIn\" Val=\"implementation\"/>\n          <Attr Name=\"UsedIn\" Val=\"simulation\"/>\n        </FileInfo>\n      </File>\n"
    set src_block "      <File Path=\"$src_marker\">"
    set text [string map [list $src_block "${file_block}${src_block}"] $text]
    set fh [open $project_xpr w]
    puts -nonewline $fh $text
    close $fh
}

open_project $project_xpr

foreach src [lsort [glob -nocomplain [file join $project_root src *.v]]] {
    add_if_missing $src sources_1
}

# Keep critical top-level sources explicit so reopened projects do not depend on
# source-tree discovery state.
add_if_missing [file join $project_root src PanoramaBase_DdrBringupStub.v] sources_1
add_if_missing [file join $project_root src PanoramaBase_DdrBringup.v] sources_1
add_if_missing [file join $project_root src PanoramaBase_DdrBlackFrame.v] sources_1
add_if_missing [file join $project_root src PanoramaBase_IrSingleBuffered.v] sources_1
add_if_missing [file join $project_root src KintexTop_EO_IR_HD_SDI_panorama_base.v] sources_1

add_if_missing [file join $project_root constraints camera_base.xdc] constrs_1
add_if_missing [file join $project_root constraints ddr4_sub64_firstpass.xdc] constrs_1

source [file join $project_root scripts create_ddr4_sub64_ip.tcl]

# Debug ILA cores (dbg_ila_0/1) are regenerated via scripts/codex_add_ila*.tcl
# and referenced directly from PanoramaBase_DdrBlackFrame.v, but unlike
# ddr4_sub64 they were only ever added to the in-memory project session, not
# durably to the persisted fileset -- so they silently vanish (module 'not
# found' at synthesis) any time the project is reopened fresh, e.g. after
# scripts/create_ddr4_sub64_ip.tcl's own open/close cycle above. Ensure both
# are present on every run, matching the ddr4_sub64 robustness pattern.
foreach ila_name {dbg_ila_0 dbg_ila_1} {
    set ila_xci [file join $project_root ip $ila_name "${ila_name}.xci"]
    if {[file exists $ila_xci]} {
        add_if_missing $ila_xci sources_1
    }
}

set_property top KintexTop_EO_IR_HD_SDI_panorama_base [current_fileset]
update_compile_order -fileset sources_1
puts "Project update complete for $project_xpr"
puts "Top module: KintexTop_EO_IR_HD_SDI_panorama_base"
puts "DDR IP: [file join $project_root ip ddr4_sub64 ddr4_sub64.xci]"
ensure_xci_in_xpr $project_xpr
