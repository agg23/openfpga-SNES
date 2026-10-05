# Test scope for the draft MSU-1 contribution

From the repository root, these source tests are self-contained:

```sh
python3 -m unittest discover -s tests -p test_assets.py -v
python3 -m unittest discover -s tests -p test_standard_save_testrom.py -v
python3 -m unittest discover -s tests -p test_package_standard_msu1.py -v
python3 -m unittest discover -s tests -p test_standard_package_sources.py -v
```

They check packaging policy, Git source handling, the generated diagnostic
program, formats, simulated instruction behavior, and disposable save validator. They do not simulate the full SNES
or validate FPGA hardware. During local PR preparation, all 25 tests passed.
The PCM HDL class was not run because Icarus was unavailable in that Windows
environment. A local temporary-directory adapter was needed for its sandbox;
the checked-in test assertions were unchanged. The latest Linux clean-export
run needs no sandbox adapter: 15 asset tests, 10 save-validator tests, all 81
packaging-policy tests and 7 real-Git/fixture-integrity tests pass (113 total).
That export has no `.git` directory or engineering history. The dedicated
`MSU source tests` workflow runs these same commands.

Other tests and tools are retained engineering regression sources. Many need
Linux, HDL simulators, user-provided Quartus simulation models, and exact old
Git objects (including `b63f800`, `982f103`, `84d8d5e`, `3ddde3f`, `116961d`,
and `af743650`). Those engineering objects and generated evidence archives
are not included here. In particular, full unittest discovery, the aggregate
standard-memory runner, and historical package generation are not standalone
clean-checkout acceptance commands. Missing dependencies are not a pass.

The packaging-policy dependency is now supplied by [pinned source snapshots](fixtures/standard_package/README.md).
All original mutation/rejection assertions remain. The test-only source
provider does not alter production packaging, and separate real-Git tests
cover committed bytes, missing revisions, empty selections, object types and
symlink rejection. Other historical HDL comparisons still need their inputs;
this change does not claim those aggregate suites are standalone.

Before this fixture change, the final 81-test packaging suite was attempted in an isolated Linux
checkout carrying the verified 11-file final delta. Locally, 74 passed and
7 failed/errored because required historical Git objects were absent from the
available bundles (4 failures, 3 errors). That attempt was not a pass.
That earlier dependency failure is resolved by the 81/81 clean-export run
above. Historical complete-history verification is separate evidence.

See [the review guide](../docs/MSU1-STANDARD.md) for separately identified
historical qualification and limited real-hardware feedback.
