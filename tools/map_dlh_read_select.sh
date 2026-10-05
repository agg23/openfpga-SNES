#!/usr/bin/env bash
# Optional licensed-Quartus unit synthesis only; never runs fitting or timing.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
quartus=$(command -v "${QUARTUS_MAP:-quartus_map}") || { echo 'Installed quartus_map required' >&2; exit 127; }
out=${1:-"$root/build/dlh-resource-map"}
mkdir -p "$out"
out=$(cd "$out" && pwd)
run=$(mktemp -d "$out/dlh-read-select-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
printf '%s\n' "$run"
"$quartus" --version > "$run/quartus-version.log"
(cd "$root" && git rev-parse HEAD) > "$run/source-commit.txt" 2>/dev/null || true
sha256sum "$root/rtl/upstream/chip/DSP/DSP_LHReadSelect.vhd" "$root/tests/timing/dlh_read_select_unit.sv" > "$run/source-sha256.txt"
for choice in original dual; do
  use_dma=0; [[ $choice == dual ]] && use_dma=1
  dir="$run/$choice"; mkdir -p "$dir"
  cp "$root/tests/timing/dlh_read_select_unit.sv" "$dir/unit.sv"
  printf 'QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n' > "$dir/unit.qpf"
  cat > "$dir/unit.qsf" <<QSF
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY unit
set_global_assignment -name SYSTEMVERILOG_FILE unit.sv
set_global_assignment -name VHDL_FILE "$root/rtl/upstream/chip/DSP/DSP_LHReadSelect.vhd"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
set_global_assignment -name MUX_RESTRUCTURE ON
set_global_assignment -name AUTO_RESOURCE_SHARING ON
set_parameter -name USE_DMA $use_dma
set_instance_assignment -name VIRTUAL_PIN ON -to *
QSF
  (cd "$dir" && "$quartus" unit > map.log 2>&1) || { tail -30 "$dir/map.log" >&2; exit 1; }
  echo "$choice:"
  grep -m1 '; |unit ' "$dir/output_files/unit.map.rpt"
done
echo 'Unit synthesis only: inspect ALUT/FF/RAM/DSP rows. No whole-core fit, ALM, or timing claim.'
