#!/usr/bin/env bash
# Native Cyclone V unit synthesis ONLY. Does not fit the core or run STA.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
quartus=$(command -v "${QUARTUS_SH:-quartus_sh}") || { echo 'Installed quartus_sh required' >&2; exit 127; }
out=${1:-"$root/build/rom-download-map"}
mkdir -p "$out"; out=$(cd "$out" && pwd)
run=$(mktemp -d "$out/map-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
echo "$run"
"$quartus" --version > "$run/quartus-version.log"
sha256sum "$root/rtl/memory_ready/rom_download_queue.sv" > "$run/source-sha256.log"
printf 'QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n' > "$run/unit.qpf"
cat > "$run/unit.qsf" <<QSF
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY rom_download_queue
set_global_assignment -name SYSTEMVERILOG_FILE "$root/rtl/memory_ready/rom_download_queue.sv"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_global_assignment -name OPTIMIZATION_TECHNIQUE AREA
set_instance_assignment -name VIRTUAL_PIN ON -to *
QSF
cat > "$run/map.tcl" <<'TCL'
load_package flow
project_open unit
execute_module -tool map
project_close
TCL
(cd "$run" && "$quartus" -t map.tcl > map.log 2>&1) || { tail -50 "$run/map.log" >&2; exit 1; }
grep -E 'Total registers|Total block memory bits|Total RAM Blocks|Combinational ALUT usage|Memory ALUT usage' "$run/output_files/unit.map.rpt"
echo 'Native unit map only; no full-core fit, physical CDC/SDRAM timing, or hardware claim.'
