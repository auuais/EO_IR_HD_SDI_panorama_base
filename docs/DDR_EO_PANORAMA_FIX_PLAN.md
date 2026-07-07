# DDR Frame-Buffer Failure Analysis and EO-Panorama-over-DDR Fix Plan

Date: 2026-07-06 (implementation attempted 2026-07-06/07, see status addendum
at the end of this file before reading the plan below as a to-do list)
Project: `E:\Xylinx\EO_IR_HD_SDI_panorama_base\EO_IR_HD_SDI_panorama_base.xpr`
Reference (proven, no-DDR) project: `E:\Xylinx\EO_IR_HDSDI_BRAM-URAM_FRAMESIZE`

This document is the work order for the implementing model. It contains: the
observed symptoms, the verified root causes (with file/line evidence), and a
staged fix plan whose end state is the **EO panorama (6-camera 3x2 stack)
displayed on HD-SDI with the frame passing through the DDR4 buffer**.

---

## 1. Observed symptoms (hardware)

- All DDR-routed modes fail: `EO stack/panorama (0x15)`, `IR single`, `IR stack`.
- `EO single` (direct pass-through, no DDR) works — so cameras, I2C mode
  decode, BT.1120 output, and the HD-SDI link are all healthy.
- Failure appearance: a **green window** on black background; sometimes the
  **top few lines of the window show noise, the rest green**.
- Timing is met (routed WNS +1.855 ns, WHS +0.011 ns,
  `impl_1/..._timing_summary_routed.rpt`), so this is functional, not timing.
- DDR calibration completes (the diagnostic palette states that precede green
  are passed — see decoder table in §5).

In the renderer's diagnostic palette (`src/PanoramaBase_DdrBlackFrame.v`,
`PanoramaBase_HdDdrRenderer`), green `{Y=128,C=256}` means one of exactly two
states, and both were reached:

- **Underflow-green** (line ~842): a committed frame is streaming, the pixel
  FIFO ran empty while the DDR scan is still active → the display starved.
- **Copy-stuck-green** (line ~864): writes granted, copy active, but no frame
  ever commits.

"Top lines noise then green" = the first few hundred DDR beats of the frame
made it to the screen (with corrupted content), then the pipe starved.
This exact signature is fully explained by the two bugs below.

---

## 2. Root causes (verified in source)

### Bug 1 — `USE_ADV_FEATURES("0004")` disables all FIFO flow control (dominant; guarantees failure every frame)

`src/PanoramaBase_DdrBlackFrame.v` lines 215 and 260: both the pixel FIFO
(`xpm_fifo_async`) and the beat FIFO (`xpm_fifo_sync`) are instantiated with
`USE_ADV_FEATURES("0004")`.

In XPM, `USE_ADV_FEATURES` is a bit map: bit1 = `prog_full`, bit9 =
`prog_empty`. `"0004"` sets only bit2 (`wr_data_count`). The XPM source
(`C:\AMDDesignTools\2025.2\data\ip\xpm\xpm_fifo\hdl\xpm_fifo.sv`, lines
538–539) hard-wires disabled flags:

```systemverilog
assign prog_full  = EN_PF == 1 ? ... : 1'b0;   // -> constant 0
assign prog_empty = EN_PE == 1 ? ... : 1'b0;   // -> constant 0
```

So in this design, **all of the following signals are constant 0**:

| Signal | Consumer | Consequence |
|---|---|---|
| `beat_fifo_prog_full` | `scan_ok` gate (line 400) | Scan read-issue is throttled **only** by `outstanding < 32`. Since `outstanding` recycles on every data return, the scan issues all 10,240 reads at near full DDR speed (~50 µs). The unpack drains only ~1 beat/33 ui-cycles. The 128-deep beat FIFO fills in ~170 cycles, and `beat_fifo_wr_en` (line 494) **does not check `full`** → roughly **90–95 % of every frame's beats are silently dropped**. Only the first ~500–700 beats (≈ top 25–35 window lines) reach the screen; the rest of the window starves → green. This alone reproduces the "top lines then green" symptom deterministically. |
| `pix_fifo_prog_full` | unpack gate (line 487) | Mostly benign (per-pixel writes still check exact `full`), but removes intended pacing. |
| `pix_fifo_prog_empty` | renderer prefill (`pix_prefill_empty`, lines 671/704/808) | `stream_started` arms immediately with **zero** prefill instead of 4096 pixels; the renderer begins consuming on a trickle → immediate underflow on any hiccup. |

### Bug 2 — MIG native-interface handshake violation (causes the permanent solid-green lockup and the data corruption/noise)

Every DDR command in the design is issued as a **single-cycle registered pulse
qualified by the *previous* cycle's ready**:

- Scan read: `scan_ok` samples `c0_ddr4_app_rdy` in cycle N (line 399), then
  `c0_ddr4_app_en <= 1'b1` for cycle N+1 only (line 611).
- Copy write: `write_ok` samples `app_rdy && app_wdf_rdy` in cycle N (lines
  403–404), then pulses `app_en + app_wdf_wren + app_wdf_end` in N+1 only
  (lines 624–629).
- The same pattern exists in `PanoramaBase_DdrBringup.v` (it survived there
  because a single write+read on an idle controller almost never collides
  with a ready deassertion).

Per PG150, a command/data beat transfers **only in a cycle where the enable
and its ready are high simultaneously**; if ready is low, the user must hold
the enable and the command until it is accepted. `app_rdy` deasserts
regularly (refresh every ~2,340 ui-cycles at 300 MHz, ZQ cal, command-queue
backpressure under the scan's full-rate issue bursts). Whenever ready falls
exactly between the sample cycle and the pulse cycle, the command or data
beat is **silently lost**. Consequences:

- **Dropped read command** → `outstanding` was incremented at issue (line
  615), never decremented (no data will return). Each drop leaks +1
  permanently. When the leak reaches 32, `scan_ok` is false forever,
  `scan_active` sticks at 1, and — because commit requires
  `frame_edge && !scan_active` (line 587) — no new frame is ever committed.
  **Permanent solid green window until reprogram.** No recovery path exists.
- **Dropped write command with accepted data (or vice versa)** → the MIG
  pairs the write-data FIFO with write commands strictly in order; one orphan
  shifts every subsequent (address ↔ data) pairing by one burst. Frame
  contents in DDR become misplaced/garbage → the **noise** seen in the top
  window lines (with `PATTERN_TEST=1` a clean horizontal ramp should have
  been displayed instead).
- Bookkeeping counts attempts, not acceptances: `rd_issue_count` (line 616),
  `fb_burst_count` (line 633), `outstanding` (line 615) all advance even when
  the command was dropped → scans "complete" short, copies "complete" with
  missing bursts.

### Bug 3 — No resynchronization anywhere (turns any transient into permanent corruption)

- Leftover beats/pixels in `beat_fifo` / `unpack_shift` / `pix_fifo` are
  never flushed at a frame boundary; the renderer pops only when a pixel is
  actually displayed, so after one starved pixel the stream is permanently
  offset — frames scroll/garble cumulatively.
- Stale read data returning after the frame edge (scan issued near the end
  of a frame) is pushed into `beat_fifo` for the *next* frame (the
  `outstanding_next = 0` reset at line 599 zeroes the counter while data is
  still in flight).
- Even with `prog_full` enabled, the margin is wrong:
  `PROG_FULL_THRESH(96) + MAX_OUTSTANDING(32) = 128 = FIFO depth`, plus 1–2
  cycles of flag latency → boundary overflow remains possible.
- No watchdog: a stuck `scan_active` blocks all future commits forever.

### Non-causes (verified, do not spend time here)

- Timing closure: met with margin; CDCs use 2-FF sync / async FIFOs and the
  XDC declares the clock groups asynchronous.
- DDR calibration: completes (diag states past "waiting" are reached).
- The x64-of-x80 subset (4 of 5 x16 devices used, `DQ64..79` unbound) is
  electrically viable: shared CA bus, the 5th chip's DQ float; unused FPGA
  pins are weak-pulled. Keep it. (§6 has an optional hardware sanity gate if
  residual doubt remains after Stage A.)
- The junk lines at the end of `constraints/ddr4_sub64_firstpass.xdc`
  (`set_operating_conditions -process maximum`, `dbg_hub` properties,
  `connect_debug_port dbg_hub/clk [get_nets clk]`) generate warnings only —
  clean them up in passing (Stage A step 6), they are not the failure cause.

---

## 3. Stage A — make the existing DDR path correct (ramp test, no new features)

Scope: `src/PanoramaBase_DdrBlackFrame.v` only (plus XDC cleanup). Keep
`PATTERN_TEST = 1'b1` (line 107) and the existing 640×512 window. The goal of
this stage is: **stable, clean, repeating horizontal ramp in the window,
indefinitely, in any processed mode** — that is the "DDR availability and
functionality" proof the user asked for, before any EO plumbing.

### A1. Enable the FIFO flags

Both FIFOs: `USE_ADV_FEATURES("0004")` → `"0303"`
(bit0 `overflow` + bit1 `prog_full` + bit8 `underflow` + bit9 `prog_empty`).
Wire `overflow`/`underflow` outputs to sticky debug registers (spare diag
bits, see A5) — silent data loss must never be invisible again.

### A2. Fix the MIG handshake — hold enables until accepted

Replace the pulse-issue arbiter with a held-launch FSM. One command in flight
at a time (same as today's single-command arbiter), enables held until fire:

```verilog
// launch/hold registers (drive the app_* ports combinationally or as regs
// that are only cleared on fire)
reg        cmd_pend, cmd_is_rd, wdf_pend;
reg [28:0] cmd_addr_q;
reg [511:0] wdf_data_q;

assign c0_ddr4_app_en       = cmd_pend;
assign c0_ddr4_app_cmd      = cmd_is_rd ? 3'b001 : 3'b000;
assign c0_ddr4_app_addr     = cmd_addr_q;
assign c0_ddr4_app_wdf_wren = wdf_pend;
assign c0_ddr4_app_wdf_end  = wdf_pend;
assign c0_ddr4_app_wdf_data = wdf_data_q;
assign c0_ddr4_app_wdf_mask = 64'd0;

wire cmd_fire = cmd_pend && c0_ddr4_app_rdy;
wire wdf_fire = wdf_pend && c0_ddr4_app_wdf_rdy;
wire issue_busy = cmd_pend || wdf_pend;

always @(posedge c0_ddr4_ui_clk) begin
    ...
    if (cmd_fire) cmd_pend <= 1'b0;
    if (wdf_fire) wdf_pend <= 1'b0;

    if (!issue_busy) begin
        if (scan_want) begin            // read launch
            cmd_pend  <= 1'b1; cmd_is_rd <= 1'b1; cmd_addr_q <= rd_addr;
        end else if (write_want) begin  // write launch: cmd + data together
            cmd_pend  <= 1'b1; cmd_is_rd <= 1'b0; cmd_addr_q <= wr_addr;
            wdf_pend  <= 1'b1; wdf_data_q <= fb_pack_buf;
        end
    end
end
```

- `scan_want` = current `scan_ok` conditions minus the rdy terms
  (`running && scan_active && !beat_fifo_prog_full && (outstanding < MAX_OUTSTANDING)`).
- `write_want` = `running && copy_active && fb_write_pending`.
- **All bookkeeping moves to acceptance**: increment `outstanding`, advance
  `rd_addr`/`rd_issue_count`, and clear `scan_active` on read `cmd_fire`;
  advance `wr_addr`/`fb_burst_count`, clear `fb_write_pending`, and publish
  `pending_bank` on write completion (= both `cmd_fire` and `wdf_fire` seen
  for the burst; track with two sticky bits per burst).
- Keep read priority over write when both want to launch.
- Throughput: 1 command per ≥2 ui-cycles = 150 M cmd/s available vs ~1.3 M/s
  needed (2 × 10,240 per 60 Hz frame) — no concern. This also naturally
  paces the scan so the beat FIFO margin (A3) holds.

### A3. Fix the beat-FIFO overflow margin

- `MAX_OUTSTANDING`: 32 → **16**; `PROG_FULL_THRESH` of the beat FIFO: 96 →
  **64**. Invariant: `PROG_FULL_THRESH + MAX_OUTSTANDING + 4 ≤ 128`.
- Defensively gate `beat_fifo_wr_en` with `!beat_fifo_full` and set a sticky
  `dbg_beat_overflow` if it ever would have dropped (should never fire after
  A1/A2 — it indicates a logic regression).

### A4. Frame-boundary resynchronization + recovery

ui_clk side — replace the commit condition (line 587) with a small sequencer:

1. At `frame_edge`: set `flush_req` if `scan_active || outstanding != 0 ||
   !beat_fifo_empty || unpack_count != 0`; abort the scan
   (`scan_active <= 0`).
2. FLUSH state: issue nothing; wait `outstanding == 0` (all in-flight data
   returned), then drain `beat_fifo` (assert `beat_fifo_rd_en`, discard) and
   clear `unpack_shift/unpack_count`.
3. Only when clean (`!flush_req`) does a `frame_edge` adopt
   `pending_bank`/restart the scan — exactly today's logic otherwise.
   A frame that needed flushing simply repeats the previous committed bank
   one frame later; deterministic, no drift.

rd_clk side (renderer):

4. During a fixed early-vblank window (`v_cnt` in [1080, 1099]), assert
   `pix_rd_en` whenever `!pix_empty` → discards any leftover pixels every
   frame. The per-frame pixel budget then self-heals no matter what happened
   mid-frame.
5. Move `frame_toggle` (and the `stream_started` clear) from `end_frame` to
   the **end of the flush window** (`end_line && v_cnt == 11'd1099`). The
   scan then starts ~25 blank lines before active video, which both gives
   prefill time and (critically) makes Stage B's `Y_OFF = 0` window possible.
   Note the ui-side "frame_edge" is the CDC'd toggle edge — no other change.

### A5. Keep and extend the diagnostics

- Keep the palette. Repurpose two spare `dbg_sync` bits for the new sticky
  flags: `dbg_beat_overflow` (or FIFO `overflow` OR-reduce) and
  `dbg_cmd_retry_seen` (a `cmd_pend` that did not fire in its first cycle —
  proves the handshake fix is actually exercising retries).
- Acceptance for Stage A (hardware): in IR-single or EO-stack mode, the
  640×512 window shows a **stable horizontal ramp (256-px period), no green,
  no drift, for ≥ 10 minutes**; power-cycle twice to confirm cold-boot
  calibration; all six processed-mode selections behave identically.

### A6. XDC cleanup (in passing)

Remove from `constraints/ddr4_sub64_firstpass.xdc`:
`set_operating_conditions -process maximum`, the three `dbg_hub` property
lines, and `connect_debug_port dbg_hub/clk [get_nets clk]`.

---

## 4. Stage B — EO panorama through DDR

Precondition: Stage A ramp is clean. Now swap the *source* of the DDR frame
from the IR test ramp to the proven EO 3×2 stack, and widen the geometry.
Reuse the proven modules from the BRAM-URAM project **verbatim wherever
possible** — they are the "working logic to replicate".

### B1. Import the proven EO tile capture

- Copy `E:\Xylinx\EO_IR_HDSDI_BRAM-URAM_FRAMESIZE\src\EOStackModules.v` into
  `src\` and add to the project. Only `EO1920x1080_Decimate3_FrameBuffer` is
  needed (the `EO6Stack_To_HD1080p_Buffered` renderer is not — DDR replaces
  its BRAM-read path; its geometry logic is reused conceptually in B2/B3).
- Instantiate **six** tile buffers in `PanoramaBase_DdrBlackFrame` (or a new
  sibling module `PanoramaBase_EoStackDdr` if cleaner), fed by the EO camera
  taps, with:
  - `rd_clk = c0_ddr4_ui_clk` (the copy engine reads them),
  - `USE_ASYNC_FIFO(1)` and `CLOCKING_MODE_STR("common_clock")` for **all
    six** (in the donor project cam0 was the direct/common-clock special
    case because wr==rd clock; here ui_clk ≠ CAM0_PCLK, so every camera
    needs the async-FIFO variant — that keeps both RAM ports on ui_clk),
  - `MEMORY_PRIMITIVE_STR("ultra")` for all six (6 × 640×480×16 b ≈ 29.5 Mb;
    KU15P URAM = 36 Mb; the existing six IR block-RAM buffers ≈ 15.7 Mb stay
    in BRAM — both fit only with this split, same as the donor project).
  - `frame_valid` outputs AND-reduced (or just cam0's) → copy trigger
    qualifier.
- Top level: wire `CAM0..5` pixel buses (`{YOUT,COUT}` 20-bit reconstruction
  identical to the donor top: `wr_pixel = {CAMn_YOUT, 2'b00, CAMn_COUT ...}`
  — copy the exact hookup from
  `EO_IR_HDSDI_BRAM-URAM_FRAMESIZE\src\KintexTop_EO_IR_PanoramaStack_BRAM.v`
  lines around the `u_eo_stack_to_hd` instance; note the donor feeds
  `wr_pixel[19:0]` from the per-camera pipeline outputs `eoN_dout`, and the
  buffer packs `{Y[9:2], C[9:2]}` internally).

### B2. Copy engine: raster-order compositor, pipelined reads

Geometry constants (parameterize; Stage A values in parentheses):

```
STACK_W      = 1920      (640)
STACK_H      = 960       (512)
FRAME_PIXELS = 1_843_200 (327_680)
BEATS_TOTAL  = 57_600    (10_240)   // FRAME_PIXELS / 32
ADDR_STRIDE  = 8
BANK0_BASE   = 0
BANK1_BASE   = 460_800               // BEATS_TOTAL * ADDR_STRIDE
```

- Address generation per output pixel `(x, y)` with `x` in 0..1919, `y` in
  0..959: `cam = (y >= 480 ? 3 : 0) + (x >= 1280 ? 2 : x >= 640 ? 1 : 0)`,
  `tile_addr = (y % 480) * 640 + (x % 640)`. Implement with counters (no
  divides): x-counter with 640-boundary column increments, y-counter with a
  480 boundary — mirror the donor renderer's `next_cam_idx/local_x/local_y`
  logic, just driven by the copy sequencer instead of the display beam.
- **Pipeline the tile reads 1 pixel/cycle** (the current one-outstanding
  read takes ~4 cycles/pixel = 24.6 ms/frame for this size — too slow).
  `xpm_memory_sdpram` with `READ_LATENCY(2)` streams perfectly: keep `enb`
  high, stream `addrb`, delay-match the `cam` select by 2 cycles (same
  `cam_pipe` trick as the donor renderer), capture one pixel/cycle into the
  pack buffer. 32 pixels → one 512-bit burst → write launch (A2 FSM).
  Copy time ≈ 57,600 × ~34 cycles ≈ 6.6 ms at 300 MHz — fits 16.7 ms with
  scan interleave (total DDR bus utilization ≈ 2–3 %).
- Packed pixel format written to DDR: 16-bit `{Y[7:0], C[7:0]}` — identical
  to the tile-buffer storage and to what the unpack/renderer already emit.
- Copy trigger: on `frame_edge` when `!copy_active && eo_frames_valid`
  (free-running like the current PATTERN_TEST branch — do **not** gate the
  trigger on camera vsync; the tiles are always-fresh rolling captures and
  the ping-pong bank isolates tearing at the DDR level; this matches the
  simple "pass the frame through DDR" objective). Keep a `SRC_SEL` localparam
  to choose {RAMP, EO_STACK} so Stage A's ramp remains one edit away.

### B3. Renderer window

- Parameterize the window: `X_OFF = 0`, `Y_OFF = 0`, `SRC_W = 1920`,
  `SRC_H = 960` (donor layout: stack occupies rows 0..959, black band below —
  `EO6Stack_To_HD1080p_Buffered` used exactly this). The A4/A5 change
  (scan starts at blank-line 1099, prefill ≥4096 px before line 0) is what
  makes `Y_OFF = 0` viable.
- Output word: `{pix[15:8], 2'b00, pix[7:0], 2'b00}` — same restore as the
  donor's `rd_pixel` assign (line 114 of EOStackModules.v). The current
  renderer already emits `{{pix_dout[15:8],2'b00},{pix_dout[7:0],2'b00}}` —
  unchanged.
- Chroma cadence: the decimator preserves Cb/Cr pairs and every geometry
  offset here (X_OFF 0, tile width 640) is even, so pair alignment survives
  the DDR round trip. Do not introduce odd horizontal offsets.
- pix_fifo prefill threshold: keep `PROG_EMPTY_THRESH 4096`; producer
  (~0.97 px/ui-cycle ≈ 290 Mpx/s) far exceeds display consumption
  (74.25 Mpx/s peak), so the FIFO stays ahead once armed.

### B4. Top-level routing

`src/KintexTop_EO_IR_HD_SDI_panorama_base.v`:

- Feed the six EO camera streams into the DDR module (new ports), keep the
  IR ports as-is.
- `mode_enabled` for the renderer diag palette: pass
  `(ir_single_mode_active || eo_stack_mode_active || ir_stack_mode_active)`
  instead of `ir_single_mode` so EO-stack mode doesn't show the "mode
  disabled" dark-blue state once live sources are used.
- Internal source select: EO stack drives the copy engine when
  `eo_stack_mode_active`; leave IR-single source selection for Stage C.
- Everything else (HD mux at lines 296–300, genlock, EO-single path) stays.

Acceptance for Stage B (hardware): mode `0x15` shows the live 3×2 EO panorama
(1920×960, black band at bottom) via DDR, stable ≥ 10 minutes, no green, no
drift, mode switches EO-single ↔ EO-stack are glitch-free and recover within
one frame.

---

## 5. Diagnostic color decoder (for hardware bring-up, unchanged palette)

While no committed frame exists (window area):
| Color | Meaning |
|---|---|
| dark blue | mode not enabled |
| blue | no frame/copy trigger seen |
| red | trigger seen, no packed burst yet |
| yellow | packed burst, no DDR write grant |
| **green** | **writes granted, copy running, never completes** |
| magenta | copy done, pending bank awaiting commit |
| cyan | copy done historically, no live frame |
| white | unexpected fallback |

While a committed frame streams but FIFO underflows:
| Color | Meaning |
|---|---|
| blue | no DDR read ever issued |
| yellow | reads issued, no data returned |
| magenta | data returned, no pixels unpacked |
| **green** | **scan still active after pixels flowed → starvation** |
| red | pixels flowed, starved near window end |

Suggested new stickies (A5): beat-FIFO overflow, cmd-retry-seen.

---

## 6. Optional hardware de-risk gate (only if Stage A ramp is still corrupted)

If, after A1–A4, the ramp shows banding/noise (not starvation), suspect the
physical x64 subset rather than the RTL. Definitive isolation, no custom RTL:
`open_example_project` on `ip/ddr4_sub64/ddr4_sub64.xci` → build the MIG
example design (built-in traffic generator + `init_calib_complete`/error
LEDs via VIO/ILA) with `constraints/ddr4_sub64_firstpass.xdc` pin map → run
for minutes. Pass ⇒ hardware fine, bug is in our RTL. Fail ⇒ investigate the
five-device topology (signal integrity of shared CA with the 5th device
unterminated on DQ, `UNUSEDPIN` pull settings) before further RTL work.

## 7. Build / program / verify workflow

1. `scripts/codex_synth_only.tcl` → check no new critical warnings (esp.
   URAM inference of the six EO tiles: expect `URAM288` in
   `report_utilization`; ~82 % URAM used, IR buffers still BRAM).
2. `scripts/codex_impl_bit.tcl` → confirm timing still met (ui_clk 300 MHz
   paths got *simpler* — held enables remove the wide same-cycle
   issue cone).
3. `scripts/codex_program_once.tcl` → observe against §5 table.
4. Regression order per stage: EO single (must stay perfect) → target mode.

## 8. Explicit non-goals of this plan

- Live IR video through DDR (`PATTERN_TEST=0` IR path) — Stage C later; the
  Stage A fixes are exactly what it needs, only the trigger/source differ.
- The 5th x16 device / x80 interface, ECC, AXI conversion, >60 Hz.
- Any change to EO-single pass-through, I2C decode, or BT.1120 TRS coding
  (donor-proven, byte-identical here).

---

## 9. Implementation status (2026-07-06/07) — read this before resuming work

Both stages were implemented in full and validated with real Vivado runs
(`xvlog`/`xelab` full elaboration, then repeated `synth_design` +
`launch_runs impl_1 -to_step write_bitstream`, not just visual review). **Stage
A is fully fixed and proven at the synthesis level.** **Stage B is functionally
complete and logically correct — it elaborates, synthesizes, places, routes,
and produces a bitstream with 0 DRC errors — but routed timing does not yet
close**, and hand-editing further one violation at a time has hit diminishing
returns. This section is the handoff: what's done, what's proven, what's
still broken, and the concrete next step.

### 9.1 Stage A — DONE, validated clean

All of §3 (A1–A6) was implemented in `src/PanoramaBase_DdrBlackFrame.v` and
`constraints/ddr4_sub64_firstpass.xdc` exactly as specified: `USE_ADV_FEATURES`
fixed to `"0303"` on both FIFOs, the MIG command/write-data path rewritten as
a held-until-accepted launch FSM (`cmd_pend`/`wdf_pend`/`cmd_fire`/`wdf_fire`),
`MAX_OUTSTANDING` dropped to 16 with beat-FIFO `PROG_FULL_THRESH` at 64, a
`flush_active` frame-boundary resync sequencer added, a renderer-side vblank
pixel drain and a moved `frame_toggle` point (25 blank lines of scan headroom
before line 0) added, and the stray XDC debug-hub lines removed. A full
`synth_design` run on this state alone came back **0 errors, 0 new critical
warnings** (the two remaining `CRITICAL WARNING`s about `mmcm_clkout0` are
pre-existing, present in the baseline commit before any of this work, and
unrelated). One self-inflicted issue was caught and fixed in the same pass:
`dbg_cmd_retry_seen` had no logic consumer and was being silently trimmed;
it now carries `(* mark_debug = "true", dont_touch = "true" *)` so it survives
for future ILA probing. **If you need a clean, timing-proven fallback while
investigating Stage B, set `SRC_SEL = SRC_RAMP` at the top of
`PanoramaBase_DdrBlackFrame.v` (line ~120) and rebuild — this reverts to the
Stage-A ramp-through-DDR proof, which is solid.**

### 9.2 Stage B — functionally complete, NOT timing-clean

Everything in §4 (B1–B4) was implemented: `src/EOStackModules.v` was added
(verbatim `EO1920x1080_Decimate3_FrameBuffer` from the donor project, plus one
retiming register — see 9.3), six instances feed off the real EO camera taps
via `SRC_SEL = SRC_EOSTK` in `PanoramaBase_DdrBlackFrame.v`, the copy engine
composites the 1920x960 canvas in raster order, and the renderer window was
parameterized and now defaults to the full top-aligned 1920x960 panorama
layout. `KintexTop_EO_IR_HD_SDI_panorama_base.v` wires all six EO camera
streams into the new ports. **All of this is logically correct**: full
`xelab` elaboration (with the real XPM library and the project's own DDR IP
stub compiled in) succeeds with 0 errors, and `synth_design` +
`write_bitstream` both complete successfully every time — the design is not
broken, it simply does not yet meet its 300MHz `ui_clk` timing constraint.

Two real RTL bugs were found and fixed during validation (both are already
in the tree, not just diagnosed):

1. **Declaration-order bug (was a real functional bug, now fixed).** The
   shared wires `eo_frames_valid`/`copy_px_valid`/`copy_px_data` and the regs
   `copy_active`/`fb_write_pending` were originally declared *after* the
   `generate` block that uses them. `xvlog`/`xelab` tolerated the forward
   reference; **Vivado's synthesis elaborator did not** — it silently bound
   each `generate` branch's reference to an implicit net scoped *inside* that
   branch instead of the real module-scope signal, leaving the real
   `eo_frames_valid` permanently undriven (confirmed via `WARNING: [Synth
   8-3848] Net eo_frames_valid ... does not have driver`). That made
   `copy_active` provably always 0 to the synthesizer, and all six EO tile
   buffers were optimized away as dead logic (`WARNING: [Synth 8-13161] RAM
   ... is optimized away because it doesn't have any load`). **Fix (already
   applied):** every signal a `generate` block drives or reads must be
   declared textually *before* that `generate` block. This is a general
   Vivado-synthesis gotcha worth remembering for any future generate-based
   RTL in this codebase — the simulator will not catch it.
2. **Combinational multiply on a 300MHz path (was a real timing bug, now
   fixed).** The first working version computed
   `copy_tile_addr = copy_tile_y_c * 640 + copy_tile_x_c` combinationally
   every cycle from the raster-walk counters, synthesizing to a DSP48
   multiplier whose output fanned out unregistered into all six tile
   memories' address/enable ports. That is fine at the donor project's
   74.25MHz render clock (13.47ns period) but was measured at ~5.9-6.0ns of
   data-path delay against this design's 3.332ns (300MHz `ui_clk`) period —
   the single largest contributor to the first routed run's failure (WNS
   -2.777ns, TNS -36,590ns, 29,818 failing endpoints, *every* worst path
   sourced from `copy_y_reg`/`copy_tile_y_c` through a `DSP_MULTIPLIER`).
   **Fix (already applied):** replaced with an increment-only walk
   (`col_in_tile`/`col_group`/`row_in_tile`/`row_group`/`row_base`, the last
   maintained by `+= 640` once per display row, never multiplied) — plain
   adders and compares only. This alone cut the violation to WNS -1.261ns /
   TNS -7,809ns / 16,871 endpoints — real, verified, substantial progress,
   confirmed via a from-scratch re-synthesis (checkpoint timestamp checked
   against the source-edit timestamp both times, since `launch_runs impl_1`
   silently reused a stale synth_1 result once during this work — always
   verify the `.dcp` mtime is newer than your source edit before trusting a
   routed timing report).

### 9.3 What's still broken, and why (the actual open problem)

After the two fixes above, three more targeted attempts were made, each
producing measurable but incomplete improvement:

| Attempt | WNS | TNS | Failing endpoints | What changed |
|---|---|---|---|---|
| Multiply feeding all 6 tiles | -2.777 ns | -36,590 ns | 29,818 | (baseline, broken) |
| Multiply → adder | -1.261 ns | -7,809 ns | 16,871 | removed the DSP multiply |
| + READ_LATENCY 2→7, deterministic 1-URAM/5-BRAM split | -1.575 ns | -8,420 ns | 14,144 | see below |
| + write-broadcast retiming register | -1.549 ns | -4,237 ns | 8,131 | see below |

Root cause of everything in this table below the second row: **each
640x480x16-bit EO tile is a genuinely large memory (4.9 Mb) stored only 16
bits wide**, far narrower than a Xilinx block RAM's native ~36-bit port or an
UltraRAM's native 72-bit port. That mismatch forces an extremely deep
cascade — **75 URAM288 blocks** or **~142 RAMB36E2 blocks** per tile, just to
get the required depth at 16 bits wide, instead of a shallow/wide layout.
Two independent physical consequences follow directly from that, and both
were observed:

- **KU15P only has 128 URAM288 total.** One tile alone needs 75 of them
  (58%); a second tile would need 150, over budget. All six tiles at 16-bit
  width literally cannot fit in URAM (`6 x 75 = 450 > 128`) — confirmed by a
  hard synthesis failure (`ERROR: [Synth 8-5867] Design has over-utilized
  URAMs`) when more pipeline headroom made Vivado's heuristic *try* to push
  more than one tile into URAM. The fix applied (exactly one tile pinned to
  `MEMORY_PRIMITIVE_STR("ultra")`, the other five explicit `"block"`) is
  correct and necessary, but only relocates the problem: the five BRAM tiles
  now consume **727 of 984 RAMB36E2 (74%)** just for this feature, on top of
  everything else in the chip.
- **At that occupancy, physical placement cannot keep a tile's ~75-142
  cascaded blocks close together**, because a single narrow write/read
  broadcast bus must reach every one of them. Every violated path after the
  multiply fix is *either* (a) an internal cascade output-select/pipeline
  path inside one memory (fixed by raising `READ_LATENCY` to Xilinx's own
  stated recommendation of 7, `5-of-7 pipeline stages absorbed` — real,
  helped, insufficient alone), or (b) **pure routing delay with 0-5 logic
  levels and 3.8-4.2ns of route delay** from one small source (the
  compositor's counters, or the per-tile CDC FIFO's popped output) to a
  cascade segment placed far away on the die. The write-broadcast retiring
  register (§9.2 point 2's sibling fix, added directly in
  `src/EOStackModules.v`'s `gen_async_wr` branch) attacks exactly that second
  category and roughly halved both TNS and the failing-endpoint count — real
  progress — but the *worst single path* has now plateaued in the -1.5 to
  -1.6ns range for three iterations in a row, because fixing one dominant
  contributor immediately exposes the next one at nearly the same magnitude.
  That plateau, not any single remaining bug, is the signal that this is a
  **structural resource/placement problem, not a collection of independent
  point bugs** — the previous few fixes were each correct and worth keeping,
  but continuing to chase individual violated paths one at a time is very
  unlikely to converge.

**[CORRECTION 2026-07-07 — read §10 instead of the rest of this paragraph.
The BRAM half of the recommendation below is arithmetically wrong: a BRAM's
block count is bounded by total bits (4.92 Mb / 36 Kb ⇒ ≥134 RAMB36E2 per
tile at ANY word width — the donor project's own utilization report confirms
142/tile), so packing pixels wider does NOT shrink the BRAM cascades or their
broadcast distances. Packing only helps URAM (16-of-72 bits used per row today
⇒ 75 URAM/tile; packed 64-bit words ⇒ ~19/tile). More importantly, §10 shows
the root cause is the clock domain, not the cascade shape, with a decisively
simpler fix.]**

Original (superseded) recommendation: reduce the cascade depth
by packing multiple pixels per stored word. Concretely: widen
`EO1920x1080_Decimate3_FrameBuffer`'s internal `PACKED_PIXEL_W` (currently a
hardcoded `16` in `src/EOStackModules.v`) to something that better fills a
BRAM/URAM row — e.g. 4 pixels packed into 64 bits — which would divide the
required depth (and therefore the block count and cascade length) by roughly
that same factor (75 URAM288 -> ~19; ~142 RAMB36E2 -> ~36), directly shrinking
both the resource footprint and the physical distance signals need to travel.
This requires: (a) a small write-side accumulator in the donor module to
gather 4 incoming Y/C samples before committing one wide write (currently
one pixel writes at a time), and (b) a matching change on the read side —
`PanoramaBase_DdrBlackFrame.v`'s compositor currently expects one pixel per
memory read per cycle; reading a 4-pixel-wide word would need a small
de-packing shift register there instead, and the copy engine's per-cycle
cadence/addressing would change accordingly (word-address instead of
pixel-address, one memory read per 4 output pixels). This is real, scoped
work, not a parameter tweak, which is why it wasn't attempted in this
session — but it directly targets the measured root cause rather than
chasing its symptoms. Secondary/complementary options if that alone isn't
enough: PBLOCK floorplanning to physically cluster each tile's cascade
(bounds the placement search instead of letting it spread across the whole
die), or revisiting whether all six tiles truly need to be buffered
simultaneously for the "prove DDR works" milestone (e.g. a reduced
resolution or fewer simultaneous tiles as an intermediate step).

### 9.4 Where everything is

- Current RTL state (all fixes applied, timing not closed) is committed to
  the working tree — nothing here needs to be reverted to resume.
- Latest bitstream (builds, but not timing-clean; do not program hardware
  with it and expect correct operation):
  `EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit`
- Latest routed timing report:
  `EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base_timing_summary_routed.rpt`
- Build logs from this session, in chronological order, if you want the full
  history of what was tried and its measured effect: `stage_a_synth.log`,
  `stage_b_synth.log` (had the declaration-order bug), `stage_b_synth2.log`
  (bug fixed), `stage_b_impl.log`/`stage_b_impl2.log` (the second was a
  stale-checkpoint false read — see §9.2), `stage_b_synth3.log` (confirmed
  fresh), `stage_b_impl3.log` (multiply bug found here), `stage_b_synth4.log`
  (multiply fixed but over-allocated URAM), `stage_b_synth5.log`/
  `stage_b_impl5.log` (deterministic URAM/BRAM split + READ_LATENCY=7),
  `stage_b_synth6.log`/`stage_b_impl6.log` (write-broadcast retiming
  register, latest/best result: WNS -1.549ns, TNS -4,237ns, 8,131 endpoints).
- Final utilization at the latest attempt: `727/984 RAMB36E2 (74%)`,
  `75/128 URAM288 (59%)`, `1/1968 DSP48E2 (0.05%, unrelated to this work)` —
  confirms plenty of DSP/logic headroom remains; block RAM is the binding
  constraint, consistent with the root-cause analysis above.

---

## 10. VERIFIED root cause of the Stage-B timing failure + corrective plan (2026-07-07)

This section supersedes §9.3's analysis and recommendation. It is based on
two measurements that were not taken during the §9 session, and they change
the conclusion.

### 10.1 The two decisive measurements

**(a) Per-clock breakdown of the current failure.** The routed report's
Intra Clock Table (`..._timing_summary_routed.rpt`, latest run) shows that
**every one of the 8,131 failing endpoints is in `mmcm_clkout0` — the 300 MHz
DDR `ui_clk`**. Every other domain has large positive slack:

| Clock | WNS | Failing endpoints |
|---|---|---|
| `mmcm_clkout0` (ui_clk, 3.332 ns) | **-1.549 ns** | **8,131** |
| `CAM0_PCLK` (constrained 10.000 ns) | +5.699 | 0 |
| `CAM1..5_PCLK` | +6.9 … +10.5 | 0 |
| everything else (MIG internal, dbg) | positive | 0 |

**(b) The donor project closes timing with the *same* memories on the *same*
part at *higher* BRAM utilization.** From
`E:\Xylinx\EO_IR_HDSDI_BRAM-URAM_FRAMESIZE\impl_utilization.rpt` and
`impl_timing_summary.rpt` (routed, xcku15p-ffve1517-2-i, same speed grade):
each donor `EO1920x1080_Decimate3_FrameBuffer` is **142 RAMB36 — identical
block count and cascade shape to ours** — for a design total of **863/984
RAMB36 (88%) + 96 URAM**, and it routes at **WNS +0.433 ns**. Its tile
memories are clocked at CAM0_PCLK (constrained 10 ns). Ours fail at 74%
BRAM utilization — the only difference is that our tile memories live on the
3.332 ns clock.

### 10.2 Root cause statement

**Stage B moved all six EO tile memories — ~29.5 Mb of storage in 75-URAM /
142-BRAM cascades, plus their address/enable/write-data broadcast networks —
into the 300 MHz `ui_clk` domain. Those broadcast nets physically cannot
reach 142 spread-out block RAMs within 3.332 ns on this die, at any
utilization we can reach. The identical memories at 10 ns close with nearly
6 ns to spare (donor-proven, §10.1b).** That is why per-path fixes plateaued:
each fix (multiply removal, retiming register, more cascade pipelining) was
individually correct and measurably helped TNS/endpoints, but the next
longest broadcast route always surfaced at ≈ -1.5 ns because the physical
distance problem is intrinsic to *where the memories are clocked*, not to
any particular net.

The critical realization: **the 300 MHz domain never needed random access
into the tiles at all.** It only needs the composed pixel *stream*, whose
required rate is 55.3 Mpx/s average (1,843,200 px per 33.3 ms display frame
— note the BT.1120 timing here is 2200x1125 at 74.25 MHz = 30 Hz frame
cadence). A 74.25 MHz compositor walking 1 px/cycle produces 74.25 Mpx/s —
comfortably sufficient — and completes a full 1,843,200-px walk in 24.8 ms,
inside one 33.3 ms display frame, so the existing per-frame ping-pong
cadence is preserved exactly.

### 10.3 The fix (Option A, primary): move the compositor + tile RAMs to `rd_clk`, stream pixels to `ui_clk` through one small async FIFO

All changes are inside `src/PanoramaBase_DdrBlackFrame.v`'s `g_src_eostk`
generate branch (plus nothing else — the pack/burst FSM, scan, unpack,
pix_fifo, renderer, Stage-A logic, and XDC are all untouched; the required
`set_clock_groups -asynchronous` between `mmcm_clkout0` and `CAM0_PCLK`
already exists at `constraints/camera_base.xdc:788`, verified).

1. **Re-clock the six tile buffers to `rd_clk`** (the module input, CAM0
   PCLK domain — donor-identical): change `.rd_clk(c0_ddr4_ui_clk)` to
   `.rd_clk(rd_clk)` on all six `EO1920x1080_Decimate3_FrameBuffer`
   instances. This puts both memory ports (the donor module clocks its
   write port on `rd_clk` too — the camera CDC happens in its small
   internal FIFO) back at 10 ns.
2. **Restore the donor's cam0 exception.** With the tile read clock back on
   the CAM0-PCLK-derived domain, `u_eo_fb0`'s write clock (`eo0_wr_clk` =
   `eo0_pclk`, same source) and read clock are the *same clock* again. The
   donor hit a bitgen DRC using an independent-clock FIFO with identical
   clocks and solved it by instantiating fb0 with **`USE_ASYNC_FIFO(0)`**
   (direct write path, no CDC FIFO — see
   `EO_IR_HDSDI_BRAM-URAM_FRAMESIZE\src\KintexTop_EO_IR_PanoramaStack_BRAM.v:425`
   and its README). Replicate exactly: fb0 gets
   `.USE_ASYNC_FIFO(0), .CLOCKING_MODE_STR("common_clock"), .FIFO_RELATED_CLOCKS(1)`;
   fb1..5 keep the async-FIFO variant (their camera clocks are genuinely
   unrelated to CAM0). Note fb0's direct path bypasses the §9 retiming
   register (that lives in the async branch only) — donor-proven at 10 ns,
   fine.
3. **Revert `EO_READ_LATENCY` from 7 back to 2** (the donor value). The
   extra cascade pipelining was only needed for 3.332 ns; our own routed
   reports measured the worst URAM-cascade read path at ~5.6 ns total —
   trivially inside 10 ns at RL=2. The walk-side delay-matching pipes
   (`eo_cam_pipe`/`eo_use_pipe`) are already written generically in terms
   of `EO_READ_LATENCY`, so only the localparam changes. Expect (and
   ignore) Vivado's `[Synth 8-6013] UltraRAM ... under-pipelined,
   recommended 7` warning — it is a clock-agnostic Fmax advisory; our
   constraint on that logic is now 10 ns, not 3.332 ns.
4. **Re-clock the compositor walk to `rd_clk`**: the three `always
   @(posedge c0_ddr4_ui_clk)` blocks in `g_src_eostk` (walk counters
   `col_in_tile/col_group/row_in_tile/row_group/row_base/copy_walk_done`;
   the `eo_cam_pipe/eo_use_pipe` delay-match pipes) become
   `always @(posedge rd_clk)`. Their reset term changes from
   `ui_rst || !copy_active` to `!rst_n || !copy_active_rd`, where
   `copy_active_rd` is a new 2-FF synchronization of the ui-domain
   `copy_active` into `rd_clk` (a slow level — plain 2-FF is correct).
5. **Add the copy-stream CDC FIFO** (`xpm_fifo_async`, the one genuinely
   new element): write side `rd_clk`, read side `c0_ddr4_ui_clk`.
   Parameters: `WRITE_DATA_WIDTH(16), READ_DATA_WIDTH(16),
   FIFO_WRITE_DEPTH(512), READ_MODE("fwft"), FIFO_READ_LATENCY(0),
   USE_ADV_FEATURES("0303")` ← **must** enable prog_full, bit1 — same
   lesson as fix A1 — `PROG_FULL_THRESH(448), CDC_SYNC_STAGES(2),
   RELATED_CLOCKS(0)`, `rst(~rst_n)` (write-domain reset, donor pattern).
   Wiring:
   - `wr_en` = the existing pixel-valid (`eo_use_pipe[EO_READ_LATENCY-1]`),
     `din` = the existing 16-bit repacked pixel (`{eo_cur_pixel[19:12],
     eo_cur_pixel[9:2]}`) — i.e., what previously drove
     `copy_px_valid/copy_px_data` directly now feeds the FIFO instead.
   - **Walk issue gating**: `copy_issue = copy_active_rd && !copy_walk_done
     && !copyfifo_prog_full`. prog_full is a native write-side (rd_clk)
     flag — no CDC needed. In-flight pixels after prog_full asserts ≤
     EO_READ_LATENCY+1 = 3, against 512-448 = 64 words of headroom.
6. **ui-side consumption** (replaces the old direct assigns):
   - `assign copy_px_data  = copyfifo_dout;`
   - `wire copy_px_take = copy_active && !fb_write_pending &&
     !copyfifo_empty;` → `assign copyfifo_rd_en = copy_px_take;` and
     `assign copy_px_valid = copy_px_take;` (FWFT: pop and pack in the same
     cycle; the pack engine already tolerates gaps in `copy_px_valid`).
   - **Idle drain rule** (defensive, for aborted copies e.g. calibration
     loss): when `!copy_active && !copyfifo_empty`, assert `copyfifo_rd_en`
     to discard; set a sticky `dbg_copyfifo_resid` if this ever fires
     outside reset — in normal operation pixel conservation is exact
     (walk produces exactly FRAME_PIXELS = 1,843,200; the pack engine
     retires exactly BEATS_TOTAL = 57,600 bursts x 32 px, then drops
     `copy_active`).
7. **`eo_frames_valid` CDC**: the six `frame_valid` flags are now rd_clk-
   domain levels; 2-FF-sync their AND into `ui_clk` before use in
   `copy_start_trig` (slow monotonic level, plain 2-FF).
8. **Declaration order**: any new signal referenced inside `g_src_eostk`
   must be declared *before* the `generate` block (Vivado synthesis
   elaboration gotcha from §9.2 — the simulator will not catch it; check
   the synth log for `[Synth 8-3848] no driver` / `8-6901 used before
   declaration` messages afterwards).

What deliberately does NOT change: `MEMORY_PRIMITIVE` split stays
1x"ultra"(fb0) + 5x"block" — it fits (727 BRAM + 75 URAM measured) and at
10 ns either primitive closes; the §9 write-broadcast retiming register in
`EOStackModules.v` stays (harmless at 10 ns, still useful); `SRC_RAMP`
branch untouched (its IR-buffer reads stay on ui_clk — that configuration
met timing in the June baseline at +1.855 ns and in Stage A).

Expected outcome: the `mmcm_clkout0` group loses every EO-memory endpoint
(~all 8,131 current failures) and returns to its Stage-A footprint, which
met timing; the EO memories move to a 10 ns domain where the donor closed
the same netlist shape with ~6 ns of margin. Resource delta: +1 small FIFO
(≤1 RAMB18/36).

Note in passing: in `SRC_EOSTK` builds the six IR capture BRAMs are
optimized away by synthesis (their read path has no consumer in this build)
— expected, not a bug; they return in `SRC_RAMP`/Stage-C builds.

### 10.4 Fallback (Option B) and rejected option

**Option B — pack 4 px per 64-bit word and put ALL SIX tiles in URAM.**
Corrected arithmetic (see §9.3 correction): packing does nothing for BRAM
(bit-bound at ~134-142 RAMB36/tile) but raises URAM row efficiency from
16/72 to 64/72 bits ⇒ ~19-20 URAM288 per tile ⇒ 6 tiles ≈ 114-120 of 128
URAM, freeing ~680 BRAM and shrinking each tile to a single-column URAM
matrix with dedicated cascade routing. The donor project itself uses this
exact trick for its IR buffers (its 96 URAM = 6 IR buffers packed 4 px/word)
— functionally proven, though not at 300 MHz. Cost: real surgery in
`EOStackModules.v` (write-side 4-sample accumulator — addresses are strictly
sequential so gathering is clean, and 307,200 px = exactly 76,800 words, no
partial-word flush) plus word-addressing and a read-side de-pack shifter in
the compositor. Keep this as the fallback if Option A shows an unforeseen
hardware issue; do not start with it.

**Option C — rejected**: half-rate enables + `set_multicycle_path 2` on the
walk→memory paths. Constraint scoping across XPM-generated hierarchy is
fragile and silently under-constrains when it misses cells; not worth it
when Option A removes the fast-clock requirement outright.

### 10.5 Validation workflow + acceptance (for the implementing model)

1. `xvlog` syntax pass on the edited file(s).
2. Fresh synthesis (`scripts/codex_synth_only.tcl`); **verify
   `EO_IR_HD_SDI_panorama_base.runs/synth_1/*.dcp` mtime is newer than your
   source edit** (a stale-checkpoint `launch_runs impl_1` produced a false
   timing read once in §9 — don't trust a routed report without this check).
   Confirm no `[Synth 8-3848]`/`[Synth 8-6901]` messages and no URAM
   over-allocation error.
3. Implementation (`scripts/codex_impl_bit.tcl`). Acceptance: **routed WNS
   ≥ 0 in EVERY row of the Intra Clock Table** (not just headline WNS), and
   0 bitgen DRC errors — pay attention to any FIFO clock DRC around
   `u_eo_fb0` (that is what step 10.3-2 prevents).
4. Hardware: mode `0x15` shows the live 3x2 EO panorama through DDR, stable
   ≥10 min (acceptance list in §4/B4 unchanged). Regression: EO-single
   still perfect; optionally rebuild with `SRC_SEL = SRC_RAMP` for the
   Stage-A ramp check.

---

## 11. Section 10 fix IMPLEMENTED and TIMING CLOSES (2026-07-07)

Section 10's plan was implemented exactly as specified, in
`src/PanoramaBase_DdrBlackFrame.v`'s `g_src_eostk` branch, and validated with
a full `xvlog`/`xelab` elaboration (real XPM library + donor module + DDR IP
stub, 0 errors) followed by a from-scratch `synth_design` +
`launch_runs impl_1 -to_step write_bitstream` (checkpoint timestamp verified
newer than the source edit both times, per the standing caution in this
file). **Routed result: timing closes, every clock domain positive:**

| Clock | WNS | Notes |
|---|---|---|
| **Design headline** | **+0.074 ns** | "All user specified timing constraints are met." |
| `mmcm_clkout0` (ui_clk, 300MHz) | **+0.074 ns** | was -1.549 ns / 8,131 failing endpoints before this fix |
| `CAM0_PCLK` (rd_clk, 74.25MHz) | **+0.295 ns** | now hosts the walk + all six tile memories |
| `CAM1..5_PCLK` | +7.4 to +10.8 ns | unaffected, as expected |
| `c0_sys_clk_p` | +3.804 ns | unaffected |

0 bitgen DRC errors across all four DRC passes (opt/place/route/bitgen) --
confirms the `u_eo_fb0` `USE_ASYNC_FIFO(0)`/`CLOCKING_MODE_STR("common_clock")`
exception correctly avoided the identical-wr/rd-clock async-FIFO DRC the
donor project's README warns about. 0 critical warnings (the `mmcm_clkout0`
`set_clock_groups` critical warning present in every prior run of this
project, including the original working baseline, is also gone -- the
groups it referenced are simply no longer adjacent to any timed path in a
way that trips it). Final utilization: **751/984 RAMB36E2 (76%)**,
**75/128 URAM288 (59%)**, 3 DSP48E2 (unrelated to this design). Resource
totals are essentially unchanged from the pre-fix attempt (was 727 BRAM/75
URAM) -- confirming, as diagnosed, that this was purely a clock-domain
problem, not a resource-count problem.

Bitstream:
`EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit`
(built from the commit including this fix -- safe to program).

**What changed vs. the section-10 spec**: nothing structural. Implementation
notes for anyone diffing against the spec:
- `copy_issue`'s gate on `!copyfifo_prog_full` requires `copyfifo_prog_full`
  to be declared before `copy_issue`'s own `wire` statement; the FIFO's wire
  declarations (not the instance itself) were hoisted just above the
  raster-walk-state section for exactly that reason -- a self-imposed
  belt-and-suspenders measure, not a repeat of the §9.2 cross-generate-block
  bug (this is a same-scope forward reference, which is ordinary two-pass
  Verilog elaboration; hoisting it just removed any need to reason about
  the distinction under time pressure).
- The `dbg_copyfifo_resid` sticky diagnostic (§10.3 step 6) was added with
  `(* mark_debug = "true", dont_touch = "true" *)`, matching the
  `dbg_cmd_retry_seen` precedent from §9.2 (it has no logic consumer, so
  without that attribute pair synthesis would trim it as dead logic).

**Remaining work is hardware bring-up only** (§10.5 step 4): program the
bitstream above and confirm mode `0x15` shows the live 3x2 EO panorama
through DDR, stable for several minutes, with clean mode switching to/from
EO-single. This is now a timing-clean, DRC-clean bitstream -- if hardware
behavior doesn't match, the fault is almost certainly in the pixel data
path or camera timing, not in the DDR/clocking work covered by this
document.

---

## 12. Hardware bring-up result: timing-clean, but a new visual defect (2026-07-07)

The section-11 bitstream was programmed and mode `0x15` renders a
recognizable, correctly-geometried EO panorama (confirming the timing fix
and the whole clocking/CDC rework are sound) -- but the image is overlaid
with a dense grid of thin, static, evenly-spaced vertical magenta stripes
(visual estimate: roughly 60-90 stripes across 1920 columns, i.e. one
every ~20-32 px). User's own hypothesis was "still a timing issue"; this
section records why that reading doesn't fit the evidence and what test
is running instead.

### 12.1 Why this is very unlikely to be residual timing

The routed report backing the section-11 bitstream shows **positive slack
on every single clock domain**, not just the headline WNS -- there is no
marginal/near-zero path for silicon-level PVT variation to tip negative.
Beyond that, a real STA violation degrades unpredictably (different
frame-to-frame, sensitive to temperature/voltage) and would not produce a
*static, perfectly regular* grid. A fixed-period, fixed-position pattern
that repeats identically every frame is the signature of a **deterministic
logic or data-value bug tied to a periodic address/count boundary**, not a
marginal timing path.

### 12.2 Ruled out: async-FIFO fill-rate/CDC timing jitter

The first hypothesis considered was a periodic pix_fifo/beat_fifo
underrun -- e.g. the unpack side's 32-cycle "pop a beat's 32 pixels, then
1 cycle to load the next beat" cadence creating a recurring gap on the
`ui_clk` (write) side of `pix_fifo`. This doesn't survive scrutiny: that
gap is on `c0_ddr4_ui_clk` (300 MHz), `pix_fifo` is 8192 deep, and the
renderer drains it on the *asynchronous, unrelated* `rd_clk` (74.25 MHz)
domain after crossing through the FIFO's CDC logic. There is no phase
relationship between a "every 33rd `ui_clk` cycle" event and a "fixed
`rd_clk`-domain display column" -- deep async buffering decorrelates
exactly this kind of timing jitter. It could produce occasional,
randomly-positioned glitches under sustained rate starvation, but not a
static grid locked to screen position on every frame. (Bandwidth math
also argues against sustained starvation: average fill rate is ~291 Mpx/s
against a ~55.3 Mpx/s drain requirement, over 5x headroom.)

### 12.3 Leading hypothesis: a value-correct-but-periodic-in-address bug

A bug that corrupts *which value* lands at a specific periodic pixel
*position* (rather than *when* it arrives) survives every clock-domain
crossing and buffering stage unchanged, because the pipeline preserves
order even when it doesn't preserve timing -- the wrong value just rides
along and lands in its correct positional slot in the final raster, every
frame, identically. That matches the observed symptom exactly. The
prime suspect location is the 32-pixel DDR beat granularity shared by
`fb_pack_buf` (write/pack side) and `unpack_shift` (read/unpack side) in
`src/PanoramaBase_DdrBlackFrame.v` -- 1920/32 = 60, matching the low end
of the observed stripe count. Both sides were re-checked by hand
(pack: `fb_pack_buf[{fb_pack_count,4'b0000} +: 16] <= copy_px_data`, slot N
= bits `[16N+15:16N]`, pixel 0 first; unpack: `pix_fifo_wr_data <=
unpack_shift[15:0]` then `unpack_shift <= {16'd0, unpack_shift[511:16]}`,
also pixel-0-first) and both are internally consistent with no visible
off-by-one -- so if the bug is here, it is subtler than a simple index
error, or it is elsewhere on a similarly-periodic boundary (e.g. an
addressing-granularity mismatch such as `ADDR_STRIDE` vs. the DDR4 MIG's
actual per-beat address increment -- untouched by any fix in this
document, so if this is it, it is a **pre-existing** bug that live camera
content newly makes visible, since a synthetic ramp is harder to
eyeball for fine positional corruption than real scene content).

### 12.4 Decisive next test: PATTERN_TEST ramp bisection (in progress)

Rather than guess further, this project already has a purpose-built
bisection switch for exactly this situation (§2's diagnostic decoder /
the `SRC_SEL` localparam): flip `SRC_SEL` from `SRC_EOSTK` to `SRC_RAMP`
and rebuild. This routes a known, deterministic raster ramp
(`{fb_rd_addr[7:0], 8'h80}`, `PATTERN_TEST=1'b1` already set) through the
**exact same shared back end** the EO path uses -- `fb_pack_buf` pack →
DDR write → scan → `beat_fifo` → `unpack_shift` → `pix_fifo` → renderer
-- while completely bypassing the EO-specific front end (six tile
buffers, rd_clk compositor walk, `u_copy_cdc_fifo`). Note the ramp branch
is **not** a clean 1:1 substitute for the whole pipeline: it drives
`copy_px_valid`/`copy_px_data` directly from `ui_clk`-domain
`fb_rd_en_d2`/`fb_rd_addr` (Stage-A's original single-BRAM-read design),
so it does not exercise `u_copy_cdc_fifo` or anything upstream of
`copy_px_data` -- but everything *downstream* of `copy_px_data` (all of
§12.3's suspects) is identical code, shared unconditionally by both
branches.

**Interpretation once the ramp bitstream is on hardware:**
- **Ramp shows the same regular stripes** → the bug is confirmed in the
  shared pack/DDR/scan/unpack/render back end (§12.3's suspects), fully
  decoupled from the EO compositor, tile buffers, and copy CDC FIFO. Next
  step: instrument `fb_pack_count`/`unpack_count`/DDR address bits with
  `mark_debug` and an ILA, since static re-reading has not found the bug.
- **Ramp is clean** → the bug is specific to the EO front end (tile
  capture, rd_clk compositor walk/tile-select muxing, `u_copy_cdc_fifo`,
  or the 20-bit→16-bit EO pixel repack at line ~728). Next step: audit
  `col_group`/`row_group` tile-select muxing and the `eo_cur_pixel`
  repack for a boundary that recurs every ~20-32 columns within a tile.

This is a compile-time-only change (one localparam flip), already
committed to `src/PanoramaBase_DdrBlackFrame.v` pending a fresh
synth+impl+program cycle. It is expected to build significantly faster
than the EO-panorama bitstream since `g_src_ramp` instantiates none of
the six 20-bit EO tile framebuffers.

**Build result (2026-07-07): timing-clean, ready to test.** As predicted,
much smaller/faster than the EO build (synth 3m51s vs. 5m31s but with
only 11 RAMB36E2 used vs. 751; full impl+bitgen 25m10s). Routed:
**WNS +0.058 ns, "All user specified timing constraints are met,"** 0
DRC errors, 0 critical warnings (2 critical warnings during synthesis
only, matching the same standing/expected count seen in every prior
successful run of this project). Checkpoint/bitstream mtime verified
newer than the source edit. Bitstream:
`EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit`.

Note for whoever programs this: `SRC_SEL` is a compile-time constant, not
a runtime mode switch -- the ramp free-runs continuously on every
`processed_mode_active` mode (any IR-single mode, mode `0x14`, or mode
`0x15`; see `eo_stack_mode_active`/`ir_single_mode_active`/
`ir_stack_mode_active` in `KintexTop_EO_IR_HD_SDI_panorama_base.v`) since
`PATTERN_TEST=1'b1` makes the copy trigger depend only on `frame_edge`,
not on which mode is selected. Expect the same 640x512 centered
diagonal-ramp window as the original Stage-A bring-up test. **Remember
to flip `SRC_SEL` back to `SRC_EOSTK` and rebuild once this bisection
test's result is in** -- this build intentionally does not show the EO
panorama.

**Result: the ramp ALSO shows the same dense regular vertical striping**
(reported by the user as noisy, non-smooth vertical bands rather than a
clean diagonal gradient). This conclusively confirms §12.3/§12.4's
prediction: the bug is in the shared DDR write/scan/unpack/render back
end, fully independent of the EO compositor, tile buffers, and copy CDC
FIFO (none of which this build even instantiates).

---

## 13. ROOT CAUSE FOUND via hardware ILA: DDR4 MIG read-data corruption, not an RTL bug (2026-07-07)

Static analysis (timing, addressing arithmetic, pack/unpack indexing,
write-launch handshake FSM) could not find a bug after extensive review,
and the ramp bisection had already proven the fault is in the shared
back end. Rather than keep guessing, an ILA (`xilinx.com:ip:ila:6.2`,
instance `u_dbg_ila_0`, 19 probes, 16384-deep, `c0_ddr4_ui_clk`) was
added directly in `PanoramaBase_DdrBlackFrame.v` (see the instantiation
right before `u_hd_renderer`) probing both sides of the write/read
datapath end to end: `copy_px_valid/data` → `fb_pack_count` →
`wdf_data_q` (first+last pixel of each 512-bit beat) → `wr_addr` → MIG
handshake (`cmd_pend`/`cmd_is_rd`/`app_rdy`/`wdf_pend`/`app_wdf_rdy`) →
`rd_addr` → `c0_ddr4_app_rd_data_valid`/`c0_ddr4_app_rd_data` (first+last
pixel) → `beat_fifo` → `unpack_count`/`pix_fifo_wr_data`. Two independent
hardware captures were taken (`scripts/codex_ila_capture.tcl`, full
program+arm+trigger+upload+CSV-export automated via `open_hw_manager`/
`run_hw_ila`/`write_hw_ila_data` -- no GUI needed) and parsed
programmatically (queue-correlating each `read_retiring`-issued address
with the `c0_ddr4_app_rd_data_valid` event that later returns it, since
reads pipeline up to `MAX_OUTSTANDING`=16 deep and arrive well after
their issuing cycle).

**Finding, in order of certainty:**

1. **The write side is 100% correct.** Every one of 123 captured write
   beats had `wdf_data_q`'s first and last packed pixels exactly match
   the value the ramp source should have produced for that `wr_addr`.
   This rules out `fb_pack_buf`/the copy-side pack logic entirely.
2. **`beat_fifo` is a perfectly faithful pass-through.** All 244 captured
   pop events exactly matched their corresponding push event's data (0
   mismatches). This rules out `beat_fifo`/`unpack_shift`/the unpack
   logic entirely -- whatever comes out is exactly what went in.
3. **The corruption is already present on `c0_ddr4_app_rd_data`
   straight from the `ddr4_sub64` MIG instance**, before any of this
   design's own logic touches it. Across two independent captures (each
   following a fresh reprogram + fresh DDR4 calibration), **93-100% of
   ALL read beats** have their low 16 bits (`c0_ddr4_app_rd_data[15:0]`,
   the first pixel of the unpacked beat) wrong, while the high 16 bits
   checked (`c0_ddr4_app_rd_data[511:496]`, the last pixel) were correct
   in every single sample of both captures (0 failures). This is not a
   marginal/occasional glitch -- it is the dominant, repeatable behavior
   of essentially every read.
4. The wrong low-16-bit values are **not** explained by any fixed
   beat-offset/shift against neighboring reads (tested offsets -8..+8,
   best match only ~34%) -- ruling out a clean addressing/pointer/FIFO-
   skew bug. They are also **not always even a well-formed ramp pixel**
   (valid ramp pixels always end in byte `0x80`; several captured wrong
   values did not, e.g. `0x8000`, `0x8020`, `0x8060`). A mix of
   "looks like a valid pixel from a nearby-but-wrong position" and
   "doesn't look like valid ramp data at all" is the signature of a
   **read-capture timing/signal-integrity margin issue specific to
   whichever DQ bits/timing-window the first sub-beat of each BL8 burst
   depends on**, not a logic/RTL bug -- a clean logic bug would only ever
   produce well-formed-but-wrong values, never partially-garbled ones.
5. This precisely explains the visual symptom reported by the user: one
   wrong pixel in every 32-pixel DDR beat, on almost every beat, produces
   a static, regular, ~32-pixel-period vertical stripe pattern -- and
   because the corruption happens **before** the EO-vs-ramp fork (it's on
   the raw MIG output, shared unconditionally by both `SRC_SEL` builds),
   it is identical in both the EO panorama and the ramp test, exactly as
   observed.

**This is very likely a DDR4 PHY / read-calibration margin issue, not
fixable by further RTL changes to this design.** The write path, the
command/data handshake FSM, `beat_fifo`, and the unpack logic are all
now cleared by direct hardware evidence, not just static reasoning.

**Recommended next steps (needs user input on direction / hardware
access, hence not yet started):**
1. Inspect DDR4 calibration margins. The MIG instance already exposes a
   `dbg_bus`/`dbg_clk` debug port (`ip/ddr4_sub64/ddr4_sub64.xci`,
   currently unconnected) intended for exactly this: wiring it to a
   Vivado debug hub exposes per-bit read/write eye-margin data through
   Hardware Manager's Memory IP view. If margins are thin specifically
   around the DQ bits landing in `app_rd_data[15:0]`, that confirms a
   calibration/SI margin issue directly.
2. Check repeatability against power cycles / temperature -- a pure SI
   margin issue may shift or clear at different temperatures or after a
   cold power-cycle (vs. the JTAG-reprogram-only recalibration tested
   here); a hard/fixed board-layout issue on those specific DQ lines
   would not.
3. Consider whether the MIG IP's calibration settings (e.g., additional
   read leveling/calibration stages, `C0.DDR4_CalXXX`-family options in
   `ddr4_sub64.xci`) have adjustable margin/retry parameters worth
   revisiting.
4. As a pragmatic mitigation (treats the symptom, not the cause, but may
   be acceptable if the underlying PHY issue proves hard to fully
   resolve): since the corrupted position is deterministic (pixel 0 of
   every 32-pixel beat), that one pixel per beat could be masked/
   interpolated from its neighbors downstream in the unpack logic.
5. This is a strong candidate for a targeted Xilinx Answer Record search
   ("UltraScale+ DDR4 MIG native interface first beat/word of read burst
   incorrect") -- web search was unavailable in this session to check.

---

## 14. Calibration margin investigation via `get_hw_migs` XSDB interface (2026-07-07)

Following §13, the user asked to investigate calibration margins directly
rather than jump to a workaround. Classic UltraScale/UltraScale+ MIG (as
used here -- NOT the Versal "DDRMC" hard controller, so `get_hw_ddrmcs`
correctly returns empty) exposes a live XSDB debug interface via
`get_hw_migs`, confirmed reachable from this machine the same way the
ILA was (`scripts/codex_ddr_margins.tcl`/`codex_ddr_margins2.tcl`/
`codex_ddr_eyescan.tcl`). Two useful, concrete facts came out of this,
plus one hard wall:

**1. All 27 calibration stages report PASS (rest SKIP, none FAIL), and
`CAL_ERROR_MSG` = "No errors detected during calibration."** (queried via
`CAL_STATUS.RANK0.NN_STAGE_NAME` properties -- note the property naming
convention is dot-hierarchical, e.g. `CAL_STATUS.RANK0.04_READ_PER_BIT_DESKEW`,
not the underscore form `CAL_STATUS_RANK0_4` that seemed plausible from a
first glance at a truncated property-name dump). This means calibration
completes cleanly by its own internal pass/fail criteria -- it is not
reporting an outright failure, only (per §13) producing data that's wrong
on the read side almost every beat despite "passing."

**2. One structural anomaly on exactly the suspect byte.** `BISC_ALIGN_PQTR_NIBBLE<0-15>`
(built-in self-calibration alignment tap per DQ nibble; 16 nibbles = 8
bytes x 2) are 2-12 (hex) for 15 of the 16 nibbles -- **except
`BISC_ALIGN_PQTR_NIBBLE1`, which is exactly `000`, the only zero among
all 16.** Nibble1 belongs to byte0, i.e. `c0_ddr4_app_rd_data[7:0]` --
exactly half of the `[15:0]` field the ILA in §13 found corrupted on
93-100% of reads. This is circumstantial (a single non-margin alignment
tap reading zero isn't proof of a bad read-data margin by itself, and
zero is a mathematically valid tap value in general), but it is a
concrete, hardware-measured anomaly landing precisely on the already-
suspect byte, not a coincidence to dismiss lightly. `BISC_NQTR`/`PQTR`/
`ALIGN_NQTR` values for byte0's two nibbles otherwise look unremarkable
(in-family with neighboring bytes).

**3. The actual per-bit read/write eye-margin numbers (`CAL_EYE_LEFT_EDGE`/
`RIGHT_EDGE`/`SIZE`) do NOT exist as static properties** -- `2D_EYE_SCAN_START`/
`2D_EYE_SCAN_END` exist but are **read-only** (confirmed:
`set_property 2D_EYE_SCAN_START ...` errors with "property is read-only"),
both currently `000`. Getting the live, per-bit 2D eye-scan margin grid
-- the actual quantitative answer to "does byte0 have a smaller read eye
than the other 7 bytes" -- appears to require Hardware Manager's
interactive "Memory IP" / MIG dashboard GUI (confirmed via web search:
this is documented as a GUI-driven feature, "select the MIG tab on the
HW Manager" to see calibration stages, margins, and center point; PG150
ch. 17 covers the underlying data but not a scriptable trigger). No
scriptable Tcl trigger for a fresh 2D eye scan was found in this
session -- this is the concrete wall between what's been fully automated
here and what still needs either GUI interaction or further protocol
research to go further.

**Net assessment (superseded by §15 below -- kept for the record)**: the
write-clean/read-corrupted split from §13 plus this session's
calibration data (clean PASS status, but one concrete per-nibble anomaly
on exactly the corrupted byte) together make a DDR4 PHY/calibration
margin issue the leading explanation, with real (if not airtight)
hardware evidence now behind it, not just inference. Getting a fully
quantitative confirmation (an actual eye-width number for byte0 vs. the
rest) needs the interactive GUI dashboard -- reproducible by opening
Vivado Hardware Manager, programming this bitstream + its `.ltx`, and
selecting the MIG core's debug tab.

---

## 15. Margin dashboard result: byte0 is NOT the outlier -- theory revised (2026-07-07)

The user opened Hardware Manager's Memory IP "Calibration and Margins"
table (Read Mode, Simple Pattern, Rising Clock Edge) and shared the full
per-nibble left/center/right margin numbers for all 8 bytes x 2 nibbles
(Rank 0). Total eye width (left+right margin, ps) per nibble:

| Byte.Nibble | Eye (ps) | | Byte.Nibble | Eye (ps) |
|---|---|---|---|---|
| Byte3.N1 | **438** (min) | | Byte2.N0 | 464 |
| Byte2.N1 | 441 | | Byte4.N0 | 466 |
| Byte1.N1 | 458 | | Byte0.N0 | 472 |
| Byte3.N0 | 460 | | Byte6.N0 | 476 |
| Byte7.N1 | 460 | | Byte5.N1 | 478 |
| Byte0.N1 | 462 | | Byte1.N0 | 480 |
| Byte5.N0 | 462 | | Byte7.N0 | 480 |
| Byte6.N1 | 463 | | Byte4.N1 | **496** (max) |

Byte0's average (467 ps) is essentially identical to the whole-bus
average (466 ps) -- **byte0 is not the outlier the §14 BISC-tap anomaly
suggested it might be.** Spread across all 16 nibbles is only ~12%
(438-496 ps), which reads as healthy, unremarkable calibration -- if
anything, Byte2/Byte3 have the *smallest* eyes, not Byte0. This
concretely refutes the leading §13/§14 theory ("byte0 has a marginal
read-capture window that explains why `app_rd_data[15:0]` is wrong").

**Revised theory**: since every byte lane calibrates fine in isolation
under the MIG's own test pattern, the corruption is more likely tied to
a **specific time-slot/beat-position within the BL8 burst's 512-bit
assembly** (a digital/logical assembly effect), which would corrupt
whichever byte happens to occupy that position -- not something wired to
byte0's physical/analog margin specifically. This also raises a live
alternative: the calibration-time margin scan runs an isolated test
pattern, which may not represent margin under this design's actual
traffic (continuous, aggressive back-to-back read/write command
issuance via the held-launch arbiter) -- so a genuine SI margin issue
still can't be fully excluded, just no longer pinned to byte0
specifically by the available evidence.

**§13's original ILA only sampled two of the eight 64-bit "chunks" of
the 512-bit word** (bits `[15:0]` and `[511:496]`), so it cannot
distinguish "byte0 is always wrong regardless of time-slot" from "one
specific time-slot is wrong regardless of byte." The decisive next
capture (in progress) widens probing to check whether a *different*
byte at the *same* burst chunk position is also wrong -- if so, that
confirms a time-slot-specific effect over a byte-specific one.

---

## 16. DECISIVE: the entire first 64-bit chunk of every read burst is wrong, not just byte0 (2026-07-07)

Widened the ILA to give `wdf_data_q`, `c0_ddr4_app_rd_data`, and
`beat_fifo_dout` their own dedicated, single-contiguous-range probes for
the first and last 64-bit chunks (`[63:0]` and `[511:448]`) instead of
concatenating two disjoint 16-bit corners into one port -- the first
attempt at widening did that concatenation and Vivado's debug-probe
auto-naming silently only produced a usable name for a 32-bit fragment
of it (confirmed via `report_property` on the `hw_probe` object: `MAP =
"probe5[31:0]"`), so the fix was giving each contiguous range its own
probe port (`probe19`-`probe24`) rather than trying to concatenate two
far-apart ranges into one. Also hit and fixed a stale-IP-run gotcha:
after bumping `C_NUM_OF_PROBES`, `EO_IR_HD_SDI_panorama_base.runs/dbg_ila_0_synth_1`
(an auto-created IP-level synth run) still held the old netlist/stub
until explicitly `reset_run`, causing "named port connection does not
exist" errors on the new probes despite the `.xci`/`.veo` already being
correct -- same family of stale-checkpoint trap as the synth/impl
checkpoint-freshness rule already in this document, just at the IP
level instead of the top-level run.

With real 64-bit-wide data (routed WNS +0.164ns, 0 DRC errors), checking
all 4 sampled pixels in each of the first and last chunks against their
expected ramp value (queue-correlated the same way as before) gives an
extremely clean, total result across 312 correlated read beats:

| Pixel position in beat | Wrong |
|---|---|
| 0 | 312/312 (100%) |
| 1 | 312/312 (100%) |
| 2 | 312/312 (100%) |
| 3 | 311/312 (99.7%) |
| 28 | 0/312 (0%) |
| 29 | 0/312 (0%) |
| 30 | 0/312 (0%) |
| 31 | 0/312 (0%) |

**This settles the byte-vs-time-slot question definitively: it is not
"byte0" -- it is the entire first 64-bit transfer of the BL8 burst
(pixels 0-3, i.e. all 8 physical byte lanes at that one time-slot),
corrupted on essentially every single read, while the last 64-bit
transfer (pixels 28-31, also all 8 byte lanes) is correct on every
single read.** This is exactly consistent with -- and considerably
stronger evidence for -- the read DQS-gate/preamble-timing theory from
§13.3: the first beat of a read burst is uniquely exposed to the
transition from "no DQS activity" to "DQS toggling and must be
correctly gated," while later beats in the same burst benefit from DQS
already toggling steadily. It also fully explains why §15's margin
dashboard showed nothing unusual for byte0 specifically -- that
dashboard's "Simple Pattern" margin scan measures steady-state bit
sampling accuracy generic to a byte lane, not first-beat/DQS-gate timing
specifically, and per §14 `CAL_STATUS.RANK0.01_DQS_GATE`/
`02_DQS_GATE_SANITY_CHECK` both report PASS -- a pass/fail calibration
gate that isn't necessarily tight enough to guarantee zero failures
under this design's actual continuous, deeply-pipelined (up to 16
outstanding) read traffic, as opposed to whatever isolated pattern
calibration itself uses.

One RTL-level alternative was checked before settling on the timing-gate
explanation: whether this design issues read commands aggressively
enough to cause a MIG-internal pipeline hazard specifically at burst
boundaries. The capture shows a dominant ~2-cycle spacing between
consecutive read command issues (287/312 gaps) and outstanding counts
ranging 1-16 (9 most common) at the moment data returns -- i.e. deep,
sustained pipelining is genuinely happening, all accepted by the MIG's
own `app_rdy` handshake (which is the documented, correct backpressure
mechanism -- this design cannot violate it by construction). This
doesn't rule out a MIG-internal hazard specific to deep pipelining, but
there's no RTL-side protocol violation to point to; if the corruption
changes at a *lower* `MAX_OUTSTANDING`, that would implicate pipelining
depth specifically rather than burst-position timing in general -- a
cheap (one-parameter, one-rebuild) experiment worth running before
concluding this needs a hardware/calibration-level fix.
