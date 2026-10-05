#!/usr/bin/env bash
# Native unit synthesis only. No placement/routing or physical timing claim.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
quartus=$(command -v "${QUARTUS_SH:-quartus_sh}")
out=${1:-"$root/build/save-reader-map"}; mkdir -p "$out"; out=$(cd "$out" && pwd)
run=$(mktemp -d "$out/map-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
"$quartus" --version > "$run/quartus-version.log"
sha256sum "$root/target/pocket/data_unloader.sv" > "$run/source-sha256.log"
for safe in 0 1; do
  d="$run/safe$safe"; mkdir -p "$d"
  cat > "$d/top.sv" <<SV
module save_reader_unit(input clk_74a,clk_memory,reset_n,bridge_rd,bridge_endian_little,
 input [31:0] bridge_addr,output [31:0] bridge_rd_data,output read_en,
 output [16:0] read_addr,input [15:0] read_data);
 data_unloader #(.ADDRESS_MASK_UPPER_4(4'h2),.ADDRESS_SIZE(17),.INPUT_WORD_SIZE(2),
 .READ_MEM_CLOCK_DELAY($safe ? 2 : 7),.SAFE_RESPONSE_HANDSHAKE($safe)) dut(.*);
endmodule
SV
  printf 'QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n' > "$d/unit.qpf"
  cat > "$d/unit.qsf" <<QSF
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY save_reader_unit
set_global_assignment -name SYSTEMVERILOG_FILE "$root/target/pocket/data_unloader.sv"
set_global_assignment -name SYSTEMVERILOG_FILE "$d/top.sv"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZATION_MODE "AGGRESSIVE AREA"
set_instance_assignment -name VIRTUAL_PIN ON -to *
QSF
  cat > "$d/map.tcl" <<'TCL'
load_package flow
project_open unit
execute_module -tool map
project_close
TCL
  (cd "$d" && "$quartus" -t map.tcl > map.log 2>&1) || { tail -60 "$d/map.log"; exit 1; }
  echo "SAFE_RESPONSE_HANDSHAKE=$safe"
  grep -E 'Total registers|Total block memory bits|Total RAM Blocks|Combinational ALUT usage|Memory ALUT usage' "$d/output_files/unit.map.rpt"
done
sha256sum -c "$run/source-sha256.log"
echo "Native unit map only: $run"
