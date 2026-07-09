# DDR4 first-pass pin map for the panorama-base bring-up project.
#
# Source:
# - C:/SVNProjects/IMU_Stabilize_v40/Circuit Diagram/tbt_camerasystem_251106.pdf
#   - page 11: FPGA bank/package mapping
#   - pages 17-18: Micron device breakout
#
# Important:
# - The board is physically five x16 components, i.e. x80 total.
# - Vivado DDR4 IP on this machine does not support x80 directly.
# - This bring-up intentionally uses only the lower x64 data lanes:
#   - DQ0..63
#   - DQS0..7
#   - DM/DBI0..7
# - The fifth x16 component (DQ64..79 / DQS8..9 / DM8..9) is not bound here.
# - ALERT_N / PAR are also not bound because the current DDR4 IP configuration
#   has parity disabled and does not expose those ports.
#
# Clocking:
# - The generated DDR4 IP XDC carries the electrical constraints and create_clock
#   for c0_sys_clk_p/n. This file contributes the board package-pin bindings.

# ---------------------------------------------------------------------------
# System clock and control/address
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN AR32 [get_ports c0_sys_clk_p]
set_property PACKAGE_PIN AT32 [get_ports c0_sys_clk_n]

set_property PACKAGE_PIN AH34 [get_ports c0_ddr4_reset_n]
set_property PACKAGE_PIN AT37 [get_ports c0_ddr4_act_n]
set_property PACKAGE_PIN AP33 [get_ports {c0_ddr4_cs_n[0]}]
set_property PACKAGE_PIN AU37 [get_ports {c0_ddr4_cke[0]}]
set_property PACKAGE_PIN AR33 [get_ports {c0_ddr4_odt[0]}]
set_property PACKAGE_PIN AR34 [get_ports {c0_ddr4_ck_t[0]}]
set_property PACKAGE_PIN AT34 [get_ports {c0_ddr4_ck_c[0]}]
set_property PACKAGE_PIN AR31 [get_ports {c0_ddr4_bg[0]}]
set_property PACKAGE_PIN AW33 [get_ports {c0_ddr4_ba[0]}]
set_property PACKAGE_PIN AP36 [get_ports {c0_ddr4_ba[1]}]

set_property PACKAGE_PIN AV38 [get_ports {c0_ddr4_adr[0]}]
set_property PACKAGE_PIN AR38 [get_ports {c0_ddr4_adr[1]}]
set_property PACKAGE_PIN AV37 [get_ports {c0_ddr4_adr[2]}]
set_property PACKAGE_PIN AR36 [get_ports {c0_ddr4_adr[3]}]
set_property PACKAGE_PIN AU39 [get_ports {c0_ddr4_adr[4]}]
set_property PACKAGE_PIN AP38 [get_ports {c0_ddr4_adr[5]}]
set_property PACKAGE_PIN AT31 [get_ports {c0_ddr4_adr[6]}]
set_property PACKAGE_PIN AP39 [get_ports {c0_ddr4_adr[7]}]
set_property PACKAGE_PIN AV28 [get_ports {c0_ddr4_adr[8]}]
set_property PACKAGE_PIN AT39 [get_ports {c0_ddr4_adr[9]}]
set_property PACKAGE_PIN AU38 [get_ports {c0_ddr4_adr[10]}]
set_property PACKAGE_PIN AW36 [get_ports {c0_ddr4_adr[11]}]
set_property PACKAGE_PIN AR37 [get_ports {c0_ddr4_adr[12]}]
set_property PACKAGE_PIN AR39 [get_ports {c0_ddr4_adr[13]}]
set_property PACKAGE_PIN AP31 [get_ports {c0_ddr4_adr[14]}]
set_property PACKAGE_PIN AP34 [get_ports {c0_ddr4_adr[15]}]
set_property PACKAGE_PIN AP35 [get_ports {c0_ddr4_adr[16]}]

# ---------------------------------------------------------------------------
# x48 map retained from the lane-isolation experiment:
# logical byte lanes 0..5 are placed on old physical lanes 2..7. Final USB
# and temporal-phase evidence isolated the fault to old physical lanes 6/7,
# not the omitted lanes 0/1. PanoramaBase_DdrBlackFrame therefore stores all
# image payload in logical app_data[255:0] (old lanes 2..5) and leaves the
# logical top x16 contribution (old lanes 6/7) unused.
# ---------------------------------------------------------------------------
set_property PACKAGE_PIN AR23 [get_ports {c0_ddr4_dm_dbi_n[0]}]
set_property PACKAGE_PIN AN25 [get_ports {c0_ddr4_dq[0]}]
set_property PACKAGE_PIN AP23 [get_ports {c0_ddr4_dq[1]}]
set_property PACKAGE_PIN AP24 [get_ports {c0_ddr4_dq[2]}]
set_property PACKAGE_PIN AT25 [get_ports {c0_ddr4_dq[3]}]
set_property PACKAGE_PIN AN23 [get_ports {c0_ddr4_dq[4]}]
set_property PACKAGE_PIN AP26 [get_ports {c0_ddr4_dq[5]}]
set_property PACKAGE_PIN AP25 [get_ports {c0_ddr4_dq[6]}]
set_property PACKAGE_PIN AT26 [get_ports {c0_ddr4_dq[7]}]
set_property PACKAGE_PIN AR26 [get_ports {c0_ddr4_dqs_t[0]}]
set_property PACKAGE_PIN AR27 [get_ports {c0_ddr4_dqs_c[0]}]

set_property PACKAGE_PIN AW23 [get_ports {c0_ddr4_dm_dbi_n[1]}]
set_property PACKAGE_PIN AU23 [get_ports {c0_ddr4_dq[8]}]
set_property PACKAGE_PIN AV26 [get_ports {c0_ddr4_dq[9]}]
set_property PACKAGE_PIN AU24 [get_ports {c0_ddr4_dq[10]}]
set_property PACKAGE_PIN AW25 [get_ports {c0_ddr4_dq[11]}]
set_property PACKAGE_PIN AT24 [get_ports {c0_ddr4_dq[12]}]
set_property PACKAGE_PIN AW26 [get_ports {c0_ddr4_dq[13]}]
set_property PACKAGE_PIN AV23 [get_ports {c0_ddr4_dq[14]}]
set_property PACKAGE_PIN AV27 [get_ports {c0_ddr4_dq[15]}]
set_property PACKAGE_PIN AU25 [get_ports {c0_ddr4_dqs_t[1]}]
set_property PACKAGE_PIN AV25 [get_ports {c0_ddr4_dqs_c[1]}]

set_property PACKAGE_PIN AM37 [get_ports {c0_ddr4_dm_dbi_n[2]}]
set_property PACKAGE_PIN AM38 [get_ports {c0_ddr4_dq[16]}]
set_property PACKAGE_PIN AK39 [get_ports {c0_ddr4_dq[17]}]
set_property PACKAGE_PIN AL37 [get_ports {c0_ddr4_dq[18]}]
set_property PACKAGE_PIN AL39 [get_ports {c0_ddr4_dq[19]}]
set_property PACKAGE_PIN AN38 [get_ports {c0_ddr4_dq[20]}]
set_property PACKAGE_PIN AJ39 [get_ports {c0_ddr4_dq[21]}]
set_property PACKAGE_PIN AL36 [get_ports {c0_ddr4_dq[22]}]
set_property PACKAGE_PIN AM39 [get_ports {c0_ddr4_dq[23]}]
set_property PACKAGE_PIN AK37 [get_ports {c0_ddr4_dqs_t[2]}]
set_property PACKAGE_PIN AK38 [get_ports {c0_ddr4_dqs_c[2]}]

set_property PACKAGE_PIN AK33 [get_ports {c0_ddr4_dm_dbi_n[3]}]
set_property PACKAGE_PIN AM35 [get_ports {c0_ddr4_dq[24]}]
set_property PACKAGE_PIN AL35 [get_ports {c0_ddr4_dq[25]}]
set_property PACKAGE_PIN AM34 [get_ports {c0_ddr4_dq[26]}]
set_property PACKAGE_PIN AL34 [get_ports {c0_ddr4_dq[27]}]
set_property PACKAGE_PIN AH33 [get_ports {c0_ddr4_dq[28]}]
set_property PACKAGE_PIN AK35 [get_ports {c0_ddr4_dq[29]}]
set_property PACKAGE_PIN AJ33 [get_ports {c0_ddr4_dq[30]}]
set_property PACKAGE_PIN AJ34 [get_ports {c0_ddr4_dq[31]}]
set_property PACKAGE_PIN AN35 [get_ports {c0_ddr4_dqs_t[3]}]
set_property PACKAGE_PIN AN36 [get_ports {c0_ddr4_dqs_c[3]}]

set_property PACKAGE_PIN AH30 [get_ports {c0_ddr4_dm_dbi_n[4]}]
set_property PACKAGE_PIN AK32 [get_ports {c0_ddr4_dq[32]}]
set_property PACKAGE_PIN AL32 [get_ports {c0_ddr4_dq[33]}]
set_property PACKAGE_PIN AJ30 [get_ports {c0_ddr4_dq[34]}]
set_property PACKAGE_PIN AM33 [get_ports {c0_ddr4_dq[35]}]
set_property PACKAGE_PIN AH31 [get_ports {c0_ddr4_dq[36]}]
set_property PACKAGE_PIN AH32 [get_ports {c0_ddr4_dq[37]}]
set_property PACKAGE_PIN AJ29 [get_ports {c0_ddr4_dq[38]}]
set_property PACKAGE_PIN AM32 [get_ports {c0_ddr4_dq[39]}]
set_property PACKAGE_PIN AK31 [get_ports {c0_ddr4_dqs_t[4]}]
set_property PACKAGE_PIN AL31 [get_ports {c0_ddr4_dqs_c[4]}]

set_property PACKAGE_PIN AM28 [get_ports {c0_ddr4_dm_dbi_n[5]}]
set_property PACKAGE_PIN AL29 [get_ports {c0_ddr4_dq[40]}]
set_property PACKAGE_PIN AM30 [get_ports {c0_ddr4_dq[41]}]
set_property PACKAGE_PIN AM29 [get_ports {c0_ddr4_dq[42]}]
set_property PACKAGE_PIN AN33 [get_ports {c0_ddr4_dq[43]}]
set_property PACKAGE_PIN AP28 [get_ports {c0_ddr4_dq[44]}]
set_property PACKAGE_PIN AL30 [get_ports {c0_ddr4_dq[45]}]
set_property PACKAGE_PIN AP29 [get_ports {c0_ddr4_dq[46]}]
set_property PACKAGE_PIN AN32 [get_ports {c0_ddr4_dq[47]}]
set_property PACKAGE_PIN AN30 [get_ports {c0_ddr4_dqs_t[5]}]
set_property PACKAGE_PIN AN31 [get_ports {c0_ddr4_dqs_c[5]}]
