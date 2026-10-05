> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# Standard-memory experimental branch status

Status recorded 2026-10-04 UTC. This is the separately authorized development
branch `experiment/standard-refresh-ready`. The preserved `b63f800` minimal
prototype remains a separate historical artifact.

## Exact identities

- All three final native builds use clean source
  `e71101fd06a452da53cb0924e1d3701f53133435`
- Hardware/build inputs: **173** committed files, SHA-256
  `a9c619f6a2b1fa60b25dbbd9f5d39ad1f4a57e1c045b546b6c53a02545c41f29`
- Final functional executions: audit `b45914b`, remaining families `39d8d26`.
  The 53-group archive (retained archive: `evidence/standard-memory-final-39d8d26/README.md`) and
  final-source comparison (retained archive: `evidence/standard-memory-e71101f-source-continuity.json`)
  verify that all **155** simulation HDL/QIP/SDC/MIF inputs are unchanged in
  `e71101f`. This source comparison is not a claim to have rerun those tests
  after each documentation or placement-policy commit
- The earlier compiler-only WRAM state mapping change has a
  [mapped-state equivalence proof](wram-state-sync-control-evidence.md) covering
  all binary assignments of 144 register bits and all 98 pad data/OE functions
- Relative to the internally closed `0da938e` NTSC checkpoint, the final build
  changes only the PAL seed2/Standard Fit policy and the full-fitter-settings
  receipt. No RTL, clock, command edge, wait-cycle or timing exception changed
- Delivery/documentation/tool HEAD can be later than `e71101f`; it is not the
  compiled hardware identity. Original failed placements and exact reports are
  retained, and no dirty diagnostic build was promoted to a final image

## Completed native builds

All three completed full native flows have nonnegative internal setup, hold,
recovery, removal and pulse-width checks in all four reported corners, with
zero TNS. Actual seed/effort values are read from each retained full fitter
report and matched by byte count and SHA-256 to its build receipt.

| Profile | Seed / effort | Setup / hold / recovery / removal minima (ns) | ALMs / RAM blocks / DSP |
| --- | --- | --- | --- |
| `msu_standard_ntsc` | 1 / Auto Fit | +0.341 / +0.102 / +5.227 / +0.242 | 17,421 / 291 / 24 |
| `msu_standard_pal` | 2 / Standard Fit | +0.038 / +0.107 / +4.929 / +0.191 | 17,377 / 291 / 24 |
| `standard_ntsc_spc` | 1 / Auto Fit | +0.869 / +0.085 / +5.234 / +0.227 | 16,141 / 216 / 20 |

PAL's **+0.038 ns is only 38 ps**; it must not be rounded away or presented as
large margin. Hold optimization remains All Paths and multicorner optimization
On for every profile. The unsuccessful PAL seed1/Auto placement is preserved.
The SPC profile supplies SPC7110/SDD1/BSX and does not enable MSU; the main
regional profiles retain SA-1 and SuperFX/GSU. The SPC compiled BS-X initialization
was checked against the actual mapped memory content, including its deliberate
550-byte source plus 474 zero-filled bytes. This check retains the explicit
observed bit-plane serialization inference and its nine rejection controls; it
is not an independent vendor specification of that internal atom encoding.

Native receipts: NTSC (retained archive: `evidence/standard-memory-native-e71101f-ntsc/REPORT-MANIFEST.json`),
PAL (retained archive: `evidence/standard-memory-native-e71101f-pal/REPORT-MANIFEST.json`),
SPC (retained archive: `evidence/standard-memory-native-e71101f-spc/REPORT-MANIFEST.json`).
The last SPC checkout omitted only `docs/` to conserve disk; all 173 build inputs
were verified from actual working-tree bytes before compilation, with clean Git
status and recorded sparse patterns. No QIP-referenced input was omitted.

Source-bound physical reviews:
[NTSC](standard-ntsc-sdram-save-cdc-e71101f.md),
[PAL](standard-pal-sdram-save-cdc-e71101f.md),
[SPC](standard-spc-sdram-save-cdc-e71101f.md).
These retain actual I/O packing, conditional external timing, mailbox/reader
boundaries, mapper ownership, and reset-stage consumers. Placement-specific
register replication and control-pin differences are documented individually.
The external scenarios assume explicitly stated zero-PCB delays; they are not
board measurements. Native MTBF headlines and separate classifier controls are
preserved, including the slow0/slow85 difference. There is no global MTBF claim,
and raw PLL-lock asynchronous release remains unquantified.

## Functional qualification and Save scope

The final RTL qualification passed **53/53 aggregate groups**, including **188
Python tests**. Counts overlap and are not a single exhaustive coverage metric.
Save qualification passed 36 cases, 18 complete 128-KiB comparisons (2,359,296
bytes, zero differences), 84 reader checks, 13 legacy checks, 71 actual-APF checks
and 29 original-SRAM-smoke checks. CPU/SA-1/GSU/CX4/SPC7110/SDD1/BSX,
refresh/initialization/fairness, reset/ROM lifetime and audio-continuity tests
retain their documented actual-core/model boundaries.

**The ordered Save lifecycle and safe backup reader repair are standard-profile
features.** The 13 legacy checks establish preservation of the inherited legacy
behavior, including its unsafe old reader path; they do not show that legacy
Save was repaired. Battery SRAM and unsupported savestates are distinct:
Savestates, Memories and Sleep remain unsupported.

## Remaining real-world limits

- Board flight/skew, extra uncertainty, device loading, signal integrity, actual
  firmware command pacing, SD latency and long hardware stability are not
  established by simulation or the conditional I/O scenarios
- Nominal clocks remain unchanged; memory waits can change effective executed
  cycles. Directed performance measurements are not all-game compatibility
- Current MSU transport uses 32-bit byte offsets; files at or above 4 GiB are
  rejected. Later 48-bit APF commands are not implemented in this handler
- A core-specific directory does not isolate common saves. Use the independent
  [original SRAM smoke ROM](standard-save-smoke.md), no prewritten save, a new
  basename and a blank/spare SD. Never start with real games/saves

The final package must retain these exact source/profile/settings/bitstream
receipts and the experimental qualification boundary. Successful native timing
and simulations do not constitute an actual Pocket hardware validation.
