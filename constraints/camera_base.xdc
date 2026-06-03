#IRCAM0_PCLK as use fpga_clock

#IRCAM0_PCLK
set_property PACKAGE_PIN AN18 [get_ports IRCAM0_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM0_PCLK]
#IRCAM1_PCLK
set_property PACKAGE_PIN AN21 [get_ports IRCAM1_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM1_PCLK]
#IRCAM2_PCLK
set_property PACKAGE_PIN E23 [get_ports IRCAM2_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM2_PCLK]
#IRCAM3_PCLK
set_property PACKAGE_PIN G21 [get_ports IRCAM3_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM3_PCLK]
#IRCAM4_PCLK
set_property PACKAGE_PIN AM15 [get_ports IRCAM4_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM4_PCLK]
#IRCAM5_PCLK
set_property PACKAGE_PIN AR14 [get_ports IRCAM5_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM5_PCLK]



create_clock -period 10.000 -name IRCAM0_PCLK [get_ports IRCAM0_PCLK]
create_clock -period 10.000 -name IRCAM1_PCLK [get_ports IRCAM1_PCLK]
create_clock -period 10.000 -name IRCAM2_PCLK [get_ports IRCAM2_PCLK]
create_clock -period 10.000 -name IRCAM3_PCLK [get_ports IRCAM3_PCLK]
create_clock -period 10.000 -name IRCAM4_PCLK [get_ports IRCAM4_PCLK]
create_clock -period 10.000 -name IRCAM5_PCLK [get_ports IRCAM5_PCLK]

# bank 64
#NET "IRCAM0_PCLK"	LOC = AN18
#NET "IRCAM1_PCLK"	LOC = AN21

#NET "IRCAM0_HSYNC"	LOC = AR19
#NET "IRCAM0_VSYNC"	LOC = AP19
#NET "IRCAM0_DOUT[0]"	LOC = AR18
#NET "IRCAM0_DOUT[1]"	LOC = AR17
#NET "IRCAM0_DOUT[2]"	LOC = AN17
#NET "IRCAM0_DOUT[3]"	LOC = AH17
#NET "IRCAM0_DOUT[4]"	LOC = AH21
#NET "IRCAM0_DOUT[5]"	LOC = AJ21
#NET "IRCAM0_DOUT[6]"	LOC = AL19
#NET "IRCAM0_DOUT[7]"	LOC = AM19
#NET "IRCAM0_DOUT[8]"	LOC = AJ20
#NET "IRCAM0_DOUT[9];	LOC = AJ19
#NET "IRCAM0_DOUT[10]"	LOC = AK19
#NET "IRCAM0_DOUT[11]"	LOC = AK18
#NET "IRCAM0_DOUT[12]"	LOC = AH18
#NET "IRCAM0_DOUT[13]"	LOC = AJ18
#NET "IRCAM0_DOUT[14]"	LOC = AM18
#NET "IRCAM0_DOUT[15]"	LOC = AM17
#NET "IRCAM0_GENLOCK"	LOC = AT17
#NET "IRCAM1_GENLOCK"	LOC = AR21
#set_property PACKAGE_PIN AN18 [get_ports IRCAM0_PCLK]
#set_property IOSTANDARD LVCMOS18 [get_ports IRCAM0_PCLK]
set_property PACKAGE_PIN AR19 [get_ports IRCAM0_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM0_HSYNC]
set_property PACKAGE_PIN AP19 [get_ports IRCAM0_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM0_VSYNC]
set_property PACKAGE_PIN AR18 [get_ports {IRCAM0_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[0]}]
set_property PACKAGE_PIN AR17 [get_ports {IRCAM0_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[1]}]
set_property PACKAGE_PIN AN17 [get_ports {IRCAM0_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[2]}]
set_property PACKAGE_PIN AH17 [get_ports {IRCAM0_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[3]}]
set_property PACKAGE_PIN AH21 [get_ports {IRCAM0_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[4]}]
set_property PACKAGE_PIN AJ21 [get_ports {IRCAM0_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[5]}]
set_property PACKAGE_PIN AL19 [get_ports {IRCAM0_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[6]}]
set_property PACKAGE_PIN AM19 [get_ports {IRCAM0_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[7]}]
set_property PACKAGE_PIN AJ20 [get_ports {IRCAM0_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[8]}]
set_property PACKAGE_PIN AJ19 [get_ports {IRCAM0_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[9]}]
set_property PACKAGE_PIN AK19 [get_ports {IRCAM0_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[10]}]
set_property PACKAGE_PIN AK18 [get_ports {IRCAM0_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[11]}]
set_property PACKAGE_PIN AH18 [get_ports {IRCAM0_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[12]}]
set_property PACKAGE_PIN AJ18 [get_ports {IRCAM0_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[13]}]
set_property PACKAGE_PIN AM18 [get_ports {IRCAM0_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[14]}]
set_property PACKAGE_PIN AM17 [get_ports {IRCAM0_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM0_DOUT[15]}]

#SET IR_CAM1
set_property PACKAGE_PIN AL21 [get_ports IRCAM1_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM1_HSYNC]
set_property PACKAGE_PIN AK21 [get_ports IRCAM1_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM1_VSYNC]
set_property PACKAGE_PIN AU22 [get_ports {IRCAM1_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[0]}]
set_property PACKAGE_PIN AV22 [get_ports {IRCAM1_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[1]}]
set_property PACKAGE_PIN AU20 [get_ports {IRCAM1_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[2]}]
set_property PACKAGE_PIN AV20 [get_ports {IRCAM1_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[3]}]
set_property PACKAGE_PIN AV21 [get_ports {IRCAM1_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[4]}]
set_property PACKAGE_PIN AW21 [get_ports {IRCAM1_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[5]}]
set_property PACKAGE_PIN AW20 [get_ports {IRCAM1_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[6]}]
set_property PACKAGE_PIN AW19 [get_ports {IRCAM1_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[7]}]
set_property PACKAGE_PIN AT22 [get_ports {IRCAM1_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[8]}]
set_property PACKAGE_PIN AT21 [get_ports {IRCAM1_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[9]}]
set_property PACKAGE_PIN AV18 [get_ports {IRCAM1_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[10]}]
set_property PACKAGE_PIN AW18 [get_ports {IRCAM1_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[11]}]
set_property PACKAGE_PIN AV17 [get_ports {IRCAM1_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[12]}]
set_property PACKAGE_PIN AN22 [get_ports {IRCAM1_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[13]}]
set_property PACKAGE_PIN AR22 [get_ports {IRCAM1_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[14]}]
set_property PACKAGE_PIN AN20 [get_ports {IRCAM1_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM1_DOUT[15]}]


#SET IR_CAM2
set_property PACKAGE_PIN F24 [get_ports IRCAM2_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM2_HSYNC]
set_property PACKAGE_PIN F23 [get_ports IRCAM2_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM2_VSYNC]
set_property PACKAGE_PIN E20 [get_ports {IRCAM2_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[0]}]
set_property PACKAGE_PIN D20 [get_ports {IRCAM2_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[1]}]
set_property PACKAGE_PIN C25 [get_ports {IRCAM2_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[2]}]
set_property PACKAGE_PIN C24 [get_ports {IRCAM2_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[3]}]
set_property PACKAGE_PIN C22 [get_ports {IRCAM2_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[4]}]
set_property PACKAGE_PIN C23 [get_ports {IRCAM2_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[5]}]
set_property PACKAGE_PIN C20 [get_ports {IRCAM2_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[6]}]
set_property PACKAGE_PIN B20 [get_ports {IRCAM2_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[7]}]
set_property PACKAGE_PIN B21 [get_ports {IRCAM2_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[8]}]
set_property PACKAGE_PIN A21 [get_ports {IRCAM2_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[9]}]
set_property PACKAGE_PIN B22 [get_ports {IRCAM2_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[10]}]
set_property PACKAGE_PIN A22 [get_ports {IRCAM2_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[11]}]
set_property PACKAGE_PIN B24 [get_ports {IRCAM2_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[12]}]
set_property PACKAGE_PIN B25 [get_ports {IRCAM2_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[13]}]
set_property PACKAGE_PIN A23 [get_ports {IRCAM2_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[14]}]
set_property PACKAGE_PIN A24 [get_ports {IRCAM2_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM2_DOUT[15]}]


#SET IR_CAM3
set_property PACKAGE_PIN G20 [get_ports IRCAM3_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM3_HSYNC]
set_property PACKAGE_PIN H20 [get_ports IRCAM3_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM3_VSYNC]
set_property PACKAGE_PIN M21 [get_ports {IRCAM3_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[0]}]
set_property PACKAGE_PIN M22 [get_ports {IRCAM3_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[1]}]
set_property PACKAGE_PIN M19 [get_ports {IRCAM3_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[2]}]
set_property PACKAGE_PIN M20 [get_ports {IRCAM3_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[3]}]
set_property PACKAGE_PIN L23 [get_ports {IRCAM3_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[4]}]
set_property PACKAGE_PIN L24 [get_ports {IRCAM3_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[5]}]
set_property PACKAGE_PIN L21 [get_ports {IRCAM3_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[6]}]
set_property PACKAGE_PIN L22 [get_ports {IRCAM3_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[7]}]
set_property PACKAGE_PIN K23 [get_ports {IRCAM3_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[8]}]
set_property PACKAGE_PIN K24 [get_ports {IRCAM3_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[9]}]
set_property PACKAGE_PIN K20 [get_ports {IRCAM3_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[10]}]
set_property PACKAGE_PIN K21 [get_ports {IRCAM3_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[11]}]
set_property PACKAGE_PIN J23 [get_ports {IRCAM3_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[12]}]
set_property PACKAGE_PIN H23 [get_ports {IRCAM3_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[13]}]
set_property PACKAGE_PIN J22 [get_ports {IRCAM3_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[14]}]
set_property PACKAGE_PIN F21 [get_ports {IRCAM3_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM3_DOUT[15]}]



#SET IR_CAM4
set_property PACKAGE_PIN AL14 [get_ports IRCAM4_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM4_HSYNC]
set_property PACKAGE_PIN AL15 [get_ports IRCAM4_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM4_VSYNC]
set_property PACKAGE_PIN AK16 [get_ports {IRCAM4_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[0]}]
set_property PACKAGE_PIN AL16 [get_ports {IRCAM4_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[1]}]
set_property PACKAGE_PIN AN16 [get_ports {IRCAM4_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[2]}]
set_property PACKAGE_PIN AP10 [get_ports {IRCAM4_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[3]}]
set_property PACKAGE_PIN AT12 [get_ports {IRCAM4_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[4]}]
set_property PACKAGE_PIN AT11 [get_ports {IRCAM4_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[5]}]
set_property PACKAGE_PIN AN13 [get_ports {IRCAM4_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[6]}]
set_property PACKAGE_PIN AP13 [get_ports {IRCAM4_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[7]}]
set_property PACKAGE_PIN AR13 [get_ports {IRCAM4_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[8]}]
set_property PACKAGE_PIN AR12 [get_ports {IRCAM4_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[9]}]
set_property PACKAGE_PIN AM12 [get_ports {IRCAM4_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[10]}]
set_property PACKAGE_PIN AN12 [get_ports {IRCAM4_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[11]}]
set_property PACKAGE_PIN AP11 [get_ports {IRCAM4_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[12]}]
set_property PACKAGE_PIN AR11 [get_ports {IRCAM4_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[13]}]
set_property PACKAGE_PIN AM14 [get_ports {IRCAM4_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[14]}]
set_property PACKAGE_PIN AM13 [get_ports {IRCAM4_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM4_DOUT[15]}]


# SET IR_CAM5
set_property PACKAGE_PIN AR16 [get_ports IRCAM5_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM5_HSYNC]
set_property PACKAGE_PIN AP16 [get_ports IRCAM5_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM5_VSYNC]
set_property PACKAGE_PIN AW11 [get_ports {IRCAM5_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[0]}]
set_property PACKAGE_PIN AW10 [get_ports {IRCAM5_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[1]}]
set_property PACKAGE_PIN AU12 [get_ports {IRCAM5_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[2]}]
set_property PACKAGE_PIN AV11 [get_ports {IRCAM5_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[3]}]
set_property PACKAGE_PIN AW14 [get_ports {IRCAM5_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[4]}]
set_property PACKAGE_PIN AW13 [get_ports {IRCAM5_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[5]}]
set_property PACKAGE_PIN AU10 [get_ports {IRCAM5_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[6]}]
set_property PACKAGE_PIN AV10 [get_ports {IRCAM5_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[7]}]
set_property PACKAGE_PIN AV13 [get_ports {IRCAM5_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[8]}]
set_property PACKAGE_PIN AV12 [get_ports {IRCAM5_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[9]}]
set_property PACKAGE_PIN AU14 [get_ports {IRCAM5_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[10]}]
set_property PACKAGE_PIN AU13 [get_ports {IRCAM5_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[11]}]
set_property PACKAGE_PIN AT10 [get_ports {IRCAM5_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[12]}]
set_property PACKAGE_PIN AT16 [get_ports {IRCAM5_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[13]}]
set_property PACKAGE_PIN AV16 [get_ports {IRCAM5_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[14]}]
set_property PACKAGE_PIN AT14 [get_ports {IRCAM5_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IRCAM5_DOUT[15]}]


#IRCAM0_GENLOCK
set_property PACKAGE_PIN AT17 [get_ports IRCAM0_GENLOCK]
#IRCAM1_GENLOCK
#set_property PACKAGE_PIN AR21 [get_ports IRCAM0_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM0_GENLOCK]

set_property PACKAGE_PIN AR21 [get_ports IRCAM1_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM1_GENLOCK]

set_property PACKAGE_PIN D22 [get_ports IRCAM2_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM2_GENLOCK]

set_property PACKAGE_PIN H22 [get_ports IRCAM3_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM3_GENLOCK]

set_property PACKAGE_PIN AK17 [get_ports IRCAM4_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM4_GENLOCK]

set_property PACKAGE_PIN AW16 [get_ports IRCAM5_GENLOCK]
set_property IOSTANDARD LVCMOS18 [get_ports IRCAM5_GENLOCK]


############################################################
#NET "STROBE_OUT0"	LOC = C4
set_property PACKAGE_PIN C4 [get_ports STROBE_OUT0]
set_property IOSTANDARD LVCMOS33 [get_ports STROBE_OUT0]
############################################################
#NET "CAM0_PCLK"	LOC = C5
set_property PACKAGE_PIN C5 [get_ports CAM0_PCLK]
set_property IOSTANDARD LVCMOS33 [get_ports CAM0_PCLK]
#create_clock -period 13.468 -name CAM0_PCLK [get_ports CAM0_PCLK]
create_clock -period 10.000 -name CAM0_PCLK [get_ports CAM0_PCLK]
############################################################


#####################################################################
#DEbug port (bank 71)	J26 CON IEG0(LVCMOS18)
#####################################################################

#NET "IEG0_HSYNC"	LOC = H15
#NET "IEG0_VSYNC"	LOC = J15
#NET "IEG0_PCLK"	LOC = G19
#NET "IEG0_DOUT[0]"	LOC = E18
#NET "IEG0_DOUT[1]"	LOC = E19
#NET "IEG0_DOUT[2]"	LOC = F16
#NET "IEG0_DOUT[3]"	LOC = H19
#NET "IEG0_DOUT[4]"	LOC = G16
#NET "IEG0_DOUT[5]"	LOC = G17
#NET "IEG0_DOUT[6]"	LOC = G15
#NET "IEG0_DOUT[7]"	LOC = G14
#NET "IEG0_DOUT[8]"	LOC = H14
#NET "IEG0_DOUT[9]"	LOC = H17
#NET "IEG0_DOUT[10]"	LOC = H18
#NET "IEG0_DOUT[11]"	LOC = J18
#NET "IEG0_DOUT[12]"	LOC = J17
#NET "IEG0_DOUT[13]"	LOC = K14
#NET "IEG0_DOUT[14]"	LOC = K15
#NET "IEG0_DOUT[15]"	LOC = J16
#NET "IEG0_DOUT[16]"	LOC = L16
#NET "IEG0_DOUT[17]"	LOC = L17
#NET "IEG0_DOUT[18]"	LOC = K18
#NET "IEG0_DOUT[19]"	LOC = L18
set_property PACKAGE_PIN H15 [get_ports IEG0_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IEG0_HSYNC]
set_property PACKAGE_PIN J15 [get_ports IEG0_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IEG0_VSYNC]
set_property PACKAGE_PIN G19 [get_ports IEG0_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IEG0_PCLK]
set_property PACKAGE_PIN E18 [get_ports {IEG0_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[0]}]
set_property PACKAGE_PIN E19 [get_ports {IEG0_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[1]}]
set_property PACKAGE_PIN F16 [get_ports {IEG0_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[2]}]
set_property PACKAGE_PIN H19 [get_ports {IEG0_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[3]}]
set_property PACKAGE_PIN G16 [get_ports {IEG0_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[4]}]
set_property PACKAGE_PIN G17 [get_ports {IEG0_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[5]}]
set_property PACKAGE_PIN G15 [get_ports {IEG0_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[6]}]
set_property PACKAGE_PIN G14 [get_ports {IEG0_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[7]}]
set_property PACKAGE_PIN H14 [get_ports {IEG0_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[8]}]
set_property PACKAGE_PIN H17 [get_ports {IEG0_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[9]}]
###########################################################
set_property PACKAGE_PIN H18 [get_ports {IEG0_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[10]}]
set_property PACKAGE_PIN J18 [get_ports {IEG0_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[11]}]
set_property PACKAGE_PIN J17 [get_ports {IEG0_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[12]}]
set_property PACKAGE_PIN K14 [get_ports {IEG0_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[13]}]
set_property PACKAGE_PIN K15 [get_ports {IEG0_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[14]}]
set_property PACKAGE_PIN J16 [get_ports {IEG0_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[15]}]
set_property PACKAGE_PIN L16 [get_ports {IEG0_DOUT[16]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[16]}]
set_property PACKAGE_PIN L17 [get_ports {IEG0_DOUT[17]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[17]}]
set_property PACKAGE_PIN K18 [get_ports {IEG0_DOUT[18]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[18]}]
set_property PACKAGE_PIN L18 [get_ports {IEG0_DOUT[19]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG0_DOUT[19]}]
###########################################################

#####################################
#DEBUG port2 (bank 64 & 70) J30 connector   IEG1 LVCMOS18
#####################################
#NET "IEG1_HSYNC"	LOC = AL20
#NET "IEG1_VSYNC"	LOC = AM20
#NET "IEG1_PCLK"	LOC = AP18

#NET "IEG1_DOUT[0]"	LOC = AU18
#NET "IEG1_DOUT[1]"	LOC = AU19
#NET "IEG1_DOUT[2]"	LOC = AU17
#NET "IEG1_DOUT[3]"	LOC = AT19
#NET "IEG1_DOUT[4]"	LOC = AT20
#NET "IEG1_DOUT[5]"	LOC = AP20
#NET "IEG1_DOUT[6]"	LOC = AP21
#NET "IEG1_DOUT[7]"	LOC = AM22
#NET "IEG1_DOUT[8]"	LOC = AL22
#NET "IEG1_DOUT[9]"	LOC = D21
#NET "IEG1_DOUT[10]"	LOC = E21
#NET "IEG1_DOUT[11]"	LOC = D23
#NET "IEG1_DOUT[12]"	LOC = D25
#NET "IEG1_DOUT[13]"	LOC = E25
#NET "IEG1_DOUT[14]"	LOC = E24
#NET "IEG1_DOUT[15]"	LOC = F22
#NET "IEG1_DOUT[16]"	LOC = G22
#NET "IEG1_DOUT[17]"	LOC = G24
#NET "IEG1_DOUT[18]"	LOC = H24
#NET "IEG1_DOUT[19]"	LOC = J21
set_property PACKAGE_PIN AL20 [get_ports IEG1_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IEG1_HSYNC]
set_property PACKAGE_PIN AM20 [get_ports IEG1_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports IEG1_VSYNC]
set_property PACKAGE_PIN AP18 [get_ports IEG1_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports IEG1_PCLK]
set_property PACKAGE_PIN AU18 [get_ports {IEG1_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[0]}]
set_property PACKAGE_PIN AU19 [get_ports {IEG1_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[1]}]
set_property PACKAGE_PIN AU17 [get_ports {IEG1_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[2]}]
set_property PACKAGE_PIN AT19 [get_ports {IEG1_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[3]}]
set_property PACKAGE_PIN AT20 [get_ports {IEG1_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[4]}]
set_property PACKAGE_PIN AP20 [get_ports {IEG1_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[5]}]
set_property PACKAGE_PIN AP21 [get_ports {IEG1_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[6]}]
set_property PACKAGE_PIN AM22 [get_ports {IEG1_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[7]}]
set_property PACKAGE_PIN AL22 [get_ports {IEG1_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[8]}]
set_property PACKAGE_PIN D21 [get_ports {IEG1_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[9]}]
set_property PACKAGE_PIN E21 [get_ports {IEG1_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[10]}]
set_property PACKAGE_PIN D23 [get_ports {IEG1_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[11]}]
set_property PACKAGE_PIN D25 [get_ports {IEG1_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[12]}]
set_property PACKAGE_PIN E25 [get_ports {IEG1_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[13]}]
set_property PACKAGE_PIN E24 [get_ports {IEG1_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[14]}]
set_property PACKAGE_PIN F22 [get_ports {IEG1_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[15]}]
set_property PACKAGE_PIN G22 [get_ports {IEG1_DOUT[16]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[16]}]
set_property PACKAGE_PIN G24 [get_ports {IEG1_DOUT[17]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[17]}]
set_property PACKAGE_PIN H24 [get_ports {IEG1_DOUT[18]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[18]}]
set_property PACKAGE_PIN J21 [get_ports {IEG1_DOUT[19]}]
set_property IOSTANDARD LVCMOS18 [get_ports {IEG1_DOUT[19]}]
##############################################################

set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.D00_MOSI PULLNONE [current_design]
set_property BITSTREAM.CONFIG.D01_DIN PULLNONE [current_design]
set_property BITSTREAM.CONFIG.M2PIN PULLDOWN [current_design]

# I2C (FPGA slave) pins (same as EO project wiring)
set_property PACKAGE_PIN G11 [get_ports SCL]
set_property IOSTANDARD LVCMOS33 [get_ports SCL]
set_property PULLUP true [get_ports SCL]
set_property PACKAGE_PIN F11 [get_ports SDA]
set_property IOSTANDARD LVCMOS33 [get_ports SDA]
set_property PULLUP true [get_ports SDA]

#####################################################################
# EO camera inputs / HD-SDI output (merged from previous working EO build)
#####################################################################

# --- CAM0 data ---
set_property PACKAGE_PIN A6 [get_ports {CAM0_YOUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[0]}]
set_property PACKAGE_PIN B6 [get_ports {CAM0_YOUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[1]}]
set_property PACKAGE_PIN A3 [get_ports {CAM0_YOUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[2]}]
set_property PACKAGE_PIN A4 [get_ports {CAM0_YOUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[3]}]
set_property PACKAGE_PIN B4 [get_ports {CAM0_YOUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[4]}]
set_property PACKAGE_PIN B5 [get_ports {CAM0_YOUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[5]}]
set_property PACKAGE_PIN B2 [get_ports {CAM0_YOUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[6]}]
set_property PACKAGE_PIN C2 [get_ports {CAM0_YOUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_YOUT[7]}]
set_property PACKAGE_PIN E1 [get_ports {CAM0_COUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[0]}]
set_property PACKAGE_PIN F1 [get_ports {CAM0_COUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[1]}]
set_property PACKAGE_PIN F2 [get_ports {CAM0_COUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[2]}]
set_property PACKAGE_PIN F3 [get_ports {CAM0_COUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[3]}]
set_property PACKAGE_PIN E3 [get_ports {CAM0_COUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[4]}]
set_property PACKAGE_PIN F4 [get_ports {CAM0_COUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[5]}]
set_property PACKAGE_PIN E4 [get_ports {CAM0_COUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[6]}]
set_property PACKAGE_PIN E5 [get_ports {CAM0_COUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM0_COUT[7]}]

# --- CAM1 ---
set_property PACKAGE_PIN C10 [get_ports CAM1_PCLK]
set_property IOSTANDARD LVCMOS33 [get_ports CAM1_PCLK]
create_clock -period 10.000 -name CAM1_PCLK [get_ports CAM1_PCLK]
set_property PACKAGE_PIN A11 [get_ports {CAM1_YOUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[0]}]
set_property PACKAGE_PIN B11 [get_ports {CAM1_YOUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[1]}]
set_property PACKAGE_PIN A9 [get_ports {CAM1_YOUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[2]}]
set_property PACKAGE_PIN B10 [get_ports {CAM1_YOUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[3]}]
set_property PACKAGE_PIN A8 [get_ports {CAM1_YOUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[4]}]
set_property PACKAGE_PIN B9 [get_ports {CAM1_YOUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[5]}]
set_property PACKAGE_PIN A7 [get_ports {CAM1_YOUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[6]}]
set_property PACKAGE_PIN B7 [get_ports {CAM1_YOUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_YOUT[7]}]
set_property PACKAGE_PIN E9 [get_ports {CAM1_COUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[0]}]
set_property PACKAGE_PIN E10 [get_ports {CAM1_COUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[1]}]
set_property PACKAGE_PIN E8 [get_ports {CAM1_COUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[2]}]
set_property PACKAGE_PIN F9 [get_ports {CAM1_COUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[3]}]
set_property PACKAGE_PIN F7 [get_ports {CAM1_COUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[4]}]
set_property PACKAGE_PIN F8 [get_ports {CAM1_COUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[5]}]
set_property PACKAGE_PIN E6 [get_ports {CAM1_COUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[6]}]
set_property PACKAGE_PIN F6 [get_ports {CAM1_COUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM1_COUT[7]}]
set_property PACKAGE_PIN C9 [get_ports TRIG_IN1]
set_property IOSTANDARD LVCMOS33 [get_ports TRIG_IN1]

# --- CAM2 ---
set_property PACKAGE_PIN M12 [get_ports CAM2_PCLK]
set_property IOSTANDARD LVCMOS33 [get_ports CAM2_PCLK]
create_clock -period 13.468 -name CAM2_PCLK [get_ports CAM2_PCLK]
set_property PACKAGE_PIN K10 [get_ports {CAM2_YOUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[0]}]
set_property PACKAGE_PIN K11 [get_ports {CAM2_YOUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[1]}]
set_property PACKAGE_PIN L11 [get_ports {CAM2_YOUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[2]}]
set_property PACKAGE_PIN L12 [get_ports {CAM2_YOUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[3]}]
set_property PACKAGE_PIN K13 [get_ports {CAM2_YOUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[4]}]
set_property PACKAGE_PIN L13 [get_ports {CAM2_YOUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[5]}]
set_property PACKAGE_PIN M10 [get_ports {CAM2_YOUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[6]}]
set_property PACKAGE_PIN N10 [get_ports {CAM2_YOUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_YOUT[7]}]
set_property PACKAGE_PIN P10 [get_ports {CAM2_COUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[0]}]
set_property PACKAGE_PIN P11 [get_ports {CAM2_COUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[1]}]
set_property PACKAGE_PIN P12 [get_ports {CAM2_COUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[2]}]
set_property PACKAGE_PIN P13 [get_ports {CAM2_COUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[3]}]
set_property PACKAGE_PIN R13 [get_ports {CAM2_COUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[4]}]
set_property PACKAGE_PIN R14 [get_ports {CAM2_COUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[5]}]
set_property PACKAGE_PIN P15 [get_ports {CAM2_COUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[6]}]
set_property PACKAGE_PIN R15 [get_ports {CAM2_COUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM2_COUT[7]}]
set_property PACKAGE_PIN M11 [get_ports TRIG_IN2]
set_property IOSTANDARD LVCMOS33 [get_ports TRIG_IN2]

# --- CAM3 ---
set_property PACKAGE_PIN E13 [get_ports CAM3_PCLK]
set_property IOSTANDARD LVCMOS33 [get_ports CAM3_PCLK]
create_clock -period 13.468 -name CAM3_PCLK [get_ports CAM3_PCLK]
set_property PACKAGE_PIN A14 [get_ports {CAM3_YOUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[0]}]
set_property PACKAGE_PIN B14 [get_ports {CAM3_YOUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[1]}]
set_property PACKAGE_PIN A12 [get_ports {CAM3_YOUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[2]}]
set_property PACKAGE_PIN A13 [get_ports {CAM3_YOUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[3]}]
set_property PACKAGE_PIN B12 [get_ports {CAM3_YOUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[4]}]
set_property PACKAGE_PIN C13 [get_ports {CAM3_YOUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[5]}]
set_property PACKAGE_PIN C12 [get_ports {CAM3_YOUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[6]}]
set_property PACKAGE_PIN D12 [get_ports {CAM3_YOUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_YOUT[7]}]
set_property PACKAGE_PIN G10 [get_ports {CAM3_COUT[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[0]}]
set_property PACKAGE_PIN H10 [get_ports {CAM3_COUT[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[1]}]
set_property PACKAGE_PIN H12 [get_ports {CAM3_COUT[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[2]}]
set_property PACKAGE_PIN H13 [get_ports {CAM3_COUT[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[3]}]
set_property PACKAGE_PIN J10 [get_ports {CAM3_COUT[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[4]}]
set_property PACKAGE_PIN J11 [get_ports {CAM3_COUT[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[5]}]
set_property PACKAGE_PIN J12 [get_ports {CAM3_COUT[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[6]}]
set_property PACKAGE_PIN J13 [get_ports {CAM3_COUT[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {CAM3_COUT[7]}]
set_property PACKAGE_PIN D13 [get_ports TRIG_IN3]
set_property IOSTANDARD LVCMOS33 [get_ports TRIG_IN3]

# --- CAM4 ---
set_property PACKAGE_PIN E28 [get_ports CAM4_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports CAM4_PCLK]
create_clock -period 13.468 -name CAM4_PCLK [get_ports CAM4_PCLK]
set_property PACKAGE_PIN A29 [get_ports {CAM4_YOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[0]}]
set_property PACKAGE_PIN A28 [get_ports {CAM4_YOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[1]}]
set_property PACKAGE_PIN A26 [get_ports {CAM4_YOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[2]}]
set_property PACKAGE_PIN B26 [get_ports {CAM4_YOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[3]}]
set_property PACKAGE_PIN A27 [get_ports {CAM4_YOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[4]}]
set_property PACKAGE_PIN B27 [get_ports {CAM4_YOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[5]}]
set_property PACKAGE_PIN A31 [get_ports {CAM4_YOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[6]}]
set_property PACKAGE_PIN B31 [get_ports {CAM4_YOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_YOUT[7]}]
set_property PACKAGE_PIN C28 [get_ports {CAM4_COUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[0]}]
set_property PACKAGE_PIN C27 [get_ports {CAM4_COUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[1]}]
set_property PACKAGE_PIN B29 [get_ports {CAM4_COUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[2]}]
set_property PACKAGE_PIN C29 [get_ports {CAM4_COUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[3]}]
set_property PACKAGE_PIN B30 [get_ports {CAM4_COUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[4]}]
set_property PACKAGE_PIN C30 [get_ports {CAM4_COUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[5]}]
set_property PACKAGE_PIN D28 [get_ports {CAM4_COUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[6]}]
set_property PACKAGE_PIN D27 [get_ports {CAM4_COUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM4_COUT[7]}]
set_property PACKAGE_PIN F29 [get_ports TRIG_IN4]
set_property IOSTANDARD LVCMOS18 [get_ports TRIG_IN4]

# --- CAM5 ---
set_property PACKAGE_PIN G27 [get_ports CAM5_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports CAM5_PCLK]
create_clock -period 13.468 -name CAM5_PCLK [get_ports CAM5_PCLK]
set_property PACKAGE_PIN J31 [get_ports {CAM5_YOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[0]}]
set_property PACKAGE_PIN J30 [get_ports {CAM5_YOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[1]}]
set_property PACKAGE_PIN F26 [get_ports {CAM5_YOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[2]}]
set_property PACKAGE_PIN K25 [get_ports {CAM5_YOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[3]}]
set_property PACKAGE_PIN G26 [get_ports {CAM5_YOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[4]}]
set_property PACKAGE_PIN G25 [get_ports {CAM5_YOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[5]}]
set_property PACKAGE_PIN J26 [get_ports {CAM5_YOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[6]}]
set_property PACKAGE_PIN K26 [get_ports {CAM5_YOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_YOUT[7]}]
set_property PACKAGE_PIN H25 [get_ports {CAM5_COUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[0]}]
set_property PACKAGE_PIN J25 [get_ports {CAM5_COUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[1]}]
set_property PACKAGE_PIN L27 [get_ports {CAM5_COUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[2]}]
set_property PACKAGE_PIN L26 [get_ports {CAM5_COUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[3]}]
set_property PACKAGE_PIN H27 [get_ports {CAM5_COUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[4]}]
set_property PACKAGE_PIN J27 [get_ports {CAM5_COUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[5]}]
set_property PACKAGE_PIN M26 [get_ports {CAM5_COUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[6]}]
set_property PACKAGE_PIN M25 [get_ports {CAM5_COUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {CAM5_COUT[7]}]
set_property PACKAGE_PIN F31 [get_ports TRIG_IN5]
set_property IOSTANDARD LVCMOS18 [get_ports TRIG_IN5]

# HD-SDI output for EO selected stream
set_property PACKAGE_PIN F14 [get_ports HD_DE]
set_property IOSTANDARD LVCMOS18 [get_ports HD_DE]
set_property PACKAGE_PIN F18 [get_ports HD_VSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports HD_VSYNC]
set_property PACKAGE_PIN F19 [get_ports HD_HSYNC]
set_property IOSTANDARD LVCMOS18 [get_ports HD_HSYNC]
set_property PACKAGE_PIN F17 [get_ports HD_PCLK]
set_property IOSTANDARD LVCMOS18 [get_ports HD_PCLK]
set_property PACKAGE_PIN E16 [get_ports {HD_DOUT[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[0]}]
set_property PACKAGE_PIN E15 [get_ports {HD_DOUT[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[1]}]
set_property PACKAGE_PIN D18 [get_ports {HD_DOUT[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[2]}]
set_property PACKAGE_PIN D17 [get_ports {HD_DOUT[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[3]}]
set_property PACKAGE_PIN D16 [get_ports {HD_DOUT[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[4]}]
set_property PACKAGE_PIN D15 [get_ports {HD_DOUT[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[5]}]
set_property PACKAGE_PIN E14 [get_ports {HD_DOUT[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[6]}]
set_property PACKAGE_PIN C19 [get_ports {HD_DOUT[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[7]}]
set_property PACKAGE_PIN C18 [get_ports {HD_DOUT[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[8]}]
set_property PACKAGE_PIN C17 [get_ports {HD_DOUT[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[9]}]
set_property PACKAGE_PIN C15 [get_ports {HD_DOUT[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[10]}]
set_property PACKAGE_PIN C14 [get_ports {HD_DOUT[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[11]}]
set_property PACKAGE_PIN B19 [get_ports {HD_DOUT[12]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[12]}]
set_property PACKAGE_PIN A19 [get_ports {HD_DOUT[13]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[13]}]
set_property PACKAGE_PIN B16 [get_ports {HD_DOUT[14]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[14]}]
set_property PACKAGE_PIN B15 [get_ports {HD_DOUT[15]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[15]}]
set_property PACKAGE_PIN A18 [get_ports {HD_DOUT[16]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[16]}]
set_property PACKAGE_PIN A17 [get_ports {HD_DOUT[17]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[17]}]
set_property PACKAGE_PIN B17 [get_ports {HD_DOUT[18]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[18]}]
set_property PACKAGE_PIN A16 [get_ports {HD_DOUT[19]}]
set_property IOSTANDARD LVCMOS18 [get_ports {HD_DOUT[19]}]

# EO camera clocks are physically exclusive
set_clock_groups -physically_exclusive -group [get_clocks CAM0_PCLK] -group [get_clocks CAM1_PCLK] -group [get_clocks CAM2_PCLK] -group [get_clocks CAM3_PCLK] -group [get_clocks CAM4_PCLK] -group [get_clocks CAM5_PCLK]

# The EO stack and IR-to-HD paths cross from per-camera capture clocks into the
# CAM0_PCLK HD output domain only through dual-port memories. Those crossings
# are asynchronous by design and should not be timed as synchronous paths.
set_clock_groups -asynchronous \
    -group [get_clocks CAM0_PCLK] \
    -group [get_clocks {CAM1_PCLK CAM2_PCLK CAM3_PCLK CAM4_PCLK CAM5_PCLK IRCAM0_PCLK}]

# The processed DDR path uses the MIG ui clock domain internally and crosses
# to camera/HD clocks only through explicit FIFOs or 2-FF synchronizers.
# Those domains must not be timed synchronously against each other.
set_clock_groups -asynchronous \
    -group [get_clocks mmcm_clkout0] \
    -group [get_clocks {CAM0_PCLK CAM1_PCLK CAM2_PCLK CAM3_PCLK CAM4_PCLK CAM5_PCLK IRCAM0_PCLK IRCAM1_PCLK IRCAM2_PCLK IRCAM3_PCLK IRCAM4_PCLK IRCAM5_PCLK}]
