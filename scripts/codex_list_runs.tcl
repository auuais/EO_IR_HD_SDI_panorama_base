open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
puts "---- runs ----"
foreach r [get_runs] {
    puts "$r TYPE=[get_property TYPE $r] SRCSET=[get_property SRCSET $r] NEEDS_REFRESH=[get_property NEEDS_REFRESH $r] STATUS=[get_property STATUS $r]"
}
close_project
exit
