# DDR read-cadence / VT-tracking root cause and fix plan

Date: 2026-07-08
Project: `E:\Xylinx\EO_IR_HD_SDI_panorama_base`

This is the focused plan for the current residual EO panorama failure after the
green-frame/lockup, compositor geometry, renderer starvation, chroma packing, and
read-data latch issues were already handled or ruled out.

## Current root cause

The remaining visible flicker/distortion is caused by DDR4 read data corruption
at the MIG output, driven by DQS-gate / VT-tracking instability under this
design's app-level traffic pattern.

The strongest current explanation is not a bad camera path, tile walk, renderer
window, native-interface handshake, or FPGA timing path. It is this:

1. PG150's read-DQS gate tracking requires ongoing read activity at a minimum
   cadence.
2. The current scheduler issues scan reads only while `scan_active` is true, but
   allows long write-dominated stretches while copying a frame.
3. Saved DDR4-1866 ILA captures show app-level read gaps above the 1 us tracking
   budget: for example `ila_capture_unpack_1866_4.csv` has a 405-cycle gap
   (~1.74 us) and `ila_capture_unpack_1866_6.csv` / `_8.csv` have 467-cycle
   gaps (~2.00 us) at a 233.25 MHz ui clock.
4. The keepalive experiment closed the measured gap: the saved
   `ila_capture_readgap_*.csv` captures max out at 201 cycles (~862 ns), under
   the 1 us budget.
5. That same keepalive bitstream blanked the display, so the lever is right but
   the first integration was unsafe.
6. A direct USB3 capture taken on 2026-07-08 reproduces the same artifact
   without monitor-camera ambiguity. The captured 1920x1080 frame set in
   `captures/usb3_direct_20260708_184115/` has a very strong 32-pixel column
   periodicity: the aggregate column-score autocorrelation peaks at 32 px
   (0.9928), with 64/96/128 px harmonics. That maps exactly to this design's
   packing ratio of one 512-bit MIG beat = 32 packed 16-bit pixels.

The root problem is therefore: **the design must guarantee periodic accepted
read commands during write-heavy phases, without letting dummy-read completions
enter the video beat FIFO or interfere with frame-boundary flush.**

## Evidence already closed

- Corruption is present on `c0_ddr4_app_rd_data`, before `beat_fifo`, unpack,
  pix FIFO, and renderer.
- The write side has been ILA-proven clean; packed write data matches expected
  values before entering the MIG.
- `beat_fifo` and unpack are faithful after the `rd_data_capture` latch fix.
- The corrupted positions are whole burst time slots across all byte lanes, not
  one bad physical byte lane.
- Calibration reports PASS and read-eye margins are healthy and uniform. The
  last pre-fix MIG margin screenshot in Read Mode / Simple Pattern / Rising
  Clock Edge shows all rank-0 nibbles with roughly 278-303 ps left/right
  margins, with no obvious weak byte or nibble.
- Compositor tile-select was hardware-verified; tile duplication was a visual
  artifact of DDR corruption and non-neutral chroma.
- Renderer starvation was not observed in targeted ILA captures.
- Read corruption persists when the write engine is idle, ruling out read/write
  bank overlap as the primary cause.
- Timing is currently closed after the revert build: routed WNS +0.449 ns, WHS
  +0.016 ns, 0 DRC errors at bitgen.
- The USB3 output artifact is phase-locked to the 512-bit beat unpack cadence,
  not to EO tile boundaries or HD timing. Green/magenta speckles in an otherwise
  neutral-chroma grayscale EO stream are consistent with corrupted returned DDR
  pixel words.
- This 32-pixel spacing sharpens, rather than weakens, the DQS-gate theory: a
  bad sub-beat/word slot inside each returned 512-bit app beat would unpack into
  narrow vertical stripes at the same pixel phase every 32 columns.
- The healthy simple-pattern read margins argue against a static board/pin/byte
  lane read-eye failure. They do not rule out a dynamic gate-tracking failure
  that appears only under the design's write-heavy app traffic and long read
  gaps.

## Why the first keepalive attempt regressed

The first keepalive mechanism proved that dummy reads can close the app-level
read gap, but it added two high-risk interactions:

1. Keepalive reads were allowed during `flush_active`. A frame-boundary flush
   waits for `outstanding == 0`; issuing new dummy reads while flushing can keep
   that condition from becoming stable and plausibly leaves the renderer with no
   committed stream.
2. Returned data was classified through an XPM FWFT tag FIFO popped directly on
   `c0_ddr4_app_rd_data_valid`. If the tag stream goes off by one, real scan
   completions can be discarded as dummy completions, which also plausibly
   produces an all-black output.

The next fix should keep the same read-cadence idea, but remove both hazards.

## Fix plan

### Phase 0 - add visibility first

Before changing behavior again, add ILA probes for:

- `read_gap_counter`
- `keepalive_want`
- `keepalive_launch`
- `cmd_is_keepalive`
- `rd_return_is_keepalive`
- `rd_tag_count`
- `rd_tag_overflow`
- `rd_tag_underflow`
- `flush_active`
- `outstanding`
- `beat_fifo_wr_en`
- `frame_valid`
- read-return word/slot phase visibility, enough to correlate any bad 16-bit
  lane inside `c0_ddr4_app_rd_data` with the 32-pixel USB3 artifact period

Keep the current `dbg_ila_0` read/write probes. Save new captures under unique
names; do not overwrite `ila_capture_unpack.csv`.

### Phase 1 - implement keepalive v2

Add a dummy-read path to `src/PanoramaBase_DdrBlackFrame.v` with these rules:

1. `read_gap_counter` counts ui-clock cycles since any accepted read command
   (`read_retiring`, real or dummy). Reset it to zero on every accepted read.
2. Use `KEEPALIVE_THRESHOLD = 150` cycles at DDR4-1866. That is about 643 ns,
   below the 1 us requirement and matching the experiment that worked.
3. Arbitration order becomes: real scan read, keepalive read, real write.
4. `keepalive_want` is true only when:
   - `running`
   - `!flush_active`
   - `!scan_want`
   - `read_gap_counter >= KEEPALIVE_THRESHOLD`
   - `outstanding < MAX_OUTSTANDING`
   - the read-tag queue is not full
5. Never issue keepalive reads during `flush_active`.
6. Issue dummy reads to the bank not currently being written:
   `keepalive_addr = wr_bank ? BANK0_BASE : BANK1_BASE`.
7. Increment `outstanding` for both real and dummy reads.
8. Advance `rd_addr`, `rd_issue_count`, and `scan_active` only for real scan
   reads.
9. On `c0_ddr4_app_rd_data_valid`, decrement `outstanding` for both real and
   dummy completions, but push into `beat_fifo` only when the matching return
   tag says "real scan read".

### Phase 2 - replace the XPM tag FIFO with a tiny explicit tag queue

Do not reuse the previous FWFT tag FIFO shape. Use a small register-ring queue
for read-return tags:

- depth 32 or 64
- one bit per accepted read command: `0 = real scan`, `1 = keepalive`
- push on every accepted read command
- pop on every `c0_ddr4_app_rd_data_valid`
- classify the current return from `tag_mem[tag_head]` before advancing the
  head pointer
- set sticky underflow/overflow flags if the queue ever mismatches hardware

This avoids any ambiguity about FWFT `dout` timing.

### Phase 3 - hardware acceptance

After synth/impl/bitgen:

1. Capture at least 10 write-phase ILA windows.
2. Confirm max accepted-read gap is below 1 us in every capture.
3. Confirm `flush_active` always clears.
4. Confirm `rd_tag_count` tracks `outstanding` and no tag overflow/underflow
   fires.
5. Confirm dummy completions do not assert `beat_fifo_wr_en`.
6. Confirm the display is not black and renderer starvation stays at zero.
7. Use a real frame-sequence/temporal-variance check, not only small ILA
   uniqueness samples, to judge whether the read corruption is gone.
8. Capture direct USB3 frames and re-run the column-period analysis. The 32-px
   artifact peak and green/magenta glitch density should collapse along with
   the ILA read-gap fix.

## Fallbacks

If keepalive v2 closes the read-gap and the image is still corrupted, then the
MIG's DQS gate is still unstable even with app-level reads inside the documented
cadence. At that point:

1. Enable MIG debug signals if possible and inspect internal gate-tracking /
   `gt_data_ready` visibility.
2. Try a post-cal DQS-gate coarse-tap nudge through RIU/XSDB if accessible.
3. Revisit DDR rate only as a secondary search, not the main fix.
4. Use unpack-stage interpolation/masking only as a temporary display
   mitigation, not as root-cause closure.

## Phase 3 result (2026-07-08): keepalive v2 hardware-verified clean, VT-tracking gap fixed, chroma corruption eliminated -- but the dominant 32px luma striping persists

Implemented v2 exactly per phases 0-2 above: `read_gap_counter`, flush-gated
`keepalive_want`/`keepalive_launch`, an explicit register-ring `rd_tag_*`
tag queue (not an XPM FWFT FIFO), scan-walk/`beat_fifo_wr_en` gating on
`cmd_is_keepalive`/`rd_return_is_keepalive`, and the ILA probes listed in
phase 0 (`dbg_ila_0` widened from 25 to 28 probes). First hardware pass at
`KEEPALIVE_THRESHOLD=150` cycles was NOT a regression (display stayed live,
no black screen) but one of 10 ILA captures showed a 1023.9ns worst-case
gap, just over the 1us limit -- root-caused via the new probes to a ~87-cycle
(~372ns) stall in `cmd_pend` waiting on `c0_ddr4_app_rdy` right after
`keepalive_want` correctly fired, almost certainly the MIG servicing a
periodic DDR4 refresh (tRFC), which no app-level arbitration change can
avoid. Lowered `KEEPALIVE_THRESHOLD` to 60 cycles (~257ns) to leave margin
for a repeat of that stall; rebuilt, reprogrammed, recaptured.

**Full Phase 3 acceptance result on the tuned build (10 ILA captures, 2048
samples each, `dbg_ila_0` triggered on `write_retiring`):**

| Check | Result |
|---|---|
| Max accepted-read gap < 1us in every capture | **PASS** -- worst 634.0ns (148 cycles), 0/10 over the 1000ns/233.4-cycle limit (vs. pre-fix worst 6344.6ns, 4/10 over) |
| `flush_active` always clears | **PASS** -- 0/10 captures ended mid-flush |
| `rd_tag_count` tracks `outstanding` | **PASS** -- 0 mismatches across all 10x2048=20,480 pooled samples |
| No `rd_tag_overflow`/`rd_tag_underflow` | **PASS** -- never fired in any capture |
| Dummy completions never assert `beat_fifo_wr_en` | **PASS** -- 0 violations across 554 pooled read events (300 keepalive, 254 real) |
| Display not black | **PASS** -- confirmed via direct USB3 capture (see below), all six EO tiles visible with real scene content |

Every hardware safety/correctness criterion this phase set out to check
passed cleanly. The keepalive v2 redesign (flush-gating + the explicit tag
ring buffer replacing the v1 XPM FWFT tag FIFO) did not reproduce the v1
blank-screen regression.

**Direct USB3 capture + column-autocorrelation re-analysis, using the exact
same methodology re-run against both the pre-fix baseline
(`captures/usb3_direct_20260708_184115/`) and the new keepalive-v2 capture
(`captures/usb3_direct_kv2_20260708_203326/`) for a true apples-to-apples
comparison (the original baseline JSON was produced by a different,
undocumented script, so it was re-analyzed with the new script rather than
trusted as directly comparable):**

| Metric | Pre-fix baseline | Keepalive v2 (tuned) |
|---|---|---|
| green chroma-glitch pixels | 6.07% / 6.31% / 2.44% (3 frames) | **0.0% / 0.0% / 0.0%** |
| magenta chroma-glitch pixels | 0.24% / 0.24% / 0.12% | **0.0% / 0.0% / 0.0%** |
| Column autocorrelation at 32px lag (the burst-periodic stripe signature) | 0.9726 | 0.9293 |

**Interpretation**: the VT-tracking read-gap fix eliminated the chroma
(green/magenta) corruption specks entirely -- a real, hardware-confirmed
win, consistent with those being the more sporadic/intermittent corruption
component that a periodic-read-gap-driven gate drift would produce. But the
32px-periodic luma striping -- the original, dominant, ~100%-of-bursts
deterministic artifact characterized back in plan sections 16-18 (first two
64-bit chunks of every 32-pixel/512-bit read burst wrong) -- is only
marginally reduced (0.9726->0.9293, roughly a 4-5% drop in autocorrelation
strength) and remains clearly visible on the live monitor and in direct
USB3 captures. This matches this document's own "Fallbacks" section
predicting exactly this outcome: closing the read-gap does not by itself
guarantee the DQS gate is otherwise stable.

**Conclusion: keepalive v2 is a genuine, hardware-verified partial fix --
ship it (it strictly improves image quality with no observed downside) --
but it does NOT resolve the core vertical-stripe artifact.** The dominant
remaining mechanism is almost certainly the same first-beat-of-burst
DQS-gate misalignment identified in plan section 20/PG150's documented
failure class, not further app-level read-cadence tuning. Per the
Fallbacks section: next steps are (1) enable MIG debug signals and inspect
internal gate-tracking/`gt_data_ready` visibility, (2) a post-cal DQS-gate
coarse-tap nudge through RIU/XSDB if accessible, before revisiting DDR rate
sweeps or unpack-stage masking again.

## Phase 3 follow-up (2026-07-08, same day): a 10-frame USB3 capture surfaced a real, previously-uncharacterized prefill-timing side effect

The 3-frame USB3 capture above was too small a sample to catch this. Asked
to capture more output frames, a 10-frame direct USB3 capture (same
methodology) showed 3 of 10 frames as a solid, flat, uniform color across
the entire active area (only 2 distinct RGB values in the whole 1920x900
region -- real image content never looks like that). Reverse-matching the
measured color (BGR mean (255,189,255)) against every hardcoded renderer
diagnostic-color constant in `PanoramaBase_HdDdrRenderer` (BT.601 YCbCr->RGB
on each {Y10,C10} candidate) identified it precisely: predicted RGB for the
"orange" state (`Y=900,C=700`, meaning *"a committed frame exists but the
renderer has not yet reached the pix_fifo prefill threshold"* --
`cur_inside_window && frame_valid_sync && !stream_started`) is
(255,175,255), error 13.7 against the measured value -- next-closest
candidate (the "magenta: data returned but nothing unpacked" state) is
almost 5x worse. This is not DDR data corruption at all; it is the
renderer's own designed fallback display firing.

Confirmed directly on hardware via `dbg_ila_1` (renderer-side ILA, already
present, no rebuild needed): armed a trigger on exactly
`cur_inside_window && frame_valid_sync && !stream_started`, and it fired
**immediately** (not a rare event). The captured window (8192 samples,
~110us at 74.25MHz rd_clk) showed the condition held continuously for the
entire post-trigger window -- at least 4 full display lines (v_cnt 0-3)
with zero recovery inside that window -- and `pix_empty` was asserted 100%
of those same samples, meaning `pix_fifo` was not merely under its prefill
threshold but genuinely empty: the scan/write engine had not delivered a
single pixel by the time active video began for that frame.

**This is a real, hardware-confirmed side effect of the keepalive
mechanism competing for the single held-command issue slot** (`cmd_pend`):
this design issues one DDR4 command at a time, held until `app_rdy`/
`app_wdf_rdy` accept it (PG150's required handshake). A keepalive read
occupying that slot -- especially one that gets stuck waiting through a
refresh stall (see the threshold-tuning discussion above, ~87 cycles
observed) -- can delay a real scan read from being issued during that same
window, exactly the way a write already could before keepalive existed.
With keepalive now also competing for that slot, pix_fifo's refill can
fall further behind its prefill deadline on some frames than it did
before. **This has not been proven to be strictly new** (no directly
comparable pre-keepalive `dbg_ila_1` capture exists with this exact
trigger to compare against), but it is a structurally plausible and
sufficient explanation, and the instant/repeated triggering suggests it is
not rare.

**This does not invalidate the Phase 3 acceptance results above** -- the
read-gap, tag-queue, and `beat_fifo_wr_en` correctness checks are all still
true and unaffected; this is a distinct, softer symptom (a multi-line
placeholder flash on some frames, self-correcting frame-to-frame, not a
lockup) that the original acceptance checklist did not test for, because it
targeted the v1 blank-screen failure mode specifically.

**Not yet fixed. Candidate next steps, not yet attempted:**
1. Give the scan engine more head start: increase how many lines before
   active video `FRAME_TOGGLE_LINE` fires (currently 25 lines,
   `PanoramaBase_HdDdrRenderer`), or lower `pix_fifo`'s
   `PROG_EMPTY_THRESH` so streaming can arm sooner with less buffered data.
2. Reduce keepalive's contention for the single issue slot -- e.g. skip a
   keepalive launch if `scan_active` is true and behind schedule, or track
   the shared slot's utilization directly rather than only gating on
   `!scan_want`.
3. Add a sticky ILA/dbg counter for how many display lines are lost to this
   condition per frame, to quantify severity precisely rather than relying
   on a single capture's snapshot before deciding how urgent a fix is.

## Side note

`docs/DDR4_PINMAP.md` and `constraints/ddr4_sub64_firstpass.xdc` currently do
not agree on several DDR package pins. The live behavior does not look like a
gross pin-map failure: calibration passes, margins are sane, and the failure is
whole-burst/time-slot coherent. Still, reconcile that documentation separately
so future bring-up work does not chase stale pin data.
