> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# Final e71101f SPC: physical timing, ownership and BSX initialization

## Result and exact compiled source

The completed `standard_ntsc_spc` fit of
`e71101fd06a452da53cb0924e1d3701f53133435` was independently re-queried.
Original modeled internal setup/hold/recovery/removal is positive in all four
corners, with zero TNS. Conditional SDRAM pin timing, all 47 examined neighboring
stage pairs, reader isolation, normally timed mailbox/DSP paths, and the added
SPC7110/SDD1/BSX ownership boundaries have no identified routed-timing failure.
The actual compiled BSX initialization content matches the required source and
zero padding under the explicit observed serialization described below.

This is a source-bound post-fit result. **Board operation, raw PLL-reset analog
behavior, global CDC and numerical MTBF remain unverified.** Timing checks do
not substitute for protocol tests, board measurements or reliability inputs.

Archive:
`standard-fit-spc-e71101f/projects/output_files/msu1-builds/standard_ntsc_spc-20261004T181501Z-ZDaKSp`.
Full fitter report SHA-256:
`bdb473f0fa881792be1b042c1dc7c4b44cff3372a39e806c978e0bfd81189d6c`.
Quartus 21.1.1 Build 850 Lite / 5CEBA4F23C8; native report and receipt confirm
seed **1**, **Auto Fit**, hold optimization **All Paths**, multi-corner **On**.
The native resource count is 16,141 ALMs / 216 RAM blocks / 20 DSP blocks.

The build records clean source e71101f. All 173 preflight hardware inputs exist;
the sparse checkout omits docs only. The post-build generated QSF profile/output
changes are distinguished from the clean pre-build source status. No source,
QSF, SDC, PLL, original report or fitted database was altered by the audit; no
fit was launched. All native queries used the completed project's shared lock.
Large newly generated query outputs were losslessly compressed, with original
and compressed hashes retained. No additional worktree was created.

## Internal timing and small margins

Independent original-summary/detail comparison covers 124 timing rows including
pulse width. The setup/hold/recovery/removal categories have 28/28/16/16 rows.

| Check | Minimum slack |
|---|---:|
| Setup | +0.869 ns |
| Hold | +0.085 ns |
| Recovery | +5.234 ns |
| Removal | +0.227 ns |
| Pulse width | +0.582 ns |

All reported TNS values are zero. The setup minimum is slow0 C1 DSP
`STEP_CNT[1]` → C0 `psram:aram|cram_data[14]`: relationship 11.640 ns,
data delay 10.129 ns, skew -0.522 ns, arrival 12.821 ns, required 13.690 ns.
The fast0 hold minimum is `wram_write_stage|write_data[0]` →
`psram:wram|latched_data_in[8]`: relationship 0, data delay 0.779 ns,
skew +0.634 ns and arrival 23.882 ns. The native full paths are retained.
The +0.085-ns hold margin is genuinely small; it is not rounded into a larger
reserve or replaced by the main NTSC placement's number.

## Actual SDRAM I/O and conditional four-corner timing

Actual placement is 16 DDIOINCELL DQ input FFs, 37 DDIOOUTCELL command/data FFs,
and 16 DDIOOECELL OE FFs: **16 inputs / 53 output-and-OE FFs**. Forwarded-clock
halves share their DDIO output cell. The same native 9.312-ns NTSC period and
explicit comparison fixture are used: zero PCB flight bounds and additional
margins, tAC=5.5 ns, tOH=2.5 ns, tIS=2 ns, tIH=1 ns. Native FPGA uncertainty
remains active. The same-period/device/PCB/margin comparison guard passes.

CL3/BL1 word selection remains READ at A+2.5, E2 drive/tAC reference A+4.5,
physical `dq_sample` at A+6, and internal copy at A+7. The copy is not an input
sample. Read setup/hold relationships are 1.5T/0.5T; no conventional hold=1
compensation or payload multicycle is introduced.

| Corner | Read setup | Read hold | Cmd setup | Cmd hold | Data setup | Data hold | OE setup | OE hold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| slow85 | 2.140 | 2.528 | 1.546 | 3.410 | 1.550 | 3.378 | 1.427 | 3.544 |
| slow0 | 2.182 | 2.493 | 1.526 | 3.454 | 1.527 | 3.423 | 1.414 | 3.597 |
| fast85 | 5.282 | 0.265 | 1.984 | 3.668 | 1.977 | 3.646 | 1.923 | 3.692 |
| fast0 | 5.457 | 0.098 | 1.970 | 3.674 | 1.964 | 3.653 | 1.934 | 3.707 |

All figures are ns and conditional. Main NTSC e711 had minimum read hold
+0.100 and OE setup +1.416; this SPC placement has +0.098 and +1.414.
These whole-placement differences are not isolated causal chipset measurements.
With additional uncertainties Us/Uh and clock-out plus DQ-return flight bounds:

```text
max(0, Uh - 0.098 ns) <= Lmin <= Lmax <= 2.140 ns - Us
```

Positive return-loop flight helps hold while consuming setup. The zero-flight
0.098 ns is not measured board margin. Outgoing signal-minus-clock flight skew
must lie within these conservative class bounds:

| Class | Minimum skew | Maximum skew |
|---|---:|---:|
| Command/address/DQM/CKE | Uh - 3.410 ns | 1.526 ns - Us |
| Write data | Uh - 3.378 ns | 1.527 ns - Us |
| OE | Uh - 3.544 ns | 1.414 ns - Us |
| Combined write/OE | Uh - 3.378 ns | 1.414 ns - Us |

Real flight, extra uncertainty/jitter, SI, turnaround, loading/slew, pulse width
and device/operating applicability remain unestablished. Original external-port
constraint gaps remain; the fixture is not a silent production-SDC completion.

## Save isolation, mailbox and reset release

Reader source head FF_X48_Y34_N2 feeds only tail FF_X48_Y34_N20;
memory head FF_X42_Y30_N16 feeds only tail FF_X42_Y30_N14. The tails have
103/44 functional register endpoints. First-stage→datatable setup/hold queries
return zero paths; the earlier merged first-stage functional fanout is absent.
All 13 explicit control/reset neighbor pairs have only their intended next
stage as register fanout and positive four-corner setup/hold.

The 26 dedicated FIFO pointer pairs have minimum +11.694/+0.154 ns, six FIFO
release pairs +11.666/+0.230, and two engine/RAM-clear pairs +7.709/+0.258.
All **47** examined pairs pass. Normally timed C1↔C4 payload paths retain their
related 5:1 clocks and setup/hold relationship 9.312/0 ns: request minima
+6.049/+0.129; response +5.083/+0.336. Existing clk74 asynchronous grouping
and vendor Gray-pointer exceptions are unchanged; no payload cut is added.

| Release-source group | Minimum recovery | Minimum removal |
|---|---:|---:|
| Queue | 15.002 | 1.128 |
| Host reset | 15.483 | 1.005 |
| Reader | 11.396 | 0.268 |
| Mailbox group | 14.992 | 1.084 |
| Engine/RAM-clear | 5.234 | 0.227 |
| Vendor FIFO | 10.037 | 0.395 |

The mailbox row includes system-side release. It is not a raw PLL LOCK or
memory-reset-tail recovery/removal guarantee.

## Actual DSP replication and state-control pins

Eight logical DSP RAM_DI bits occupy **nine physical FFs**: bit 7 has a fitter
`~DUPLICATE`. All nine input endpoints and the retained output paths were queried.
The 16-bit ARAM data source remains present.

| Corner | DSP input setup | Input hold | Output setup | Output hold |
|---|---:|---:|---:|---:|
| slow85 | 8.184 | 0.651 | 6.786 | 23.527 |
| slow0 | 8.266 | 0.627 | 6.831 | 23.585 |
| fast85 | 9.712 | 0.221 | 16.077 | 23.360 |
| fast0 | 9.903 | 0.188 | 16.732 | 23.346 |

Input relationships are 11.640/0 ns into falling-edge C1, output
23.280/-23.280 ns. These functional data stages are not separate asynchronous
control synchronizers. External PSRAM/audio behavior is not qualified here.

Fresh CDB inspection finds all 13 WRAM state FFs have no ENA/SCLR/SLOAD pins.
ARAM has 11 state FFs, all without ENA/SLOAD; ten lack SCLR, while
`state[0]` at FF_X19_Y13_N8 has its own Q connected to SCLR, not a constant.
That is the actual SPC mapping. Unlike the main NTSC mapping, it must not be
described as all ARAM SCLR pins absent. No ARAM policy change or new exception
was made; original constrained timing remains positive.

## SPC7110, SDD1 and BSX owner/lifecycle boundaries

Native hierarchy confirms SPC7110Map and SDD1Map instantiate reusable
SA1RomBridge transports even though the SA1 mapper itself is disabled. Their
global owners are 13 and 14; BSXMemoryBridge uses global owner 15. Source review
and native optimization rows are retained separately from timing evidence.

On acceptance, main captures response source, local owner and global owner;
response delivery uses that captured identity rather than a later MAP_ACTIVE.
Cart lifecycle closes admission, waits for client flush acknowledgement and
physical transport drain, then advances epoch. The mailbox's 21-bit metadata
is held and returned entirely in C1; it is not the C1→C4 payload bus.

BSX `post_pending/post_addr/post_data` are a separate crucial stage outside the
bridge. CPU-retired PSRAM writes occupy local owner 2 (`COMMITTED="0100"`) and
survive soft flush/deselect until physical completion. The top arbiter allows
only that pre-existing drain obligation through flush and gives it priority over
new download traffic. DATAPAK ordinary flash state has separate reset/flush
semantics. BSRAM uses a separate same-clock dual-port BRAM path, not SDRAM owner 15.

The actual retained boundary inventory contains 162 SPC bridge, 161 SDD1 bridge,
195 BSX bridge, 29 BSX posted-write, 40 DATAPAK, eight captured-owner, 19 cart
lifecycle, 42 mailbox metadata and 35 cache-metadata register nodes. Three CPU
wait/phase nodes and the BSRAM timing-node set were also examined. Fitter copies
and constant/merged owner bits are retained as observed; source bus widths are
not used as physical register-count assertions.

Four-corner from/to setup/hold and recovery/removal queries retain full worst
paths and 107,704 path rows. Representative direct C1→C1 data boundaries:

| Direct boundary | Minimum setup | Minimum hold |
|---|---:|---:|
| Held request metadata → returned metadata | 42.644 | 0.311 |
| BSX posted stage → BSX owner bridge | 36.662 | 0.224 |
| Captured owner → mapper bridge consumers | 31.059 | 0.767 |

Each has ordinary 46.560/0-ns setup/hold relationships. Real timing clock objects
place these boundaries in C1; no asynchronous exception or multicycle was used.
The inventory's `clock_sources`/`async_sources` columns name local edge-source
pins, not root clock/reset nets; root-clock conclusions use the timing-path
clock objects, not those column labels.

A second query explicitly covers first-offer and completion-forwarding bypasses
that bridge-only inventories would miss: all 64 retained accepted-request hold
nodes, 40 response nodes and 35 cached-response nodes. Their from/to setup/hold
paths are positive. Into request acceptance the minima are +18.038/+0.244 ns;
out of normal response +10.065/+0.210; out of cached response +9.933/+0.191.
These include paths with no intervening bridge state register.

Queries retain up to 1,024 worst endpoint paths per group/check. Several large
from-groups and BSRAM reach that limit, so they are worst-path reviews rather
than exhaustive path enumerations. The 7,817 BSRAM timing nodes include logical
RAM endpoints and must not be called 7,817 physical FFs. Native original global
closure provides the wider modeled timing check. Zero raw-hard-reset
recovery/removal paths are not numerical reset acceptance. Physical path review
also does not replace functional stale-response/flush/post-write protocol tests.

## Actual compiled BSX initialization

Original compile/map messages resolve the correct
`rtl/upstream/chip/BSX/bsx121-124.mif`, read its **550×8** contents, and explicitly
zero-fill the remaining addresses through 1023. Fitter retains CH_DATA at
**M10K_X51_Y43_N0**. A locked read-only CDB query goes beyond filename evidence:
it returns that post-fit atom's actual **10,240-bit BITVEC_CONTENT**, logical
shape 1024×8, physical width 10, content view A, first address/bit 0,
RAM_INITIALIZED=1, power-up-uninitialized=0 and ROM/ECC metadata.

The captured content exactly matches all 550 source bytes, all 474 zero-pad
bytes and the 2,048 zero bits in the two unused physical lanes. The explicit
observed decoding is:

```text
byte[a] = sum(int(BITVEC_CONTENT[10239 - (b*1024 + a)]) << b for b in 0..7)
a = 0..1023
```

The decoded 1024-byte SHA-256 is
`266352bac90f91c7a7f06fcf6ad34f24eec9368d874379e85a350cdee775a733`.
Every logical bit plane uniquely matches its same-numbered source plane. This
is the only complete match among 24 tested simple planar/word-major layouts.
Nine corruption controls are rejected, including source-byte changes, nonzero
padding and flips in either unused physical lane.

The installed Tcl help documents legal properties and returned values but not
BITVEC_CONTENT serialization. The plane order is therefore an explicit, unique
full-payload observation consistent with actual shape/offset metadata, not an
independently documented serialization guarantee. It verifies captured compiled
content, not separate physical port wiring, SOF-bitstream decoding or hardware
operation. The simulator's word-major mem_init format is a different interface
and is not incorrectly substituted here. Portable offline replay uses retained
MIF/query bytes and never opens a database or rewrites native evidence.

## Memory-reset topology and MTBF interpretation

The constant-one memory-reset head is FF_X41_Y44_N40, tail FF_X41_Y43_N32.
Head D is a constant-one feeder with LUTMASK_SUM FFFFFFFFFFFFFFFF and no variable
input support; its only register fanout is the tail. Tail SDATA is head Q,
SLOAD is fixed VCC and no D pin is used. Both have non-inverted C4 clocks and
CLRN from the actual PLL LOCK output. Source hard reset is tied high at the
call site; soft/mount/flush do not independently clear this chain.

All **159** tail consumers are matched in CDB, rather than reusing NTSC's 154:
68 mailbox CLRN inputs use raw PLL LOCK, 90 engine CLRN inputs and one engine
ALOAD use engine release_sync[1]. All use non-inverted C4. None uses the memory
reset tail as async reset: it is a synchronous guard/handshake qualifier.

| Corner | Head→tail setup | Head→tail hold | Tail→159 setup | Tail→159 hold |
|---|---:|---:|---:|---:|
| slow85 | 7.540 | 0.965 | 2.545 | 0.720 |
| slow0 | 7.544 | 0.944 | 2.568 | 0.742 |
| fast85 | 8.505 | 0.405 | 6.543 | 0.285 |
| fast0 | 8.557 | 0.370 | 6.725 | 0.274 |

All 159 endpoints are present in each setup/hold query. Tail values are ordinary
synchronous setup/hold paths, including data/control pins, not head→tail settling
or raw-reset recovery/removal. The tail directly drives ENA on some mailbox
consumers; those paths must not all be described as D-input paths.
Focused recovery/removal from and to the head/tail returns zero numerical paths;
raw PLL LOCK has no ordinary launch clock. Zero is not a pass, and other release
groups' positive recovery/removal cannot replace that gap. No startup/init_done
interval is used as a blanket exception.

Original native MTBF headlines are slow85 932 years, slow0 0.00082 years
(2.58e4 seconds), fast85 1e9 years and fast0 2.43e7 years. The population is
119 chains with 51.3% uncalculated, different from the main chipset. These are
not accepted reliability numbers. FORCED still splits the actual memory-reset
pair into separate one-register heads; the tail entry uses only downstream
2.545/2.568/6.543/6.725 ns and an unverified 13.42M transitions/s.

Separate in-memory head-FORCED/tail-AUTO controls on this same routed database
produce one two-register chain in each corner, remove the independent tail and
change 119 chains to 118. Reported settling is respectively
10.085/10.112/15.048/15.282 ns, exactly the head→tail plus downstream values.
Original reports remain preserved, and no assignment is exported. Source Clock
Unknown and unverified rates remain; improved scenario numbers are not adopted.
Native FIFO comparators and functional ARAM/DSP consumers are not counted as
extra independent synchronization stages in this review.

No examined structural or routed defect was found. Actual PLL/reset waveform
and pulse requirements, event-rate bounds, analog recovery, operating/silicon
applicability and a reliability target remain necessary for numerical MTBF.

## Reproduction and evidence integrity

Evidence: `docs/evidence/standard-spc-sdram-save-cdc-e71101f/`.
Raw completed queries remain in sibling `final-audit-spc-e71101f/`; large files
are losslessly retained according to the compression/hash manifest. Original
build reports/database are unchanged. Full routed critical paths, I/O/fanout
inventories, ownership/bypass paths, all reset consumers, physical state pins,
original/classifier reports and actual BSX compiled content are retained.

Seven Save preflight and ten I/O policy/budget tests pass. Offline validation
checks every manifest payload and isolated missing-file/wrong-hash controls,
physical counts and boundaries, all 159 consumers, nine DSP FFs, actual ARAM
SCLR usage, and the BSX payload with nine negative controls. Every manifest
payload, including `.txt` and `.mif`, is force-tracked and hash-verified before
commit. This evidence completion is not board/global-MTBF acceptance.

```sh
bash docs/evidence/standard-spc-sdram-save-cdc-e71101f/reproduce.sh \
  ../final-audit-spc-e71101f-rerun
python3 docs/evidence/standard-spc-sdram-save-cdc-e71101f/validate.py
```
