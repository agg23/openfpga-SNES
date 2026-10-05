# Experimental MSU-1 and standard SDRAM refresh

This document accompanies the proposed Pocket MSU-1/standard-memory changes.
It describes an experimental implementation, its evidence, and reproducible
checks. It is not a release or a claim of general game compatibility.

## Scope and provenance

The implementation was developed from upstream
`ad9fed4e9cbeee56f624ffcffc6477b2908daa3d`. The three historical native builds
used `e71101fd06a452da53cb0924e1d3701f53133435`. The engineering handoff
records source/documentation revision
`08cace3302f1963c52ab1fb35a42284776ce36ef`; this later revision does not change
the recorded build identity. The handoff identifies 173 build inputs and their
combined SHA-256 as
`a9c619f6a2b1fa60b25dbbd9f5d39ad1f4a57e1c045b546b6c53a02545c41f29`.
Historical commit IDs identify retained engineering evidence; they must not be
mistaken for a new build of the eventual PR commit.

| Profile | Region | MSU | Cartridge coprocessors |
| --- | --- | --- | --- |
| `msu_standard_ntsc` | NTSC | Enabled | Main selection retains SA-1 and SuperFX/GSU |
| `msu_standard_pal` | PAL | Enabled | Main selection retains SA-1 and SuperFX/GSU |
| `standard_ntsc_spc` | NTSC | Disabled | Separate SPC7110, S-DD1 and BSX configuration |

The standard-memory and SRAM transport fixes are qualified for these profiles.
Legacy `ntsc`, `pal`, `ntsc_spc`, `msu_ntsc` and `msu_pal` profiles are comparison
paths, not recipients of the standard profiles' qualification. In particular,
the preserved early prototype's inherited SRAM backup-reader defect is not
made safe by rebuilding that legacy profile from a later checkout.

This Pocket build does not enable Savestates, Memories or Sleep. Existing
MiSTer state RTL and the Pocket `save_state_controller` are not evidence of a
complete, enabled integration. Their interface and state coverage require
separate evaluation. This change does not enable those flags or implement Sleep.

As checked on 2026-10-05, upstream
[PR #113, Add save states, Memories, and Sleep support](https://github.com/agg23/openfpga-SNES/pull/113)
is open and unmerged. It is separate work, not released support and not part of
this MSU/standard-memory proposal.

## Architecture

The MiSTer MSU register block exposes `$2000`–`$2007`. Pocket-specific transport
obtains the selected cartridge path through APF `0190`, opens companion files
through `0192`, and reads bounded chunks through `0180`. It does not copy
MiSTer's HPS/DDRAM transport or preload complete audio files into FPGA memory.

The data path has two 4-KiB blocks, with sequential prefetch, seek invalidation,
EOF handling and error propagation. Completion crosses clock domains only
after the receiving transfer RAM is ready. Mount/reinitialization logic drains
accepted operations and invalidates obsolete work rather than allowing a late
response to satisfy a new cartridge request.

PCM data uses a bounded FIFO, 8 KiB by default (4/8/16 KiB configurations).
Reads are at most 1,024 bytes, except the initial eight-byte header read.
Track changes reuse audio slot 101; data slot 100 holds the MSU data file.
Payloads remain stable across the associated handshake. The existing Pocket
I2S path receives the mixed, saturated signed-16-bit output.

Relevant implementation boundaries:

| Area | Source |
| --- | --- |
| Registers and bus semantics | `rtl/upstream/chip/MSU1/MSU.sv` |
| Dynamic file commands, bounds and arbitration | `rtl/msu1/msu_pocket_host.sv` |
| Data buffering and crossings | `rtl/msu1/msu_data_cache.sv`, `msu_block_cdc.sv` |
| PCM, track changes and initialization | `rtl/msu1/msu_pcm_player.sv`, `msu_mount_cdc.sv`, `msu_init_guard.sv` |
| Pocket integration | `rtl/msu1/msu_pocket.sv`, `target/pocket/core_top.sv` |
| Standard memory queue and SDRAM engine | `rtl/memory_ready/` |
| SRAM export handshake | `target/pocket/data_unloader.sv` |

## File and audio contract

Use one exact basename for a cartridge and its companions:

```text
Assets/snes/common/Example/Example.sfc
Assets/snes/common/Example/Example.msu
Assets/snes/common/Example/Example-1.pcm
Assets/snes/common/Example/Example-2.pcm
```

The transport replaces the cartridge's last extension while retaining its
directory. Paths are limited to 255 bytes. PCM files start with ASCII `MSU1`,
then a little-endian 32-bit loop position measured in stereo frames after the
header, then signed 16-bit little-endian interleaved stereo at 44.1 kHz.
The current handler uses 32-bit byte offsets and rejects files at or above
4 GiB. It does not implement the newer 48-bit-offset APF protocol.

PCM uses nearest-sample hold into 48-kHz I2S, not a high-quality resampling
filter. Volume follows the inherited `/256` convention. On underrun it outputs
silence and retains the file position; playback resumes there, so late data can
extend playback time. FIFO duration is not a guarantee about SD-card latency.
The minimum firmware version supporting the complete dynamic-file sequence
has not been established by this work; the inherited `version_required` value
must not be interpreted as such a qualification.

## Standard refresh and per-client waits

The standard controller uses CL3/BL1. Initialization waits for stable clocks,
precharges all banks, issues two AUTO_REFRESH commands, then sets MR and EMR.
An independent age counter schedules refresh even while a response is held.
The configured refresh bound is 831 SDRAM clock cycles.

| Clock | NTSC MHz | PAL MHz |
| --- | ---: | ---: |
| System | 21.477270 | 21.281370 |
| Existing PSRAM, 4× system | 85.909080 | 85.125480 |
| Separate SDRAM, 5× system | 107.386350 | 106.406850 |

The fifth PLL output leaves the original nominal clocks and phases intact.
Related system/PSRAM/SDRAM clocks are not covered by blanket false paths.
At the controller's internal edge A, ACT is issued; READ/WRITE is at A+2,
DQ capture at A+6, the captured-data copy at A+7 and response validity at A+8.
The earliest next ACT is A+9. These are internal edges; external sampling and
board delays require separate timing analysis.

Requests have four distinct events: allocation, acceptance, response and
architectural retirement. Descriptors retain physical address, byte lane,
owner, tag and epoch. A matching response may release a wait only at that
client's legal completion point. Repeated DMA reads of the same address remain
distinct transactions. Response slots let paused SA-1/GSU clients retain their
results without permanently occupying the shared return path.

SCPU instruction/data, DMA and HDMA; SA-1 CPU/DMA/variable-bit operations;
GSU load/fetch/cache; CX4 cache/DMA/direct reads; SPC7110; S-DD1; and BSX have
separate ownership and wait obligations. Posted BSX writes must drain across
soft reset/mount boundaries. ROM download, SRAM restore, BEGIN/END and backup
fences share ordering, and download completion means physical writes finished.
Bus waits do not stop the master clock or globally freeze video/audio timing.

Nominal clock preservation does not imply unchanged execution time. A directed
57-CPU-read/3-DMA-read program took 1,034 system clocks with the one-word cache
and matched forwarding, versus 802 for an ideal immediate-ROM reference:
**+28.93% elapsed cycles for that synthetic program**. This is not a measured
whole-game slowdown or a comparison against a fully fitted legacy controller.

## Battery SRAM lifecycle

The inherited backup reader could pop the response FIFO again before the next
halfword existed. A loader/vendor-RAM fixture reproduced `xxxx2211` returned
where RAM contained `2211/4433`. The standard profiles enable
`SAFE_RESPONSE_HANDSHAKE=1` and `READ_MEM_CLOCK_DELAY=2`: later beats wait for
nonempty FIFO, PLL loss clears FIFO/local state, and a reset reader first
observes read strobe low before accepting another request.

Every BEGIN clears RAM after draining previous operations; restore writes obey
the clear frontier, and counter completion still waits for controller idle.
Save traffic does not select cartridge configuration, create a valid ROM, or
clear a cartridge error. Slot-10 backup admission is fenced behind physical
operations. The host soft-reset path asserts asynchronously and releases over
three system edges, holding the CPU during backup.

These changes repair modeled SRAM transport behavior. They do not establish
power-loss atomicity, all-game save compatibility or hardware SRAM acceptance.
SRAM backup is distinct from save-state support.

## Build and source verification

Use an authorized Quartus Prime Lite 21.1.1 Build 850 installation with Cyclone V
support, device `5CEBA4F23C8`, Python 3 and Bash/flock. No Intel installer or
vendor simulation library is distributed here. Review source and generated
constraints before running tool scripts.

Build each profile serially in its own clean checkout. `generate.tcl` modifies
the tracked QSF, so reusing the preceding generated checkout would not give
the next build a clean source receipt. For each separate checkout:

```sh
export QUARTUS_SH=/path/to/quartus/bin/quartus_sh
export MSU1_BUILD_JOBS=1
bash tools/build_msu1.sh --check-tools
bash tools/build_msu1.sh msu_standard_ntsc
# In separate clean checkouts: msu_standard_pal and standard_ntsc_spc
```

Record exact source status, tool version, effective QSF, resources, all timing
corners, unconstrained paths, and output hashes. Reversing bits within each RBF
byte produces Pocket REV format; this conversion is not a new compilation or
hardware validation. A new PR commit needs new build evidence before release.

## Recorded verification and its limits

Historical functional qualification reports 53/53 groups, including 188 Python
tests. Counts overlap and must not be added into an inflated total. Execution
was recorded on the frozen test revisions, with 155 simulation inputs checked
against e71101f; this is source continuity, not a fresh complete run on e71101f
or on a later PR commit. Native builds used e71101f and these results:

| Profile | ALMs | RAM blocks | DSPs | Min setup ns | Min hold ns |
| --- | ---: | ---: | ---: | ---: | ---: |
| MSU NTSC | 17,421 | 291 | 24 | +0.341 | +0.102 |
| MSU PAL | 17,377 | 291 | 24 | +0.038 | +0.107 |
| SPC NTSC | 16,141 | 216 | 20 | +0.869 | +0.085 |

Reported internal four-corner TNS is zero. PAL's 38-ps setup margin is small.
Conditional external I/O analysis assumes zero PCB flight and extra margin;
it is not board-level measurement. Actual PCB skew, loading, signal integrity,
firmware pacing, SD latency, raw PLL/reset behavior and numerical MTBF remain
unqualified. Positive internal slack alone does not close those questions.

For new testing use Linux/WSL, Python 3.10+, Git, Bash, Icarus, GHDL with VHDL-2008
synthesis support, Verilator with `--binary --timing`, Yosys/ABC, Make and C++.
The archived reproduction versions are GHDL 5.0.1, Icarus 12.0, Verilator 5.032
and Yosys 0.52. Vendor-model tests additionally require the user's authorized
Quartus simulation models. Missing tools or missing historical reference
objects are **not run**, not passing checks.

```sh
python3 -m unittest discover -s tests -p test_assets.py -v
python3 -m unittest discover -s tests -p test_standard_save_testrom.py -v
```

The clean PR includes the historical regression sources, but not the private
engineering Git history or bulk evidence archives. The aggregate runners
`tools/test_msu1.py` and `tools/run_standard_memory_regression.py`, and the
historical packaging regression, still require pinned engineering references.
They are not advertised as runnable from this clean checkout alone. Supplying
reviewable, self-contained reference fixtures is an outstanding draft-review
item; replacing missing references with current RTL would invalidate the
comparisons. See [test scope](../tests/README.md). The two commands above use
original generated assets and do not require that historical Git history.

For source builds, use an existing Quartus Lite 21.1 installation with Cyclone V
support and run `bash tools/build_msu1.sh msu_standard_ntsc`,
`bash tools/build_msu1.sh msu_standard_pal`, or
`bash tools/build_msu1.sh standard_ntsc_spc`. A successful build does not by
itself qualify timing or hardware operation. The historical packaging tool
accepts only its pinned, reviewed source identities; it is not a release tool
for this new PR commit.

During PR preparation, all 11 selected source/documentation files from the
final `08cace3` delta were verified against their byte counts, SHA-256 hashes,
and Git blob IDs in an isolated worktree. Production RTL and build inputs
remain those of `e71101f`. Public historical Markdown records add an archive
availability note; one validation JSON replaces an absolute local path with
a logical relative archive reference. These documented adaptations are not
claims to reproduce the complete historical `08cace3` tree.

## Installation and hardware test

The experimental package maps loader ID 0/main to `msu_standard_ntsc`, ID 1/
SPCSDD1 to `standard_ntsc_spc`, and ID 2/PAL to `msu_standard_pal`. Do not duplicate
one main image into the other slots. Merge only intended package files into a
blank/spare card. Do not distribute commercial ROMs, audio packs, saves or
prewritten simulation SRAM images.

The experimental core ID is `agg23.SNES-STD-EXPERIMENT`. With platform `snes`,
assets live at `/Assets/snes/common` and saves at `/Saves/snes/common`.
**A different core name alone does not isolate those common saves.**

For an isolated small-directory diagnostic, set only that experimental core's
`metadata.platform_ids` to `["snes_msu_diag"]`, add
`/Platforms/snes_msu_diag.json` with the display name `SNES MSU Diagnostic`, and
place original test assets in `/Assets/snes_msu_diag/common`. Standard APF save
paths then use `/Saves/snes_msu_diag/common`. Back up the original core JSON and
verify its hash before this reversible change; restoring it restores the old
platform path. No existing ROM or save needs to be moved.

Generate original assets locally:

```sh
python3 tools/msu1_testrom.py --out build/msu-diagnostic \
  --basename MSU1-STD-e71101f-HOMEBREW
```

Copy only the resulting SFC, MSU and two PCM files into the test directory;
keep the manifest on the computer for hash verification. Check visibility
before launch, then record on-screen data checks, each available track,
pause/resume, repeat, intentionally absent track 3 and reload behavior. Record
firmware, build hash, region, card, observed behavior and failures separately.

For battery SRAM, separately generate the original save smoke program with
`tools/standard_save_testrom.py generate --out build/save-diagnostic`. Start
with no prewritten save: first boot initializes erased SRAM and shows blue;
quit normally and wait; second boot should validate all bytes, show green and
counter 2. Quit normally, export only that disposable test save, then run:

```sh
python3 tools/standard_save_testrom.py check-save /path/to/test-export.sav \
  --expect-counter 2 \
  --expect-sha256 073f5a2e3d47ef13360f6e4d41a1bb6960ba5a08c64bb90bde0f6f501c744633
```

Expected length is 2,048 bytes. Red, a repeated first-boot blue screen, an
unexpected length/content or any error is a failed smoke test. Preserve the
result instead of rewriting it or trying real saves. This smoke is not a
general hardware-save acceptance test.

On 2026-10-05 the tester reported successful Pocket execution of the original
MSU diagnostic and a privately supplied Chrono Trigger MSU game. That report
does not establish PAL operation, SRAM persistence, long-term stability or
broader game compatibility. No commercial content accompanies this work.

During that test, a common directory with 1,745 entries did not show the two
new MSU ROMs. Both had valid `.sfc` names and normal attributes, and the original
diagnostic matched its hash. They appeared late in host enumeration; an
independent small asset directory subsequently worked. This supports a
directory-size/enumeration hypothesis, but establishes no exact Pocket limit
and does not prove that companion `.msu` files hide ROMs.

## Review and release boundary

Keep upstream attribution and GPLv3 notices. Submit source, original test
generators, reproducible fixtures and concise evidence summaries. Do not push
engineering bundles/history containing bulk logs, local paths, installers,
vendor models or bitstreams. Native build and simulation evidence must be
bound to the reviewed source; changes made while preparing the PR require
their own validation. The upstream PR workflow currently builds legacy
profiles and must not be presented as standard-profile qualification.
