open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
puts "PART=[get_property PART [current_project]]"
puts "TOP=[get_property top [current_fileset]]"
puts "SRCS_START"
foreach f [get_files -of_objects [get_filesets sources_1]] {puts $f}
puts "SRCS_END"
puts "CONSTR_START"
foreach f [get_files -of_objects [get_filesets constrs_1]] {puts $f}
puts "CONSTR_END"
close_project
