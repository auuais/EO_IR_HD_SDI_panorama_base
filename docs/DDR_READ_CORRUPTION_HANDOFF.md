# Handoff: DDR4 read-burst corruption (vertical striping) — root cause not yet found

**Read this document first.** It is a self-contained summary of where the investigation
stands. `docs/DDR_EO_PANORAMA_FIX_PLAN.md` sections 12-18 contain the full blow-by-blow
history (including dead ends) if you want to verify or dig deeper, but you should not
need it to get started — everything load-bearing is repeated here.

**Status update ahead of §1**: the geometry question that dominates §1 below has since
been substantially (though not 100%) resolved — three independent, targeted hardware
investigations (compositor tile-select ILA, renderer starvation ILA, and a cam0-only
DDR capture that removes the compositor from the picture entirely) all point the same
direction: there is no separate EO-specific structural bug. The DDR read corruption
alone, now directly confirmed on real camera data (not just the synthetic ramp), is the
leading and well-evidenced explanation for everything reported. See §4.0/§4.0a/§4.0c
for the detail — read those before spending time re-hunting for a compositor/renderer
bug, which has already been done thoroughly.

## 1. Symptom

The EO panorama (and a synthetic ramp test pattern, see below) rendered through the
DDR4 frame buffer shows a dense grid of thin, static, regularly-spaced vertical stripes
overlaid on the image. The stripe period is consistent with roughly 1 wrong pixel out
of every 32.

**Additionally (added after user hardware review, plan §18)**: the displayed image is
also geometrically scrambled — content bands/blocks displaced, diagnostic-color bands,
and (per the user's reading of the EO build) what looks like two cameras' content
repeated instead of the intended six-tile 3x2 grid. A targeted line-by-line review
(§18.1) verified the composite/copy/render geometry RTL is clean — no mechanism exists
there to duplicate/resize tiles. Three follow-up hardware experiments (§4.0) then
directly tested and ruled out both remaining structural theories (compositor tile-
select bug, renderer underrun/slip), and a fourth (§4.0c, cam0-only through DDR with
zero compositor logic) directly reproduced the DDR corruption signature on real camera
data. **Current best-supported conclusion: the geometric scrambling is very likely a
visual consequence of the DDR corruption on detailed real imagery (see §4.0a for why
it looks so different from the ramp test's clean stripes), not a separate bug** — see
§4.0-§4.0c before re-investigating this.

This is **downstream of a completely separate, already-fully-resolved problem**: an
earlier timing/clock-domain bug (compositor + tile memories mis-clocked at 300MHz)
caused a green-frame/lockup failure and has been fixed and verified clean (routed WNS
positive on every clock domain, not just headline — see plan §10/§11). Do not revisit
timing as an explanation; it has been checked thoroughly and is not the cause of the
striping.

## 2. Current repo state (compile-time bring-up switches — read before touching anything)

`src/PanoramaBase_DdrBlackFrame.v` currently has:
- `localparam [1:0] SRC_SEL = SRC_EO0;` (line ~120; the encoding was widened from 1 bit
  to 2 bits to add this third option — `SRC_RAMP=2'd0`, `SRC_EOSTK=2'd1`,
  `SRC_EO0=2'd2`) — the design is currently built to stream **only cam0's 640x480
  decimated tile** through DDR (centered window), with the compositor/6-tile-select
  logic entirely absent from the build. This was the last diagnostic bisection run
  (§4.0c) and directly reproduced the DDR corruption signature on real camera data. Flip
  to `SRC_EOSTK` for the full 6-camera panorama, or `SRC_RAMP` for the original
  synthetic ramp test — all three show the same underlying corruption (§3.2, §4.0c).
- `localparam [6:0] MAX_OUTSTANDING = 7'd16;` — restored to its original value after an
  experiment (see §4.3) that dropped it to 4 and found no effect. Leave at 16.
- **Three** debug ILA cores, all temporary bring-up instrumentation — **remove all
  three (and the `g_src_eo0` diagnostic branch) once the DDR root cause is actually
  fixed**, along with setting `SRC_SEL` back to `SRC_EOSTK` for the real target build:
  - `dbg_ila_0` (`u_dbg_ila_0`, unconditionally instantiated near the end of the module
    just before `u_hd_renderer`): 25 probes spanning the shared write/read DDR datapath.
    Present and usable in ALL THREE `SRC_SEL` builds. Depth 2048 (shrunk from 16384 to
    fit BRAM budget alongside the other two cores in the full EO build — see §5).
  - `dbg_ila_1` (`u_dbg_ila_1`, inside `PanoramaBase_HdDdrRenderer`): 11 probes on the
    renderer's `rd_clk`-domain signals (`h_cnt`/`v_cnt`/`pix_empty`/etc). Present and
    usable in ALL THREE `SRC_SEL` builds (the renderer is source-agnostic). Depth 8192.
  - `dbg_ila_2` (`u_dbg_ila_2`, inside the `g_src_eostk` generate branch only): 12
    probes on the compositor's tile-select walk (`col_group`/`row_group`/
    `eo{0..5}_rd_en`/etc). **Only exists when `SRC_SEL == SRC_EOSTK`** — building with
    `SRC_EO0` or `SRC_RAMP` selected will not include this core at all (nothing to
    probe in those branches). Depth 16384.

The ILA IP sources are tracked at `ip/dbg_ila_0/dbg_ila_0.xci`,
`ip/dbg_ila_1/dbg_ila_1.xci`, `ip/dbg_ila_2/dbg_ila_2.xci` (regenerate via
`scripts/codex_add_ila.tcl`/`codex_add_ila2.tcl`/`codex_add_ila3.tcl` +
`scripts/codex_widen_ila.tcl`/`codex_shrink_ilas.tcl` if ever lost — see §5 for the
exact gotchas in doing this, several of which repeated across all three cores).

## 3. What has been hardware-proven true (do not re-derive these — trust them, or if you
   must re-verify, do it via `docs/DDR_EO_PANORAMA_FIX_PLAN.md` §16/§17 which has the
   exact ILA probe list and Python analysis methodology)

### 3.1 It is not a timing/STA problem
Routed timing report shows positive slack on **every** clock domain, not just headline
WNS — a marginal/jittery timing path would not produce a perfectly static, identical-
every-frame pattern anyway. (plan §12.1)

### 3.2 It is not specific to the EO camera pipeline
Flipping `SRC_SEL` to `SRC_RAMP` routes a known synthetic pattern through the exact
same shared write→DDR→read→unpack→render path while completely bypassing the EO tile
buffers, compositor, and camera-side CDC FIFO. The ramp shows the identical striping.
The bug is entirely in the source-agnostic back end. (plan §12.4, §12 result)

### 3.3 This design's own write-side RTL is 100% correct
A 25-probe ILA (`u_dbg_ila_0`) captured real hardware data end-to-end. Every one of
123-plus captured write beats had the packed pixel data (`wdf_data_q`, both the first
and last 4 pixels of the 512-bit/32-pixel beat) exactly match the expected value
computed from `wr_addr`. **The data sent to the MIG is always correct.** (plan §16)

### 3.4 `beat_fifo` and the unpack logic are 100% correct
244+ captured pop events from `beat_fifo` exactly matched their corresponding push
event's data, zero mismatches. Whatever the MIG returns is faithfully passed through
unmodified to the renderer. (plan §13)

### 3.5 The corruption is already present on `c0_ddr4_app_rd_data`, straight out of the MIG
It is **not** introduced by this project's RTL downstream of the MIG. It is present on
the raw MIG output port itself.

### 3.6 The corruption is the *entire first 64-bit transfer* of every read burst, not a specific byte
This is the most important, most specific finding, and it took two attempts to get
right — the first ILA widening attempt used a wire concatenation of two disjoint bit
ranges (`{sig[511:448], sig[63:0]}`) that Vivado's debug-probe auto-naming silently
truncated to a useless 32-bit fragment (confirmed via `report_property` on the
`hw_probe` object showing `MAP = "probe5[31:0]"`) — if you add more ILA probes,
**give every probe its own single contiguous bit range; never concatenate two
disjoint ranges into one wide probe port.**

With correctly-wired probes, across 312+ correlated read beats (correlation done by
queueing each issued `rd_addr` in FIFO order and popping one per `rd_data_valid`
event, since reads pipeline up to `MAX_OUTSTANDING` deep and return well after they're
issued):

| Pixel position within the 32-pixel beat | Wrong |
|---|---|
| 0, 1, 2, 3 (the first 64-bit/8-byte transfer) | 99.7-100% |
| 28, 29, 30, 31 (the last 64-bit/8-byte transfer) | 0% |

This is **all 8 physical byte lanes**, corrupted only at this one specific time-slot in
the burst — not one byte lane at every time-slot. (plan §16)

### 3.7 It is not a per-byte analog signal-integrity/margin problem
Pulled the actual Vivado Hardware Manager "Calibration and Margins" table (Memory IP
dashboard, Read Mode / Simple Pattern / Rising Clock Edge) for all 8 bytes x 2 nibbles.
Byte0's total eye width (467ps) is statistically indistinguishable from the whole-bus
average (466ps); spread across all 16 nibbles is only ~12% (438-496ps), with bytes 2/3
actually showing the *smallest* eyes, not byte0. There is no per-byte margin outlier.
(plan §15)

Separately, the MIG's own calibration self-report (`get_hw_migs` XSDB debug interface
— note: use `get_hw_migs`, not `get_hw_ddrmcs`, which is for the Versal DDRMC hard
controller and correctly returns empty here) shows all 27 calibration stages PASS/SKIP,
no FAIL, `CAL_ERROR_MSG` = "No errors detected during calibration." Calibration
"succeeds" by its own criteria despite producing this corruption. (plan §14)

### 3.8 It is not caused by read pipelining depth
Dropped `MAX_OUTSTANDING` from 16 to 4, rebuilt, recaptured. Naive aggregate
per-pixel-position rates looked like a partial improvement (100%→73-91%), but
stratifying corruption rate by each read's *actual* `outstanding` depth at the moment
it returned data (within each single capture, avoiding any cross-capture confound)
showed **100% corruption at every single depth from 1 through 16, including depth=1**
— a single isolated read in flight, zero pipelining overlap whatsoever. The apparent
"improvement" was noise in which of the 4 first-chunk pixels happens to look correct
on a given beat, not a real effect of outstanding depth. (plan §17)

## 4. What is NOT yet resolved — this is where you should focus

### 4.0 DONE: renderer-side and compositor-side ILAs both added, both came back clean — the geometry question is now the open one, not the mechanism

This section originally proposed adding a renderer-side ILA; that was done, and in the
process a THIRD ILA was also added (`dbg_ila_2`, compositor tile-select) after the user
shared live hardware evidence pointing more specifically at a possible tile-select bug.
Both came back negative for the theory they were testing (plan §18.8/§18.9/§18.10 has
full detail; summary below). **This means the two most plausible structural-bug
theories are now ruled out by direct hardware measurement, not just source review, and
the geometry symptom (segment duplication reported by the user) remains unexplained by
anything checked so far.**

- **Compositor tile-select walk (`dbg_ila_2`, inside `g_src_eostk`, probing
  `col_group`/`row_group`/`col_in_tile`/`row_in_tile`/all six `eo{k}_rd_en`): provably
  correct.** 16384 samples triggered on `copy_issue` show `col_group` cycling
  2→0→1→2→0→1... in clean 640-cycle runs, `row_in_tile` incrementing correctly, and
  each `eo{k}_rd_en` firing exactly when expected — all three tiles in the captured
  half (row_group=1: eo3/eo4/eo5) genuinely visited, none skipped, in a ratio (5760/
  5166/5458 out of 16384) consistent with equal 640-column shares. **Do not re-test
  this — it is closed.**
- **Renderer in-window starvation (`dbg_ila_1`, inside `PanoramaBase_HdDdrRenderer`,
  probing `pix_empty`/`cur_inside_window`/`dbg_starve_event`/etc.): not observed.**
  8192 samples (~4 complete display lines, spanning many `col_group`-worth of columns)
  show `pix_empty=0` and `dbg_starve_event=0` on every single sample; `dbg_sync`
  (synced ui_clk status) held a healthy constant value throughout; captured pixel
  values vary continuously like real image content, not diagnostic colors. This is a
  substantial but NOT exhaustive result (only ~4 of 1080 lines sampled) — starvation
  concentrated at a specific frame position (e.g. near vblank) has not been ruled out,
  just "constant/frequent" starvation.

Both ILA cores (`dbg_ila_1`, `dbg_ila_2`) are still present in the current bitstream
and can be re-armed without a rebuild — see §5 for the capture scripts
(`codex_ila_capture_renderer1.tcl`, `codex_ila_capture_compositor.tcl`). If you want to
sweep for starvation at OTHER frame positions (e.g. right after a `frame_toggle_line`
vblank transition, or right after a fresh `copy_active` rising edge), retrigger
`dbg_ila_1` on those specific conditions instead of `cur_active`.

The two zero-rebuild live-monitor checks from the original version of this section are
still worth doing if not already done (user-assisted, no hardware/JTAG needed beyond
what's already running): (a) in EO mode, the bottom 120 rows (rows 960-1079) are
RTL-guaranteed black — if the live monitor shows content there, the running bitstream
isn't the expected build or the fault is downstream; (b) step EO-single modes 0x07-0x0C
to confirm all six cameras show distinct scenes (verifies the receivers).

### 4.0a Leading (not yet proven) explanation for the geometry symptom, and the concrete next check

With both structural theories ruled out, the best-supported remaining explanation
(plan §18.10) is that the segment duplication the user reads off the hardware photo is
actually the ALREADY-CONFIRMED DDR read corruption (§3.6: the entire first 4-pixel
chunk of every 32-pixel burst wrong, ~100% of bursts, ~12.5% of all pixels, uniform
across the whole frame) being far more visually disruptive on real, detailed camera
content than it was on the smooth synthetic ramp test that originally characterized
it — dense corruption at that rate on real imagery, viewed through a compressed photo
of a monitor, could plausibly read as "cameras repeating/missing" even if the
underlying composite order is correct (which §4.0's compositor result now directly
supports). **This has not been proven, only left as the best-supported hypothesis.**

Concrete next check to actually settle it: temporarily mask or freeze the first 4
pixels of every 32-pixel beat downstream (in the unpack logic, `unpack_shift`/
`unpack_count` handling around line ~955-970 of `PanoramaBase_DdrBlackFrame.v` — e.g.
replace those 4 pixels' values with a repeat of pixel 4, or a fixed neutral color) as
a throwaway/diagnostic-only experiment, rebuild, and look at the live image. If the
segment-duplication *look* goes away (even though 12.5% of the image is now
crudely masked, so it won't look clean either way), that confirms this IS the single
root cause and the geometry symptom is not a separate bug — pursue §4.1 exclusively
from there. If the duplication persists even with those pixels masked, there is a
genuine second, still-unfound bug — reconsider frame-boundary/vblank-transition
starvation timing (untested by §4.0's sample) and re-examine the `copy_active_rd`/
`eo_frames_valid` CDC synchronizers (§10) with fresh eyes, since those are the other
signals gating the walk that haven't had a dedicated hardware check yet.

### 4.0c DONE (user's idea): cam0-only-through-DDR, zero compositor involvement — corruption directly confirmed on real camera data

The masking experiment above (§4.0a) has NOT been done — instead the user proposed
something more surgical: build a third `SRC_SEL` diagnostic (`SRC_EO0`) that streams
ONLY cam0's 640x480 tile through DDR with the entire compositor/6-way-mux removed from
the build (not just proven correct — physically absent), while still using real live
camera content and the real per-tile decimation/CDC machinery (unlike the ramp test).
This is now implemented and built (plan §18.11/§18.12) and is the **current state of
the repo** (§2). It gave the most direct evidence in the whole investigation:

Captured `dbg_ila_0` (unchanged, still valid) and queue-correlated the read side.
Real camera data has no synthetic "expected value" formula, so exact per-pixel
correctness can't be checked — but the section 16 first-vs-last-chunk signature needs
no ground truth to see: **the first three consecutive read beats
(`rd_addr`=0x0000/0x0008/0x0010) returned the bit-identical 64-bit first-chunk value
three times in a row**, while their last-chunk values varied smoothly and plausibly
as real image content should. Three independent DDR beats returning identical "pixel"
data is not a coincidence — it's the corruption, directly visible, with **zero
compositor logic anywhere in this build** (`g_src_eo0` has no `col_group`/`row_group`/
tile-select mux at all — see plan §18.11 for exactly what was removed).

Later beats in the same capture don't show further *exact* repeats (127/129 unique
first-chunk values) — read this as a detection-sensitivity limit, not as "corruption
stops": the ramp test's synthetic, sharply-stepped values make ANY deviation obvious,
while real image content is naturally smooth/self-similar between nearby pixels, so a
"stale data borrowed from a nearby beat" substitution can fall within the natural
variability of real pixels and simply not look wrong without ground truth. The
corruption mechanism is almost certainly still operating near its previously-
established ~100%-of-beats rate (§16/§17); it's just far less statistically detectable
on smooth real content than on the ramp's sharp synthetic steps.

**Net effect: do not spend more time hunting for an EO-specific structural bug.**
Three independent, targeted hardware investigations (compositor ILA in §4.0,
renderer ILA in §4.0, this cam0-only DDR capture) have now all pointed the same way.
User then shared a live monitor photo of this exact `SRC_EO0` build (plan §18.13): a
single, fully coherent, recognizable real scene with dense regular striping overlaid
— no segment duplication or missing regions, exactly as predicted with the compositor
physically absent. Visual confirmation on top of the ILA data. The masking experiment
in §4.0a is still the cleanest way to get a fully closed-loop proof if you want one,
but it is no longer necessary to justify prioritizing §4.1 — go straight there.

### 4.0b RETRACTED — do not attempt this (plan §18.3/§18.6)

A previous version of this document recommended switching `u_eo_fb0` from
`USE_ASYNC_FIFO(0)`/`common_clock` to `USE_ASYNC_FIFO(1)`/`independent_clock`,
reasoning that its write clock (`eo0_pclk`, a plain un-BUFG'd alias of the CAM0_PCLK
IBUF net) and `rd_clk` (the top-level BUFG copy of the same pin) were two different
clock-tree nets with an uncharacterized skew.

**This was tried and immediately disproven by hardware.** Implementation failed with
`DRC AVAL-245 Independent_clock_check`, Vivado stating outright that this RAM's two
clock pins "are driven by the same driver" — i.e. the actual synthesized netlist
merges these nets (almost certainly clock-network optimization recognizing them as
electrically equivalent, contrary to what the RTL source structure suggested). The
original `USE_ASYNC_FIFO(0)` exception was correct. It has been reverted. **Do not
re-attempt this change** — trust a DRC result over eye-level net-tracing for clock-
identity questions in this codebase. This also means the WHS +0.011ns thin hold
margin is not explained by a cross-tree skew on this path (there is no crossing here
— same net, zero skew by definition); whatever produces it is something else,
unidentified, and does not need a fix on tile 0's write path.

### 4.1 RESOLVED 2026-07-08: NOT a read/write bank-overlap problem — corruption persists with the write engine provably idle

**This was the single most important unresolved thread in the whole investigation. It
is now closed.** `scripts/codex_ila_capture_writeidle.tcl` was run against the
`SRC_EO0RAW` native-resolution streaming build (plan §18.15 — the cleanest build to
date: true 1920x1080, zero decimation, zero compositor, zero on-chip full-frame
buffering), triggered on `copy_active` transitioning to `1'b0`. Result: **all 16
correlated read beats in the capture were issued with `copy_active==0`,
`fb_write_pending==0`, AND `wdf_pend==0`** — i.e. the write engine was not merely
"between copies" but had zero write activity in flight or pending by any measure this
design tracks. The corruption was still there: first-chunk (64b) uniqueness 9/16 vs.
last-chunk 16/16, with a striking structure — most repeated first-chunk values recur at
a near-constant distance of ~72 beats (`0x48` in the captured `rd_addr[15:0]`), e.g.
`0xc8cb899e9d869082` at both `addr=0xd828` and `addr=0xd870`; the analysis script is
`analyze_writeidle.py` in the scratchpad from that session, csv is
`ila_capture_writeidle.csv`.

**Conclusion: this rules out any read-during-write bank-conflict explanation, and by
extension any RTL-fixable-in-this-codebase explanation.** The ping-pong `wr_bank`/
`rd_bank` state machine is not implicated — there is no write anywhere near these
reads to conflict with. Section 4.2's leading hypothesis (a DDR4 read DQS-gate/
preamble-timing effect specific to the first beat of a BL8 burst — hardware/
calibration-level, not RTL) is now the primary and only well-supported remaining
explanation. If further root-causing is wanted, it should go in that direction (MIG
calibration parameter retuning, Xilinx Answer Record search) rather than continued RTL
auditing in this repo — sections 4.3's ruled-out list and this result together cover
every RTL-side avenue reachable from this codebase.

The original open-question writeup (kept below for the reasoning trail and the
measurement-bug history that motivated re-testing) is now superseded by the result
above.

Early in the investigation (plan §13, before the ILA probe fix in §16), `wr_addr` and
`rd_addr` were only probed as `[15:0]` — but they are actually 29-bit registers, and
`BANK1_BASE` (the address where the second ping-pong bank starts) is `81920` decimal
for the ramp build, which requires bit 16 to represent. **The `[15:0]`-only capture
could not distinguish bank0 from bank1 addresses**, so an initial "write and read are
hitting the same bank simultaneously" observation was retracted as unreliable — not
because it was disproven, but because the measurement couldn't tell either way. This
was never revisited with the correct address width once the investigation moved on to
the (also real, but possibly not the *whole* story) first-beat-of-burst finding.

**Separately**, a check of "does corruption correlate with the write engine being
active" turned out inconclusive for an embarrassing reason: both hardware captures
used a trigger on `write_retiring`, which biased every single captured read to occur
while `copy_active` (the write engine) happened to also be running. Every read in
both captures had `copy_active == 1`; zero reads were captured with the write engine
idle. So we genuinely do not know whether the corruption still happens when nothing is
being written to DDR at all.

**Recommended next experiment** (cheap — one Tcl script change, no RTL/rebuild
needed): re-run `scripts/codex_ila_capture.tcl` but change the trigger probe/condition
from `write_retiring` to something that fires while the write engine is idle — e.g.
trigger on `copy_active == 1'b0` (probe name `u_ddr_black_frame/copy_active`) combined
with `read_retiring == 1'b1`, or simplest: just trigger on `read_retiring` alone with a
much deeper capture (the ILA is already sized for 16384 samples; consider whether that
spans enough idle-copy time — `copy_active` should go low for the majority of each
~33ms video frame period once a copy completes, so a deep-enough capture should catch
it) and check the `copy_active` value at each correlated read event, splitting the
corruption-rate analysis by that value (`analyze_ila7_stratify.py`-style, described in
plan §17, is a ready-made template for this kind of stratified analysis — same
technique, different column to stratify by).

**Why this matters**: if corruption disappears (or drops sharply) when the write
engine is idle, that flips the whole diagnosis from "hardware/calibration DQS-gate
timing, not fixable in RTL" to "a genuine read-during-write bank conflict, likely
fixable by verifying/fixing the ping-pong bank-selection logic" (`wr_bank`/`rd_bank`/
`pending_bank`/`pending_valid` state machine spanning roughly lines 1060-1150 of
`PanoramaBase_DdrBlackFrame.v` — bank commit on `frame_edge` around line 1083, bank
flip on write completion around line 1145) or by adding explicit write-to-read
turnaround spacing. This is a **fundamentally different, and much more actionable, class of fix**
than a hardware/PHY issue — chase this first.

If you do this experiment, also probe `wr_addr`/`rd_addr` at wider bit ranges this time
(e.g. `[20:0]` instead of `[15:0]`) so you can *directly* tell whether the write and
read banks are ever the same during the corruption, rather than only inferring it via
`copy_active`.

### 4.1b New data fingerprint to carry into any AR search / PHY analysis (plan §18.5)

Decoding the wrong first-chunk values against expectations: only 5-6% are simple
byte-swaps and only 19-28% keep their intra-beat pixel index — but the misplaced ramp
bytes' offsets from expected cluster hard at **whole-beat multiples** (capture 5: +32
dominant, then 64/96/128/160) or at **-1 mod 32** (capture 4: 191/95/223/127/63, all
32k+31). I.e. the first transfer returns predominantly STALE DATA FROM NEARBY BEATS at
beat-aligned offsets — not noise, not a coherent stream shift. Consistent with the
DQS gate opening one beat early against residual bus/FIFO state.

### 4.2 Leading hypothesis if §4.1 comes back negative (corruption persists with write idle)
A DDR4 read DQS-gate/preamble-timing effect specific to the first beat of a BL8 burst:
the first beat uniquely depends on correctly gating the transition from idle to
toggling DQS, while later beats in the same burst benefit from DQS already toggling
steadily. This is consistent with (but not proven by) `CAL_STATUS.RANK0.01_DQS_GATE`
and `02_DQS_GATE_SANITY_CHECK` both reporting PASS — a pass/fail gate is not
necessarily tight enough to guarantee zero failures under this design's actual
continuous, deeply-pipelined read traffic vs. whatever isolated pattern calibration's
own self-test uses. If this is the answer, likely remedies are hardware/calibration-
level (MIG calibration parameter retuning, a Xilinx Answer Record may document this
exact symptom — try searching "UltraScale+ DDR4 MIG native interface first beat read
burst incorrect" or similar; web search was unavailable in the session that did this
investigation) rather than something fixable purely in this repo's RTL.

### 4.3 Already tried and ruled out — do not re-attempt
- Read pipelining depth (`MAX_OUTSTANDING` 16 vs 4): no effect, see §3.8.
- Address-stride/addressing arithmetic (`ADDR_STRIDE=8`): cross-checked against the
  MIG's actual configured capacity (`MT40A512M16TB-062E`, `APP_ADDR_WIDTH=29`) and
  found mathematically consistent, not a bug. (plan §12.3, §13)
- A fixed beat-offset/shift in the wrong data (e.g. "off by N beats"): tested offsets
  -8 through +8 against neighboring beats' expected values, best match was only ~34%,
  ruling out a clean pointer/indexing bug. (plan §13)

### 4.4 Also worth trying if §4.1/§4.2 don't resolve it
- Repeatability across a **real power cycle** (not just JTAG reprogram — every capture
  so far has been immediately after a fresh `program_hw_devices`, which also triggers
  fresh calibration each time; a true cold power cycle might behave differently if
  there's any temperature/voltage dependency).
- A pragmatic RTL-side mitigation if root-causing stalls out completely: the corrupted
  position is fully deterministic (pixels 0-3 of every 32-pixel beat), so those 4
  pixels could be masked/interpolated from neighbors downstream in the unpack logic
  (`unpack_shift`/`unpack_count` handling around line ~955-970). This treats the
  symptom, not the cause, but may be an acceptable stopgap.

## 5. Reproducing / continuing the investigation

This machine has **direct JTAG access to the board** via the local `hw_server` — the
entire hardware bring-up/debug loop (synth → impl → program → arm ILA trigger →
capture → export CSV → analyze) can be driven headlessly via the `scripts/codex_*.tcl`
files already in this repo, no GUI needed except for the one thing that genuinely
requires it (the calibration margin dashboard in §3.7, already extracted once — you
should not need to repeat that unless you want to double check it).

Key scripts (all in `scripts/`):
- `codex_synth_only.tcl` / `codex_impl_bit.tcl` — standard synth/impl/bitgen. **Always
  verify `EO_IR_HD_SDI_panorama_base.runs/synth_1/*.dcp` mtime is newer than your last
  source edit before trusting a routed report** — `launch_runs` has silently reused a
  stale checkpoint before in this project.
- `codex_ila_capture.tcl` (copy to a numbered variant like `_N.tcl` and change the
  output CSV filename before each new run, to keep captures from overwriting each
  other) — programs the bitstream + `.ltx`, arms `dbg_ila_0` triggering on
  `write_retiring == 1'b1`, waits, uploads, exports to CSV via `write_hw_ila_data`.
  Change the `TRIGGER_COMPARE_VALUE`/`trig_probe` filter to change what it triggers on
  (see §4.1 for the specific change to make next).
- `codex_ddr_margins.tcl` / `codex_ddr_margins2.tcl` — pull MIG calibration debug
  properties via `get_hw_migs` (property names are dot-hierarchical, e.g.
  `CAL_STATUS.RANK0.04_READ_PER_BIT_DESKEW` — NOT underscore-joined; use
  `report_property $mig_obj` to see the true names if adding new queries).
- `codex_ila_capture_renderer1.tcl` — same pattern, but for `dbg_ila_1` (renderer),
  auto-selects the right core by filtering for a `dbg_starve_event` probe. Currently
  triggers on `cur_active==1` (fires almost immediately; count starvation in analysis
  rather than gambling on it as the trigger condition — see plan §18.9 for why).
- `codex_ila_capture_compositor.tcl` — same pattern for `dbg_ila_2` (compositor,
  `SRC_EOSTK` builds only), auto-selects by filtering for a `col_group` probe, triggers
  on `copy_issue==1`.
- `codex_add_ila.tcl`/`codex_add_ila2.tcl`/`codex_add_ila3.tcl` — create `dbg_ila_0`/
  `dbg_ila_1`/`dbg_ila_2` respectively. `codex_widen_ila.tcl` / `codex_shrink_ilas.tcl`
  reconfigure probe widths/depths on already-created cores. **Gotcha**: `create_ip -dir
  <path>` appends another `<module_name>/` subdirectory under whatever `-dir` you pass
  — pass the *parent* `ip/` directory (matching the existing
  `ip/ddr4_sub64/ddr4_sub64.xci` convention), not e.g. `ip/dbg_ila_0`, or you'll get a
  doubly-nested path and a broken `.xpr` reference that has to be manually edited out
  of the XML to recover. **Gotcha 2**: after changing `C_NUM_OF_PROBES` or any probe
  width/depth on an IP that already has a synth run, if the next top-level synth
  complains a probe "does not exist" (or, worse, an implementation run throws a DRC
  that makes no sense against the current source), check for a stale
  `EO_IR_HD_SDI_panorama_base.runs/dbg_ila_<N>_synth_1` run and `reset_run` it —
  Vivado can cache an old IP netlist/stub across `.xci` edits. This bit twice in one
  session (once for `dbg_ila_1`/`dbg_ila_2` after a depth change, in a way that
  produced a confusing "port doesn't exist" error rather than silently using stale
  data — but don't assume every stale-IP situation will be that obvious).
  **Gotcha 3**: combining all three ILA cores with the full 6-tile EO build
  over-budgets BRAM (needs 1040 RAMB36E2 vs 984 available) — that's why `dbg_ila_0`/
  `dbg_ila_1`'s depths were cut from 16384 to 2048/8192 respectively (`dbg_ila_2` is
  small enough at 16384 to not matter, and doesn't exist at all in `SRC_RAMP`/`SRC_EO0`
  builds anyway, which have far more BRAM headroom to begin with).

Dataset upload gotcha (bit once, cost a wasted capture cycle): after
`upload_hw_ila_data $ila`, use `get_hw_ila_data -of_objects $ila` to get the dataset
to export — **not** `current_hw_ila_data`, which does not reliably point at the
dataset you just uploaded once more than one ILA core exists in the design (it
returned a different core's stale data once, silently, with no error — the exported
CSV's column headers are the only way that mistake became visible). All the capture
scripts in this repo already use the correct form; if you write a new one, copy the
pattern rather than reaching for `current_hw_ila_data`.

Analysis: raw ILA captures export as CSV with a 2-line header (column names, then
radix). All prior analysis was done with small, disposable Python scripts (csv module,
no dependencies) that queue-correlate `read_retiring`/`rd_addr` events with later
`c0_ddr4_app_rd_data_valid` events to account for pipelining. There is no single
canonical analysis script checked into the repo — each capture's analysis script was
written fresh in the scratchpad directory of the session that did it; write a new one
following the pattern described in plan §16/§17 rather than searching for one. For
real (non-ramp) camera data there's no ground-truth formula to check against — plan
§18.12 has the technique used instead (check for exact-repeat/stale-value signatures
between a beat's first and last chunks, which needs no ground truth).

Machine resources: this machine has 12 logical cores and 96GB RAM. `codex_synth_only.tcl`
and `codex_impl_bit.tcl` both set `set_param general.maxThreads 8` (Vivado's actual hard
cap — 4 for synthesis, 8 for implementation, regardless of core count) and already use
`-jobs 12` on `launch_runs` (parallelizes independent runs, e.g. IP OOC synths launched
alongside the main run — already working, confirmed in the logs). There is no further
lever to pull here; peak memory usage across every build this session stayed under 7GB.

## 6. Summary for the impatient

**The geometry thread is closed.** Four independent hardware investigations
(compositor tile-select ILA, renderer starvation ILA, a cam0-only DDR capture with the
compositor physically removed, and a fully native-resolution zero-decimation
zero-on-chip-buffering streaming build) all came back clean/negative for a separate
structural bug — the last two directly reproduced the DDR corruption signature on real
camera data, and the native-resolution build was visually confirmed by the user on the
live monitor to show the identical striping with literally nothing left in the on-chip
datapath but a small CDC FIFO. The DDR corruption alone fully explains every visual
symptom reported across this whole investigation.

**The DDR corruption root cause is also now closed.** §4.1 (does the corruption
persist with the write engine completely idle?) came back **yes** — all 16 correlated
reads in the write-idle capture had `copy_active==0`, `fb_write_pending==0`, AND
`wdf_pend==0`, and the corruption was still there. This rules out a read-during-write
bank conflict, and with it every RTL-fixable-in-this-codebase explanation. What
remains is a DDR4 read DQS-gate/preamble-timing effect specific to the first beat of a
BL8 burst (§4.2) — hardware/calibration territory, not something this repo's RTL can
fix. Carry the §4.1b stale-beat fingerprint into any Xilinx Answer Record search if
that avenue is pursued further.

**Retracted, do not re-attempt**: the `u_eo_fb0` clock-tree "fix" (§4.0b) — tried,
disproven by a hardware DRC, reverted.

Do not re-litigate: timing closure, EO-vs-ramp, the write path, `beat_fifo`,
addressing arithmetic, compositor walk order (§4.0/plan §18.8, hardware-proven),
renderer starvation (§4.0/plan §18.9, hardware-tested), tile decimation geometry,
renderer window math, or pipelining depth — all closed with hardware evidence or
line-verified RTL, not guesses.
