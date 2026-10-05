> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# PAL 0da938e physical audit: unresolved C4 setup and hold

## Outcome and exact source

The successful full compiler flow for source
`0da938eb1eaaefc6ff23347568cd69a8240e4f37`, profile `msu_standard_pal`, archive
`msu_standard_pal-20261004T162952Z-LYogMa`, **does not meet its original timing
constraints**. PAL qualification remains blocked by two distinct C4 paths.
The NTSC result for the same source does not establish PAL closure.

This read-only review used Quartus 21.1.1 Build 850 Lite / 5CEBA4F23C8, the
existing shared project lock and completed fitted database. No source, QSF, SDC,
PLL, exception or fitting changes were made. All original archive files and
critical source/generated QSF hashes remain unchanged.

## Original-SDC failures, with full worst20 routes

| Check | Exact path | Worst slack |
|---|---|---:|
| C4 setup, slow0 | engine init_count[11] → dram_dqm[0] | -0.231 ns |
| Same setup path, slow85 | engine init_count[11] → dram_dqm[0] | -0.205 ns |
| C1→C4 hold, fast0 | request_data_hold[9] → mem_data[9] | -0.026 ns |

The slow0 setup relationship is 9.392 ns, data delay 10.372 ns, skew +0.869 ns,
and setup uncertainty 0.120 ns. This is logic into the command/DQM output FF.
Positive FF-to-pin external timing below does not repair its late D input.

The hold path is a normally timed held mailbox payload, with a 0 ns edge
relationship, 0.710 ns data delay and +0.676 ns clock skew. Its data arrival is
3.396 ns and requirement 3.422 ns, including 0.060 ns hold uncertainty. Fast85
hold for this path is +0.073 ns; fast0 is negative. This is not a vendor FIFO
false path or a metastability-report labeling artifact. The functional handshake
is not used to waive the original physical requirement.

The independent C4 query prioritizes fast0 hold and records worst20 complete
routed paths plus worst64 summary rows for setup and hold at every corner.
Exactly one negative endpoint is present in each of the slow0/slow85 setup
extracts, and one in fast0 hold; none in the other C4 corner/check extracts.

| Original whole-report check | Minimum slack | TNS status |
|---|---:|---|
| Setup | -0.231 ns | Fails C4 |
| Hold | -0.026 ns | Fails C4 |
| Recovery | +4.331 ns | All reported TNS zero |
| Removal | +0.259 ns | All reported TNS zero |

C0 and C1 are positive in the compiled summary, but this is not whole-design
timing closure. No PAL hardware/board verification is claimed.

## Physical SDRAM I/O and PAL edge model

All 16 DQ input FFs remain in DDIOINCELL, 37 command/data outputs in DDIOOUTCELL,
and 16 OE FFs in DDIOOECELL. The total remains 16 input plus 53 command/data/OE
output FFs, with both forwarded-clock halves in their shared DDIO output cell.

The native TimeQuest C4 is `mf_pllbase_pal_sdram_inst` with period **9.392 ns**, not the
NTSC 9.312 ns. Device/PCB/extra-margin fixture values are identical to the NTSC
audit: explicit zero PCB flight and additional margins, tAC=5.5 ns, tOH=2.5 ns,
tIS=2 ns and tIH=1 ns, with native FPGA uncertainty included. The period differs,
so no same-period routing-delta comparison is claimed or passed through --compare.

The unchanged CL3 word selection uses external READ at A+2.5, E2 drive reference
at A+4.5, dq_sample capture at A+6 and internal copy at A+7. The external setup/
hold relationships are 1.5T / 0.5T; the later copy is not the physical sample.

### Conditional four-corner pin timing (ns)

| Corner | Read setup | Read hold | Cmd setup | Cmd hold | Data setup | Data hold | OE setup | OE hold |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| slow85 | 2.260 | 2.492 | 1.583 | 3.450 | 1.590 | 3.418 | 1.464 | 3.584 |
| slow0 | 2.302 | 2.457 | 1.562 | 3.494 | 1.567 | 3.463 | 1.451 | 3.637 |
| fast85 | 5.402 | 0.223 | 2.024 | 3.708 | 2.017 | 3.686 | 1.962 | 3.732 |
| fast0 | 5.577 | 0.056 | 2.008 | 3.714 | 2.004 | 3.693 | 1.973 | 3.747 |

All external classes are positive under this explicit fixture. The minimum read
setup is +2.260 ns and read hold only +0.056 ns in the zero-flight scenario.
Those external results do not excuse either internal failure above.

For additional uncertainty Us/Uh and package-pin clock-out plus DQ-return flight
bounds Lmin/Lmax, reads require:

```text
max(0, Uh - 0.056 ns) <= Lmin <= Lmax <= 2.260 ns - Us
```

Positive flight improves hold while consuming setup. The 0.056-ns number is not
a measured real-board margin. For output signal-minus-clock skew Sj:

| Class | Sj,min lower bound | Sj,max upper bound |
|---|---:|---:|
| Command/address/DQM/CKE | Uh - 3.450 ns | 1.562 ns - Us |
| Write data | Uh - 3.418 ns | 1.567 ns - Us |
| OE | Uh - 3.584 ns | 1.451 ns - Us |
| Combined write/OE | Uh - 3.418 ns | 1.451 ns - Us |

Real flight, additional jitter/uncertainty, SI, turnaround, loading/slew, clock
pulse width and applicable device/operating conditions remain unestablished.

## Save/reset and normally timed mailbox results

Reader first stages are still isolated to their intended second stages:

| First stage | Location | Sole register endpoint |
|---|---|---|
| source_release[0] | FF_X52_Y12_N13 | source_release[1] at FF_X49_Y12_N56 |
| memory_release[0] | FF_X37_Y32_N28 | memory_release[1] at FF_X37_Y32_N26 |

The source/memory tails have 104/45 downstream register endpoints. Every targeted
first-stage→datatable setup/hold query has zero paths. The old unintended first-
stage functional fanout remains absent. All 13 explicit control/reset pairs have
only their intended next-stage fanout and positive four-corner setup/hold.

The supplemental 26 dedicated FIFO pointer pairs have minimum setup/hold
+11.272/+0.175 ns; 6 FIFO clear-release pairs +11.219/+0.231 ns; and 2 RAM-clear/
engine release pairs +7.060/+0.261 ns. All 47 examined neighboring pairs pass.

Downstream release-source recovery/removal is separately positive:

| Release-source group | Recovery | Removal |
|---|---:|---:|
| Queue | 14.475 | 1.135 |
| Host reset | 14.933 | 1.033 |
| Reader | 11.355 | 0.361 |
| Mailbox group | 14.525 | 1.091 |
| RAM-clear/engine | 4.331 | 0.282 |
| Vendor FIFO | 8.407 | 0.312 |

The mailbox row is a grouped query including system-side release. It is not a
claim that mem_reset_sync[1] drives downstream asynchronous resets. Its source
role remains the synchronous update/clear guard and handshake qualifier; raw
transport clears and the engine local release remain separate. The exact NTSC
source/atom analysis is documented in `standard-mem-reset-mtbf-audit-0da938e.md`;
its physical values are not substituted for this PAL placement.

C1/C4 remains related 5:1. Payload paths retain normal setup=9.392 ns / hold=0:

| Payload | Min setup | Min hold |
|---|---:|---:|
| Held request C1→C4 | +5.213 ns | **-0.026 ns** |
| Held response C4→C1 | +5.536 ns | +0.213 ns |

The independently repeated request-hold failure matches the C4 worst20 report
exactly. Existing clk74↔C1 asynchronous groups and vendor pointer exceptions
remain unchanged; no payload cut or multicycle has been added.

## Actual DSP-stage timing

All eight physical DSP RAM_DI FFs remain present. The real 16-bit ARAM source
and DSP/SMP consumer paths are positive in every corner:

| Corner | Input setup | Input hold | Output setup | Output hold |
|---|---:|---:|---:|---:|
| slow85 | 7.781 | 0.567 | 6.643 | 23.575 |
| slow0 | 7.832 | 0.590 | 6.780 | 23.569 |
| fast85 | 9.639 | 0.165 | 16.153 | 23.531 |
| fast0 | 9.833 | 0.154 | 16.839 | 23.526 |

Input setup/hold minima are +7.781/+0.154 ns, outputs +6.643/+23.526 ns. PAL
relationships are 11.740/0 ns into the falling-edge C1 stage and 23.480/-23.480 ns
out. Functional data stages are not independent asynchronous synchronizers.

## Metastability-report interpretation

The original slow85 report prints 0.0 years / 0.000236 seconds, dominated by
mem_reset_sync[1] as a one-register FORCED head with 0.119 ns downstream slack
and a default-like 13.31M transitions/s. The actual preceding pair exists, has
exclusive first-stage fanout, and minimum +8.051 ns setup / +0.260 ns hold.
The engine release tail is also separately labeled, with 0.905 ns downstream
slack. These are not accepted hardware failure-rate estimates.

The 158 native entries include 57.0% with no calculated MTBF, 26 vendor pointer
chains that count functional comparators as third members, and functional ARAM/
DSP stages whose entries are Not Calculated. Chain boundaries, actual reset/PLL
event and data-toggle rates, analog reset requirements, complete external timing,
operating assumptions and reliability targets remain unestablished. The separate
NTSC classifier experiment demonstrated the split-head mechanism; no corrected
PAL number or global MTBF is asserted here. PAL also has the independent real
setup and hold failures above, which remain blockers regardless of labels.

## Evidence, reproduction and integrity

Evidence: `docs/evidence/standard-pal-sdram-save-cdc-0da938e/`. Full local results
remain in sibling `final-audit-pal-0da938e/`. The original-SDC C4 worst20 reports
are preserved in full, gzip-compressed, with readable first-path excerpts:

- `c4-original-fast0-c4-hold-worst20.log.gz`
- `c4-original-slow0-c4-setup-worst20.log.gz`
- `c4-original-c4-paths.tsv`: four-corner worst64 summaries

Source/report receipts, all 47 stage-pair details, physical inventories, external
assumptions, DSP edge paths and complete original archive hashes are retained.
No old database or report was overwritten. Seven preflight tests pass. The
offline validator checks every manifest file and SHA-256, rejects isolated
missing-file/wrong-hash controls, and deliberately asserts that the PAL timing
failures remain present; “validation passed” means complete truthful evidence,
not successful PAL timing.

```sh
bash docs/evidence/standard-pal-sdram-save-cdc-0da938e/reproduce.sh \
  ../final-audit-pal-0da938e-rerun
python3 docs/evidence/standard-pal-sdram-save-cdc-0da938e/validate.py
```
