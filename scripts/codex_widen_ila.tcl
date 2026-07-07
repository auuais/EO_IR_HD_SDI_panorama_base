open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr

set_property -dict [list \
    CONFIG.C_PROBE5_WIDTH  {32} \
    CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_NUM_OF_PROBES {25} \
    CONFIG.C_PROBE19_WIDTH {64} \
    CONFIG.C_PROBE20_WIDTH {64} \
    CONFIG.C_PROBE21_WIDTH {64} \
    CONFIG.C_PROBE22_WIDTH {64} \
    CONFIG.C_PROBE23_WIDTH {64} \
    CONFIG.C_PROBE24_WIDTH {64} \
] [get_ips dbg_ila_0]

generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci] -no_script -sync -force -quiet }

update_compile_order -fileset sources_1
close_project
