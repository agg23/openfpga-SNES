> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# PAL Standard Fit / seed 2: source-bound physical audit

## Result and scope

The completed PAL fit for `e71101fd06a452da53cb0924e1d3701f53133435` meets
its **original modeled internal setup, hold, recovery and removal constraints**
in all four corners. The smallest setup margin is only **+0.038 ns**. Both
previously failing C4 paths are independently positive. Actual SDRAM I/O packing,
conditional external timing, Save stage isolation, mailbox payload paths and DSP
return-stage timing have been re-extracted from this placement.

No structural or routed-timing defect was found in the examined two-register
`mem_reset_sync` chain or its 157 matched functional consumers. Its low native
MTBF headline is affected by a directly reproduced chain-identification split.
Raw PLL/reset analog behavior remains outside this numerical timing model.
**Board operation, global CDC and numerical MTBF are not signed off.**

The native archive is
`standard-fit-pal-seed2-e71101f/projects/output_files/msu1-builds/msu_standard_pal-20261004T171726Z-BMB7hm`.
The full fitter report SHA-256 is
`d7a69b389eec08383f1f89632dfa76ab556c305b90cfa1fc65fee136845f9d4b`.
Quartus is 21.1.1 Build 850 Lite, device 5CEBA4F23C8. Native report and build receipt
agree on seed **2**, **Standard Fit**, **All Paths** hold optimization and
multi-corner optimization **On**. All 88 original timing-summary rows agree
with the original detailed STA report.

Relative to 0da938e, HDL/QIP/SDC/MIF inputs are unchanged. Root `generate.tcl`
invokes the new PAL-only `target/pocket/standard_pal_fit.tcl`; the build helper
also records actual fitter settings and report hash. This comparison combines
seed and fitter-effort changes; it does not isolate their separate effects.

All native queries used the completed database and shared project lock. No fit,
production assignment, source or original report was changed. The sole temporary
identification experiment below was kept in memory and never exported to QSF.

## Original internal timing and the small C0 margin

All figures are ns; every reported endpoint TNS is zero.

| Corner | Setup | Hold | Recovery | Removal |
|---|---:|---:|---:|---:|
| slow85 | 0.038 | 0.289 | 4.929 | 0.638 |
| slow0 | 0.207 | 0.281 | 5.086 | 0.535 |
| fast85 | 5.455 | 0.131 | 7.396 | 0.243 |
| fast0 | 5.789 | 0.107 | 7.550 | 0.191 |

The +0.038-ns slow85 path is:

```text
C1: core_top:ic|MAIN_SNES:snes|main:main|SNES:SNES|SCPU:CPU|
    P65C816:P65C816|MCode:MCode|MI.addrInc[0]
 -> C0: core_top:ic|MAIN_SNES:snes|psram:wram|cram_data[7]
```

`cram_data[13]` ties at +0.038 ns. Relationship is 11.740 ns, data delay 10.385 ns,
clock skew -1.197 ns, arrival 18.880 ns and required time 18.918 ns. This is a
real, very small modeled margin, not rounding to a larger guard band. Evidence
includes the complete original full-routing 64-path report, first full path and
per-point TSV; no additional timing exception was introduced.

### Direct checks of the former C4 failures

| Original exact path/check | PAL 0da938e | PAL e71101f |
|---|---:|---:|
| init_count[11] → dram_dqm[0], slow85 setup | -0.205 | +2.226 |
| init_count[11] → dram_dqm[0], slow0 setup | -0.231 | +2.324 |
| request_data_hold[9] → mem_data[9], fast0 hold | -0.026 | +0.465 |

Every one of these exact endpoint pairs was queried for setup and hold in all
four corners, even when absent from the current worst64. All are positive.
Current C4 worst setup is +0.622 ns, `step_count[4] → dram_dqm[0]` at slow85;
worst C4 hold is +0.170 ns, `state.S_REFRESH → state.S_REFRESH` at fast0.
Full worst20 routed reports and the two named pairs' full paths are preserved.

## Actual I/O placement and conditional pin timing

All 16 `dq_sample` FFs are in DDIOINCELL, 37 command/data FFs in DDIOOUTCELL,
and 16 OE FFs in DDIOOECELL: **16 inputs plus 53 command/data/OE outputs**.
The forwarded-clock register halves retain their shared DDIO output cell.
The OE packing result is actual fitted placement, not an assignment count.

The same explicit external fixture as PAL 0da938e is used: native C4 period
9.392 ns; zero PCB clock/read/command/write flight bounds; tAC=5.5 ns,
tOH=2.5 ns, tIS=2 ns, tIH=1 ns; extra setup/hold margins zero. Native FPGA
clock uncertainty remains active. The same-period comparison guard accepted
these identical numeric assumptions.

CL3/BL1 word selection is unchanged: READ is externally sampled at A+2.5,
E2 data-drive reference is A+4.5, physical `dq_sample` captures at A+6, and
internal `read_data` copies at A+7. The latter is not the SDRAM input sample.
Read setup/hold relationships remain **1.5T / 0.5T**, with the narrowly scoped
setup=2 word-selection multicycle and no conventional hold=1 compensation.

| Corner | Read setup | Read hold | Cmd setup | Cmd hold | Data setup | Data hold | OE setup | OE hold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| slow85 | 2.249 | 2.514 | 1.594 | 3.438 | 1.598 | 3.407 | 1.480 | 3.573 |
| slow0 | 2.310 | 2.462 | 1.560 | 3.501 | 1.561 | 3.471 | 1.454 | 3.645 |
| fast85 | 5.392 | 0.243 | 2.035 | 3.698 | 2.025 | 3.676 | 1.975 | 3.722 |
| fast0 | 5.570 | 0.073 | 2.018 | 3.707 | 2.010 | 3.686 | 1.983 | 3.740 |

Minimum read setup/hold changed from +2.260/+0.056 to +2.249/+0.073 ns;
OE setup from +1.451 to +1.454 ns. These are conditional fixture results.
For additional uncertainties Us/Uh and package-pin clock-out plus DQ-return
flight bounds Lmin/Lmax, reads require:

```text
max(0, Uh - 0.073 ns) <= Lmin <= Lmax <= 2.249 ns - Us
```

Positive return-loop flight improves hold while consuming setup. The 0.073 ns
zero-flight value is not measured real-board remaining margin. Output
signal-minus-clock skew bounds are:

| Class | Required minimum skew | Allowed maximum skew |
|---|---:|---:|
| Command/address/DQM/CKE | Uh - 3.438 ns | 1.560 ns - Us |
| Write data | Uh - 3.407 ns | 1.561 ns - Us |
| OE | Uh - 3.573 ns | 1.454 ns - Us |
| Combined write/OE | Uh - 3.407 ns | 1.454 ns - Us |

Real flight, extra jitter/uncertainty, SI, turnaround, loading/slew, receiver
clock pulse width and applicable device/operating conditions remain to be
established. Original production reports retain unconstrained external ports;
this explicitly conditional scenario does not silently complete production SDC.

## Save, reader isolation and normally timed mailbox

The physical reader source head is `FF_X52_Y15_N13`; its **only** register
fanout is `source_release[1]` at `FF_X52_Y15_N53`. The memory head is
`FF_X39_Y30_N28`, with only `memory_release[1]` at `FF_X39_Y30_N56`.
Their tails have 110 and 42 functional register endpoints. All targeted
source-head → datatable setup/hold queries return zero paths. The unintended
first-stage functional fanout found in 982f103 remains absent.

All 13 explicit neighboring control/reset pairs have only their intended next
stage as register fanout and positive four-corner setup/hold. The supplemental
26 dedicated FIFO pointer pairs have minimum +11.743/+0.245 ns, 6 FIFO release
pairs +11.952/+0.223 ns, and 2 engine/RAM-clear pairs +8.050/+0.256 ns.
All **47** examined neighboring pairs pass. Actual complete fanout inventories
are archived, including high-fanout functional tails.

| Release-source group | Minimum recovery | Minimum removal |
|---|---:|---:|
| Queue | 14.089 | 0.965 |
| Host reset | 13.538 | 1.136 |
| Reader | 11.276 | 0.270 |
| Mailbox group | 12.998 | 1.345 |
| Engine/RAM-clear | 4.929 | 0.256 |
| Vendor FIFO | 11.184 | 0.191 |

The mailbox recovery/removal row includes system-side release. It must not be
transferred to the memory-side tail's distinct role described below.

C1↔C4 retains its related 5:1 clocks. Mailbox request and response payloads
are normally timed with setup relationship 9.392 ns and hold relationship 0:
request minima +4.222/+0.212 ns; response +6.258/+0.107 ns. The latter is also
the global minimum hold. Functional payload holding is not used as a timing
waiver. Original clk74↔C0/C1/C4 asynchronous grouping and vendor Gray-pointer
first-stage exceptions remain unchanged, with active/ignored exception reports
retained. No payload false path or multicycle was added.

## DSP return stage

The eight actual DSP RAM_DI FFs and 16-bit ARAM source are present. Four-corner
input/output setup and hold paths are positive:

| Corner | Input setup | Input hold | Output setup | Output hold |
|---|---:|---:|---:|---:|
| slow85 | 8.340 | 0.626 | 6.363 | 24.011 |
| slow0 | 8.391 | 0.581 | 6.568 | 24.082 |
| fast85 | 9.906 | 0.279 | 16.054 | 23.699 |
| fast0 | 10.098 | 0.240 | 16.798 | 23.681 |

Input relationship is 11.740/0 ns to the falling-edge C1 stage; output is
23.480/-23.480 ns. The detailed paths retain launch/latch edges. These are
functional stages on related clocks, not independent asynchronous synchronizers.

## Exact memory-reset source, topology and consumer roles

The unchanged `sdram_transaction_cdc.sv:38–47` shifts constant 1 through
`mem_reset_sync[0:1]`, with raw `hard_reset_n` asynchronous clear. The cart port
combines hard reset with PLL lock; its SNES call site ties hard reset high.
The fitted source is therefore PLL LOCK. Soft reset/mount/flush do not
independently clear this chain. Exact source excerpts are retained.

The actual head/tail are `FF_X43_Y41_N14` / `FF_X43_Y41_N26`. CDB confirms:

- Head D uses a feeder with LUTMASK_SUM `FFFFFFFFFFFFFFFF` and no variable input
  support; the head's sole register fanout is the tail
- Tail SDATA comes directly from head Q, SLOAD is tied VCC, and no D pin is used
- Both clocks are the same C4 CLKENA output, non-inverted
- Both CLRN inputs are from the actual FRACTIONAL_PLL output of type LOCK,
  `locked_wire[0]`, non-inverted

This implements asynchronous assertion and two rising-C4-edge release. CDB
independently matches **all 157** timing-inventory tail consumers:

| Consumer type | Count | Actual asynchronous control |
|---|---:|---|
| Mailbox FFs | 67 | CLRN from raw PLL LOCK |
| Engine FFs | 89 | CLRN from engine release_sync[1] |
| Engine dram_ras_n | 1 | ALOAD from engine release_sync[1] |

All 157 use the same non-inverted C4 clock. None uses the memory-reset tail as
an asynchronous reset source. The tail is a synchronous update/clear guard and
engine handshake qualifier. Engine release remains a separate chain. Physical
duplication makes consumer counts placement-dependent; NTSC's 154 are not
substituted for these 157.

| Corner | Head→tail setup | Head→tail hold | Tail→157 setup | Tail→157 hold |
|---|---:|---:|---:|---:|
| slow85 | 8.156 | 0.551 | 0.624 | 0.668 |
| slow0 | 8.145 | 0.574 | 0.690 | 0.702 |
| fast85 | 8.847 | 0.252 | 5.501 | 0.256 |
| fast0 | 8.870 | 0.237 | 5.816 | 0.241 |

Every consumer is included once per corner/check, using npaths=1024 rather than
only the first 32. All relationships remain normal setup=9.392 ns / hold=0.

The +0.624-ns slow85 tail path is ordinary setup into
`dram_addr[4].D` at `DDIOOUTCELL_X40_Y45_N67`, through `dram_addr~0`,
`pending_write~0`, `dram_addr[9]~3`, and `Selector9~1`. Data delay is 9.381 ns,
skew +0.733 ns, uncertainty 0.120 ns, arrival 17.220 ns and required 17.844 ns.
It is neither head→tail settling nor an asynchronous-reset-pin timing check.

Focused recovery/removal **from** head/tail has zero paths because neither drives
an async-reset pin. Focused checks **to** head/tail also have zero numerical
paths because raw PLL LOCK lacks an ordinary timed source clock. Zero paths are
not a pass. Positive downstream engine/system-side recovery/removal cannot
supply missing raw-LOCK recovery/removal. Neither engine initialization wait
nor init_done gating is used as a blanket exception.

## Native MTBF classification and independent control

The original slow85 headline is 0.0 years / 0.207 seconds, with 158 chains and
57.0% uncalculated. Both reset registers are FORCED heads; the tail's separate
one-register entry uses only 0.624 ns and an assumed 13.31M transitions/s.
The engine release tail is also separately counted, with 1.155 ns downstream
slack. These labels and numbers are not accepted failure-rate predictions.

A separate report-only experiment assigns the exact memory-reset head FORCED
and tail AUTO in memory, recreates the timing view from the same routed database,
loads original SDC and closes with `-dont_export_assignments`. It yields one
**two-register** chain containing head and tail, with reported settling
**8.780 ns = 8.156 + 0.624**. The independent tail entry disappears; total chains
become 157. This directly confirms the split-head reporting mechanism on this
PAL placement. The original report remains preserved.

The control still has Source Clock Unknown and the unverified 13.31M/s rate;
its improved per-chain number is not adopted. Even its overall headline remains
dominated by another separately labeled reset tail. The native inventory also
counts 26 FIFO empty/full comparators as third synchronization members and 16
functional ARAM→DSP paths as two-register chains, the latter Not Calculated and
excluded. Functional consumers are not extra independent synchronizer stages.

The examined topology/data timing shows no identified structural or routed
failure. Actual PLL/reset assertion duration and release waveform, valid event/
data-toggle bounds, analog recovery behavior, device voltage/temperature/silicon
applicability and a reliability target remain necessary for numerical MTBF.
This scoped result does not claim global CDC, reset analog or hardware safety.

## Reproduction and retained evidence

Evidence directory: `docs/evidence/standard-pal-sdram-save-cdc-e71101f/`.
Raw successful queries remain in sibling `final-audit-pal-e71101f/`.

- `c0-slow85-first-path.log`, `c0-slow85-full64.log.gz`: exact +0.038 path
- `c4-original-*-c4-*-worst20.log.gz` and `*-prior_*`: full former/current paths
- `conditional-summary.json`, actual I/O inventories and first-path logs
- Full fanout inventories, 47 pair paths, DSP edge paths and native exceptions
- `focus-mem-reset-*`, `mem-reset-atoms-*`, `mem-reset-consumers-*`: exact reset
  topology, every consumer, full path counts and separate classifier control
- `audit-input-provenance.json`, native receipts, original archive hashes and
  independent `provenance-provenance-review.json`

Seven Save preflight tests and ten I/O policy/budget tests pass. The offline
validator checks every manifest entry, including `.txt`, against SHA-256 and
runs isolated positive, missing-file and wrong-hash controls. All payloads are
also checked as Git-tracked before commit. Validation checks the +0.038 margin
and exact old-failure replacements; it is not a board/MTBF acceptance switch.

```sh
bash docs/evidence/standard-pal-sdram-save-cdc-e71101f/reproduce.sh \
  ../final-audit-pal-e71101f-rerun
python3 docs/evidence/standard-pal-sdram-save-cdc-e71101f/validate.py
```
