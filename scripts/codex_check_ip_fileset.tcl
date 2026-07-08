open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr
puts "---- IPs in project ----"
foreach ip [get_ips] {
    puts "IP: $ip  ->  [get_property IP_FILE $ip]"
}
puts "---- .xci files known to the project ----"
foreach f [get_files -quiet *.xci] {
    puts "XCI: $f"
}
close_project
