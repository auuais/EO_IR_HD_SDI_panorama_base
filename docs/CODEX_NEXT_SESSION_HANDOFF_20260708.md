# Next-session handoff: DDR4 EO panorama striping

Date: 2026-07-08
Project: `E:\Xylinx\EO_IR_HD_SDI_panorama_base`

## RESOLVED UPDATE - 2026-07-09

The dominant DDR striping failure is now isolated and fixed in hardware.
Everything below this update is retained as historical investigation context.

### YCbCr 4:2:2 color restoration

The grayscale output was an intentional RTL substitution added during the
earlier DDR investigation, not an SDI decoder requirement. All three EO
source branches discarded the camera `COUT` byte and packed `8'h80` as
neutral chroma.

The EO pipeline was already structured for BT.1120 YCbCr 4:2:2:

- Camera pixels are `{Y[7:0], C[7:0]}`, with `C` alternating Cb/Cr.
- `EO1920x1080_Decimate3_FrameBuffer` stores both bytes.
- Its horizontal decimator selects complete chroma pairs.
- Each tile is 640 pixels wide and all horizontal offsets are even, so
  chroma phase is preserved across the 3x2 panorama.
- DDR stores the packed 16-bit `{Y,C}` pixels unchanged.
- The renderer emits Y on the upper BT.1120 component and Cb/Cr on the lower
  component, extending each 8-bit sample to 10 bits with two zero LSBs.

The fix restores the original chroma byte in `g_src_eostk`, `g_src_eo0`, and
`g_src_eo0raw`. The IR/ramp path remains intentionally grayscale with neutral
chroma. No DDR address, payload-placement, or scheduler logic changed.

Color build evidence:

- Synthesis: `codex_vivado_synth_yuv422_20260709.log`
  - 0 synthesis errors
- Implementation: `codex_vivado_impl_yuv422_20260709.log`
  - WNS `+0.494 ns`, 0 setup failures
  - WHS `+0.010 ns`, 0 hold failures
  - WPWS `+0.099 ns`, 0 pulse-width failures
  - 0 failed, unrouted, or partially routed nets
  - Bitstream completed with 0 critical warnings and 0 errors
- Programming: `codex_program_yuv422_20260709.log`
  - FPGA startup status reached `HIGH`

Hardware evidence:

- Renderer ILA: `ila_capture_renderer2.csv`
  - 7,269 in-window samples
  - `pix_empty=0`, `stream_started=1`, and `frame_valid_sync=1`
  - 165 distinct luma values and 25 distinct chroma values
  - C range 448..580 in 10-bit units; all component low two bits were zero
- The running `PC_MCU_COM` application owned the physical `USB3 Video`
  DirectShow device, so a second OpenCV process could not open it.
- Its live USB preview showed all six panorama tiles in color at 30 FPS:
  `captures/pc_mcu_com_yuv422_20260709_1836.png`
- Preview-region measurements changed from the old exact-zero grayscale
  baseline to mean channel spread `19.98`, p95 spread `63`, and mean HSV
  saturation `112.84`.

### Root cause isolation

The corruption is one complete x16 DDR4 component contribution, not one BL8
time transfer and not application-side pack/unpack logic:

- Original x64/512-bit UI: exactly 8 of every 32 pixels were unstable =
  128 bits = one x16 device across BL8.
- x48/384-bit UI: exactly the same 8 pixels were unstable, now out of every
  24 pixels = still 128 bits.
- The x48 remap used old physical byte lanes 2..7. Its logical top 128 bits
  map to old physical byte lanes 6/7 (`FU_DDR4_DQ48..63`,
  `FU_DDR4_DQS6/7`), so the earlier experiment omitted the wrong x16 device.
- A first guard experiment using app bits `[319:64]` still overlapped 64 bits
  of the bad component. It reduced the unstable region from eight pixels to
  four/five boundary phases, which located the bad app region at
  `app_data[383:256]`.
- Keeping all image payload in `app_data[255:0]` and leaving
  `app_data[383:256]` unused removed the corruption completely.

This isolates the operational root cause to the physical x16 device/interface
on original byte lanes 6/7. The PCB CSV still shows tight DQ-to-DQS matching
(about 17 ps maximum), and MIG calibration passes, so the available evidence
does not distinguish DRAM silicon, assembly/contact, or the FPGA byte-lane
interface. It does rule out the frame-buffer scheduler, address walk, tag
queue, FIFO timing, renderer, VT keepalive cadence, and generic app-beat
boundary logic as the source of the striping.

### Final fix

Current hardware configuration:

- MIG data width: x48 (`C0.DDR4_DataWidth=48`)
- Physical byte lanes: old lanes 2..7
- App width: 384 bits
- Image payload: 16 pixels / 256 bits in `app_data[255:0]`
- Unused failing region: `app_data[383:256]`
- Address stride remains 8 native-interface address units per BL8 command.
- Frame/bank beat counts were recomputed for 16 pixels per command.

The fix is lossless. It does not interpolate, mask, or repair displayed
pixels; it never writes image data into the failing x16 component.

Primary RTL:

- `src/PanoramaBase_DdrBlackFrame.v`

### Build and timing evidence

- Synthesis log:
  `codex_vivado_synth_component_guard_20260709_0605.log`
- Implementation log:
  `codex_vivado_impl_component_guard_20260709_0606.log`
- Program log:
  `codex_program_component_guard_20260709_0636.log`
- Routed timing:
  - Setup: 0 failing endpoints, WNS `+0.648 ns`
  - Hold: 0 failing endpoints, WHS `+0.011 ns`
  - Pulse width: 0 failing endpoints
- Route: 0 failed, unrouted, or partially routed nets.
- Bitstream completed with 0 critical warnings and 0 errors.

### USB-grabber verification

First run:

- `captures/usb3_component_guard_20260709_0638/`
- 120/120 real frames
- 0 uniform diagnostic frames
- Visually clean six-camera panorama, no periodic DDR stripes

Independent confirmation:

- `captures/usb3_component_guard_confirm_20260709_0640/`
- 120/120 real frames
- 0 uniform diagnostic frames
- Frame 119 remained clean

Temporal phase evidence:

- Failed overlapping-guard build: per-phase mean temporal difference ranged
  from about `0.86` to `36.60` gray levels, with the bad phases clustered at
  the beat boundary.
- Final component-bypass build: all 16 phases are uniform, about
  `0.88` to `0.95` gray levels.

The old 16/24/32-column autocorrelation values remain high because the static
scene itself has strong low-frequency column correlation; temporal phase
variance is the discriminating metric for this fault.

### Logic-audit note

No additional scheduler or FIFO logic error was found during the final audit.
One earlier real RTL issue remains fixed: `rd_data_capture` must be declared
before use and must latch `app_rd_data` alongside the delayed FIFO write
strobe. The deferred `flush_commit_pending` fix also remains required for the
separate uniform diagnostic-frame failure.

## User instruction for the next session

Before applying any next fix, re-check:

1. The PCB files in `docs/`:
   - `docs/DDR4_Parameter_DQ-2.csv`
   - `docs/DDR4_Parameter_CAC-1.csv`
2. AMD/Xilinx DDR4 Memory IP documentation, especially the UltraScale DDR4 IP / PG150 material around read DQS gate tracking, VT tracking, calibration debug visibility, and whether any board-delay or gate-tap controls are exposed.

Do not jump straight into another RTL mitigation without doing that review.

## Current source state

`src/PanoramaBase_DdrBlackFrame.v` currently contains the keepalive-v2 work from the previous model plus one verified fix from this session:

- `KEEPALIVE_THRESHOLD = 10'd60` is still present.
- `SRC_SEL = SRC_EOSTK` is still present.
- `flush_commit_pending` has been added to avoid waiting a whole extra display frame after a frame-boundary flush completes.
- The failed EO-only phase repair and the failed source-agnostic interpolation mitigation were removed from source.

Current `git diff -- src/PanoramaBase_DdrBlackFrame.v` should show only the deferred flush/commit change.

Important hardware mismatch: the board is currently programmed with the failed interpolation bitstream from `codex_takeover_interp_program.log`. After removing that mitigation from source, only synthesis was rerun:

- `codex_takeover_cleanflush_synth.log`: synthesis completed successfully.
- No clean-flush-only implementation/bitgen/programming was run after that source revert.

So before using live hardware as evidence again, rebuild implementation/bitstream from current source and program it, or intentionally revert to a known bitstream.

## Verified this session

### 1. Full-frame diagnostic/prefill flash is fixed

Before the fix, direct USB3 capture showed uniform pink/orange diagnostic frames. The renderer-side ILA evidence was:

- `cur_inside_window && frame_valid_sync && !stream_started`
- `pix_empty = 1`
- `scan_active = 0`

Root cause: the UI-side flush logic could defer scan restart until the next `frame_edge`, while the renderer had already reset `stream_started`. That created a whole active frame with no pixels ready.

Fix applied in `PanoramaBase_DdrBlackFrame.v`:

- Add `flush_commit_pending`.
- When a frame edge happens during or starts a flush, remember that a commit/scan restart is pending.
- As soon as `flush_active && outstanding == 0 && beat_fifo_empty`, commit the pending bank if available and restart scan immediately instead of waiting for another `frame_edge`.

Build/program/capture evidence:

- Synth: `codex_takeover_deferred_flush_synth.log`
- Impl/bit: `codex_takeover_deferred_flush_impl.log`
- Program: `codex_takeover_deferred_flush_program.log`
- Capture: `captures/usb3_deferred_flush_20260708_213243/`
- Result: 70/70 real frames, `uniform_diag_count = 0`.

This fix should be kept.

### 2. The dominant 32-pixel vertical luma striping is not fixed

After deferred flush/commit:

- Capture: `captures/usb3_deferred_flush_20260708_213243/idx0_frame00.png`
- Chroma speckles stayed near zero.
- 32-pixel luma autocorrelation stayed high, about `0.9357`.
- Visible vertical striping remained severe.

This is still the main open problem.

## Failed mitigations tried and removed

### EO-only display-phase repair

Attempted to patch EO display phases based on USB3 column phase (`x mod 32` around 25..31 and 0). This was wrong because USB3 display column phase is not necessarily the raw MIG 512-bit beat-slot phase.

Evidence:

- Build/program succeeded.
- Capture: `captures/usb3_slotrepair_20260708_221720/`
- `uniform_diag_count = 0`, but image became visibly blockier and still badly striped.
- Source was reverted.

### Source-agnostic first-8-slot interpolation

Attempted to repair the first eight 16-bit slots of each 512-bit beat using interpolation between neighboring luma values. This matched prior raw ILA evidence better than the EO-only phase patch, but it still did not produce an acceptable image.

Evidence:

- Synth: `codex_takeover_interp_synth.log`
- Impl/bit: `codex_takeover_interp_impl.log`
- Program: `codex_takeover_interp_program.log`
- Capture: `captures/usb3_interp_20260708_230219/`
- `uniform_diag_count = 0`
- 32-pixel autocorrelation remained high, about `0.8916`.
- Visible vertical corruption remained severe.
- Source was reverted.

Do not reapply either mitigation as a "fix." If a future temporary display mask is desired, it needs a fresh raw-ILA-to-display-phase correlation first.

## PCB CSV review already performed in this session

Files parsed directly:

- `docs/DDR4_Parameter_DQ-2.csv`: 110 nets, 10 byte lanes worth of DQ/DM/DQS.
- `docs/DDR4_Parameter_CAC-1.csv`: 32 nets, address/command/control/clock.

Important correction: compare command/address and DQS delays to memory `FU_DDR4_CK_C/T`, not `FU_DDR4_SYSCLK_P/N`. `SYSCLK` is the FPGA input reference clock, not the DDR CK delivered to memory.

Using `FU_DDR4_CK_C = 0.573 ns`, `FU_DDR4_CK_T = 0.574 ns`, average `0.5735 ns`:

- CA/CMD/CTL vs DDR CK range: `+11.5 ps` to `+99.5 ps`.
- Worst CA/CMD/CTL skew vs CK: `FU_DDR4_A16_RAS_N` at `+99.5 ps`, `A15_CAS_N` at `+79.5 ps`, `ODT` at `+62.5 ps`.
- Used x64 byte lanes are bytes 0..7.
- DQS-to-DQ abs max for used x64 bytes: `17 ps`.
- DQ span max for used x64 bytes: `17 ps`.
- DQS avg vs DDR CK for bytes 0..7 ranges from `-57 ps` to `-376 ps`.

Interpretation so far:

- DQS-to-DQ matching is very tight.
- CA/CMD/CTL-to-CK matching is modest and not obviously pathological.
- DQS-to-CK differs by byte group by a few hundred ps, which is expected in a multi-chip layout and should be handled by DDR4 calibration.
- The PCB files do not show an obvious per-byte layout outlier matching the all-bytes-simultaneous burst-slot corruption.

Still, the next session should independently re-check this against AMD documentation before touching RTL.

## AMD/Xilinx docs and installed IP metadata status

This session checked installed Vivado IP metadata enough to confirm:

- `C0.DDR4_isCustom` is shown in the GUI Tcl as "Enable Custom Parts Data File"; it is for custom DRAM part data, not PCB trace delay.
- The current IP has `Debug_Signal = Disable`.
- `dbg_bus` exists as a port but is tied/driver-valued zero in the generated XCI when debug is disabled.
- Hardware-manager MIG properties expose DQS/gate telemetry, but direct property writes like `DQS_GATE_COARSE_RANK0_BYTE0` are read-only.

Files/commands already involved:

- Installed GUI Tcl: `C:\AMDDesignTools\2025.2\Vivado\data\ip\xilinx\ddr4_v2_2\xgui\ddr4_v2_2.tcl`
- XCI: `ip/ddr4_sub64/ddr4_sub64.xci`
- MIG property logs:
  - `codex_takeover_mig_props.log`
  - `codex_takeover_mig_writable.log`

The official AMD documentation re-check was started but interrupted. Continue it from primary AMD sources; do not rely only on the repo's prior prose.

## Current leading technical view

The most supported root cause is still below this repo's unpack/renderer RTL:

- Prior ILA work showed write data into MIG is correct.
- Prior ILA work showed corruption already present on `c0_ddr4_app_rd_data`.
- The failure is periodic at one 512-bit app beat = 32 packed pixels.
- The failure is time-slot/whole-rank shaped, not one weak DQ byte lane.
- Calibration and margins report healthy values.
- Keepalive v2 fixed the app-level read-cadence violation and eliminated chroma speckles, but did not remove the dominant luma striping.

Most likely next paths after the required docs review:

1. Enable or regenerate MIG debug visibility if the IP truly supports useful `dbg_*`/calibration status signals in this configuration.
2. Find an AMD-supported way to observe or adjust DQS gate / RIU / XSDB tap state post-calibration, if one exists for this DDR4 v2_2 UltraScale IP.
3. If no PHY lever is exposed, build a more disciplined raw-ILA experiment that correlates full 512-bit returned data, raw beat slot, display column, and frame output before any further masking/interpolation.
4. Only after that, consider rate/timing or controller-configuration experiments. Blind RTL masking already failed twice.

## Useful commands

Vivado path:

```powershell
C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat
```

Build from current source:

```powershell
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source scripts\codex_synth_only.tcl -log codex_next_synth.log -journal codex_next_synth.jou
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source scripts\codex_impl_bit.tcl -log codex_next_impl.log -journal codex_next_impl.jou
& 'C:\AMDDesignTools\2025.2\Vivado\bin\vivado.bat' -mode batch -source scripts\codex_program_once.tcl -log codex_next_program.log -journal codex_next_program.jou
```

Known recurring warning:

- `constraints/camera_base.xdc:788` has pre-existing `set_clock_groups` critical warnings for missing `mmcm_clkout0`. These have appeared across builds and are not new to this handoff.

## Do not lose this nuance

There are now two separate classes of symptoms:

1. Full-frame uniform diagnostic/prefill frames: fixed by deferred flush/commit.
2. Dominant 32-pixel vertical luma striping: still open, likely MIG/PHY/gate-related.

Do not conflate them. The first is an RTL scheduling bug and has a verified fix. The second survived keepalive, slot repair, and interpolation attempts.
