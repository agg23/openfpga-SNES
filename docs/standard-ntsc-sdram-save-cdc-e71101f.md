> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# Final e71101f NTSC: source-bound I/O, Save, DSP and reset audit

## Result and exact source

The completed `msu_standard_ntsc` fit of
`e71101fd06a452da53cb0924e1d3701f53133435` was independently re-queried.
All original modeled internal setup/hold/recovery/removal checks are positive,
with zero TNS. Actual I/O packing, conditional pin timing, 47 neighboring-stage
pairs, reader isolation, mailbox payload timing, DSP stage timing, memory-reset
physical topology and WRAM state controls match the earlier NTSC 0da938e
measurements. This is fresh evidence bound to the final source, not a transfer
of old timing acceptance to a different compiled image.

No structural or routed-timing defect was found in the examined memory-reset
chain and its 154 functional consumers. **Board operation, raw PLL-reset analog
behavior, global CDC and numerical MTBF remain unverified.**

Archive:
`standard-fit-ntsc-e71101f/projects/output_files/msu1-builds/msu_standard_ntsc-20261004T174132Z-5zK0WK`.
Full fitter report SHA-256:
`479919847d88eb2f02c3e2a4ec8219846f49bf0ad4081c4063f81d0beb801e73`.
Quartus 21.1.1 Build 850 Lite, device 5CEBA4F23C8; native settings and receipt
agree on **seed 1 / Auto Fit / All Paths hold / multi-corner On**.

The generator's PAL-only seed/effort helper does not change NTSC settings.
RTL/QIP/SDC/MIF are unchanged from 0da938e; the generated NTSC QSF differs only
in archive output path. The original STA summary is byte-identical. Independent
review matched all 124 timing rows, including pulse-width entries, against the
original detailed reports. After narrowly normalizing timestamps, absolute paths,
peak memory and runtimes, the detailed STA reports also match.

All native inspections used this completed project's shared lock. No fit,
source/QSF/SDC/PLL change, original report overwrite or atom export was performed.
The separate classifier experiments were in-memory views, closed without export.
All 20 original archive files, 315 critical source files and generated QSF remain
hash-identical to the recorded inputs. Build hardware-verification flags remain false.

## Original internal timing

| Check | Minimum slack | Reported clock/corner entries |
|---|---:|---:|
| Setup | +0.341 ns | 28 |
| Hold | +0.102 ns | 28 |
| Recovery | +5.227 ns | 16 |
| Removal | +0.242 ns | 16 |

Every listed TNS is zero. Native minimum pulse width is +0.582 ns.
The slow85 global setup path is C1 CPU `MCode|MI.addrInc[0]` → C0
`psram:wram|cram_ce0_n`: relationship 11.640 ns, data delay 10.650 ns,
skew -0.529 ns, arrival 13.392 ns and required 13.733 ns. Its complete routed
64-path report, first path and per-point TSV are archived. The global +0.102-ns
hold minimum is in `altera_reserved_tck`, not the mailbox payload.

## Actual SDRAM I/O and unchanged conditional fixture

The placement has 16 `dq_sample` FFs in DDIOINCELL, 37 command/data FFs in
DDIOOUTCELL and 16 OE FFs in DDIOOECELL: **16 input / 53 output-and-OE FFs**.
Both forwarded-clock halves share their DDIO cell. These are actual locations,
not simply packing assignment counts.

The fixture is identical to the previous NTSC audits: native period 9.312 ns;
explicitly zero PCB flight and additional setup/hold margins; tAC=5.5 ns,
tOH=2.5 ns, tIS=2 ns, tIH=1 ns. Native FPGA clock uncertainty is retained.
The same-period comparison guard passes and **all 40 per-corner/class/check
slack deltas against 0da938e are exactly zero** at report precision.

CL3/BL1 selection is unchanged: external READ at A+2.5 (E0), E2 drive/tAC
reference at A+4.5, physical `dq_sample` at A+6 and internal `read_data` copy at
A+7. The copy is not the external sample. Setup/hold relationships are 1.5T/0.5T;
no conventional hold=1 compensation or payload multicycle was added.

| Corner | Read setup | Read hold | Cmd setup | Cmd hold | Data setup | Data hold | OE setup | OE hold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| slow85 | 2.140 | 2.543 | 1.543 | 3.410 | 1.550 | 3.378 | 1.428 | 3.544 |
| slow0 | 2.182 | 2.511 | 1.522 | 3.454 | 1.527 | 3.423 | 1.416 | 3.597 |
| fast85 | 5.282 | 0.267 | 1.982 | 3.668 | 1.977 | 3.646 | 1.924 | 3.692 |
| fast0 | 5.457 | 0.100 | 1.970 | 3.674 | 1.964 | 3.653 | 1.935 | 3.707 |

All figures are ns and conditional on the fixture. For additional uncertainty
Us/Uh and package-pin clock-out plus DQ-return flight bounds Lmin/Lmax:

```text
max(0, Uh - 0.100 ns) <= Lmin <= Lmax <= 2.140 ns - Us
```

Positive return-loop flight improves hold while consuming setup; 0.100 ns is
not a measured real-board remaining hold margin. Output signal-minus-clock
flight skews must satisfy:

| Class | Minimum skew bound | Maximum skew bound |
|---|---:|---:|
| Command/address/DQM/CKE | Uh - 3.410 ns | 1.522 ns - Us |
| Write data | Uh - 3.378 ns | 1.527 ns - Us |
| OE | Uh - 3.544 ns | 1.416 ns - Us |
| Combined write/OE | Uh - 3.378 ns | 1.416 ns - Us |

Real flight, extra jitter/uncertainty, SI, turnaround, pulse width, loading/slew
and device/operating applicability remain missing. Original unconstrained
external ports remain reported; this comparison fixture does not silently
complete production external SDC.

## Reader isolation, Save and normally timed payload

`source_release[0]` at FF_X47_Y12_N26 has only `source_release[1]` at
FF_X49_Y14_N56 as register fanout. `memory_release[0]` at FF_X37_Y30_N35
has only `memory_release[1]` at FF_X36_Y30_N53. Source/memory tails have
103/44 functional register endpoints. All targeted first-stage→datatable
setup/hold queries have zero paths. The old 982f103 first-stage functional
fanout remains absent.

All 13 explicit control/reset neighbor pairs retain only their intended next
stage and pass four-corner setup/hold. Another 26 FIFO pointer pairs have minima
+11.845/+0.233 ns, 6 FIFO release pairs +12.096/+0.238 ns, and 2 engine/RAM-clear
pairs +6.922/+0.339 ns. All **47** examined pairs pass.

| Release-source group | Minimum recovery | Minimum removal |
|---|---:|---:|
| Queue | 13.675 | 1.143 |
| Host reset | 13.188 | 1.296 |
| Reader | 11.335 | 0.346 |
| Mailbox group | 14.174 | 1.027 |
| Engine/RAM-clear | 5.227 | 0.242 |
| Vendor FIFO | 9.652 | 0.363 |

The mailbox recovery/removal row includes system-side release. It is not a
claim about raw PLL LOCK or the memory-reset tail's async-reset drive.

C1↔C4 remains related 5:1. Normally timed held-request paths have minimum
setup/hold +4.414/+0.173 ns; response paths +5.632/+0.276 ns. Both directions
retain relationship 9.312/0 ns. Existing clk74 asynchronous grouping and vendor
Gray-pointer first-stage exceptions are preserved. The active/ignored exception
reports are retained; a functional handshake is not used to waive ordinary
payload timing, and no payload false path or multicycle was added.

The complete new 743-row Save inventory, 1,752 Save path rows, 92-row additional
inventory, 1,680 additional path rows, 47 pair definitions, 1,240 focused reset
path rows and 562 consumer-port rows match 0da938e across every column after
ignoring row order. `prior-ntsc-physical-record-comparison.json` records this
explicit comparison; the new native receipts remain independently source-bound.

## DSP and actual state-control pins

All eight physical DSP RAM_DI FFs and the 16-bit ARAM data source are present.

| Corner | DSP input setup | Input hold | Output setup | Output hold |
|---|---:|---:|---:|---:|
| slow85 | 7.676 | 0.681 | 6.155 | 23.180 |
| slow0 | 7.844 | 0.731 | 6.214 | 23.135 |
| fast85 | 9.508 | 0.173 | 16.067 | 23.246 |
| fast0 | 9.718 | 0.156 | 16.676 | 23.245 |

Input relationships are 11.640/0 ns into the falling-edge C1 stage; output
relationships 23.280/-23.280 ns. These are functional data stages on related
clocks. This does not qualify external PSRAM timing or hardware audio.

Fresh CDB inspection finds all 13 physical WRAM state-related FFs have no ENA
or SCLR pin. SLOAD is absent on 11 and tied VCC on the two fitter-derived
`state[4]_NEW_REG926` / `_NEW_REG930` FFs. Those two have SDATA and no D pin:
fixed alternate data selection, not variable synchronous-load control. All
12 ARAM state FFs have no ENA/SCLR/SLOAD. This reproduces the final 0da938e
physical result; it does not substitute the eight logical QSF targets for actual
fitter copies, nor claim every SLOAD is physically absent or grounded.

## Memory-reset physical roles and ordinary timing

Source `sdram_transaction_cdc.sv:38–47` shifts constant 1 through two registers,
with raw hard-reset asynchronous clear. The cart port combines hard reset and
PLL lock; its SNES call site ties hard reset high, leaving actual PLL LOCK.
Soft reset/mount/flush do not independently clear this chain.

The actual head/tail are FF_X35_Y44_N40 / FF_X35_Y44_N50. Head D comes from a
constant-one feeder (LUTMASK_SUM `FFFFFFFFFFFFFFFF`, no variable input support),
and its only register fanout is the tail. Tail SDATA comes directly from head Q,
with SLOAD tied VCC and no D pin. Both use the same non-inverted C4 clock and
CLRN from the actual FRACTIONAL_PLL LOCK port, `locked_wire[0]`, non-inverted.
This is asynchronous assertion with release through successive rising C4 edges.

CDB separately matches all **154** tail consumers and their reset pins:

| Consumer | Count | Actual asynchronous control |
|---|---:|---|
| Mailbox FFs | 66 | CLRN directly from raw PLL LOCK |
| Engine FFs | 87 | CLRN from engine release_sync[1] |
| Engine dram_ras_n | 1 | ALOAD from engine release_sync[1] |

All use the same non-inverted C4 clock. None uses `mem_reset_sync[1]` as an
asynchronous reset source. That tail is a synchronous update/clear guard and
engine handshake qualifier, while raw transport clears and engine-local release
remain distinct.

| Corner | Head→tail setup | Head→tail hold | Tail→154 setup | Tail→154 hold |
|---|---:|---:|---:|---:|
| slow85 | 7.835 | 0.719 | 1.400 | 0.650 |
| slow0 | 7.852 | 0.754 | 1.482 | 0.615 |
| fast85 | 8.682 | 0.325 | 5.949 | 0.267 |
| fast0 | 8.714 | 0.301 | 6.199 | 0.259 |

Every tail consumer is covered once per corner/check with npaths=1024; this is
not only a first-32 sample. The +1.400-ns slow85 tail path ends at ordinary
`dram_addr[3].D` in DDIOOUTCELL_X40_Y45_N50, through `req_ready~1`,
`Selector0~0`, `pending_write~1`, `Selector10~0`. Relationship is 9.312 ns,
data delay 8.516 ns, skew +0.724 ns, uncertainty 0.120 ns, arrival 11.895 ns,
required 13.295 ns. It is not a head→tail or asynchronous-reset timing path.

Focused recovery/removal from either reset register has zero paths because
neither drives downstream async-reset pins. Checks to these registers also have
zero numerical paths because raw PLL LOCK lacks an ordinary launching clock.
**Zero paths are not a pass.** Positive engine/system-side release checks cannot
replace missing raw-LOCK recovery/removal. No engine initialization interval or
init_done qualification is used as a blanket timing exception.

## Why the native MTBF headline is 1.64e-6 years

Fresh per-corner native reports, before any classifier experiment:

| Corner | Reported design worst-case MTBF | Shortest reported settling |
|---|---:|---:|
| slow85 | 0.000216 years / 6.79e3 seconds | 1.400 ns |
| slow0 | 1.64e-6 years / 51.6 seconds | 1.482 ns |
| fast85 | 1e9 years | 5.949 ns |
| fast0 | 1.18e6 years | 6.199 ns |

All have 158 chains and 57.0% uncalculated. The earlier 0da938e focused audit
quoted **slow85**; the 51.6-second headline is **slow0**. The original native
reports already contained both. It is not a newly introduced physical regression.

The fresh slow0 report lists `mem_reset_sync[1]` first in the chain summary:
FORCED treats it as a separate one-register head, with only 1.482 ns downstream
slack and an assumed 13.42M transitions/s. The preceding physical head is also
separately identified. Other reset tails are separately counted too. These
reported totals are not accepted failure-rate estimates.

An independent **four-corner report-only control** assigns the exact head
FORCED and tail AUTO in memory, recreates the timing view from the same routed
DB and reloads original SDC. In every corner it produces one two-register chain
containing exactly head and tail, removes the independent tail entry, and changes
158 total chains to 157. Reported chain settling is:

| Corner | Report-only two-stage settling | Native component sum |
|---|---:|---:|
| slow85 | 9.235 ns | 7.835 + 1.400 |
| slow0 | 9.334 ns | 7.852 + 1.482 |
| fast85 | 14.631 ns | 8.682 + 5.949 |
| fast0 | 14.913 ns | 8.714 + 6.199 |

This directly establishes the classification mechanism on the final source and
on the actual slow0 corner. Original reports remain preserved. The control still
uses Source Clock Unknown and unverified 13.42M/s; its improved MTBF numbers
are not adopted. The original 26 FIFO entries count functional comparators as
third members, and 16 functional ARAM→DSP paths appear as two-register chains
with MTBF Not Calculated. Such consumers are not independent synchronizer stages.

No examined structural/routed defect was found. Actual PLL/reset assertion and
release waveform, reset-pulse requirements, valid reset/data event rates,
analog recovery behavior, voltage/temperature/silicon applicability and a mission
reliability target remain missing inputs. This is not global reset/CDC/MTBF or
hardware acceptance.

## Reproduction and integrity

Evidence: `docs/evidence/standard-ntsc-sdram-save-cdc-e71101f/`.
Raw queries: sibling `final-audit-ntsc-e71101f/`, with completed large outputs
losslessly gzip-compressed as recorded by `compressed-native-reports.json`.
Original build archives and fitted databases were not compressed or changed.

The evidence contains full C0/C4 routed reports, actual I/O and complete fanout
inventories, normally timed mailbox/DSP paths, reset atom/consumer pins, all
four original and report-only classifier reports, source excerpts, original
archive/source hashes and reproducible locked commands. Seven Save preflight
and ten I/O policy/budget tests pass. The offline validator verifies every
manifest payload, rejects isolated missing-file/wrong-hash controls and checks
actual stage topology, all 154 consumers, classifier behavior and physical state
pins. Every payload, including `.txt`, is force-tracked and hash-checked before
commit. None of these checks asserts board or numerical MTBF signoff.

```sh
bash docs/evidence/standard-ntsc-sdram-save-cdc-e71101f/reproduce.sh \
  ../final-audit-ntsc-e71101f-rerun
python3 docs/evidence/standard-ntsc-sdram-save-cdc-e71101f/validate.py
```
