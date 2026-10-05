#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH=/tmp/msu1-tools/bin:$PATH
BUILD=$(mktemp -d /tmp/sdd1-legacy.XXXXXX)
for FILE in InputMgr Decoder SDD1; do
    git show b63f800:rtl/upstream/chip/SDD1/$FILE.vhd | sed -e 's/InputMgr/InputMgr_Baseline/g' -e 's/SDD1_Decoder/SDD1_Decoder_Baseline/g' -e 's/entity SDD1 is/entity SDD1_Baseline is/g' -e 's/end SDD1;/end SDD1_Baseline;/g' -e 's/of SDD1 is/of SDD1_Baseline is/g' > "$BUILD/$FILE.vhd"
done
ghdl -a --std=08 -fsynopsys --workdir="$BUILD" "$BUILD/InputMgr.vhd" "$BUILD/Decoder.vhd" "$BUILD/SDD1.vhd" \
    rtl/upstream/chip/SDD1/InputMgr.vhd rtl/upstream/chip/SDD1/Decoder.vhd rtl/upstream/chip/SDD1/SDD1.vhd tests/sdd1_waits/tb_sdd1_legacy.vhd
ghdl -r --std=08 -fsynopsys --workdir="$BUILD" tb_sdd1_legacy --assert-level=error
