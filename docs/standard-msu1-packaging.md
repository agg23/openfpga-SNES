> Historical engineering record from source/docs revision `08cace3`.
> The bulk evidence archives and engineering Git objects cited below are not
> distributed in this clean PR. See [the current review guide](MSU1-STANDARD.md) for current scope and validation limits.

# Reviewed standard-refresh identities: independent local packaging

`tools/package_standard_msu1.py` stages the **standard-refresh** experiment in a
new local directory. The old `tools/package_msu1.py`, its profiles, package
identity, b63 outputs, source templates and production RTL are unchanged.
Nothing is installed, uploaded, published, mounted, or written to a real SD.

**Status: the controlled candidate is now
`e71101fd06a452da53cb0924e1d3701f53133435`. Its PAL Standard Fit/seed 2 run is
still unqualified. No actual three-image package has been created.** The
retained 0da938e NTSC and SPC runs have separate internal timing closure, but
0da938e PAL failed C4 setup (-0.231 ns) and hold (-0.026 ns). Those old images
cannot fill missing new-source profiles. See the source-matched
[native build record](memory-ready/native-builds.md) and
[controlled placement experiment](memory-ready/pal-placement-experiment.md).
Nothing in this packager changes timing, hold constraints, source code or
hardware-verification flags. Even if the new PAL experiment fails, its identity
remains explicitly unverified rather than being promoted or silently replaced.

## Explicit reviewed-source selection

The versioned configuration `tools/standard_msu1_reviewed_sources.json` retains
all four identities. Selection is mandatory on the CLI via `--source-identity`:

| Source identity | Exact required build source commit | Hardware anchor |
| --- | --- | --- |
| `baseline-982f103` | `982f103a0d7fa39294b760738ceaed5bb88eddad` | same commit |
| `candidate-64b5b51` | `aed6dd78f7852304d25c396763f47ae14d549b21` | `64b5b51f06128147c7973834baff03a1d7bf5f98` |
| `candidate-0da938e` | `0da938eb1eaaefc6ff23347568cd69a8240e4f37` | `30f55d5be697b9f740d8e5510d22d56201a4b3bf` |
| `candidate-e71101f` | `e71101fd06a452da53cb0924e1d3701f53133435` | `3320a78f44ce8a56bc6168d8869371fd2d4c7608` |

The newest e711 identity includes **173** committed hardware inputs and pins
`a9c619f6a2b1fa60b25dbbd9f5d39ad1f4a57e1c045b546b6c53a02545c41f29`.
Relative to 0da938e, only `generate.tcl`, `tools/build_msu1.sh` and the new
`target/pocket/standard_pal_fit.tcl` differ. RTL/QIP/SDC remain unchanged. The
new helper is 1,554 bytes, SHA-256
`715334f5e91d09dccdc3980683711edd7d0a0b1165becc9f69a03a9ee679ae91`.
All three manifests must name the exact e711 source, including NTSC/SPC even
though their requested seed/effort values remain at the earlier defaults.

The retained 0da938e identity includes **172** committed hardware inputs. Its canonical
inventory SHA-256 is
`e639440406e489e7ac46dce032baa1b13ef7878593a88f40860742255601a723`.
Relative to aed6dd7, only `generate.tcl` and the newly included
`target/pocket/standard_wram_state.tcl` differ in this hardware inventory. The
new helper is 1,450 bytes with SHA-256
`346a0df40700c1e5497f07f52bbd0abcfc4fd9177ad0c59a9a9f238e2d1f264a`.
It scopes eight `ALLOW_SYNCH_CTRL_USAGE OFF` assignments to standard WRAM state
flops. The production RTL/QIP/SDC are unchanged. The mapped 144-register and
98-pad equivalence evidence is documented in
[wram-state-sync-control-evidence.md](wram-state-sync-control-evidence.md),
committed as 8f50b5a. Packaging does not rerun or independently certify that proof.

The three previous identities keep their original fields and old schema; the
older 171-file identities remain:
- Original 982f103: 171 inputs, fingerprint
  `177a7b4c6148e4dd8f4694f74f96831a30cccd0255f7b557e527e8fa3341d188`
- aed6dd7 / 64b5b51: 171 inputs, fingerprint
  `90b21fdb95ed482fcdabbad78cb7eeb066eb35a5ee6e3ab2c0de941833101ecb`

All identities retain `unverified_candidate` status. The configuration cannot
promote release/hardware flags, even when separate timing review reports success.

All three manifests must match the selected identity's exact build commit, and
both its source and hardware-anchor inventories must match the configured
SHA-256. No automatic fallback, arbitrary `--baseline`, hash override or
validation bypass exists. Even a different commit with identical hardware is
rejected until explicitly added through another reviewed source change. The
private Python API retains the original identity default for existing tests;
latest-candidate API calls must select `source_identity="candidate-e71101f"`.

The selected identity controls experiment version and default homebrew basename
and is recorded, with the exact configuration bytes/hash, in package evidence.
The original source template/homebrew anchor remains 982f103. The separate
75dd Save smoke addon stays separate; this tool includes no prewritten `.sav`.
The earlier update is recorded in `standard-msu1-source-identities-validation.json`;
the retained 0da NTSC check is recorded in `standard-msu1-source-0da-validation.json`.
This controlled-receipt update is recorded in
`standard-msu1-source-e711-validation.json`.

## Identity and save-data boundary

The new staged directory is:

`Cores/agg23.SNES-STD-EXPERIMENT`

It differs from `Cores/agg23.SNES` and the previous b63 delivery. Its `author`
remains `agg23`, its `shortname` is `SNES-STD-EXPERIMENT`, and the upstream URL is
preserved. The description, prerelease version and displayed information label
it as an unpublished local experiment, with attribution to agg23's Pocket port
and srg320's SNES core. It is not an upstream release or endorsement. The date
field records this local experiment's metadata date, not a public release.

The [official core definition convention](https://www.analogue.co/developer/docs/openfpga/core-definition-files)
requires the directory to match `author.shortname`. The
[official core metadata schema](https://www.analogue.co/developer/docs/openfpga/core-definition-files/core-json)
limits author and shortname to 31 characters, description to 63, and version to
31; this identity stays within those limits. Loader-selected REV filenames
remain below the 15-character limit. Sources checked on 2026-10-04.

**A different core name does not isolate real saves.** Platform `snes` and
nonvolatile slot 10 remain unchanged. The
[official SD-directory documentation](https://www.analogue.co/developer/docs/openfpga/directories-and-sd-folder-structure)
places common assets and corresponding nonvolatile saves under platform paths.
Thus choosing an existing game can reuse its existing `Saves/snes/common/...`
save even with the new core ID. Do not test on the working SD. Use a blank/spare
SD, only the original generated homebrew, and a separately verified backup of
the entire original SD and all saves. This tool never performs that transfer.

The selected default homebrew stem (`MSU1-STD-e71101f-HOMEBREW` for the latest
candidate, or the retained 0da938e/64b5b51/982f103 stems for older identities) reduces accidental
filename collisions; it is not a security boundary or a guarantee of save
isolation. Custom stems must start `MSU1-STD-` and use only ASCII letters,
digits, underscores or hyphens. No commercial ROM or music is accepted.

## Exactly three completed profiles

| Build manifest profile | Source REV beside build.json | Staged REV | Loader mapping |
| --- | --- | --- | --- |
| `msu_standard_ntsc` | `snes_msu_standard_ntsc.rev` | `snes_main.rev` | `main`, ID 0 |
| `standard_ntsc_spc` | `snes_standard_spc.rev` | `snes_spc.rev` | `SPCSDD1`, ID 1 |
| `msu_standard_pal` | `snes_msu_standard_pal.rev` | `snes_pal.rev` | `PAL`, ID 2 |

`support/loader.asm` selects ID 1 for SPC7110/S-DD1/BSX before checking PAL and
selects ID 2 for other PAL cartridges. ID 1 **must** come from
`standard_ntsc_spc`; renaming a main MSU image is not a substitute. Its standard
SDRAM path is enabled while its MSU hardware is disabled. Legacy `msu_ntsc`,
`msu_pal`, `ntsc_spc` and other profiles are rejected here.

For each run, retain `build.json`, its RBF and REV, and these adjacent files:

- `quartus-version.log` and `compile.log`
- `snes_pocket.map.rpt`
- `snes_pocket.fit.summary`
- `snes_pocket.asm.rpt`
- `snes_pocket.flow.rpt`

For e711, the complete adjacent `snes_pocket.fit.rpt` is additionally mandatory,
with the wrapper's `fitter_settings_report` byte-count/SHA-256 receipt and
`actual_fitter_settings` in `build.json`. It is copied as a seventh provenance
report. The three older identities continue accepting their original six-report
schema, without fabricated/backfilled receipts.

The normal build wrapper already emits these. Keep the full original timing,
fit, CDC and I/O archives separately; this packager copies these six provenance
reports but does not evaluate timing closure.

## Controlled fitter receipt policy for e711

The selected source requires these **actual** native report settings:

| Profile | Fitter Initial Placement Seed | Fitter Effort | Optimize Hold Timing | Optimize Multi-Corner Timing |
| --- | --- | --- | --- | --- |
| `msu_standard_ntsc` | `1` | `Auto Fit` | `All Paths` | `On` |
| `msu_standard_pal` | `2` | `Standard Fit` | `All Paths` | `On` |
| `standard_ntsc_spc` | `1` | `Auto Fit` | `All Paths` | `On` |

Requested options, generated QSF, a fitter summary, or a copied declaration do
not substitute for the complete native report. The packager requires:

1. `fitter_settings_report` containing exactly `file`, integer `bytes`, and
   `sha256`; the filename must be the adjacent `snes_pocket.fit.rpt`
2. Actual raw bytes matching both the receipt size and hash, without symlinks,
   path traversal, substituted filenames or synthetic markers in real inputs
3. A full fitter report with one successful summary and the expected device,
   revision and top-level identity
4. Exactly one occurrence of each named setting in the authoritative Fitter
   Settings section, reading the Setting column rather than Default Value
5. `actual_fitter_settings` containing exactly those four string values, equal
   to the report and to the selected source/profile's configured expectations

The full original report is copied byte-for-byte and hashed in package
inventory. It can contain legacy-encoded temperature symbols or CRLF line
endings: parsing normalizes display text only, after the raw-byte integrity
check. Missing/duplicate setting rows, a changed actual report, stale receipts,
wrong seed/effort, disabled hold/multicorner, and NTSC/SPC with PAL controls all
fail closed. Marker-bearing regression fixtures stay synthetic and cannot be
promoted by this path.

Direct `read_build` calls for the exact e711 source also enforce its receipt.
Removing its policy from the catalog cannot downgrade it to the older schema.
Changing catalog seed/effort values to another profile's tuple is also rejected.
Existing map/profile/coprocessor checks remain required as well. Checked values
and the original receipt are retained in each profile's package provenance.
These are consistency checks; they do not certify a maliciously fabricated
compiler run or substitute for timing/CDC/I/O and hardware qualification.

## Refusal checks and their limits

All input checks precede output creation:

- Exact completed state `bitstream_generated_unverified`, profile and
  `5CEBA4F23C8` target, integer zero exit status, explicit verification booleans
  and ordered UTC start/finish timestamps
- Full lowercase source commit and empty source status from a clean checkout;
  the three manifests must name the **same commit**
- Every committed file under `rtl/`, `platform/`, `target/`, `projects/`, plus
  `generate.tcl` and `tools/build_msu1.sh`, must match the selected reviewed
  hardware anchor byte-for-byte and match its fixed SHA-256; the resulting inventory
  and SHA-256 are preserved in `evidence/hardware-inputs.json`
- The source Git repository must contain those immutable commits and regular
  blobs; unknown commits, Git symlinks/submodules, mixed sources and changed
  hardware inputs are rejected. The exact selected build-source commit is
  required as well; an unlisted tool/docs commit cannot silently replace it
- Both exact RBF/REV filenames, manifest SHA-256 and byte counts, nonempty files,
  and the complete bytewise bit reversal with unchanged byte order
- Distinct bitstreams for each profile; a main image cannot populate SPC/PAL
- Real Quartus 21.1 Lite version, successful fitter/assembler/flow and target
  device evidence, successful assembler in the compile log, and exact effective
  top/core standard/MSU/PAL and all coprocessor parameters in the map report
- RBF payload sanity envelope 1,000,000 to 8,388,608 bytes. This is **only** a
  tiny/truncated-fixture guard, not configuration-format validation. Actual
  historical standard NTSC and SPC lengths differ (2,139,948 vs 1,919,252 bytes)
- Synthetic/compiler-test markers are rejected. Stripping only a fixture flag,
  relabeling its profile, or padding a still-marked fixture does not make it real
- The source-only `pkg/pocket` must exactly match the frozen template, including
  loader, icons, platform files, all slots and all JSON features. The only output
  changes are the core directory, clearly experimental metadata and displayed
  `info.txt`. Exact original `core.json`/`info.txt` are retained as evidence
- Homebrew generator must match the frozen original. ROM, data, PCM, symbols,
  manifest, deliberately missing third track and all hashes must match the
  regenerated original bytes. Extra files in the asset directory are refused
- Files and **all existing ancestor components** may not be symlinks; special
  files are refused. Use absolute paths or ordinary relative paths without `..`
- Output must be entirely new, have an existing real parent, and be outside all
  input directories. Existing files/directories, including an empty SD folder,
  are refused. Failure removes only newly created private staging

These checks establish **consistency of supplied provenance**, not trustworthy
compiler attestation. A clean status string cannot prove that a worktree never
changed during compilation; Git comparison proves committed input identity,
not an independently observed compile. Generated files such as `build_id.mif`,
profile-exported QSF state and installed Quartus/vendor libraries are not part
of the committed-input fingerprint; relevant effective profile parameters are
checked separately from the map report. Hashes, logs and manifests could all be
maliciously fabricated together. This tool cannot cryptographically detect
that or authenticate arbitrary FPGA payloads; `compiler_run_authenticated`
stays false. Use the trusted local build/qualification process and keep its
external observations. Do not describe this as proof against every forgery.

No report or source-manifest claim promotes the package to timing/hardware
verified. `loadability_verified`, `timing_verified`, `hardware_verified`,
`ready_for_release`, and `common_saves_isolated` all stay false. Negative timing
slack is not made acceptable by successful packaging. Hardware qualification
remains a separate, explicit activity.

## Reproduce and connect the pending real builds

Python 3.10+ and Git are required. Use this packaging checkout, including its
unchanged legacy helper and original homebrew generator. It does not need a
Quartus installation itself and never invokes one.

The build commands belong in the clean, selected **build** checkouts, not this
packaging worktree. They are provided as reproduction instructions; do not
restart currently running qualification jobs merely to package them:

```sh
# In the appropriate clean e71101f build worktree, once per profile:
QUARTUS_SH=/absolute/path/to/quartus_sh tools/build_msu1.sh msu_standard_ntsc
QUARTUS_SH=/absolute/path/to/quartus_sh tools/build_msu1.sh msu_standard_pal
QUARTUS_SH=/absolute/path/to/quartus_sh tools/build_msu1.sh standard_ntsc_spc
```

For `candidate-e71101f`, all three build runs must use the clean
`e71101fd06a452da53cb0924e1d3701f53133435` source. Wait for each final
`build.json` to reach `bitstream_generated_unverified`,
complete the separate timing/CDC/I/O qualification review, and preserve the
exact run directories. Then use three actual absolute manifest paths:

```sh
# In this packaging checkout:
mkdir -p build
python3 tools/msu1_testrom.py \
  --out build/standard-homebrew \
  --basename MSU1-STD-e71101f-HOMEBREW

python3 tools/package_standard_msu1.py \
  --source-identity candidate-e71101f \
  --msu-standard-ntsc /absolute/final-ntsc-run/build.json \
  --msu-standard-pal /absolute/final-pal-run/build.json \
  --standard-ntsc-spc /absolute/final-spc-run/build.json \
  --assets build/standard-homebrew \
  --output build/standard-e71101f-local-staging
```

The placeholder paths are **not evidence that final builds exist**. A missing,
failed or unfinished input blocks the command. `--source-repository` can name
another local Git repository containing the commits; default is this checkout.
`--template` defaults to the original frozen `pkg/pocket`. To reproduce the old
identity, explicitly select `baseline-982f103` and generate its corresponding
`MSU1-STD-982f103-HOMEBREW` assets. No synthetic CLI bypass exists.

The output contains `README-FIRST.txt`, `package.json`, provenance under
`evidence/`, and a new `sd/` staging tree. Inventory hashes cover every output
except the manifest itself. Identical input snapshots produce identical file
contents regardless of output directory (filesystem timestamps are excluded).
Neither whole-folder SD replacement nor incremental SD merge is implemented.
No source checkout, build archive, existing package, b63 artifact or SD is changed.

## Validation performed for this tool

```sh
python3 -m unittest discover -s tests -p 'test_package*msu1.py' -v
python3 -m unittest discover -s tests -p test_assets.py -v
python3 -m unittest discover -s tests -p test_build_msu1.py -v
```

The new end-to-end tests use clearly marked `synthetic_fixture_only` records and
a private Python API switch. Synthetic output has **no `sd/` directory**; its
payloads live under `synthetic-not-for-hardware/`, with unmistakable notice and
state. Temporary fixtures are removed after each test. They are never real
builds and must never be delivered as runnable SD packages.

Read-only integration checks also accepted real historical 7fa334b archives for
`msu_standard_ntsc` and `standard_ntsc_spc`, including actual size/hash/REV and
report/profile checks. The old images are not qualification of any selected reviewed identity and
are rejected as a complete package by the hardware-source gate. No full
real end-to-end package or real final standard PAL was validated during this
change. See `standard-msu1-packaging-validation.json` for exact test counts and
historical input fingerprints.

### Retained 0da938e NTSC read-only check

The completed `msu_standard_ntsc-20261004T160451Z-mWGDhx` run from the exact
0da938e source passed the current packager's individual-build checks:

- 2,127,624-byte REV, SHA-256
  `1c24a1441d43b7aa26b502fb5f4e915ec7ecf26366259164643909d090debf51`
- RBF SHA-256
  `0bfbaf27b885358fc52389e574b0a73fd286e11ad2f80437166a0805df33d993`
- Clean full source commit, selected 172-file fingerprint including the new Tcl
  helper, RBF-to-REV conversion, all six original reports and expected parameters
- Attempts to treat the same reports as PAL or SPC rejected by their differing
  PAL/MSU parameters

This was a read-only check of **one earlier real image**, not a three-image
package. No synthetic companion files were supplied. The subsequent 0da PAL
failure prevents claiming that source as timing-qualified across all profiles.
The controlled e711 candidate needs its own three completed, reviewed archives;
none of these earlier images can be relabeled as e711 evidence.

### Controlled-receipt parser validation boundary

The new regression tests exercise all three expected policies, missing/bad
receipts, changed reports, all four wrong settings, profile swaps, duplicate
rows, invalid status/identity, symlinks, marker removal, legacy display encoding,
policy downgrade attempts, mixed sources and old-identity compatibility. Positive
end-to-end fixtures remain synthetic and have no `sd/` directory.

The receipt parser also reads an existing real 0da NTSC full report to check its
native table format and raw byte preservation. Any receipt reconstructed in that
parser-only test is an in-memory test input, not a newly emitted build manifest
or e711 compiler evidence. The new e711 full-fit receipt and actual three-image
staging path remain untested until the corresponding native archives are given.
