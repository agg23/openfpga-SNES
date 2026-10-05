# Test scope for the draft MSU-1 contribution

From the repository root, these original-asset tests are self-contained:

```sh
python3 -m unittest discover -s tests -p test_assets.py -v
python3 -m unittest discover -s tests -p test_standard_save_testrom.py -v
```

They check the generated diagnostic program, formats, simulated instruction
behavior, and disposable save validator. They do not simulate the full SNES
or validate FPGA hardware. During local PR preparation, all 25 tests passed.
The PCM HDL class was not run because Icarus was unavailable in that Windows
environment. A local temporary-directory adapter was needed for its sandbox;
the checked-in test assertions were unchanged.

Other tests and tools are retained engineering regression sources. Many need
Linux, HDL simulators, user-provided Quartus simulation models, and exact old
Git objects (including `b63f800`, `982f103`, `84d8d5e`, `3ddde3f`, `116961d`,
and `af743650`). Those engineering objects and generated evidence archives
are not included here. In particular, full unittest discovery, the aggregate
standard-memory runner, and historical package generation are not standalone
clean-checkout acceptance commands. Missing dependencies are not a pass.

Making the historical reference comparisons independently reproducible with
reviewed source fixtures remains a draft-review task. No baseline comparison
has been replaced with the candidate implementation to make tests pass.

The final 81-test packaging suite was also attempted in an isolated Linux
checkout carrying the verified 11-file final delta. Locally, 74 passed and
7 failed/errored because required historical Git objects were absent from the
available bundles (4 failures, 3 errors). This is not an 81-test local pass.
The coordinating source verification reports 81/81 on its complete-history
checkout; that is separate evidence, not a replacement for the local result.

See [the review guide](../docs/MSU1-STANDARD.md) for separately identified
historical qualification and limited real-hardware feedback.
