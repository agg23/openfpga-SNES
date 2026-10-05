#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
export PATH=/tmp/msu1-tools/bin:$PATH
BUILD="${SDD1_BUILD_DIR:-$(mktemp -d /tmp/sdd1-waits.XXXXXX)}"
mkdir -p "$BUILD"
git show b63f800:rtl/upstream/chip/SDD1/Decoder.vhd | sed 's/SDD1_Decoder/SDD1_Decoder_Baseline/g' > "$BUILD/DecoderBaseline.vhd"
BRIDGE=rtl/upstream/chip/SA1/SA1RomBridge.vhd
if [[ ! -f "$BRIDGE" ]]; then BRIDGE=../standard-sa1-waits/rtl/upstream/chip/SA1/SA1RomBridge.vhd; fi
ghdl -a --std=08 -fsynopsys --workdir="$BUILD" "$BRIDGE" "$BUILD/DecoderBaseline.vhd" \
    rtl/upstream/chip/SDD1/InputMgr.vhd rtl/upstream/chip/SDD1/Decoder.vhd \
    rtl/upstream/chip/SDD1/SDD1.vhd rtl/upstream/chip/SDD1/SDD1Map.vhd tests/sdd1_waits/tb_sdd1_waits.vhd
ghdl -e --std=08 -fsynopsys --workdir="$BUILD" tb_sdd1_waits
ghdl -r --std=08 -fsynopsys --workdir="$BUILD" tb_sdd1_waits --assert-level=error "$@"
echo "build=$BUILD"
