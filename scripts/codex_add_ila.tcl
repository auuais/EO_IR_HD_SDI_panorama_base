open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr

create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name dbg_ila_0 -dir E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip

set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {19} \
    CONFIG.C_DATA_DEPTH {16384} \
    CONFIG.C_TRIGIN_EN {false} \
    CONFIG.C_TRIGOUT_EN {false} \
    CONFIG.C_EN_STRG_QUAL {false} \
    CONFIG.C_ADV_TRIGGER {false} \
    CONFIG.C_INPUT_PIPE_STAGES {1} \
    CONFIG.ALL_PROBE_SAME_MU_CNT {1} \
    CONFIG.C_PROBE0_WIDTH {1} \
    CONFIG.C_PROBE1_WIDTH {16} \
    CONFIG.C_PROBE2_WIDTH {6} \
    CONFIG.C_PROBE3_WIDTH {1} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {32} \
    CONFIG.C_PROBE6_WIDTH {16} \
    CONFIG.C_PROBE7_WIDTH {5} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {16} \
    CONFIG.C_PROBE10_WIDTH {1} \
    CONFIG.C_PROBE11_WIDTH {32} \
    CONFIG.C_PROBE12_WIDTH {7} \
    CONFIG.C_PROBE13_WIDTH {4} \
    CONFIG.C_PROBE14_WIDTH {32} \
    CONFIG.C_PROBE15_WIDTH {6} \
    CONFIG.C_PROBE16_WIDTH {17} \
    CONFIG.C_PROBE17_WIDTH {4} \
    CONFIG.C_PROBE18_WIDTH {2} \
] [get_ips dbg_ila_0]

generate_target {instantiation_template} [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci]
generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci] -no_script -sync -force -quiet }

update_compile_order -fileset sources_1
close_project
