open_project E:/Xylinx/EO_IR_HD_SDI_panorama_base/EO_IR_HD_SDI_panorama_base.xpr

# Combining both debug ILAs with the full 6-tile EO build over-budgeted
# RAMB36E2 (needs 1040, device has 984). dbg_ila_0 (25 probes, ~200 bits/
# sample) is the dominant consumer; shrink its depth 16384->2048 (still
# ample for the write-idle correlation test, which only needs a few
# hundred correlated read beats). dbg_ila_1 (11 probes, ~63 bits/sample)
# shrinks 16384->8192, keeping more post-trigger context since it's
# triggered on a possibly-rare event.
set_property CONFIG.C_DATA_DEPTH {2048} [get_ips dbg_ila_0]
generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_0/dbg_ila_0.xci] -no_script -sync -force -quiet }

set_property CONFIG.C_DATA_DEPTH {8192} [get_ips dbg_ila_1]
generate_target all [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_1/dbg_ila_1.xci]
catch { export_ip_user_files -of_objects [get_files E:/Xylinx/EO_IR_HD_SDI_panorama_base/ip/dbg_ila_1/dbg_ila_1.xci] -no_script -sync -force -quiet }

update_compile_order -fileset sources_1
close_project
