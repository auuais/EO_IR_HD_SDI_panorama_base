# DDR4 First-Pass Pin Map

Project:
- `E:\Xylinx\EO_IR_HD_SDI_panorama_base\EO_IR_HD_SDI_panorama_base.xpr`

Board source:
- `C:\SVNProjects\IMU_Stabilize_v40\Circuit Diagram\tbt_camerasystem_251106.pdf`

Purpose:
- capture the exact first-pass DDR4 subset being attempted in Stage A
- keep the schematic-derived pin mapping separate from the general bring-up notes

## Context

The board schematic shows five `x16` Micron DDR4 components:
- `MT40A512M16TB-062E_R`

The physical board interface is therefore `x80`:
- `DQ0..79`
- `DQS0..9`
- `DM/DBI0..9`

Vivado DDR4 IP on this machine does not accept `80` as `C0.DDR4_DataWidth`.
The first-pass bring-up therefore uses a pragmatic `x64` subset:
- active byte lanes: `0..7`
- omitted byte lanes: `8..9`

Included in this first pass:
- `DQ0..63`
- `DQS0..7`
- `DM/DBI0..7`
- shared address/control clocking from the DDR control bank

Omitted in this first pass:
- `DQ64..79`
- `DQS8..9`
- `DM/DBI8..9`
- `PAR`
- `ALERT_N`

## System Clock

| Signal | FPGA Package Pin |
| --- | --- |
| `c0_sys_clk_p` | `AR32` |
| `c0_sys_clk_n` | `AT32` |

## Address / Command / Control

| Port | FPGA Package Pin |
| --- | --- |
| `c0_ddr4_reset_n` | `AH34` |
| `c0_ddr4_act_n` | `AT37` |
| `c0_ddr4_cs_n[0]` | `AP33` |
| `c0_ddr4_cke[0]` | `AU37` |
| `c0_ddr4_odt[0]` | `AR33` |
| `c0_ddr4_ck_t[0]` | `AR34` |
| `c0_ddr4_ck_c[0]` | `AT34` |
| `c0_ddr4_bg[0]` | `AR31` |
| `c0_ddr4_ba[0]` | `AW33` |
| `c0_ddr4_ba[1]` | `AP36` |

## Address Bus

| Port | FPGA Package Pin |
| --- | --- |
| `c0_ddr4_adr[0]` | `AV38` |
| `c0_ddr4_adr[1]` | `AR38` |
| `c0_ddr4_adr[2]` | `AV37` |
| `c0_ddr4_adr[3]` | `AR36` |
| `c0_ddr4_adr[4]` | `AU39` |
| `c0_ddr4_adr[5]` | `AP38` |
| `c0_ddr4_adr[6]` | `AT31` |
| `c0_ddr4_adr[7]` | `AP39` |
| `c0_ddr4_adr[8]` | `AV28` |
| `c0_ddr4_adr[9]` | `AT39` |
| `c0_ddr4_adr[10]` | `AU38` |
| `c0_ddr4_adr[11]` | `AW36` |
| `c0_ddr4_adr[12]` | `AR37` |
| `c0_ddr4_adr[13]` | `AR39` |
| `c0_ddr4_adr[14]` | `AP31` |
| `c0_ddr4_adr[15]` | `AP34` |
| `c0_ddr4_adr[16]` | `AP35` |

## Data Byte Lanes 0..3

These correspond to the lower x32 region shown from the DDR data banks.

| Port | FPGA Package Pin |
| --- | --- |
| `c0_ddr4_dm_dbi_n[0]` | `AU27` |
| `c0_ddr4_dq[0]` | `AR27` |
| `c0_ddr4_dq[1]` | `AV24` |
| `c0_ddr4_dq[2]` | `AP26` |
| `c0_ddr4_dq[3]` | `AU24` |
| `c0_ddr4_dq[4]` | `AU26` |
| `c0_ddr4_dq[5]` | `AR29` |
| `c0_ddr4_dq[6]` | `AT25` |
| `c0_ddr4_dq[7]` | `AR24` |
| `c0_ddr4_dqs_t[0]` | `AT27` |
| `c0_ddr4_dqs_c[0]` | `AT26` |
| `c0_ddr4_dm_dbi_n[1]` | `AP25` |
| `c0_ddr4_dq[8]` | `AT29` |
| `c0_ddr4_dq[9]` | `AT28` |
| `c0_ddr4_dq[10]` | `AU28` |
| `c0_ddr4_dq[11]` | `AP24` |
| `c0_ddr4_dq[12]` | `AR28` |
| `c0_ddr4_dq[13]` | `AP29` |
| `c0_ddr4_dq[14]` | `AV29` |
| `c0_ddr4_dq[15]` | `AU25` |
| `c0_ddr4_dqs_t[1]` | `AV27` |
| `c0_ddr4_dqs_c[1]` | `AV26` |
| `c0_ddr4_dm_dbi_n[2]` | `AL23` |
| `c0_ddr4_dq[16]` | `AH24` |
| `c0_ddr4_dq[17]` | `AK20` |
| `c0_ddr4_dq[18]` | `AK23` |
| `c0_ddr4_dq[19]` | `AH22` |
| `c0_ddr4_dq[20]` | `AJ21` |
| `c0_ddr4_dq[21]` | `AH23` |
| `c0_ddr4_dq[22]` | `AJ20` |
| `c0_ddr4_dq[23]` | `AK21` |
| `c0_ddr4_dqs_t[2]` | `AJ24` |
| `c0_ddr4_dqs_c[2]` | `AJ23` |
| `c0_ddr4_dm_dbi_n[3]` | `AL22` |
| `c0_ddr4_dq[24]` | `AL24` |
| `c0_ddr4_dq[25]` | `AM24` |
| `c0_ddr4_dq[26]` | `AN20` |
| `c0_ddr4_dq[27]` | `AM23` |
| `c0_ddr4_dq[28]` | `AM21` |
| `c0_ddr4_dq[29]` | `AL21` |
| `c0_ddr4_dq[30]` | `AN22` |
| `c0_ddr4_dq[31]` | `AN24` |
| `c0_ddr4_dqs_t[3]` | `AP23` |
| `c0_ddr4_dqs_c[3]` | `AP22` |

## Data Byte Lanes 4..7

These correspond to the second x32 region used for the first-pass x64 bring-up.

| Port | FPGA Package Pin |
| --- | --- |
| `c0_ddr4_dm_dbi_n[4]` | `G25` |
| `c0_ddr4_dq[32]` | `H26` |
| `c0_ddr4_dq[33]` | `F26` |
| `c0_ddr4_dq[34]` | `K22` |
| `c0_ddr4_dq[35]` | `E27` |
| `c0_ddr4_dq[36]` | `J23` |
| `c0_ddr4_dq[37]` | `F24` |
| `c0_ddr4_dq[38]` | `G24` |
| `c0_ddr4_dq[39]` | `G23` |
| `c0_ddr4_dqs_t[4]` | `J26` |
| `c0_ddr4_dqs_c[4]` | `J25` |
| `c0_ddr4_dm_dbi_n[5]` | `C23` |
| `c0_ddr4_dq[40]` | `B23` |
| `c0_ddr4_dq[41]` | `C26` |
| `c0_ddr4_dq[42]` | `C25` |
| `c0_ddr4_dq[43]` | `D25` |
| `c0_ddr4_dq[44]` | `B22` |
| `c0_ddr4_dq[45]` | `A25` |
| `c0_ddr4_dq[46]` | `A22` |
| `c0_ddr4_dq[47]` | `D27` |
| `c0_ddr4_dqs_t[5]` | `E23` |
| `c0_ddr4_dqs_c[5]` | `E22` |
| `c0_ddr4_dm_dbi_n[6]` | `H31` |
| `c0_ddr4_dq[48]` | `J30` |
| `c0_ddr4_dq[49]` | `G28` |
| `c0_ddr4_dq[50]` | `J28` |
| `c0_ddr4_dq[51]` | `F31` |
| `c0_ddr4_dq[52]` | `G32` |
| `c0_ddr4_dq[53]` | `F29` |
| `c0_ddr4_dq[54]` | `F28` |
| `c0_ddr4_dq[55]` | `H32` |
| `c0_ddr4_dqs_t[6]` | `J31` |
| `c0_ddr4_dqs_c[6]` | `J29` |
| `c0_ddr4_dm_dbi_n[7]` | `A29` |
| `c0_ddr4_dq[56]` | `A26` |
| `c0_ddr4_dq[57]` | `B31` |
| `c0_ddr4_dq[58]` | `B26` |
| `c0_ddr4_dq[59]` | `C32` |
| `c0_ddr4_dq[60]` | `D29` |
| `c0_ddr4_dq[61]` | `B29` |
| `c0_ddr4_dq[62]` | `A31` |
| `c0_ddr4_dq[63]` | `C31` |
| `c0_ddr4_dqs_t[7]` | `D31` |
| `c0_ddr4_dqs_c[7]` | `D30` |

## Omitted First-Pass Lanes

Not used in the current Stage A attempt:
- `c0_ddr4_dq[64..79]`
- `c0_ddr4_dm_dbi_n[8..9]`
- `c0_ddr4_dqs_t[8..9]`
- `c0_ddr4_dqs_c[8..9]`

## Notes

- This file documents the intended first-pass x64 subset only.
- The actual implementation constraints live in:
  - `E:\Xylinx\EO_IR_HD_SDI_panorama_base\constraints\ddr4_sub64_firstpass.xdc`
- If DDR calibration fails, the first question is whether this x64 subset of the board topology is electrically and logically acceptable to the DDR4 IP on this board layout.
