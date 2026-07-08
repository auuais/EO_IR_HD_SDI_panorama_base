# DDR Frame-Buffer Failure Analysis and EO-Panorama-over-DDR Fix Plan

Date: 2026-07-06 (implementation attempted 2026-07-06/07, see status addendum
at the end of this file before reading the plan below as a to-do list)
Project: `E:\Xylinx\EO_IR_HD_SDI_panorama_base\EO_IR_HD_SDI_panorama_base.xpr`
Reference (proven, no-DDR) project: `E:\Xylinx\EO_IR_HDSDI_BRAM-URAM_FRAMESIZE`

> **2026-07-07: for the CURRENT open bug (vertical read-corruption striping),
> read `docs/DDR_READ_CORRUPTION_HANDOFF.md` instead of this file.** That is a
> short, self-contained handoff with everything proven so far and the exact
> next experiment to run. This document (sections 12-17 in particular) is the
> full evidentiary history behind that handoff, useful for verification but
> not required reading to continue the investigation. Sections 1-11 below
> cover the EARLIER, already-fully-resolved DDR bring-up + timing/CDC work.

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

---

## 17. MAX_OUTSTANDING experiment: CONCLUSIVELY rules out pipelining depth (2026-07-07)

Ran the experiment proposed at the end of §16: `MAX_OUTSTANDING` dropped
from 16 to 4 (one-line change), rebuilt (routed WNS +0.149ns, 0 DRC
errors), programmed, and recaptured with the same 25-probe ILA. Confirmed
the parameter change genuinely took effect at the hardware level (max
observed `outstanding` at any `rd_data_valid` event was exactly 4 in the
new capture vs. 16 in the original, ruling out a no-op/optimized-away
change).

**First pass (aggregate per-pixel-position rate) looked ambiguous**:
pixel-in-beat 0-3 wrong rates dropped from 100%/100%/100%/99.7% (depth
<=16) to 90.0%/73.3%/84.2%/91.0% (depth<=4) -- a real but partial-looking
reduction that could have been read as weak support for a pipelining
contribution, or just capture-to-capture noise (different calibration
run, different exact phase).

**The decisive test was stratifying corruption rate by each read's own
`outstanding` depth at the moment it returned data, within each single
capture** (this avoids any cross-capture confound entirely -- both
captures span a range of depths from 1 up to their cap, all under
identical hardware/calibration conditions in one continuous run).
Result, "any of pixels 0-3 wrong" per depth bucket:

| depth | capture4 (cap=16) | capture5 (cap=4) |
|---|---|---|
| 1 | 19/19 (100%) | 43/43 (100%) |
| 2 | 19/19 (100%) | 67/67 (100%) |
| 3 | 19/19 (100%) | 125/125 (100%) |
| 4 | 19/19 (100%) | 76/76 (100%) |
| 5-16 | 100% at every depth checked (2 to 93 samples each) | -- |

**100% corruption at every single outstanding depth from 1 to 16,
including depth=1 (a single isolated read in flight, zero pipelining
overlap whatsoever).** This is fully conclusive: pipelining/outstanding
depth is not a factor at all, in either direction. The earlier "partial
reduction" in the aggregate per-position numbers was capture-to-capture
noise in *which* of the 4 positions happens to come out individually
correct on a given beat, not a real effect of `MAX_OUTSTANDING` -- the
beat-level corruption rate (at least one of the first 4 pixels wrong) is
uniformly 100% regardless.

**Conclusion: this is not fixable by any read-pipelining/outstanding-
count adjustment in this RTL.** `MAX_OUTSTANDING` reverted to 16 (no
benefit at 4, and 16 is better for sustained read throughput). The
first-beat DQS-gate/preamble-timing explanation from §16 is now the
leading theory with no remaining RTL-side alternative to check -- every
angle reachable from this codebase's own logic (write path, handshake
FSM, beat_fifo, unpack, addressing arithmetic, pipelining depth) has been
directly hardware-verified as either correct or not the cause. Remaining
avenues are hardware/calibration-level: Xilinx AR database lookup for
this exact symptom (proper web/support access, not available in this
session), MIG calibration parameter retuning, testing repeatability
across a real power cycle/temperature, or a pragmatic RTL-side mitigation
(mask/interpolate the deterministically-known-bad first 4 pixels of
every 32-pixel beat) if root-causing further is not worth pursuing.

---

## 18. User-reported geometry anomaly: targeted logic review (2026-07-07)

The user compared the first EO-build hardware photo against the current
ramp-build photo and raised a specific concern: the EO build did not
appear to show a 3x2 grid of six distinct 640x480 tiles -- it looked
like two cameras' content (their read: cam3/cam4) repeated across the
full 1920x1080, and the ramp build's window content appears scattered/
displaced. Their hypothesis: **a logic/geometry error exists in addition
to the data corruption.** This section records a targeted line-by-line
review of every mechanism that could produce wrong geometry, what was
found clean, what NEW defects were found, and what remains genuinely
unexplained.

### 18.1 Verified CLEAN (line-by-line, this session)

1. **Top-level EO wiring**: six distinct receiver instances
   (`u_eo0`..`u_eo5`, `KintexTop_EO_IR_HD_SDI_panorama_base.v` lines
   169-213) on six distinct camera pin sets (CAM0..CAM5), wired 1:1 into
   `PanoramaBase_DdrBlackFrame`'s `eo0_*`..`eo5_*` ports (lines 273-296).
   No duplication, no crossed wires.
2. **Tile decimation geometry**: `EO1920x1080_Decimate3_FrameBuffer`
   produces exactly 640x480 despite the misleading "Decimate3" name:
   horizontal = 1440-px crop starting at camera x=240, keeping 4
   chroma-PAIRS per 18 px (8 of 18 pixels -> 1440*8/18 = 640, pairs kept
   whole to preserve Cb/Cr cadence); vertical = 4 lines of every 9
   (1080*4/9 = 480). Write addressing is strictly sequential 0..307199
   with a frame-start reset; `frame_valid` rises only after the final
   address is written.
3. **Compositor walk order**: emits the true raster of the 1920x960
   composite (for each output row: tile-left 640 px, tile-mid 640 px,
   tile-right 640 px), row_group 0 = tiles 0/1/2, row_group 1 = tiles
   3/4/5. Tile-select read-enables, the EO_READ_LATENCY=2 alignment
   pipes (`eo_cam_pipe`/`eo_use_pipe`), and the output mux are all
   consistent; stall behavior under `copyfifo_prog_full` preserves
   tag/data alignment (XPM sdpram output holds when `enb`=0).
4. **Renderer window math**: 1:1 source-to-display mapping,
   EO window 1920x960 at (0,0) with rows 960-1079 forced black, ramp
   window 640x512 centered. Window position comes solely from free-
   running `h_cnt`/`v_cnt` -- pixel DATA cannot move the window.
5. **Pixel-count conservation**: walk emits exactly FRAME_PIXELS per
   copy; pack consumes exactly that; scan issues exactly BEATS_TOTAL
   beats; unpack pushes exactly 32 px/beat; renderer pops at most one
   per in-window cycle, and the vblank drain plus prefill logic resets
   FIFO occupancy between frames.

**Conclusion: no mechanism exists in the composite/copy/render RTL that
can duplicate one camera across multiple tile positions or resize/move
the grid.** If the live display genuinely shows duplicated cameras (see
18.4 for the decisive check), the cause is upstream of these blocks
(receivers) or is a perception artifact of the scrambling described
next.

### 18.2 FOUND: underrun slip-amplification explains "geometry scrambling" without a geometry bug

The renderer's in-window underrun policy is: if `pix_empty` on an
in-window cycle, paint a diagnostic color and do NOT pop. The un-popped
pixel is then consumed on a LATER in-window cycle -- so a single
transient FIFO-empty event shifts ALL remaining frame content right/down
by one position, and N stall cycles shift it by N. Nothing re-anchors
the stream until the next frame's vblank drain + prefill. **Any
transient starvation therefore geometrically scrambles the remainder of
that frame** -- displaced blocks, full-width bands of diagnostic color
(post-startup the sticky bits reduce the palette to: green = scan
active but FIFO empty, red = starved with scan done, orange = prefill
not reached), and content appearing to repeat (adjacent stream segments
re-shown at different offsets across starvation/recovery cycles). The
donor project has no such elasticity (fixed BRAM line addressing, no
stream FIFO), which is why this failure LOOK is new to the DDR path.
This mechanism can plausibly produce the user's "two cameras repeated
full-screen" reading from a composite that is actually correct in DDR:
massive accumulated slip pushes lower-half content (cams 3/4/5) up into
most of the visible window, repeatedly.

Note this mechanism is an AMPLIFIER, not a root cause: something must
first cause mid-frame starvation (or data loss) at a rate the 8192-deep
pix_fifo can't absorb. With ~5x average bandwidth headroom, sustained
starvation should not happen -- unless the §16 read corruption is
accompanied by occasional dropped/extra `rd_data_valid` events, or the
flush path (frame_edge with residue -> discard beats -> one full
diagnostic frame -> repeat) is cycling. The §18.4 experiments observe
this directly.

### 18.3 THEORY, THEN RETRACTED: eo0 tile write path clock-tree hazard

**Original theory (below), and why it was wrong, both kept for the
record -- see §18.6 for the correction and what it actually tells us.**

`PanoramaBase_DdrBlackFrame.rd_clk` = top-level `CAM0_PCLK_bufg` =
BUFG(CAM0_PCLK_ibuf) (`KintexTop...v` lines 108-111, 246). But
`eo0_wr_clk` = `eo0_pclk` = the cam0 receiver's `IEG0_PCLK` output,
which inside `Kintex_top_0cam_1ch` (`KintexTop_0cam_ch1_0108.v` lines
44-60, 162) is a **plain wire alias of the un-BUFG'd IBUF net** (`wire
CAM0_PCLK_bufg = CAM0_PCLK;` -- the BUFG is commented out; the Korean
comment says "currently IBUF only"). So the §10 `u_eo_fb0`
"same clock" exception (`USE_ASYNC_FIFO(0)`/`common_clock`) actually
crosses from IBUF-net-clocked write logic into BUFG-tree-clocked memory
-- same frequency, two different distribution trees, arbitrary fixed
skew. STA does time it (same primary clock through both), but the
design-wide worst hold slack is **WHS +0.011ns** -- looked like the
razor-thin-hold signature this structure produces. Proposed fix at the
time: switch `u_eo_fb0` to `USE_ASYNC_FIFO(1)`/`independent_clock` like
the other five tiles.

**This was implemented and immediately disproven by hardware, not just
re-reasoned about.** Rebuilding with the "fix" applied failed
implementation with `ERROR: [DRC AVAL-245] Independent_clock_check`,
Vivado stating outright about this exact RAM's clock pins: **"the two
clock pins... are driven by the same driver."** I.e. Vivado's actual
synthesized/placed netlist merges `eo0_wr_clk` and `rd_clk` onto the
same clock net -- almost certainly clock-network optimization
recognizing them as electrically equivalent once fully traced, contrary
to the RTL-source-level reading above (which only looked at whether an
explicit `BUFG` primitive appeared in each path, not at how synthesis
ultimately resolves clock identity). **The original `USE_ASYNC_FIFO(0)`/
`common_clock` exception was correct; it has been reverted back.** See
§18.6 for what this DOES still tell us, and the general lesson: trust a
DRC/implementation result over eye-level net-tracing for clock-identity
questions specifically -- Vivado's clock network optimizer can and does
merge nets that read as distinct in the RTL source.

### 18.4 Decisive experiments (updated priority order)

1. **Renderer-side rd_clk ILA** (NEW, now top priority -- directly
   answers the user's geometry question): a second ILA clocked on
   `rd_clk` probing `h_cnt`, `v_cnt`, `pix_empty`, `pix_rd_en`,
   `stream_started`, `flush_active` (sync'd), `frame_valid_sync`, and
   `hd_dout_r[19:10]`. One capture spanning a few lines answers: does
   the renderer emit content at the correct window positions (kills or
   confirms any remaining geometry doubt at the point of emission), and
   how often/where does `pix_empty` fire in-window (quantifies the slip
   of §18.2)? If the emitted geometry is correct at hd_dout while the
   monitor shows displaced content, the problem is downstream of this
   module (SDI wrapper/monitor/capture chain).
2. **Write-idle corruption capture** (unchanged from handoff §4.1):
   trigger on reads with `copy_active`==0 to test the bank-conflict
   theory. Both existing captures only ever sampled reads concurrent
   with writes.
3. **Live-monitor checks (user, no rebuild)**: (a) in EO mode, are the
   bottom 120 rows solid black? The RTL guarantees them black; if the
   live monitor (not a cropped photo) shows content there, the running
   bitstream is not the expected build or something is very wrong
   downstream. (b) step through EO-single modes 0x07-0x0C and confirm
   all six cameras show distinct live scenes (verifies receivers).
4. ~~eo0 clock fix~~ -- **retracted, do NOT do this** (§18.3/§18.6): tried,
   hardware DRC proved the theory wrong, reverted.

### 18.5 New data fingerprint from the corrupted values (for whoever chases the PHY theory)

Decoding the wrong first-chunk values against expected (both captures):
only 5-6% are byte-swapped forms; 19-28% preserve their intra-beat
pixel index (above the 3% chance rate but a minority). The informative
part: the misplaced ramp bytes' offsets from expected cluster at
**whole-beat multiples** (capture 5: +32 dominant, then 64/96/128/160)
or at **-1 mod 32** (capture 4: 191/95/223/127/63 all = 32k+31). I.e.
the first transfer's returned bytes are predominantly STALE DATA FROM
NEARBY BEATS at beat-aligned offsets -- not a coherent shift of the
stream, and not noise. This is consistent with the first DRAM beat
being captured from stale bus/FIFO state (DQS-gate opening one beat
early against residual data), and is a concrete fingerprint to match
against Xilinx Answer Records.

### 18.6 What the eo0 clock DRC actually tells us, and the corrected next step

Two useful things survive the §18.3 retraction:

1. **`eo0_wr_clk` and `rd_clk` are confirmed the same clock, hardware-
   verified, not just assumed.** This means the WHS +0.011ns razor-thin
   hold slack is NOT explained by a cross-clock-tree skew on this path
   (there is no crossing here at all -- same net, zero skew by
   definition). Whatever produces that thin hold margin is something
   else in the design; it does not need (and must not get) a CDC fix on
   tile 0's write path specifically. Do not re-attempt this "fix".
2. **General lesson for this codebase**: Vivado's clock network
   optimizer can merge nets that read as electrically distinct at the
   RTL source level (explicit `BUFG` vs. none) if it determines they are
   equivalent. When a clock-identity question matters for correctness
   (CDC FIFO needed or not), a `DRC AVAL-245`/`Independent_clock_check`
   result from a real implementation run is authoritative; net-tracing
   by eye through module hierarchy is not sufficient on its own.

Net effect on the geometry investigation: §18.3 does not explain the
user's reported cam3/cam4 duplication (nor did it ever -- it only ever
affected tile 0, and the "fix" attempt is now known to have been based
on a false premise). The corrected priority order is exactly §18.4
items 1-3 (renderer-side ILA, the two zero-rebuild live-monitor checks,
and the write-idle DDR-side capture) -- there is no tile-0-specific
clock fix to apply first anymore.

### 18.7 dbg_ila_1 (renderer-side ILA) added and captures run

Implemented §18.4 item 1: a second ILA core (`dbg_ila_1`,
`xilinx.com:ip:ila:6.2`, 11 probes) clocked on `rd_clk`, instantiated
inside `PanoramaBase_HdDdrRenderer` (only place these signals are
directly visible) as `u_dbg_ila_1`, probing `pix_empty`, `pix_rd_en`,
`stream_started`, `frame_valid_sync`, `cur_active`, `cur_inside_window`,
`h_cnt`, `v_cnt`, `hd_dout_r`, `dbg_sync`, and a dedicated trigger wire
`dbg_starve_event = cur_inside_window && pix_empty && stream_started`
(triggering on the compound condition directly in RTL rather than
relying on multi-probe AND semantics in the ILA's basic trigger mode,
to avoid any ambiguity).

Combining both ILA cores with the full 6-tile EO build over-budgeted
BRAM (`DRC UTLZ-1`: needs 1040 RAMB36E2, device has 984) -- `dbg_ila_0`
(25 probes, ~200 bits/sample) is the dominant consumer; its capture
depth was cut 16384->2048 (still ample for the write-idle correlation
test) and `dbg_ila_1`'s cut 16384->8192 (kept deeper since it's
triggered on a possibly-rare event and needs post-trigger context),
bringing synth-estimated RAMB36E2 to 727/984 with comfortable margin.
Standard gotcha repeated: after the depth change, `dbg_ila_0_synth_1`
and `dbg_ila_1_synth_1` (auto-created IP-level synth runs) needed an
explicit `reset_run` before the next top-level synth picked up the new
config -- same class of stale-IP-netlist trap as documented in §16.

### 18.8 Compositor tile-select ILA (`dbg_ila_2`): DEFINITIVELY correct on hardware

While the eo0-clock-fix rebuild cycle (§18.3/§18.6) was in progress, the
user shared a live hardware photo of the EO build and a specific reading
of it: top half of the panorama appeared to cycle cam0/cam1/cam0/cam1
(partial) rather than cam0/cam1/cam2, i.e. the third (rightmost) tile in
each row-group never visible; same pattern cam3/cam4/cam3/cam4 on the
bottom half, cam5 never visible. This is a much more specific claim than
"noisy/striped" -- it reads as a genuine tile-select/walk-order defect,
which would be a NEW bug beyond the already-confirmed DDR read
corruption, and one the §18.1 source review (however carefully done)
would not be the last word on given real hardware had already
overturned one source-level theory this same session (§18.3/§18.6).

Added a third ILA (`dbg_ila_2`, 12 probes, depth 16384) directly inside
the `g_src_eostk` generate block (rd_clk domain, same clock as the walk
itself) probing `copy_issue`, `copy_active_rd`, `col_group`, `row_group`,
`col_in_tile`, `row_in_tile`, `copy_walk_done`, `eo_cur_col_group`,
`eo_cur_row_group`, `copyfifo_wr_en`, `copyfifo_din`, and all six
`eo{0..5}_rd_en` signals concatenated into one probe -- i.e. everything
needed to directly watch which physical tile gets selected, cycle by
cycle, with no inference required. Triggered on `copy_issue` (fires on
essentially every cycle of an active copy), giving 16384 samples of
dense walk activity.

**Result: the walk is correct.** `col_group` cycles 2->0->1->2->0->1...
in clean 640-cycle runs (`col_in_tile` sweeping 0..639 exactly once per
`col_group` value before advancing), `row_in_tile` increments by exactly
1 at each full-row wraparound, and each `eo{k}_rd_en` fires precisely
when `copy_issue && row_group==<expected> && col_group==<expected>` --
matched by direct inspection, not inference. This capture happened to
land entirely within `row_group==1` (bottom half, tiles 3/4/5), and
within that half all three of `eo3_rd_en`/`eo4_rd_en`/`eo5_rd_en` were
observed firing at their correct, distinct 640-column windows (5760,
5166, and 5458 assertions respectively out of 16384 samples -- all
three tiles genuinely visited, none skipped). **This directly disproves
a col_group-stuck-cycling or tile-select-mux bug as the explanation for
the user's report** -- the walk order and tile selection are correct on
real hardware, not just in source review.

### 18.9 Renderer starvation check (`dbg_ila_1`): zero events in a substantial sample

With the walk cleared, re-armed `dbg_ila_1` (already present in the same
bitstream) to directly test the §18.2 underrun-slip theory. The original
plan (trigger on the starvation event itself) was abandoned after a long
unproductive wait -- the user asked to kill it and pivot to the
compositor check instead, which turned out to be the right call.
Re-triggered instead on `cur_active==1` (fires almost immediately) to
capture a large window of *ordinary* operation and count starvation
directly in analysis, rather than gambling on a possibly-rare/absent
event to arm the trigger.

**Result: zero starvation.** Across 8192 samples (~4 complete display
lines, h_cnt sweeping the full 0-2199 range multiple times, comfortably
spanning multiple `col_group` transitions within the window): `pix_empty`
was 0 on every single sample, `dbg_starve_event` (the in-window-and-
streaming-and-empty compound condition) never fired once, and `dbg_sync`
(the synced ui_clk-side status word) held a constant, healthy value
throughout (no overflow, `scan_active`/`copy_active` both correctly
asserted, no anomaly bits set). The actual `hd_dout_r` values captured
in-window vary continuously in a way consistent with real image content,
not a frozen or diagnostic-color output.

This is a substantial (not exhaustive) negative result: it covers only
~4 of 1080 display lines, so it does not prove starvation never happens
anywhere in the frame -- but it directly contradicts "constant/frequent"
underrun as an explanation, since the sampled window spans deep into
col_group-cycling territory (exactly where the user's reported symptom
would need to originate) without a single stall.

### 18.10 Net assessment after both hardware checks

Two independent, targeted hardware captures (not source review) have
now each looked for a specific candidate explanation of the user's
reported segment-duplication and found neither present:

- Compositor tile-select walk: **provably correct** (§18.8).
- Renderer in-window starvation: **not observed** in a substantial
  sample (§18.9).

Neither of the two most plausible NEW structural-bug theories survived
direct hardware measurement. The remaining, evidence-consistent
explanation is that the ALREADY-CONFIRMED DDR read corruption (§16:
the entire first 64-bit/4-pixel chunk of every 32-pixel DDR burst wrong,
~100% of bursts, ~12.5% of all pixels, uniform across the whole frame
regardless of source) is simply far more visually disruptive on real,
detailed camera content than it was on the smooth synthetic ramp --
dense, structured corruption at this rate on real imagery, viewed
through a compressed photo of a monitor, could plausibly be misread as
"cameras repeating/missing" even though the underlying composite order
is correct. This is the leading explanation given everything checked so
far, but it has NOT been directly proven (e.g. by showing the artifact
disappears when the known-corrupted pixels are masked) -- treat it as
the current best-supported hypothesis, not a closed question. See
handoff document section 4.2c for the concrete next check.

### 18.11 Cam0-only diagnostic source added (user's idea): removes the compositor from the picture entirely

User proposal: to remove any remaining ambiguity about the compositor/
tile-select mux, stream ONLY cam0's 640x480 decimated tile through DDR
-- no compositor, no 6-way mux, no col_group/row_group cycling -- while
still using real live camera content (unlike SRC_RAMP) and the real
`EO1920x1080_Decimate3_FrameBuffer` decimation/CDC machinery (unlike a
synthetic pattern). Implemented as a third `SRC_SEL` option, `SRC_EO0`
(`localparam [1:0]`, widened from the previous 1-bit RAMP/EOSTK
encoding): a new `g_src_eo0` generate branch, a trimmed copy of
`g_src_eostk`'s machinery (CDC synchronizers, copy CDC FIFO, ui_clk-side
pop -- all reused verbatim) with the 6-way tile-select removed and
replaced by a trivial single-tile walk (`col_in_tile`/`row_in_tile`/
`row_base`, no `col_group`/`row_group` at all). Window: 640x480 centered
(mirrors the ramp window's centering convention). Only `u_eo_fb0` is
instantiated (pinned to URAM as before) -- no `dbg_ila_2` in this build
since none of the compositor signals it probes exist in this branch.
Routed clean: WNS +0.348ns, 0 DRC errors, 75/128 URAM + 11/984 RAMB36E2
(confirms the much smaller footprint expected from dropping 5 of 6 tile
buffers and the whole compositor).

### 18.12 DECISIVE: the same corruption signature appears on real EO camera data, with zero compositor involvement

Captured `dbg_ila_0` (unchanged 25-probe DDR-side ILA, still present and
valid for this build) triggered on `write_retiring`, queue-correlated
the read side as in section 16. Real camera pixel data has no synthetic
formula for "expected value" the way the ramp test did, so exact
per-pixel correctness can't be checked the same way -- but the
first-vs-last-chunk STRUCTURAL signature from section 16 needs no
ground truth to detect, and it is directly, visibly present:

The first three consecutive read beats (`rd_addr` = 0x0000, 0x0008,
0x0010 -- the very start of a scan pass) returned the **exact same**
64-bit first-chunk value, `0x4e7d857e50799a7c`, three times in a row
(a fourth, `0x4475857e50799a7c`, differs by only one byte). Meanwhile
the last-chunk values for those same three beats vary smoothly and
plausibly (`0x6b816c7e6b81717e`, `0x65816c7c7281717d`,
`0x758175807481737d`, ...), exactly as expected for real, continuously-
varying image content. Three independent DDR beats returning bit-
identical 64-bit "pixel" data in their first chunk while the last chunk
correctly varies is statistically impossible for genuine content -- this
is the corruption, directly visible with no formula required, and it
occurs with **zero compositor/tile-select logic anywhere in this
build**.

Beats beyond the first ~4 do not show further *exact* repeats in this
capture (127/129 unique first-chunk values overall) -- but this should
NOT be read as "corruption stops after the first few beats." Unlike the
ramp test's synthetic, sharply-stepped values (where any deviation from
the exact expected value is glaringly obvious), real image content is
naturally smooth and self-similar between nearby pixels -- a "stale
data borrowed from a nearby beat" substitution (the section 16/18.5
fingerprint) can easily fall within the natural variability of
neighboring real pixels and simply not LOOK wrong without ground truth
to compare against. The corruption mechanism is almost certainly still
operating near its previously-established ~100%-of-beats rate; it is
just far less visually/statistically detectable on smooth real content
than on the ramp's sharp synthetic steps -- which is itself a plausible,
even likely, explanation for why the artifact is much more visually
disruptive on real EO camera content (with edges and fine detail) than
it appeared on the smooth ramp test.

**This closes the loop the investigation was missing**: the DDR read
corruption is now directly confirmed on real EO camera data, not merely
inferred from the ramp test and assumed to generalize. Combined with
section 18.8 (compositor walk proven correct) and 18.9 (no renderer
starvation observed), the leading hypothesis from section 18.10 is now
substantially strengthened by direct evidence rather than being merely
"not contradicted": **the already-confirmed, not-yet-root-caused DDR4
read-burst corruption is very likely sufficient by itself to explain the
user's reported geometry symptom on the full 6-camera stack**, and no
separate EO-specific structural bug has been found anywhere despite
three independent, targeted hardware investigations (compositor ILA,
renderer ILA, cam0-only DDR ILA). The path forward is squarely
handoff section 4.1 (the write-idle bank-conflict question) and the
underlying DQS-gate-timing root cause -- not further EO-side structural
hunting, which has now been thoroughly exhausted without a finding.

### 18.13 Visual confirmation from live hardware: cam0-only shows striping, no duplication

User shared a live monitor photo of the `SRC_EO0` (cam0-only) build in
operation. The image shows a single, fully coherent, recognizable real
scene (a canal/dock view -- water, boats, buildings) with dense, regular
vertical striping overlaid throughout -- visually the same character of
artifact as the original ramp-test and 6-camera-stack striping, now
unambiguously on real single-camera content. **No segment duplication
or missing regions are visible** -- consistent with (and additional,
independent confirmation of) section 18.12's ILA-based finding, since
with the compositor physically absent from this build there is no
mechanism that could produce segment-level duplication in the first
place. This is exactly the pattern predicted if the striping corruption
alone (section 16) is sufficient to explain the full-stack symptom:
isolated to one camera with no compositor in the picture, the artifact
is visibly just striping on an otherwise-intact single scene, not a
scrambled/duplicated composite. Strengthens section 18.12's conclusion
without yet being a full proof (that would require the masking
experiment from handoff section 4.0a) -- but no further EO-side
structural hunting is warranted given this and three independent
hardware ILA investigations all point the same direction.

### 18.14 User clarification: `SRC_EO0` is decimated, not "zero manipulation" -- native-resolution attempt hits a hard capacity wall (2026-07-07/08)

User viewed a hardware photo of the `SRC_EO0` build and made two
observations: (1) the striping in that capture reads as clean
*duplication*, not generic "corruption" -- consistent with, and a more
precise restatement of, the first-64-bit-chunk-of-every-burst repeat
found in section 16; (2) more importantly, `SRC_EO0` was centered
640x480, not the camera's true 1920x1080 -- because it still routed
every pixel through `EO1920x1080_Decimate3_FrameBuffer`'s crop/
subsample logic (the same decimation every tile in the real 6-camera
build uses), it was never actually an unmanipulated, native-resolution
test. The diagnostic intent (prove the DDR corruption independent of
the compositor) was still fully served -- decimation isn't the
compositor -- but it left a fair question open: does the corruption
look any different at native resolution, with literally zero frame
processing?

A fourth `SRC_SEL` option, `SRC_EO0RAW`, was added to answer that: cam0
captured at its true 1920x1080, zero crop/subsample, still no
compositor. First implementation mirrored `SRC_EO0`'s structure exactly
but swapped in a new `EO1920x1080_RawFrameBuffer` module (a copy of
`EO1920x1080_Decimate3_FrameBuffer` with all crop/phase/subsample logic
deleted) -- i.e. an entire native-resolution frame buffered **on-chip**
before ever reaching DDR, addressed by a walk state machine exactly
like the decimated tile buffers use.

This hit a hard FPGA resource wall. `MEMORY_PRIMITIVE_STR("ultra")`
requested 507 URAM288 instances against 128 available
(`WARNING: [Synth 8-5835] ... Will try to implement using BRAM`);
the automatic URAM->BRAM fallback synthesized at 963/984 RAMB36E2
(97.87%, already razor-thin), and implementation then failed outright:

```
DRC UTLZ-1: This design requires 1034 of such cell types but only
984 compatible sites are available.
```

Root cause of *why* it's this expensive: for a narrow (16-bit) word,
URAM's native 72-bit width is only ~22% utilized, while BRAM (36Kb,
18-bit-wide native ports) is ~99.5% efficient for this shape -- so BRAM
wins per-bit even though it's the "smaller" primitive family. But even
with the efficient primitive, one unbuffered 1920x1080x16-bit frame is
~31.64Mb, i.e. ~90%+ of the KU15P's *entire* on-chip memory budget
(984 RAMB36E2 = 35,424Kb total) by itself -- before the two debug ILAs,
the pack/scan/write engine, or anything else in the design gets a
single block.

### 18.15 Corrected architecture: DDR is supposed to be the frame buffer -- rewritten as a genuine streaming pass-through, no on-chip full-frame storage (2026-07-08)

The capacity wall in 18.14 was a symptom of building the wrong thing,
not a problem to work around by shrinking the test further. User
clarified directly: **"the purpose was to buffer it in the DDR and
then pass it to HD_SDI hardware"** -- i.e. DDR (gigabytes of capacity)
is meant to *be* the frame buffer for this pipeline; the on-chip logic
only needs to bridge the camera's pixel clock domain into `ui_clk`, the
same way the existing `u_copy_cdc_fifo` pattern already does for every
other source. Storing a whole frame in BRAM/URAM *before* it ever
reaches DDR was never the right shape for "buffer through DDR" -- it
duplicates the buffering DDR is already doing, and at native resolution
it simply doesn't fit.

`g_src_eo0raw` (`src/PanoramaBase_DdrBlackFrame.v`) was rewritten from
scratch as a direct streaming path:

- **No on-chip frame buffer, no walk state machine.** Camera pixels
  from `eo0_wr_clk`/`eo0_wr_hsync`/`eo0_wr_vsync`/`eo0_wr_pixel` are
  packed (`{eo0_wr_pixel[19:12], eo0_wr_pixel[9:2]}`) and pushed
  straight into a 2048-deep `xpm_fifo_async` CDC FIFO
  (`eo0_wr_clk` -> `c0_ddr4_ui_clk`) as they arrive, in raster order,
  gated only by `wr_frame_active (=~vsync) && wr_hsync && !copyfifo_full`
  -- the same shape as every other source's copy CDC FIFO, just fed
  directly from the camera instead of from an on-chip buffer's read
  port. `col_in_tile`/`row_in_tile`/`row_base`/`copy_walk_done`/
  `EO1920x1080_RawFrameBuffer` are all gone; there is no random-access
  buffer to walk, since the camera already produces pixels in the
  correct raster order.
- **Copy-start trigger changed from display-edge to camera-edge for
  this source only.** `g_src_eostk`/`g_src_eo0` can start a new DDR
  copy pass whenever the *display* needs a fresh bank (`frame_edge`,
  derived from the renderer's frame toggle) because their on-chip
  buffer already holds a complete, committed frame at all times,
  decoupled from the camera's own real-time cadence. A pure streaming
  source has no such buffer, so starting on the display's schedule
  could begin mid-camera-frame and tear the image. A new module-scope
  CDC (`eo0_ftog_wr` / `eo0_frame_edge_ui`, toggle-based, mirroring the
  existing `ftog_meta`/`ftog_sync`/`ftog_sync_d` pattern) synchronizes
  the camera's own vsync falling edge into `ui_clk`; `copy_start_trig`
  now special-cases `SRC_EO0RAW` to trigger on `eo0_frame_edge_ui` (with
  `eo_frames_valid` gating the very first pass on "camera has produced
  at least one frame boundary yet"). This had to be declared at module
  scope, above the `generate` block, for the same elaboration-order
  reason `copy_active` and friends are (see the note above that
  declaration) -- `copy_start_trig`'s ternary references it directly.
- **Why a small FIFO is enough.** Section 17 already established DDR
  write throughput comfortably exceeds the camera's real-time pixel
  rate, so a copy pass (2,073,600 pixels, triggered at the camera's own
  frame start) always finishes well before the *next* camera frame
  begins. The FIFO only ever needs to absorb momentary read-priority
  arbitration backpressure, never anywhere near a full frame -- hence
  2048 entries (4Kb) instead of ~31.64Mb.
- Added `dbg_eo0raw_fifo_ovf_seen` (sticky, `mark_debug`), matching this
  project's established bring-up-visibility convention: latches if the
  camera ever produces an active pixel while the CDC FIFO is full,
  which should never happen given the bandwidth headroom above.

Resource footprint is now trivial regardless of resolution (one
2048x16 FIFO vs. an entire frame's worth of BRAM/URAM), so this no
longer needs a compromise crop -- it runs at the camera's true native
1920x1080 with zero pixel-level manipulation of any kind.

**Result: builds clean.** Synthesis: 0 errors, 0 critical warnings
attributable to this change (the 2 critical warnings present are
pre-existing `set_clock_groups` XDC issues unrelated to `g_src_eo0raw`).
Cell usage for the new source is exactly what was expected -- a single
`u_copy_cdc_fifo` (2K x 16, `WARNING: [Synth 8-7124] ... implemented
using BRAM instead of URAM. Memory would be severely underutilized if
URAMs are used` -- correctly auto-selected) versus 1034 RAMB36E2 for
the old on-chip-buffer approach. Full implementation (place, route,
`write_bitstream`) also completed clean: `DRC finished with 0 Errors`,
`Bitgen Completed Successfully`, and timing closes with positive
margin on every check -- WNS +0.303ns, WHS +0.010ns, WPWS +0.039ns,
0 failing endpoints on all three, "All user specified timing
constraints are met." Bitstream:
`EO_IR_HD_SDI_panorama_base.runs/impl_1/KintexTop_EO_IR_HD_SDI_panorama_base.bit`.

### 18.16 Hardware result: same corruption signature confirmed on the zero-manipulation native-resolution stream

Programmed and captured via `scripts/codex_ila_capture_eo0raw.tcl` (same
`dbg_ila_0`, same `write_retiring`-triggered queue-correlation method as
section 18.12). Capture window is short (`dbg_ila_0` depth 2048 cycles
at 300MHz ui_clk, ~6.8us) so only 16 read beats fell inside it -- a much
smaller sample than section 18.12's 312, so this is corroborating, not
independently decisive on its own -- but the same qualitative signature
is present: read first-chunk (64b) uniqueness 13/16 vs. last-chunk 16/16
(write-side, for comparison, is 16/16 on both, confirming the write
path is clean here too, consistent with every earlier finding). Three
first-chunk values repeat exactly: `0xbbabbbafbaaabaae`,
`0xbfbfbebefefedefe`, `0xbbbbbbbbbbbfbabe` -- each appearing in a pair,
never a last-chunk value repeating. This is the cleanest test run in
the whole investigation: true native 1920x1080 cam0 resolution, zero
crop/subsample decimation, zero compositor, and now zero on-chip
full-frame buffering of any kind -- pixels flow camera -> small CDC
FIFO -> DDR write -> DDR read -> HD-SDI with no intermediate processing
stage left to blame. The corruption signature surviving here removes
the last remaining category of "maybe it's something in the EO capture
path" theories; combined with section 18.12 (real camera data, no
compositor) and sections 16/17 (ramp data, no EO path at all, every
outstanding-depth stratum), the corruption is now confirmed present
across four structurally distinct source configurations. Consistent
with the standing conclusion: this is a DDR4 PHY/calibration-level
effect (leading theory: first-beat DQS-gate/preamble timing, section
16), not fixable from this codebase's RTL, and the one remaining open
question is still handoff section 4.1 (does it persist with the write
engine fully idle, i.e. rules in/out a read-during-write bank conflict
as an alternative or contributing explanation).

### 18.17 Visual confirmation from live hardware: native-resolution zero-manipulation stream shows the identical striping

User viewed the `SRC_EO0RAW` build live on the monitor and confirmed:
"same symptoms" -- dense, regular vertical (mostly magenta/pink)
striping over an otherwise coherent, recognizable real scene (canal/
dock, water, boats), visually indistinguishable in character from every
prior test (original 6-camera stack, ramp, `SRC_EO0`). This is the
strongest single confirmation in the investigation: the build under
test here has cam0 at its true native 1920x1080, zero crop/subsample
decimation, zero compositor, and zero on-chip full-frame buffering --
literally nothing left in the on-chip datapath besides a small CDC FIFO
between the camera and DDR. With every processing stage that could have
harbored a geometry/logic bug physically absent from the build, and the
artifact still present and visually identical, this closes the
geometry-bug question: there never was a separate EO-side structural
bug, at any resolution or processing stage. The DDR4 read corruption
(section 16) is confirmed sufficient, alone, to fully explain every
visual symptom reported across the whole investigation. The one
remaining open thread is unchanged: handoff section 4.1's
write-engine-idle test.

### 18.18 RESOLVED: handoff section 4.1 -- corruption persists with the write engine provably idle, ruling out a bank conflict

`scripts/codex_ila_capture_writeidle.tcl` (existed since the earlier §18
work but had not yet been run) triggers `dbg_ila_0` on `copy_active`
transitioning to `1'b0`, run against the already-programmed
`SRC_EO0RAW` streaming build. Fixed one bug first: the script assumed
`PROBES.FILE` was still associated with the device from a prior
`hw_manager` session, but each batch invocation starts a fresh
`hw_manager` with no such carry-over -- added an explicit
`set_property PROBES.FILE ...` before `refresh_hw_device`, matching
every other capture script's pattern (no reprogram needed, the
already-running bitstream is untouched).

Result: **all 16 correlated read beats had `copy_active==0`,
`fb_write_pending==0`, and `wdf_pend==0`** -- the write engine wasn't
just "between copies," it had zero write activity in flight or pending
by any signal this design tracks. The corruption was still fully
present: first-chunk (64b) uniqueness 9/16 vs. last-chunk 16/16, with
most repeated first-chunk values recurring at a strikingly consistent
distance of ~72 beats in `rd_addr[15:0]` (e.g. `0xc8cb899e9d869082`
at both `addr=0xd828` and `addr=0xd870`). Analysis:
`analyze_writeidle.py` (scratchpad), data: `ila_capture_writeidle.csv`.

**This closes the investigation's last open question.** A
read-during-write bank conflict is ruled out -- there is no write
anywhere near these reads to conflict with -- and with it, every
avenue reachable from this codebase's own RTL. The remaining and now
sole explanation is section 18's/handoff 4.2's DDR4 read DQS-gate/
preamble-timing theory: a hardware/MIG-calibration-level effect
specific to the first beat of a BL8 burst, not fixable from this
repo's RTL. Further root-causing, if pursued, belongs in that
direction (MIG calibration parameter retuning, Xilinx Answer Record
search for "UltraScale+ DDR4 MIG native interface first beat read
burst incorrect" or similar) rather than continued RTL auditing here.

## 19. Mitigation implemented: local pixel substitution in the unpack stage (2026-07-08)

With the root cause confirmed as hardware/MIG-calibration-level (section
18.18) and outside this repo's ability to fix directly, the user asked
whether the physical board offered a way around it -- specifically,
whether power/soldering was implicated (checked against the schematic
at `C:\SVNProjects\IMU_Stabilize_v40\Circuit Diagram\tbt_camerasystem_251106.pdf`:
professional DDR4-appropriate power design, dedicated VPP/VTT
regulators with correct JEDEC sequencing, generous decoupling -- nothing
suggests a marginal physical rail, and the failure's whole-bus,
perfectly-deterministic, position-locked character across 4 physically
separate DDR4 packages (M1-M4) is a poor match for a physical/solder
defect regardless) and whether the board's 80-bit-wide DDR4 bus (5x
`MT40A512M16TB-062E`, only 64 of 80 bits used by `ddr4_sub64`) offered a
spare bank to fail over to (it doesn't -- the 5th chip, M5/DQ64-79,
shares the same clock/command/address/chip-select as M1-M4; it's the
same rank, driven by the same DQS-gate mechanism, not an independent
memory).

**An initially-proposed "shift the read address so useful data never
lands in the corrupted position" idea turned out not to be literally
implementable**: DDR4 BL8 bursts are fixed-size, 512-bit-aligned units,
and the MIG's native app interface exposes no sub-beat addressing --
every `app_addr` value maps to a distinct, non-overlapping 32-pixel
chunk, so a read can't be requested starting 4 pixels early. The
real implementable fix has to live downstream of the read, in how the
returned data is consumed.

**Implemented in the shared, source-agnostic unpack stage**
(`beat_fifo -> 32x16b unpack -> pix_fifo`, `PanoramaBase_DdrBlackFrame.v`
around line 536 and 1365-1377) since every finding in sections 16-18.18
confirmed the corruption pattern is 100% deterministic and position-
locked: positions 0-3 of every 32-pixel/512-bit-aligned group are wrong
on every single read, positions 4-31 are correct on every single read,
regardless of source, pipelining depth, or write activity. Since every
window width used in this design (640, 1920) is a multiple of 32, this
lands on the exact same column-modulo-32 position in every row, which
is exactly the vertical-stripe pattern seen since the very first
hardware bring-up screenshot that opened this whole investigation.

Fix: latch pixel 4 (the group's first known-good pixel, `beat_fifo_dout[79:64]`)
into a new register (`unpack_fill_pixel`) at the moment each 512-bit
beat is loaded into the unpack shift register; substitute it for
positions 0-3 (`unpack_count > 6'd28`) instead of passing through the
corrupted `unpack_shift[15:0]`. Positions 4-31 are untouched. Cost:
one 16-bit register and a 1-line mux -- zero extra DDR bandwidth, zero
extra buffer, zero extra reads, and it applies to every `SRC_SEL`
source automatically since it's in the common back-end. Trade-off:
the 4 substituted pixels per 32 (12.5% of columns, at fixed positions)
show the neighboring pixel's value rather than their own real sensor
data -- a static, thin band rather than a sharp value, in place of the
current jarring stale-data stripe.

`SRC_SEL` switched back from the `SRC_EO0RAW` diagnostic to
`SRC_EOSTK` (the real production 6-camera, 1920x960 panorama-through-
DDR target) to validate the fix on the actual deliverable rather than
the diagnostic build. Synthesis: 0 errors, 0 critical warnings.
Implementation/bitgen: 0 errors, 0 critical warnings, timing closes
with margin (WNS +0.379ns, WHS +0.010ns). Programmed to hardware;
visual confirmation pending.

### 19.1 Hardware iteration results on the mitigation (2026-07-08, same day)

Three findings from live-hardware iteration after §19's first version:

1. **The corrupted range is 8 pixels (TWO 64-bit chunks), not 4.** The
   original §16 characterization only compared chunk 1 against chunk 8
   and never directly verified chunk 2. A renderer-side `dbg_ila_1`
   capture, cross-checking the same `h_cnt` position across 4 different
   image rows (real scene content varies row-to-row; corrupted output
   was bit-identical row-to-row), showed `cur_x mod 32` positions 2-9
   (i.e. burst pixels 0-7 after pipeline offset) 100% stuck while all
   other positions were 0% stuck. Substitution range widened from 4 to
   8 pixels; fill source moved from pixel 4 (itself corrupted!) to
   pixel 8. This is why §19's first build appeared to change nothing.

2. **Found and fixed a REAL capture-timing bug**: `beat_fifo_wr_en` is
   registered (visible one cycle after `c0_ddr4_app_rd_data_valid`) but
   `u_beat_fifo`'s `din` was wired to the live `c0_ddr4_app_rd_data`
   bus -- capturing whatever the MIG drove one cycle LATER than the
   qualified word. Fixed by latching `rd_data_capture` in lockstep with
   the enable. Empirically this did NOT change the corruption (the raw
   bus is already wrong at the valid cycle -- 14/17 unique first-chunk
   vs 17/17 last-chunk after the fix), but it was a genuine latent bug.

3. **The color-cycling stripes were spurious CHROMA, not luma.** The EO
   packing (`copyfifo_din`) packed a second real sensor byte into the
   low (C) byte of every pixel, while the renderer's own comment
   documents the intent as "grayscale luma, neutral chroma (C=0x80)"
   -- and the proven-clean ramp source indeed packs `8'h80`. A real
   varying byte in C is decoded by a standards-compliant BT.1120/SDI
   receiver as actual Cb/Cr, producing spurious red/green/blue
   fringing, worst at sharp transitions. Fixed in all three EO source
   branches. **User-confirmed on live hardware: image became clean
   grayscale, color artifacts gone, all six tiles correctly placed at
   correct sizes -- the apparent "duplication" of earlier builds is
   gone**, retroactively confirming it was a corruption-induced illusion
   (as §18.10 concluded) all along.

Residual after all of the above: a fine 32px-periodic vertical banding
from the flat-hold substitution itself (verified by direct USB3 frame
capture off the board's own SDI grabber -- FFT of the column-difference
profile shows a clean 31.98px fundamental with harmonics, i.e. OUR
substitution edge, not new corruption). §19.2: replaced the flat hold
with a linear interpolation across positions 0-7 between the previous
group's last good pixel (position 31) and this group's first good pixel
(position 8) -- build in progress as of this writing.

## 20. ROOT CAUSE (mechanism level) + the actual fix to try: DQS-gate one-clock misalignment at DDR4-2400 -- retime the interface to a lower data rate (2026-07-08)

### 20.1 The mechanism, from the accumulated evidence

Every hard fact collected across sections 13-19 now fits one specific
mechanism. The decisive arithmetic: the corrupted region is the first
**128 bits = 2 beats** of every BL8 burst (§19.1 finding 1). DDR is
double-data-rate: **2 beats = exactly ONE memory clock cycle = one full
DQS toggle**. A read-DQS-gate (or equivalently, XIPHY read-FIFO
pointer) alignment that is off by exactly one memory clock produces
precisely this failure: the first two beat-slots of the burst are
popped from the capture FIFO before this burst's first DQS edge has
pushed data into them, so they deliver **stale leftovers from earlier
bursts** -- and beats 2-7 deliver correct data because by then the
(late) pushes have caught up with the pops.

Every observation matches:

- 100% deterministic, on every read (a calibration LANDING POINT is
  wrong by one clock -- not analog noise, so no randomness);
- stale data from nearby bursts at whole-beat offsets (§18.5's
  fingerprint: offsets cluster at +32k / 32k+31 -- FIFO leftovers, not
  bit noise);
- exactly one tCK worth of beats corrupted, remainder always clean;
- write path 100% clean (write timing is a different calibration);
- independent of traffic, pipelining depth, and write-engine state
  (§17, §18.18 -- the misalignment is static);
- all 27 calibration stages report PASS -- the DQS-gate cal stage's
  simple pattern check can land on (or track to) a stable-but-wrong
  gate position one clock away from the correct one, and
  `01_DQS_GATE`/`02_DQS_GATE_SANITY_CHECK` are pass/fail gates, not
  continuous-traffic stress tests;
- per-bit eye margins all healthy and uniform (§15 -- the eye itself
  is fine; the GATE is in the wrong clock cycle, which per-bit deskew
  margins do not measure).

AMD documents this class of failure (calibration passes, deterministic
post-calibration read data errors, DQS-gate tracking landing/underflow
issues) in its UltraScale/UltraScale+ MIG hardware-failure casebook:
https://adaptivesupport.amd.com/s/article/1225537 -- including a case
where a power-rail (VTT) anomaly during calibration parked the gate in
a wrong-but-stable position. See also AR 70006 (DDR4 post-calibration
data errors under specific patterns).

### 20.2 Why this is FIXABLE from this repo after all

The interface currently runs at **DDR4-2400** (`C0.DDR4_TimePeriod
{833}` ps in `scripts/create_ddr4_sub64_ip.tcl` -> 1200MHz memory
clock, ui_clk 300MHz). The DQS-gate placement window scales with tCK:
at 833ps the gate-landing decision is made against a ~0.83ns window;
at DDR4-1600 (1250ps) the window is 50% wider. A calibration that
consistently lands one clock off at 2400 has far more margin to land
correctly at 1600 -- and this design needs a tiny fraction of even
DDR4-1600's bandwidth (~250MB/s of ~12.8GB/s peak).

**The experiment (config-only, no RTL changes):**

1. Edit `scripts/create_ddr4_sub64_ip.tcl`:
   `CONFIG.C0.DDR4_TimePeriod {833}` -> `{1250}` (DDR4-1600). Keep
   `InputClockPeriod {4998}` (the physical 200MHz oscillator is
   unchanged).
2. Re-run the script in the project (it deletes and regenerates the IP
   from scratch -- self-contained, see the purge/create logic in it).
3. Full synth + impl + bitstream. Note ui_clk drops 300->200MHz; all
   ui_clk-side timing gets EASIER, and every clock-domain crossing in
   the design is a proper async FIFO or 2-FF sync, so no RTL
   assumptions break. `BEATS_TOTAL`/addressing are clock-independent.
4. Program and re-run the §16 raw-read ILA methodology
   (`codex_ila_capture_unpack.tcl` + `analyze_alignfix.py`): compare
   first-chunk vs last-chunk uniqueness on `c0_ddr4_app_rd_data`.
5. **If clean** (first-chunk uniqueness == last-chunk uniqueness):
   root cause confirmed as gate misalignment at 2400. Then decide:
   stay at 1600 permanently (recommended -- bandwidth is irrelevant
   here) and optionally remove/disable the §19 interpolation patch
   (keep the neutral-chroma and din-latch fixes -- those are correct
   regardless). Optionally step back up (2133/1866 = 938/1071ps) if
   there's ever a reason to want more bandwidth.
6. **If still corrupted identically at 1600**: the gate theory loses
   its main support; next steps become (a) scope the VTT rail
   (TPS51200 output, should be a stable 0.6V) against the AMD VTT
   case, (b) file with AMD support armed with the §18.5/§20.1
   fingerprint, (c) keep the §19 interpolation mitigation permanently.

### 20.3 Implementation notes (2026-07-08): the §19 interpolation patch was dropped, three build issues fixed along the way

Per direct user instruction, the §19/19.2 interpolation mitigation was
**fully reverted** (not just disabled) before starting the retime
experiment -- masking the symptom stops being worth the complexity once
a real fix is on the table. Removed: `unpack_fill_y`,
`unpack_prev_last_y`, and the six interpolation wires
(`unpack_y_delta*`/`unpack_interp_step_w`/`unpack_y_interp*`) from
`PanoramaBase_DdrBlackFrame.v`; `pix_fifo_wr_data` is back to an
unconditional `unpack_shift[15:0]` passthrough. The neutral-chroma
packing fix and the `beat_fifo` `din`/`rd_data_capture` latch fix were
**kept** -- both are correct, real bugs, unrelated to which DQS-gate
theory turns out to be right.

Three real build issues surfaced getting the DDR4-1600 regeneration
working, none of them RTL bugs:

1. **`C0.DDR4_InputClockPeriod {4998}` is invalid at the new
   TimePeriod.** The MIG wizard's list of legal input-clock periods is
   filtered by achievability against the *target* TimePeriod (the PLL
   needs a reachable VCO ratio) -- `4998` was a valid near-200MHz snap
   value for the 2400 config but isn't in the legal list for 1250.
   `5000` (exact 200MHz, matching the board's actual fixed oscillator)
   is in the list for both. Also updated `desired_clock_period_ns`
   (used by `patch_ddr_clock_xdcs` to retarget the `create_clock` on
   `c0_sys_clk_p`) from `4.998` to `5.000` to match.
2. **`dbg_ila_2` (compositor tile-select debug core) failed to
   synthesize ("module not found") after the IP regeneration cycle.**
   Its job was already done twice over (16374/16374 clean on the most
   recent capture, section 18.8/19.1) so it was removed outright rather
   than debugged -- see the removal note left in
   `PanoramaBase_DdrBlackFrame.v` in its place.
3. **`dbg_ila_0` then failed the same way.** Root cause: unlike
   `ddr4_sub64` (which has an explicit `ensure_xci_in_xpr` durability
   check in `update_project.tcl`), the `dbg_ila_0`/`dbg_ila_1` `.xci`
   files were only ever added to the live Vivado session, never to the
   persisted project fileset -- so every earlier build in this session
   that used them worked purely because the project was never fully
   closed and reopened from a cold `.xpr` in between. The
   `create_ddr4_sub64_ip.tcl` open/close cycle inside `update_project.tcl`
   was the first thing to do a cold reopen, exposing it. Fixed
   durably: `update_project.tcl` now re-adds both `.xci` files via
   `add_if_missing` on every run, matching the `ddr4_sub64` pattern.
   (`dbg_ila_2`'s `.xci` still exists on disk but is deliberately not
   re-added since point 2 above removed its only instantiation.)

After all three fixes: synth 0 errors, 0 critical warnings at
DDR4-1600. Implementation/bitgen: 0 errors, 0 critical warnings, timing
closes with MORE margin than at 2400 (WNS +0.491ns vs +0.379ns --
consistent with ui_clk dropping 300->200MHz making everything easier).

**RESULT: CONFIRMED.** Programmed to hardware and re-ran the exact
section 16 raw-read methodology (`codex_ila_capture_unpack.tcl` +
`analyze_alignfix.py`, correlating issued `rd_addr` with
`c0_ddr4_app_rd_data_valid` returns via the outstanding-read queue) on
`c0_ddr4_app_rd_data` directly -- the same MIG output wire, same
technique, that characterized the corruption in the first place. Two
independent captures: **14/14 and 11/11 unique first-chunk (64b)
values**, matching (module small-sample noise) the last-chunk
uniqueness that has *always* been clean. Every single prior capture at
DDR4-2400, across dozens of captures throughout sections 13-19, showed
first-chunk uniqueness dramatically below last-chunk (roughly 50-85%
vs 100%). At DDR4-1600 that gap is gone. **The DQS-gate one-clock
misalignment theory (section 20.1) is confirmed as the root cause, and
retiming to DDR4-1600 is confirmed as the fix** -- not a mitigation, a
fix, verified at the same raw MIG signal where the bug was originally
proven to exist. Live-monitor visual confirmation pending.

### 20.3.1 CORRECTION after live-monitor check: the retime moved the corruption, it did not eliminate it

User checked the live monitor: image is grayscale as expected (chroma
fix holds), duplication is still gone, clearly improved -- but reported
residual "flicker and distortion," and specifically that stripe
*position* changed and the frame start now looks clean. This is a real,
important correction to the "CONFIRMED" verdict above, and it came from
exactly the kind of larger/different-methodology check that should have
been done before declaring victory on two 11-14-sample captures.

**Direct USB3-grabber frame capture + analysis (not photos) found the
actual picture:**

1. Same-cycle uniqueness on a small sample (11-14 reads, two captures)
   looked clean purely because the sample was too small to be reliable
   -- pooling 8 more captures (577 reads total) gave 74.9% first-chunk
   unique vs 83.4% last-chunk: a real gap remains, just far smaller
   than the ~50-85% vs 100% gap at 2400. (This pooled test is also
   confounded by genuinely flat/dark real scene content repeating
   legitimately, so 74.9%/83.4% understates how clean it actually is --
   see point 3.)
2. FFT of the column-difference profile on a full captured frame still
   shows the 32px fundamental as completely dominant (period 31.98px,
   37x the mean spectral magnitude) -- magnitude 10368, essentially
   unchanged from the pre-retime capture's 10785. Raw spatial-frequency
   analysis alone cannot tell "still corrupted" apart from "genuinely
   detailed scene with lots of real vertical structure" (this room has
   shelving, poles, cabling), so this by itself is inconclusive too.
3. **The decisive test: per-pixel TEMPORAL variance across a 10-frame
   sequence.** Real static scene content has near-zero frame-to-frame
   noise; corrupted/stale DRAM reads do not track the true scene at
   all and jump around frame to frame. Bucketed by `cur_x mod 32`:
   positions 2-23 sit at a flat baseline (~1.0 std-dev); positions
   **25-31 spike to 35-57** (30-50x higher), with 24 partially elevated
   (~8.6). This is unambiguous, and it directly explains the user's
   word "flicker" -- flicker *is* what temporally-unstable stale data
   looks like to the eye, as opposed to the original 2400 corruption's
   rock-solid static wrong stripe.

**Interpretation:** the corrupted window moved from the *first* ~8
positions of each 32-pixel group (burst start, at 2400) to the *last*
~7-8 positions (burst end, at 1600) -- roughly the mirror image. This
is consistent with the DQS-gate mechanism (section 20.1) still being
right, but the gate's calibration re-converging to a *different*
marginal landing point at the new data rate rather than a comfortably
centered one -- landing one clock early at 2400, one clock late at
1600, rather than correctly in between. The "flicker" character (vs.
2400's 100%-deterministic corruption) suggests this landing point sits
right on a timing edge, probabilistic rather than solidly wrong.

Checked the calibration margin dashboard for a numeric explanation:
`CAL_ERROR_MSG = No errors detected`, `CAL_STOP_MARGIN = FALSE`, every
stage that ran reports PASS (`01_DQS_GATE`/`02_DQS_GATE_SANITY_CHECK`
included), and per-bit read-eye margins (`MARGIN_READ_SIMPLE.*`,
different property namespace at this data rate than the 2400 build
used) are healthy and uniform across all 8 bytes (70-76, no outlier).
None of this is surprising or new information -- the *data*-eye
(fine, per-bit sampling point) has always looked healthy; the *gate*
(coarse, which whole beat gets captured) calibration only exposes
PASS/FAIL, not a numeric margin, so this dashboard was never going to
show why the coarse landing point is one clock off in either
direction.

**Next experiment in flight:** DDR4-1866 (`TimePeriod {1071}`,
`InputClockPeriod` re-resolved same as the 1600 attempt). Reasoning:
2400 landed early, 1600 landed late -- if there's a rate in between (or
outside this bracket) where the gate lands correctly centered, this is
the fastest way to find it empirically. Reusable methodology for
testing any future rate: capture a 10-frame sequence via the USB3
grabber (`capture_sequence.py`), compute per-pixel temporal std-dev,
bucket by `cur_x mod 32` -- a flat ~1.0 baseline with no elevated
bucket is the bar for "actually clean," not small-sample ILA
uniqueness checks.

### 20.4 Fallback that also attacks the root cause: per-boot gate nudge

If 1600 is clean but 2400 is ever required: PG150's XSDB debug
interface exposes the DQS-gate coarse/fine tap positions per byte
(read-only via `get_hw_migs` properties in this Vivado version, but
writable through the RIU from a MicroBlaze/JTAG-to-AXI path). A
one-clock coarse-tap adjustment applied post-calibration would correct
the landing point directly. Substantially more work than the retime;
only worth it if the retime experiment both (a) proves the mechanism
and (b) 2400 bandwidth is someday genuinely needed.

## 21. AMD-documented mechanism confirmed + the exact fix levers (PG150, 2026-07-08)

Pulled the exact mechanism from PG150 (UltraScale Architecture FPGAs
Memory Interface Solutions, v7.1) -- extracted locally from the PDF, so
these are direct quotes/citations, not paraphrase.

### 21.1 The gate-open latency model INCLUDES PCB delay -- and our MIG has NO real board delays (`isCustom=false`)

PG150 Ch3 "DQS Gate" (p38-39), verbatim on how the gate landing point
is chosen:

> "The search for the DQS begins with an estimate of when the DQS is
> expected back. The total latency for the read is a function of the
> delay through the PHY, **PCB delay**, and the configured latency of
> the DRAM (CAS latency, Additive latency, etc.). The search starts
> three DRAM clock cycles before the expected return of the DQS. The
> algorithm must start sampling before the first rising edge of the
> DQS, preferably in the preamble region."

And the gate's time resolution (same section):

> "The XIPHY provides for additional granularity in the time to open
> the gate through coarse and fine taps. **Coarse taps offer 90° DRAM
> clock-cycle granularity (16 available)** and each fine tap provides a
> 2.5 to 15 ps granularity..."

90° per coarse tap => **4 coarse taps = one full DRAM clock cycle**.
A one-DRAM-clock gate error (exactly our 2-beat/8-pixel corruption) is
the gate landing 4 coarse taps early or late -- i.e. locked onto the
wrong DRAM clock cycle of the preamble/burst.

**This is the smoking gun for the rate-dependent flip we observed.**
The gate-search window is anchored on an *estimate* that includes a
fixed PCB round-trip delay. Our MIG config has **`C0.DDR4_isCustom =
false`** -- i.e. we never entered this custom board's actual DQS/DQ/CA/
CK trace propagation delays; the MIG is using its default/reference
board-delay assumptions. If the real KU15P board's DDR4 routing delay
differs from that default by a meaningful fraction of a tCK, the gate
estimate is off by a *fixed absolute time*. A fixed absolute delay
error is a *different fraction of tCK at different data rates*:
- at DDR4-2400 (tCK=833ps) it pushes the estimate past the boundary one
  way -> gate lands one clock EARLY -> first 2 beats stale;
- at DDR4-1600 (tCK=1250ps) the same absolute error is a smaller
  fraction of the (wider) clock -> gate lands the other side -> last
  ~2 beats corrupted, and close enough to the boundary that VT tracking
  hunts across it -> the "flicker."

This is exactly the fingerprint of a board-delay/gate-model mismatch,
and it is independently corroborated by everything else (cal passes,
per-bit eyes healthy -- the *data* eye is fine, the *gate* is one clock
off; 100% deterministic at a given rate -- a fixed landing point, not
noise).

### 21.2 The exact fixes, in priority order

**Fix A (RETRACTED 2026-07-08, see §22 -- `isCustom` is not a board-delay
input and this IP generation has no such field; leaving this text for
history, do not act on it):** ~~give the MIG the real board delays~~.

**Fix B (pragmatic, in progress, no board data needed): retime to a
data rate where the fixed delay error happens to land the gate
centered.** 2400 = early, 1600 = late, so a rate between/around them may
center it. DDR4-1866 (`TimePeriod {1071}`, CL13/CWL10) building now;
if not clean, 2133 (`{938}`) and 2000 (`{1000}`) are the remaining
in-between points to sweep. Judge each with the 10-frame temporal-
variance test (§20.3.1), not small ILA samples.

**Fix C (also root cause, no board data, more effort): post-cal coarse-
tap nudge.** Per §21.1 a one-clock error = 4 coarse taps. PG150 exposes
`DQS_GATE_READ_LATENCY_RANK#_BYTE#` and the coarse/fine taps in the
XIPHY RIU. After `calDone`, a MicroBlaze/JTAG-to-AXI agent could add or
subtract 4 coarse taps per byte to recenter the gate directly. This
fixes it at native rate like Fix A but without needing board data --
at the cost of writing/validating the RIU-poke sequence. Fall back to
this only if board delays (A) are unobtainable and no swept rate (B) is
clean.

### 21.3 Separately confirmed obligation: VT tracking read cadence (PG150 p143)

PG150 Ch4 "VT Tracking" (p143) -- the gate does not stay put on its own
after `calDone`:

> "The PHY requires read commands to be issued at a minimum rate to
> keep the read DQS gate signal aligned to the read DQS preamble after
> calDone is asserted... 1. At least one read command every 1 µs...
> 3. There is a three contiguous system clock cycle period with no read
> CAS commands asserted at the PHY interface every 1 µs."

Plus "Periodic Reads" (p156): "The FPGA DDR PHY requires at least one
DRAM RD or RDA command to be issued every 1 µs."

We instantiate `Phy_Only {Complete_Memory_Controller}` -- the FULL MIG
controller -- and PG150 p144 says "MIG generated controllers monitor
the mcRdCAS and mcWrCAS signals and decide each 1 µs period what
actions, if any, need to be taken to meet the VT tracking
requirements." So this is auto-handled *for us* and is NOT expected to
be the primary bug. BUT our workload is precisely the flagged worst
case: a long, read-free write-copy phase (a full 1920x960 frame of pure
writes) interleaved with a read-only scan-out phase. If the flicker at
1600 has a drift component on top of the gate mislanding, this is where
it comes from. Cheap thing worth checking on whichever rate ends up
best: confirm `dbg_cmd_retry_seen`-style visibility that reads never
stall for >1µs, or restructure the copy so reads and writes interleave
within each 1µs window rather than running in long single-direction
bursts. Not the root cause, but a contributor to temporal instability.

### 21.4 Recommended path

1. **Ask the hardware/layout owner for the DDR4 net trace delays** and
   do Fix A -- it is the only option that cleanly fixes native-rate
   operation with no derating and no post-cal hackery.
2. In parallel (no waiting), finish the Fix B rate sweep (1866 -> 2133/
   2000) as an immediate usable fallback; a derated-but-clean interface
   is fine here (bandwidth need is ~2% of even 1600).
3. If neither yields a fully-clean native-rate result and native rate
   is required, implement Fix C (coarse-tap nudge).
4. Keep the neutral-chroma and beat_fifo-din-latch fixes regardless
   (correct independent of all the above). The §19 interpolation
   masking stays reverted unless a shippable-but-imperfect stopgap is
   needed before A/B/C land.

### 21.5 DDR4-1866 result: no clear improvement over 1600 -- downgrades confidence in Fix B as a standalone plan

Built and programmed DDR4-1866 (`TimePeriod {1071}`, resolved
`InputClockPeriod {4999}`; same `isCustom=false` mismatch/InputClock-
Period-list gotcha as 1600, see §20.3 -- same fix applied). Synth/impl
clean, WNS +0.397ns.

**Capture tooling hit a wall first**: the USB3 grabber (`VideoCapture`
index shifted from 0 to 1 after this reprogram, itself a hint that the
video signal glitched during reprogramming and Windows re-enumerated
the device) returned a **byte-for-byte identical frame on every read**
across three independent attempts -- plain re-open, full close/reopen
per frame with sleeps, and a forced resolution-mode-change jolt. All
returned the exact same cached image. This was confirmed to be a
capture-side artifact, not a frozen FPGA: a `dbg_ila_0` capture in
parallel showed 15/15 unique first-chunk AND 15/15 unique last-chunk
values with addresses and data both varying normally -- the design is
live and producing fresh data. Left as an open item; likely needs a
physical USB replug or closing whatever else may hold the device, not
resolved this session.

**Fell back to the pooled small-ILA-capture method** (8x captures,
445 total read beats -- same method used for the 1600 characterization
in §20.3.1 point 1, with the same caveat: confounded by genuinely
flat/dark real scene content repeating legitimately on both first- and
last-chunk). Result: **79.1% first-chunk unique vs 90.3% last-chunk
unique (11.2-point gap)** -- not better than 1600's 74.9%/83.4%
(8.5-point gap), arguably slightly worse. Both are dramatically better
than 2400's ~50-point gap, and neither is a clean 0-point gap.

**This matters beyond just "1866 isn't the answer."** Two rate changes
in a row (2400->1600->1866) have now each produced *some* improvement
over the original but *no* clean result, with the corrupted window
visibly relocating each time (2400: burst start; 1600: burst end,
flickery) rather than shrinking to nothing. That is consistent with
§21.1's model: a **fixed absolute** delay-model error does not have any
particular reason to hit a rate where it fully cancels out inside the
gate's coarse-tap search window -- there is no guarantee *any* of the
handful of standard DDR4 rate bins lands exactly on the correct
boundary, since the correct point is a specific PCB-delay-dependent
value, not a round-number data rate. Rate-sweeping is a search over a
small, arbitrary, unevenly-spaced set of points hoping to get lucky;
it is not guaranteed to converge, and two tries without a clean hit is
a real (if not conclusive) signal against relying on it alone.

**Revised recommendation: treat Fix A (real board trace delays) as the
primary path, not a parallel option.** Fix B remains worth finishing
(2133, 2000 are cheap to try and one might still land clean) but should
no longer be treated as an equally-likely alternative to Fix A -- it's
now the fallback while waiting on trace-delay data, not a co-equal
plan. Practical next step if trace delays take time to obtain: get a
working temporal-variance capture (fix or work around the grabber
issue -- an alternate capture tool, a physical USB replug, or a
pooled-ILA sample large enough (multiple thousands, not hundreds, of
reads) to overcome the real-content confound) before spending more
rate-sweep build cycles, since a build+program+capture round trip is
~40 minutes and the pooled-ILA proxy hasn't been discriminating enough
to call a rate clean or not clean with confidence.

## 22. CORRECTION: `isCustom` is not a board-trace-delay input -- §21.2 Fix A retracted; real PCB delay data now in-repo and reviewed (2026-07-08)

User added the actual PCB DDR4 net trace-delay reports to the repo:
`docs/DDR4_Parameter_CAC-1.csv` (address/command/clock group) and
`docs/DDR4_Parameter_DQ-2.csv` (DQ/DQS/DM group), straight from the
layout tool (per-net Length, Delay(ns), R/L/C). Investigating how to
feed this into the MIG surfaced a mistake in §21.1/21.2: **`C0.DDR4_isCustom`
is not a board-delay flag.** Checked directly against the installed
IP's own GUI source
(`.../Vivado/data/ip/xilinx/ddr4_v2_2/xgui/ddr4_v2_2.tcl`): its
display name is *"Enable Custom Parts Data File"*, paired with
`C0.DDR4_CustomParts`, a file-browser parameter for a **custom DRAM
part** electrical/timing-table CSV -- for using a DRAM chip not in
Xilinx's standard supported-parts database. It has nothing to do with
PCB trace delay. `MT40A512M16TB-062E` is a standard recognized part, so
`isCustom=false` here is simply *correct*, not a missing-data gap.

**Checked whether this IP generation has ANY board-trace-delay input at
all: it does not.** The wizard has exactly 7 top-level pages (Basic,
AXI Options, Advanced_Clocking, Advanced_Options, Migration Options,
I/O Planning and Design Checklist) -- no "Board Layout"/"Trace Delay"
page. The one per-pin "Skew (ps)" table that does exist
(`C0.DDR4_*_SKEW_*`, found in §21.1's parameter search) lives under
**"Migration Options"**, and is explicitly for pin-compatible
UltraScale/UltraScale+ package migration (compensating tiny
package-internal routing differences between two related device
packages), not this board's PCB layout. The "I/O Planning and Design
Checklist" page's own text confirms the broader point: *"The
methodology for assigning I/O pins for DDR4 IP interfaces has changed.
Rather than assign I/Os within the IP, they are now assigned in the
main Vivado I/O Planner..."* -- UltraScale/UltraScale+ MIG simply does
not take a design-time board-delay table. This tracks with PG150's own
description of DQS gate training (§21.1's quote) being an **empirical,
hardware-measured** search at calibration time, not a table lookup
against a user-supplied estimate -- the "PCB delay" language in that
quote describes what the physical signal experiences (used to bound
the search window's starting point via known worst-case ranges), not
something the user provides per-net.

**§21.1/§21.2 Fix A is retracted.** There is no config-level lever to
"enter the real board delays" for this MIG/device generation. This was
a genuine mistake in the earlier analysis, not a dead end that needed
new data -- the CSVs the user added can't be fed into the IP the way
§21.2 proposed, regardless of how good the data is.

### 22.1 The trace-delay data itself: reviewed, and it looks like a healthy, well-matched layout

Even though there's no config field to feed it into, the data is still
useful as a **sanity check on the layout itself** -- if a byte lane's
DQS were wildly mismatched to its DQ pins or to CK in a way that broke
DDR4 design rules, that would be independently worth knowing regardless
of the MIG-config question. Computed key skews from the two CSVs
(`Delay(ns)` column per net):

- **DQS-to-DQ skew per byte (the tightest, most calibration-critical
  number): -9.6ps to +10.2ps across all 10 bytes.** Excellent, very
  tightly matched -- exactly what DDR4 length-matching rules require
  and calibration expects.
- **Address/command-to-CK skew: +22.5ps to +62.5ps** across all 17
  address bits and the command signals (ACT_N, CS_N, CKE, ODT, BA0/1,
  BG0, PAR). Small and well-controlled.
- **DQS-to-CK skew: -57ps (byte0) to -376ps (byte5), varying
  meaningfully across bytes.** This *looks* like the largest number in
  the set, but it is normal and expected for DDR4 -- different byte
  lanes are physically different distances from the FPGA to their DRAM
  chip (byte0/1 go to M1, byte4/5 to M3, etc., per the schematic's
  physical layout), and **this exact skew is what write-leveling and
  read-leveling calibration exist to measure and compensate for at
  runtime.** A few hundred ps of DQS-to-CK spread across byte groups on
  a multi-chip DDR4 layout is unremarkable, not a defect.

**No outlier, no red flag.** Nothing in this data explains a
one-clock, whole-rank (all bytes simultaneously, not one bad lane)
corruption. If anything, this is mild evidence *against* a
board-layout explanation specifically, since a genuine trace-length
defect would be expected to show up as a per-byte anomaly (one byte
much worse than the others), which is not what any of the hardware
evidence (ILA, temporal-variance, or this CSV) has shown -- every
finding this whole investigation has pointed at all-bytes-simultaneous
corruption of specific whole-burst positions, i.e. a *shared*
mechanism (the gate/VT-tracking control logic, common across the
rank), not an isolated physical-layer defect on one net.

### 22.2 Revised leading theory and recommended path

With Fix A off the table and the board layout looking clean, the
mechanism most consistent with everything gathered (§20.1's one-clock
DQS-gate-window finding, the 2400/1600/1866 rate-dependent relocation
without ever landing clean, all-bytes-simultaneous corruption, and the
"flicker"/temporal-instability character at 1600) shifts toward
**§21.3's VT tracking** -- not as a minor side note anymore, but as the
leading candidate:

- PG150 p143: the gate does not stay put after `calDone` -- it requires
  ongoing periodic reads and a `gt_data_ready` pulse to keep tracking
  voltage/temperature drift, "requires read commands to be issued at a
  minimum rate," and specifically "there is a three contiguous system
  clock cycle period with no read CAS commands asserted... every 1
  µs."
- Our workload is the textbook stress case PG150 calls out: long,
  single-direction write bursts (a full 1920x960 frame of writes during
  `copy_active`) interleaved with read-only scan-out. The full MIG
  controller (`Phy_Only {Complete_Memory_Controller}`) is supposed to
  auto-inject reads/`gt_data_ready` to meet this, but auto-injection
  under an unusual, very asymmetric traffic shape is exactly the kind
  of corner case that could land the gate one tracking-tick off without
  ever failing calibration's own PASS/FAIL check.
- This also explains the rate-dependent *relocation* better than a
  static delay-model error would: if this is a **tracking** phenomenon
  (an ongoing correction process, not a one-time fixed search result),
  its convergence behavior is expected to be sensitive to the data
  rate's actual tRFC/tCCD/burst-timing relationships in ways a purely
  static model wouldn't be -- consistent with three different rates
  producing three different (not just "better/worse") outcomes.

**Recommended next steps, in order:**
1. **Directly test the VT-tracking-during-write-phase theory** --
   instrument (or reuse existing `dbg_ila_0` probes) to check whether
   reads/`gt_data_ready`-triggering activity actually continues at the
   required cadence during the long write-only `copy_active` phase, or
   whether there's a multi-µs gap. This is fully in-repo, needs no
   external data, and directly tests the current leading theory.
2. **Restructure copy/scan interleaving** if step 1 finds a gap:
   interleave the write-copy with periodic read activity (even
   dummy/throwaway reads) rather than running long uninterrupted write
   bursts, so the PHY's own auto-injection logic is never pushed into
   an edge case.
3. **Fix C (post-cal coarse-tap nudge)** remains available and
   untried -- still worth it if 1-2 don't resolve it, now with more
   confidence it's addressing the right layer (the gate's *tracked*
   position, not a one-time miscalibrated search).
4. Rate-sweep (2133, 2000) is now explicitly de-prioritized -- three
   tries (2400/1600/1866) without a clean hit, plus the theory shift
   away from a static delay-model explanation, make further blind
   sweeping a weak use of a ~40-minute build cycle compared to 1-2
   above.
5. Neutral-chroma and beat_fifo-din-latch fixes stay regardless (real,
   independent bugs). §19 interpolation masking stays reverted.

### 22.3 Step 1 result: CONFIRMED -- our app-level read cadence violates PG150's 1us requirement by up to 6.3x

Ran step 1 directly: 10x `codex_ila_capture_unpack.tcl` captures
(dbg_ila_0, `write_retiring`-triggered, so biased toward landing inside
an active copy/write phase), measuring the gap between consecutive
`read_retiring` events in each ~8.8us window (2048 samples at
DDR4-1866's ui_clk period, 4.284ns/cycle -- confirmed from
`C0.DDR4_TimePeriod=1071` in the live `.xci`).

| capture | reads | writes | copy_active | max read gap |
|---|---|---|---|---|
| 1,3,4,5,7,10 | 12-17 | 20-21 | 100% | 2-8 cycles (8.6-34.3ns) -- fine |
| 2 | 136 | 19 | 99.1% | 467 cycles = **2000.6ns** |
| 6 | 28 | 20 | 100% | **1481 cycles = 6344.6ns** |
| 8 | 124 | 19 | 97.9% | 405 cycles = 1735.0ns |
| 9 | 136 | 19 | 97.9% | 561 cycles = 2403.3ns |

4 of 10 independent captures show a read-to-read gap exceeding PG150's
1000ns (233.4-cycle) limit, worst case **6.3x over the documented
requirement**. Note this is a *lower bound* on the true worst case --
each capture window is only ~8.8us, so a gap that started before or
extended past the window would be truncated, not fully measured.

**Caveat, stated for the record**: PG150 documents that the full MIG
controller (which we use, `Phy_Only {Complete_Memory_Controller}`) can
silently auto-inject reads to cover exactly this kind of app-level gap
-- those injected reads return no data to the UI, so they are
*invisible* to `read_retiring`/`c0_ddr4_app_rd_data_valid`, which only
reflect reads *our* RTL explicitly requested. This measurement proves
our own request pattern violates the documented spec by a wide margin;
it does not by itself prove the controller's safety net failed to
compensate, since a failure and a silent success would look identical
from this vantage point. The proposed fix (§22.2 step 2) is cheap and
low-risk regardless of which is true -- redundant safety margin if
auto-injection was already covering it, a real fix if it wasn't.

**Proceeding to §22.2 step 2**: restructure the copy/scan engine so
reads and writes interleave instead of running long uninterrupted
write-only stretches.

### 22.4 Keepalive-read mechanism: PROVABLY fixed the measured gap, but caused a severe hardware regression -- reverted (2026-07-08)

Implemented §22.2 step 2 as a targeted keepalive-read insertion rather
than a full copy/scan restructure: a `read_gap_counter` (10-bit, counts
ui_clk cycles since the last accepted read) that, once it reaches
`KEEPALIVE_THRESHOLD = 150` cycles (~642ns, comfortably under PG150's
233.4-cycle/1000ns limit) with the scan engine not otherwise wanting to
read, injects a throwaway read command. A 1-bit `cmd_is_keepalive` tag
followed each command through the pipeline; a small `xpm_fifo_sync`
tag queue (`u_keepalive_tag_fifo`, depth 32, matching the depth margin
of the existing in-order outstanding-read tracking) recorded which
completions were real scan data vs. keepalive throwaway, so the
keepalive completion could be silently dropped instead of being pushed
into `beat_fifo` (where it would otherwise inject a garbage pixel into
the live video stream). `read_retiring`-driven scan-walk advancement
(`rd_issue_count`/`rd_addr`/`scan_active`) was gated on
`!cmd_is_keepalive` so keepalive reads didn't consume real scan
progress, while `outstanding` was still incremented unconditionally
(both real and keepalive reads occupy an MIG command slot).

**Hardware validation of the mechanism itself, in isolation, was a
clean success**: 10 pooled `codex_ila_capture_unpack.tcl` captures
after deploying this change showed a worst-case read-to-read gap of
861ns across all 10 windows -- 0/10 violations of the 1000ns PG150
limit (vs. 4/10 violations, worst case 6344.6ns, before the change;
see §22.3 table). The keepalive logic did exactly what it was designed
to do at the level it was instrumented and measured.

**Despite that, deploying the same bitstream to the actual video path
produced a severe regression: a blank black screen**, reported
directly by the user ("Well I programmed again but the output this
time is blank black screen. I checked with other working RTL the
grabber and everything else is working fine.") -- explicitly ruling
out capture-tooling/grabber issues as the explanation, since the same
grabber worked correctly with a different (pre-keepalive) bitstream
loaded. This is a materially worse symptom than the corruption being
fixed (visible-but-flawed content -> nothing at all), and the root
cause inside the new RTL was not identified by code re-reading alone
in the time available. Candidate hypotheses that were NOT ruled out
before reverting (left here for whoever re-attempts this):

- **Interaction with `flush_active`**: keepalive reads were not gated
  on `!flush_active`. The frame-boundary flush completion check
  (`outstanding == 0 && beat_fifo_empty`) could plausibly never
  observe `outstanding == 0` if a keepalive read keeps getting issued
  during what should be a draining/idle window, stalling the flush
  sequencer indefinitely -- which would plausibly present as exactly
  "blank black screen" if the renderer's frame-valid gating depends on
  flush ever completing.
- **FWFT tag-queue pop-timing mismatch**: `u_keepalive_tag_fifo` was
  read (`rd_en`) directly on `c0_ddr4_app_rd_data_valid`, relying on
  the tag queue's FWFT `dout` being valid and correctly aligned to the
  *same* completion the data-valid pulse corresponds to. Any off-by-one
  in when the tag was pushed (`read_retiring`, i.e. command-accept
  time) vs. when the native interface actually returns data for that
  specific command could desync the tag stream from the data stream --
  every completion after the first desync would be misclassified,
  which could plausibly drop large swaths of real scan data into the
  "discard" path, producing exactly the observed all-black result.
- Something else entirely not yet considered -- the above two are the
  most structurally plausible from code inspection, not confirmed.

**Decision: reverted the keepalive mechanism in full** (all 7 pieces:
`cmd_is_keepalive` declaration, `u_keepalive_tag_fifo` instantiation,
`keepalive_want`/`read_gap_counter`/`KEEPALIVE_THRESHOLD` declarations,
the arbitration branch, the scan-walk gating, the completion-handler
skip, and the reset-block additions) rather than iterate further on
hardware with an unconfirmed hypothesis. `src/PanoramaBase_DdrBlackFrame.v`
is now back to the pre-keepalive state (verified via `git diff` against
the last commit showing only the already-decided interpolation-patch
and `dbg_ila_2` removals, zero net keepalive-related lines). Rebuilding
and reprogramming to reconfirm the pre-keepalive baseline (DDR4-1866,
"flicker and distortion... much improved" per the user's prior
description -- visible content with residual corruption, not fully
clean but not broken) is in progress as of this writing.

**The underlying measured problem from §22.3 (6.3x PG150 violation)
is still real and unaddressed.** The keepalive *mechanism design*
demonstrably closes the measured gap; what's unproven is that it can
be deployed without a side effect this severe. Before re-attempting:
add dedicated ILA visibility on the new signals themselves
(`cmd_is_keepalive`, `keepalive_want`, `read_gap_counter`,
`keepalive_tag_empty`/`dout`, and ideally `flush_active` /
`outstanding` sampled at the same time) so the next hardware iteration
can distinguish these hypotheses directly instead of reasoning blind
from a black screen alone. Gating keepalive issuance on `!flush_active`
outright is a cheap, low-risk first change to try even before adding
instrumentation, since it directly addresses the most structurally
plausible hypothesis above.

**Revert confirmed on hardware, same day.** Rebuilt from the fully
reverted source (synth: 0 errors, 0 new critical warnings, 726
RAMB36E2/75 URAM288; impl+bitgen: 0 DRC errors, 0 critical warnings,
WNS +0.449ns, WHS +0.016ns), reprogrammed the board, and the user
confirmed via the USB3 grabber's camera app that the blank-black-screen
regression is gone -- the display is back to the pre-keepalive baseline
(visible panorama content with residual flicker/distortion, the state
described in §20.3.1/the user's own report after the DDR4-1866 retime).
This closes out the regression. The vertical-stripe/read-corruption
artifact itself is still open -- §22.3's confirmed 6.3x PG150 violation
remains the leading, most actionable lever, but the next attempt at a
keepalive-style fix needs the instrumentation described above before
going back to hardware.
