# DDR4 Bring-Up Notes

Project:
- E:\Xylinx\EO_IR_HD_SDI_panorama_base\EO_IR_HD_SDI_panorama_base.xpr

Current stage:
- Stage A only: DDR controller bring-up plus processed-path placeholder output.
- `EO single` remains direct pass-through.
- `IR single`, `IR stack`, and `EO stack` are intentionally routed to a status-pattern placeholder until DDR calibration and one-word write/readback are proven.

Important constraint discovered during implementation:
- The board schematic shows five x16 DDR4 devices, i.e. a raw x80 interface.
- Vivado DDR4 IP on this machine does not accept `C0.DDR4_DataWidth = 80`.
- Valid widths reported by the IP are: `8, 16, 24, 32, 40, 48, 56, 64, 72`.
- The current bring-up therefore uses a pragmatic x64 subset attempt:
  - active data lanes: `DQ0..63`, `DQS0..7`, `DM/DBI0..7`
  - command/address/control still come from the shared DDR control bank
  - the fifth x16 component (`DQ64..79`) is ignored in this first attempt

Files added:
- `src\KintexTop_EO_IR_HD_SDI_panorama_base.v`
- `src\PanoramaBase_DdrBringup.v`
- `src\Kintex_top_I2C_test.v`
- `src\KintexTop_0cam_ch1_0108.v`
- `src\Kintex_top_[1..5]cam_ch1_1202.v`
- `constraints\camera_base.xdc`
- `constraints\ddr4_sub64_firstpass.xdc`
- `docs\DDR4_PINMAP.md`
- `ip\ddr4_sub64\ddr4_sub64.xci`
- `scripts\update_project.tcl`
- `scripts\create_ddr4_sub64_ip.tcl`

What the current processed path does:
- waits for DDR calibration
- issues a single 512-bit write to address 0
- issues a single 512-bit read from address 0
- compares returned data to the test pattern
- outputs a valid 1080p BT.1120 placeholder pattern on HD-SDI for non-EO-single modes:
  - dark gradient: waiting for calibration
  - striped gray: write/read in progress
  - white: pass
  - checkerboard: fail

First-pass DDR constraints:
- `constraints\ddr4_sub64_firstpass.xdc` is now a real schematic-derived x64 subset pin map:
  - control/address from bank 67
  - DQ0..31 from bank 66
  - DQ32..63 from bank 68
  - sysclk from `FU_DDR4_SYSCLK_P/N`
- It intentionally does not bind:
  - `DQ64..79`
  - `DQS8..9`
  - `DM/DBI8..9`
  - `ALERT_N`
  - `PAR`
- The camera/HD-SDI base constraints are copied from the previous EO/IR project.

Project update / IP recreation:
- `scripts\update_project.tcl` now:
  - adds the local HDL/XDC files if missing
  - recreates `ddr4_sub64` directly inside the actual project
  - avoids the earlier locked-XCI mismatch from the scratch project
  - prints the project/IP summary at the end instead of calling the invalid `save_project` command seen earlier in batch mode
- `scripts\create_ddr4_sub64_ip.tcl` also patches the generated IP XDC clock line to `4.998 ns`
  because the raw generated DDR4 XDC was emitting an incorrect `14.161 ns` system-clock constraint.
  `4.998 ns` is the closest legal Vivado DDR4-IP input-clock value to the board's nominal `200 MHz`.

Next expected user step:
1. In Vivado Tcl Console or batch mode, run:
   - `source E:/Xylinx/EO_IR_HD_SDI_panorama_base/scripts/update_project.tcl`
2. Re-open the project and review:
   - `ip/ddr4_sub64/ddr4_sub64.xci`
   - `constraints/ddr4_sub64_firstpass.xdc`
   - `docs/DDR4_PINMAP.md`
3. Run synth / impl / bitstream.
4. Test hardware behavior in a processed mode (`IR single`, `IR stack`, or `EO stack`).
5. Report whether the processed path shows:
   - waiting pattern only
   - transition to pass/fail pattern
   - no output / broken output
