> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](../MSU1-STANDARD.md) for current scope and validation limits.

# Standard-refresh native build evidence

These are experimental standard-refresh profiles. A generated `.rev` means compilation
completed; it does not establish timing closure, board operation or game compatibility.
The preserved prototype and older isolated-refresh studies are separate artifacts.

Current final build source is `e71101fd06a452da53cb0924e1d3701f53133435`.
All three final profiles have completed clean full flows and positive internal
four-corner summaries, plus source-bound conditional I/O/reset/CDC reviews.
See [the final status and exact margins](../STANDARD-MEMORY-STATUS.md). PAL's
minimum setup is only **+0.038 ns**; board operation and global MTBF remain
unverified. Sections below retain the complete chronological history, including
failed and superseded diagnostic placements.

## Routed baseline: fc8dff4

- Source: `fc8dff498d2d3300cc6e855ee3005f7066701863`, detached, no RTL changes during run
- Profile: `msu_standard_ntsc`, device `5CEBA4F23C8`
- Tool: Quartus Lite 21.1.1 Build 850
- UTC: 2026-10-04 10:31:55 through 10:49:09; compile exit 0
- Archive: sibling worktree `standard-fit-ntsc-fc8dff4`, directory
  `projects/output_files/msu1-builds/msu_standard_ntsc-20261004T103155Z-U19oP8`
- The archive contains `build.json`, compile log, full map/fit/STA reports and generated
  RBF/REV hashes. Later lifecycle/configuration fixes are absent from this old snapshot.

| Fitted resource | Used | Available |
|---|---:|---:|
| ALMs | 18,061 | 18,480 |
| Registers | 14,878 | — |
| RAM blocks | 290 | 308 |
| Block-memory bits | 2,227,062 | 3,153,920 |
| DSP blocks | 27 | 66 |

Worst setup slack at slow 1100 mV, 85 C is **-10.398 ns** to the sys clock and
**-5.326 ns** to the original 4x memory clock. The dedicated 5x SDRAM clock's internal
setup is +2.397 ns. The positive internal hold results do not cover missing external
SDRAM input/output delay constraints. This baseline fails internal setup closure.

### Worst-path attribution

The slow85 worst 20 setup paths all originate at WRAM `data_out[5]` and end at
cartridge request/cache metadata or data capture. The worst path has 21.433 ns data
delay, 11.640 ns launch/capture relationship and -0.485 ns clock skew. It crosses:

`WRAM data_out -> SNES bus data -> GSU TX_RESTART/TX_NEED -> owner arbitration ->
dynamic owner address slice -> mapper mux -> cache_hit -> CDC request capture enable`.

The full report shows 18 logic levels. The `pick * 23` address selection inferred a
DSP multiplier and addition, contributing a 3.535 ns cell delay on the worst path.
The reviewed fixed four-way slice removes that arithmetic without changing allocation,
priority, request timing, token matching or response retirement. Its unit synthesis and
28-check evidence are in [rom-owner-mux.md](rom-owner-mux.md). Whole-fit resource/timing
savings are reported below; the whole-core comparison also includes lifecycle/configuration
and I/O-placement changes, so a unit result is not a controlled whole-core area estimate.

The distinct 4x-memory worst path is P65C816 microcode/address and mapper read data
through `BUSA_DO`/`WRAM_DI` to WRAM `latched_data_in[0]`, with 16.262 ns data delay and
-0.584 ns skew. It includes real A-to-$2180 DMA/HDMA writes, so it cannot be dismissed as
an unused read-only capture or hidden using an unproved multicycle exception.

Read-only timing extraction is archived in sibling `standard-sdram-io-audit`, under
`build/io-extract-ntsc-fc8dff4-2/slow85-worst20-setup.rpt` and
`build/io-zero-board-scenario-2/slow85-original-to-c0-worst10-setup.rpt`.

### Physical SDRAM I/O limitation

The routed baseline uses core FFs for all 16 input-sample registers and all 37
DQ/address/control output registers. Only the forwarded clock uses its DDIO output
cell. An independent conditional STA with explicit **zero PCB flight** assumptions
finds slow85 read setup -3.374 ns, command setup -1.846 ns, write-data setup -1.744 ns,
and output-enable setup -2.690 ns. These are conditional modeled windows, not measured
Pocket margins. Real board/device bounds and four-corner hold remain required.

## Routed comparison: 7fa334b

- Frozen source: `7fa334b151cc85a78298626cad8b26ea07f55210`
- Clean detached worktree: `standard-fit-ntsc-case-ioe`
- Profile: `msu_standard_ntsc`, started 2026-10-04 11:18:58 UTC
- Changes include the functional/lifecycle/configuration fixes, fixed owner slice and
  the [standard-only IOE placement candidate](../standard-sdram-ioe-candidate.md)
- Finished 2026-10-04 11:36:19 UTC, compile exit 0, 17 minutes 21 seconds
- Archived summaries/log/source hashes (retained archive: `../evidence/standard-memory-native-7fa334b/REPORT-MANIFEST.json`)
- Only the generated project QSF changed during the run; the tracked RTL remained fixed

| Metric | fc8dff4 baseline | 7fa334b case + IOE candidate |
|---|---:|---:|
| Fitted ALMs | 18,061 | 17,348 |
| Registers | 14,878 | 15,745 |
| DSP blocks | 27 | 24 |
| RAM blocks | 290 | 291 |
| Block-memory bits | 2,227,062 | 2,235,766 |
| Slow85 sys setup / TNS (ns) | -10.398 / -1825.136 | -3.608 / -618.479 |
| Slow85 4x memory setup / TNS (ns) | -5.326 / -209.340 | -5.079 / -166.459 |
| All-corner 5x SDRAM internal setup minimum (ns) | +2.397 | +1.257 |

The design now has 1,132 unused ALMs, compared with 419, but **still fails internal
setup timing**. All reported internal hold checks are positive; the new worst is
+0.074 ns. Positive internal timing at the SDRAM clock is not external pin closure.
Fitter packing reports confirm 16 input and 37 output FFs moved into I/O buffers.
All 16 DQ output-enable packing requests were rejected with synchronous-clear
violations (Warning 176255); their placement and full read/write/OE margins require
separate post-fit extraction. No board-operation claim follows from this bitstream.

### Changed critical-path family

Post-fit extraction shows that the new worst sys path is **not** the original GSU
first-offer cone. It is WRAM `data_out[15]` (or `[7]`) through the SNES bus and P65C816
ALU to status `P[1]`, with 14.640 ns data delay and -3.608 ns setup slack. Other leading
paths end in the CPU A/PC registers. The slow85 sys and memory worst-20 reports and
64-path TSVs are included in the native evidence archive.

The memory path remains real write data: CPU `AddrGen.AAL[3]` to WRAM
`latched_data_in[15]`, 16.061 ns data delay, -5.079 ns slack. A GSU-specific extra
request stage cannot repair the new leading CPU data path, so its separately measured
cycle-changing experiment has not been merged merely because sys slack is negative.
Any WRAM sampling change must prove the actual read-completion/CPU-retirement phases,
byte lanes, repeated transfers and DMA/HDMA behavior before timing constraints change.

The packing candidate does not change SDRAM phase, clock rates, I/O voltage/drive/slew,
RTL pipelines or timing exceptions. Actual FF placement and read/write/OE setup **and**
hold must be checked after the fitter. Internal GSU-path and external SDRAM-path changes
will be attributed separately; this is not a controlled single-factor whole-core fit.

## SPC7110/SDD1/BS-X diagnostic baseline: 7fa334b

A separate full `standard_ntsc_spc` build completed from the same `7fa334b` source,
2026-10-04 11:46:08–11:59:17 UTC (13 minutes 9 seconds), exit 0. Its archived
reports (retained archive: `../evidence/standard-memory-native-spc-7fa334b/REPORT-MANIFEST.json`) record
16,155/18,480 ALMs, 13,253 registers, 216/308 RAM blocks, 1,648,385 memory bits,
and 20/66 DSP blocks. Slow85 setup still fails: 4x memory -2.179 ns/TNS -49.477 ns,
sys -1.848 ns/TNS -72.198 ns; dedicated SDRAM internal setup is +1.651 ns.

**This is not a usable BS-X image.** The full native build exposed a missing inherited
channel-data MIF path and zero-filled that memory. The repair and mapped-memory byte
proof are documented in [bsx-mif-binding.md](bsx-mif-binding.md), commit `c718ad9`.
That repair, the later WRAM timing stages and the output-enable packing control are
absent from this diagnostic snapshot. Its resource/placement numbers are retained as
observations of that exact imperfect source, not as final supported-profile results.

## Interrupted WRAM/OE diagnostic: 955ebe5

The third NTSC diagnostic used frozen `955ebe5` with WRAM read/write stages and
node-specific OE synthesis control, but still the old Save ordering. Quartus map
and placement completed; `quartus_fit` terminated unexpectedly during routing
(Error 293007, whole-flow exit 3) on 2026-10-04 12:46:03 UTC, after 12:16 elapsed.
Failure evidence (retained archive: `../evidence/standard-memory-native-955ebe5-failed/failure-receipt.json`)
retains the source/build manifest and log. It is not a timing or RTL-failure result.

Intermediate packing lists 16 input and 53 output registers, consistent with the
additional 16 OE cells, but no completed fit or four-corner improvement is claimed.
The shell's 496-MB virtual-memory statistic is not the fitter's memory peak. Kernel
logs were unavailable and no per-process kill record was captured. The later global
OOM count of four has no baseline or timestamp and cannot establish causation.

The next final-source build uses optional `MSU1_BUILD_JOBS=1` and
`tools/build_msu1_monitored.py`, recording process-tree samples, waited-child maximum
RSS, system memory and global OOM-counter deltas. Sampling is a lower bound and
shared pages may be counted twice; global counters still do not identify a victim.
The monitor self-test verifies allocation measurement and nonzero-exit propagation.
No old database or unique evidence was removed and the diagnostic is not retried
as a deliverable because its Save lifecycle is already superseded.

## Native elaboration scope

`tools/elaborate_memory_ready.sh ntsc|pal|spc` checks the complete production hierarchy
with the actual Quartus mixed-language frontend. NTSC, PAL and the SPC7110/SDD1/BSX
profiles passed Analysis & Elaboration after integration. This caught and repaired the
Verilog-to-VHDL boolean generic encoding and BSX VHDL-1993 sensitivity-list issue.
Elaboration reports are not synthesis-resource, routing or timing evidence.

## Monitored final-source interruption: 982f103

The clean final RTL snapshot `982f103a0d7fa39294b760738ceaed5bb88eddad`
was compiled with `msu_standard_ntsc` and an explicit single fitter processor.
The run lasted 2026-10-04 13:41:02–14:00:45 UTC. Map, placement and routing
completed, but `quartus_fit` terminated during the second post-fitting delay
annotation with Error 293007, whole-flow exit 3. There is no completed fit,
STA or generated bitstream from this attempt.

The failure receipt (retained archive: `../evidence/standard-memory-native-982f103-failed/failure-receipt.json`)
includes exact source hashes, the compile log, generated assignments and all
resource samples. The largest waited child RSS was 2,579,584 KiB; sampled
process-tree RSS peaked at 2,668,524 KiB. Minimum sampled system available
memory was 1,273,228 KiB, with no swap. The global OOM-kill counter increased
from four to five between the last live fitter sample at 14:00:44.132 UTC and
the terminated sample at 14:00:46.137 UTC. This gives a contemporaneous memory
pressure signal, but kernel/cgroup victim records were unavailable, so it is
not a definitive identification of the killed process. The shell's 496-MB
virtual-memory report is again not the fitter peak.

Intermediate packing again reported 16 input and 53 output registers in I/O
buffers. Without a completed routed timing database this is not external I/O
qualification. The whole failed database is retained. The next attempt will
use the identical RTL after the concurrent functional qualification finishes,
with a single fitter processor and resource sampling; no timing exception or
clock reduction is introduced to conceal this tool/execution failure.

## Completed final-source NTSC route: 982f103

The identical clean RTL was rebuilt after the other large qualification runs
finished and completed temporary C++ precompiled-header caches were removed
from RAM-backed `/tmp`. No RTL, frequency or timing exception changed between
the interrupted and successful attempts. The successful single-processor run
lasted 2026-10-04 14:12:35–14:37:19 UTC, whole-flow exit 0.

The full native receipt (retained archive: `../evidence/standard-memory-native-982f103/REPORT-MANIFEST.json`)
records reports, exact source hashes, generated assignments, output hashes and
one-second process/resource samples. Largest child RSS reached 3,412,128 KiB
and sampled tree RSS 3,619,004 KiB. The global OOM count remained five.

| Fitted resource | Used | Available |
|---|---:|---:|
| ALMs | 17,390 | 18,480 |
| Registers | 15,420 | — |
| RAM blocks | 291 | 308 |
| Block-memory bits | 2,236,790 | 3,153,920 |
| DSP blocks | 24 | 66 |

Internal setup still fails in the slow corners: slow85 sys **-1.519 ns**
(TNS -4.064 ns), original 4x memory **-1.517 ns** (TNS -39.040 ns).
The dedicated SDRAM domain's minimum setup is +1.186 ns. Across all four
corners the minimum internal hold is +0.090 ns, recovery +5.040 ns and removal
+0.158 ns. These numbers show the WRAM stages materially reduce the earlier
violations, but are not a claim of closed timing. Remaining path attribution
and the complete physical SDRAM/Save CDC review are required before changing
RTL or accepting the generated image.

Production STA reports zero unconstrained clocks but still 54 unconstrained
input ports (222 input paths) and 106 unconstrained output ports (161 output
paths). Therefore the positive SDRAM-domain result does not validate its
external read/write/output-enable windows; those require the explicitly
conditional four-corner I/O analysis and actual board/device bounds. No Pocket
hardware result is available. PAL and SPC profiles also need final-source
native qualification rather than inheriting this NTSC result.

### Remaining paths after WRAM stages

The locked original-SDC extraction completed with all protected source, QSF, SDC
and compiled report hashes unchanged. All 780 path summaries and slow-corner
full C0/C1 reports (retained archive: `../evidence/standard-memory-native-982f103/internal-paths/ARCHIVE-MANIFEST.json`)
identify two remaining path families. All table values are setup slack in ns.

| Endpoint group | slow85 | slow0 | fast85 | fast0 |
|---|---:|---:|---:|---:|
| C0 memory | -1.517 | -1.206 | +5.420 | +6.057 |
| C1 sys | -1.519 | -1.213 | +5.788 | +6.341 |
| C4 SDRAM | +1.186 | +1.222 | +5.835 | +6.100 |
| Request metadata | +4.874 | +5.298 | +15.184 | +16.109 |
| Request data | +5.128 | +5.511 | +15.451 | +16.338 |
| Cache response metadata | +5.274 | +5.717 | +15.284 | +16.206 |

The remaining C0 path is **read-request decode**, not the already staged WRAM
write packet: CPU `MCode.MI.addrInc[0]` traverses the P65 address output, CPU PA
byte mux and SWRAM `PA == 0x80` comparison into PSRAM read-start state, address
and ADV logic. Its worst data delay is 12.456 ns, setup relationship 11.640 ns,
clock skew -0.581 ns. Arbitrarily delaying the entire read request by half a sys
period could miss the existing read-return sample before fastest CPU retirement;
any repair needs phase proof or a cycle-neutral combinational decode rewrite.

The remaining C1 path starts at **ARAM**, not WRAM: `aram.data_out[5]` traverses
the SMP input mux and SPC700 shift/data/ALU/zero-condition logic to `JumpTaken`.
It has 17 logic levels, 12.515-ns data delay, 11.640-ns setup relationship and
-0.524-ns clock skew. An APU read-return stage cannot inherit the WRAM phase
proof; DSP/SPC700 consumers and their actual capture edges must be checked.

The original WRAM-to-GSU/cache/CDC bottleneck is now positive in all four
queried corners. Its source is the sys falling-edge WRAM return stage and its
available relationship is 23.280 ns. This removes the demonstrated need for
the cycle-changing GSU registered-first-offer alternative; that alternative
remains unmerged. This per-cone observation does not close the two failures above.

## Timing-cut NTSC route: aed6dd7

The clean source `aed6dd78f7852304d25c396763f47ae14d549b21` (hardware
commit `64b5b51`) includes the verified combinational WRAM predecode, independent
DSP ARAM return stage, and reader reset-stage preservation. Single-processor
full flow completed 2026-10-04 15:20:56–15:44:10 UTC, exit 0. Exact native
and original-SDC path evidence (retained archive: `../evidence/standard-memory-native-aed6dd7/REPORT-MANIFEST.json`)
retains source/assignment/report/output hashes and resource monitoring.

| Metric | Value |
|---|---:|
| ALMs | 17,391 / 18,480 (94%) |
| Registers | 15,439 |
| RAM blocks / bits | 291 / 2,236,790 |
| DSP blocks | 24 |
| Slow85 C1 sys setup / TNS | +2.873 / 0 ns |
| Slow85 C4 SDRAM setup / TNS | +1.195 / 0 ns |
| Slow85 C0 memory setup / TNS | **-0.308 / -3.042 ns** |
| Slow0 C0 memory setup / TNS | **-0.283 / -2.791 ns** |
| Four-corner minimum hold / recovery / removal | +0.106 / +5.332 / +0.237 ns |

The clock domains other than C0 are positive in all reported setup corners.
The remaining C0 violations are ten WRAM PSRAM state-register endpoints, all
using a synchronous-clear-derived mapped path. The slow85 first path is CPU
`MI.addrInc[1]` through the parallel `PA_WMDATA` predicate and PSRAM control,
then two state-control LUTs to `state[4]_NEW_REG38|sclr` and the derived
`state[4]_OTERM39` output. Total data delay is 11.282 ns against the unchanged
11.640-ns relationship, with -0.546-ns skew. The mapped SCLR-to-output cell
contributes approximately 0.936 ns. Separate CE, busy, ADV and address endpoints
are now positive (+0.236, +0.502, +0.568 and +0.780 ns respectively).

This is still a timing failure, however small its magnitude. A precisely scoped
state-register synchronous-control mapping experiment is being evaluated; no
period relaxation, false path, new CPU cycle or clock reduction has been used.
The independent SDRAM I/O and Save CDC physical review must also bind this exact
fit rather than inherit the earlier image's placement.

The fitter's maximum observed/waited RSS was 3,405,688 KiB, sampled process-tree
peak 3,614,352 KiB, with no global OOM-counter increase. Original databases,
reports and the interrupted earlier attempts remain preserved. This generated
image is not a hardware-qualified release; PAL/SPC final profiles remain open.

## Internally closed NTSC route: 0da938e

Frozen source `0da938eb1eaaefc6ff23347568cd69a8240e4f37` adds only the
[exact eight-register WRAM synthesis-control steering](../wram-state-sync-control-evidence.md)
to the preceding hardware configuration. All production RTL/QIP/SDC bytes remain
unchanged. Universal mapped state/pad-driver equivalence, real vendor-atom
NTSC/PAL edge simulations and profile ownership/switch tests accompany it.

The clean single-processor `msu_standard_ntsc` full flow completed
2026-10-04 16:04:51–16:28:26 UTC, exit 0. Full native receipt and reports (retained archive: `../evidence/standard-memory-native-0da938e-ntsc/REPORT-MANIFEST.json`)
record 17,421/18,480 ALMs, 15,365 registers, 291 RAM blocks, 2,236,790 block-memory
bits and 24 DSP blocks. The generated REV is 2,127,624 bytes, SHA-256
`1c24a1441d43b7aa26b502fb5f4e915ec7ecf26366259164643909d090debf51`.

**All reported internal timing checks are now positive in all four corners,
with zero TNS.** Slow85 setup: C0 +0.341 ns, C1 +2.969 ns, dedicated SDRAM C4
+0.979 ns. Global minimum hold is +0.102 ns, recovery +5.227 ns and removal
+0.242 ns. No clock, CPU cycle, multicycle exception or false path was changed
to obtain these results. Runtime resource monitoring shows no OOM-counter
increase; the complete database and earlier failed/negative snapshots remain.

This is internal STA closure for this exact NTSC image, not board signoff.
Production constraints still leave external pin paths unconstrained. The
source-matched conditional SDRAM I/O/reset/CDC review, actual Pocket tests, and
same-source PAL/SPC full builds are separate requirements and cannot inherit
this image's placement or margin. The build manifest therefore retains its
conservative `hardware_verified: false` and unverified-bitstream state.

## Same-source PAL route: 0da938e

The clean `msu_standard_pal` build from the exact NTSC source `0da938e`
completed 2026-10-04 16:29:52–16:53:11 UTC, exit 0. It uses 17,368 ALMs,
15,431 registers, 291 RAM blocks, 2,236,790 memory bits and 24 DSP blocks.
The full PAL receipt and original-model paths (retained archive: `../evidence/standard-memory-native-0da938e-pal/REPORT-MANIFEST.json`)
show that **NTSC closure does not transfer to this placement**:

- C0/C1 slow85 setup are positive, +0.488/+2.936 ns
- Dedicated C4 setup fails at slow85 -0.205 ns and slow0 -0.231 ns
- C4 hold fails at fast0 -0.026 ns; all other reported hold groups are positive
- Recovery/removal minima remain positive, +4.331/+0.259 ns

The setup path is `engine.init_count[11]` through the INIT_READY comparison
and selector into the packed `dram_dqm[0]` output FF. At slow0 its data delay
is 10.372 ns, edge relationship 9.392 ns and skew +0.869 ns.
The hold path is distinct: `crossing.request_data_hold[9]` (C1) to
`crossing.mem_data[9]` (C4), with a 0-ns coincident-edge relationship,
0.710-ns data delay, +0.676-ns skew and the normal +0.060-ns hold uncertainty.
It is still a normally timed mailbox-payload path, not a FIFO exception or
reset-report classification artifact.

Optimize Hold Timing is already All Paths and multicorner optimization is on.
Although the configured effort is Auto Fit, the actual log states that no
optimizations were skipped. These two failures remain open: neither a relaxed
uncertainty nor an unproved false/multicycle exception is used to hide them.
The generated PAL image must not be presented as timing-qualified. Its complete
DB/logs are preserved for controlled placement or proven logic refinement.

## Same-source internally closed SPC route: 0da938e

The clean `standard_ntsc_spc` build completed from `0da938e` on
2026-10-04 16:54:34–17:16:28 UTC, exit 0. Full native receipt (retained archive: `../evidence/standard-memory-native-0da938e-spc/REPORT-MANIFEST.json`)
includes the complete fitter settings report. Utilization is 16,141 ALMs,
12,984 registers, 216 RAM blocks, 1,649,409 block-memory bits and 20 DSP blocks.
All reported internal corners pass with zero TNS: setup minimum +0.869 ns,
hold +0.085 ns, recovery +5.234 ns and removal +0.227 ns. Slow85 C0/C1/C4
setup are +0.934/+3.067/+1.823 ns respectively.

This image actually reads the repaired BS-X `bsx121-124.mif`. The remaining
550-source-word versus 1024-hardware-word warning explicitly zero-fills the
last 474 bytes, matching the earlier mapped-content proof. It is not the old
missing-file/all-zero diagnostic. No Pocket execution, external-pin or global
MTBF qualification is inferred from these native results.

The corresponding PAL `0da938e` placement still fails two paths. A new clean,
versioned PAL Standard Fit/seed2 experiment is in progress, keeping the three
`0da938e` results intact. Final profile selection and source provenance must be
updated only from completed runs rather than relabelling these checkpoints.

## Controlled PAL placement closes internally: e71101f

The single declared Standard Fit/seed2 experiment completed from clean
`e71101fd06a452da53cb0924e1d3701f53133435`, 2026-10-04
17:17:26–17:39:44 UTC, exit 0. Full native receipt (retained archive: `../evidence/standard-memory-native-e71101f-pal/REPORT-MANIFEST.json`)
contains the complete fitter report and verifies its byte hash against
`build.json`. Actual settings are seed **2**, **Standard Fit**, Optimize Hold
Timing **All Paths**, and Optimize Multi-Corner Timing **On**.

All internal summary checks are positive in all four corners, with zero TNS.
The minimum setup is **+0.038 ns** (slow85 C0): this is a small margin, not one
to round away or call generous. Slow85 C4/C1 setup is +0.622/+3.677 ns.
Minimum hold/recovery/removal is +0.107/+4.929/+0.191 ns. Utilization is
17,377 ALMs, 15,403 registers, 291 RAM blocks and 24 DSP blocks.

No RTL, command/response edge, frequency, hold optimization or timing exception
changed. The unsuccessful seed1/Auto Fit placement and its exact negative
reports remain preserved. This result does not erase those failures or imply
that every placement passes. No further seed search is planned after this
controlled passing result unless a separate physical issue is found.

The source-matched [conditional I/O/CDC audit](../standard-pal-sdram-save-cdc-e71101f.md)
has completed. It preserves the +0.073-ns minimum conditional read-hold margin,
all 260 original evidence payload hashes and the raw PLL/global-MTBF limitations.
The same clean `e71101f` NTSC/SPC profiles are being rebuilt for consistent
delivery provenance. Actual Pocket behavior, PCB-delay bounds and
global MTBF remain unverified. The generated PAL REV has SHA-256
`62801ba77a57912ca75031e7fd0d2d5d60a615f6d6df426953b0665d0ed63210`.

## Final source-matched NTSC: e71101f

A fresh clean build of `msu_standard_ntsc` from the same `e71101f` source
completed 2026-10-04 17:41:32–18:04:27 UTC, exit 0. The native receipt (retained archive: `../evidence/standard-memory-native-e71101f-ntsc/REPORT-MANIFEST.json`)
retains the full fitter report and its exact settings/hash: seed **1**,
**Auto Fit**, hold **All Paths**, multicorner **On**. All 124 internal summary
rows are nonnegative with zero TNS. Minimum setup/hold/recovery/removal is
**+0.341/+0.102/+5.227/+0.242 ns**; minimum pulse width is +0.582 ns.

Utilization is 17,421 ALMs, 15,365 registers, 291 RAM blocks and 24 DSP blocks.
The sampled process-tree RSS peak was 3,620,900 KiB; the largest waited child
was 3,412,768 KiB, and the observed global OOM counter did not change. These
resource measures have the sampling/shared-page limitations recorded in the
receipt. The generated REV SHA-256 is
`6bdf79ddf9bc2961ab7d3f460ad37c813831dcb1bf61a0027661efb0f17cd8ee`.

The [final placement I/O/reset/CDC review](../standard-ntsc-sdram-save-cdc-e71101f.md)
has completed, with 284 hash-verified payloads. Its original per-corner
metastability outputs remain preserved without a global MTBF claim. Earlier
`0da938e` checkpoints are retained, not relabelled as these final builds.

## Final source-matched SPC: e71101f

The last fresh profile, `standard_ntsc_spc`, completed 2026-10-04
18:15:01–18:36:27 UTC, exit 0, from the same clean `e71101f` source.
Native receipt (retained archive: `../evidence/standard-memory-native-e71101f-spc/REPORT-MANIFEST.json`).
Actual seed **1**, **Auto Fit**, hold **All Paths**, multicorner **On** are
verified from the retained full fitter report, SHA-256
`bdb473f0fa881792be1b042c1dc7c4b44cff3372a39e806c978e0bfd81189d6c`.

All 124 internal summary checks are nonnegative with zero TNS. Minimum
setup/hold/recovery/removal is **+0.869/+0.085/+5.234/+0.227 ns**. Utilization
is 16,141 ALMs, 12,984 registers, 216 RAM blocks and 20 DSP blocks. The
correct BS-X `bsx121-124.mif` was read; the explicitly reported 550-to-1024
word depth difference zero-fills the remaining 474 bytes. The REV SHA-256 is
`97392c8f14b19b1b0201c7447c83fd44174d1d87b4520ccf7f1d98a9688fbb84`.

To fit the remaining workspace, this final checkout omitted only tracked
`docs/` content using sparse-checkout patterns `/*` and `!/docs/`. All other
tracked files, including root/hidden configuration, tools, tests, QIPs and
initialization files, were expanded. Before compilation, all **173** actual
hardware/build files were checked byte-for-byte against committed `e71101f`,
with fingerprint
`a9c619f6a2b1fa60b25dbbd9f5d39ad1f4a57e1c045b546b6c53a02545c41f29`
and clean Git status. The exact sparse patterns and file inventory are retained
in `sparse-source-preflight.json`; no synthesis input was omitted.

Sampled process-tree peak RSS was 3,517,956 KiB, largest waited child
3,310,648 KiB, and the observed global OOM counter stayed unchanged. All three
final profiles now have completed same-source clean builds with positive
internal native timing. The [SPC source-bound physical review](../standard-spc-sdram-save-cdc-e71101f.md)
has completed, with 845 integrity-checked payloads, actual mapper/posted-write
boundaries and compiled BS-X content interpretation plus nine rejection controls.
Its bit-plane interpretation assumption and all board/raw-PLL/global-MTBF
limits are retained. These results do not establish board timing or Pocket
execution.
