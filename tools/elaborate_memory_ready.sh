#!/usr/bin/env bash
# Native Quartus syntax/semantic/hierarchy check only. No fitter/STA/bitstream.
set -euo pipefail
profile=${1:-ntsc}
case "$profile" in available|ntsc|pal|spc) ;; *) echo 'usage: tools/elaborate_memory_ready.sh available|ntsc|pal|spc' >&2;exit 2;; esac
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
quartus_sh=$(command -v "${QUARTUS_SH:-quartus_sh}") || { echo 'Installed approved Quartus required' >&2;exit 127; }
quartus_map="$(dirname "$quartus_sh")/quartus_map"
out=${MEMORY_READY_ELAB_ROOT:-"$root/build/memory-ready-elaboration"}
mkdir -p "$out";out=$(cd "$out" && pwd)
run=$(mktemp -d "$out/$profile-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
printf '%s\n' "$run" | tee "$out/latest-$profile.path"
"$quartus_sh" --version > "$run/quartus-version.log"
printf 'QUARTUS_VERSION = "21.1"\nPROJECT_REVISION = "unit"\n' > "$run/unit.qpf"
if [[ "$profile" == available ]];then top=MAIN_SNES;else top=core_top;fi
cat > "$run/unit.qsf" <<QSF
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name TOP_LEVEL_ENTITY $top
set_global_assignment -name QIP_FILE "$root/rtl/snes.qip"
set_global_assignment -name VERILOG_FILE "$root/platform/pocket/common.v"
set_global_assignment -name QIP_FILE "$root/platform/pocket/mf_ddio_bidir_12.qip"
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_instance_assignment -name VIRTUAL_PIN ON -to *
QSF
if [[ "$profile" == available ]];then
 cat >> "$run/unit.qsf" <<QSF
# Use the production platform dependency manifest so MAIN_SNES-only checks
# include the WRAM timing stages and future platform helpers too.
set_global_assignment -name QIP_FILE "$root/target/pocket/core.qip"
set_parameter -name USE_STANDARD_SDRAM -entity MAIN_SNES 1
set_parameter -name USE_SA1 -entity MAIN_SNES 1
set_parameter -name USE_SPC7110 -entity MAIN_SNES 1
set_parameter -name USE_DSPn -entity MAIN_SNES 1
set_parameter -name USE_MSU -entity MAIN_SNES 1
set_parameter -name USE_SUFAMI -entity MAIN_SNES 1
QSF
else
 cat >> "$run/unit.qsf" <<QSF
set_global_assignment -name QIP_FILE "$root/target/pocket/core.qip"
set_global_assignment -name VERILOG_FILE "$root/platform/pocket/mf_datatable.v"
set_parameter -name USE_STANDARD_SDRAM -entity core_top 1
QSF
 if [[ "$profile" == spc ]];then
  echo 'set_parameter -name USE_MSU_POCKET -entity core_top 0' >> "$run/unit.qsf"
  flags=(USE_SDD1 USE_SPC7110 USE_BSX)
 else
  echo 'set_parameter -name USE_MSU_POCKET -entity core_top 1' >> "$run/unit.qsf"
  flags=(USE_CX4 USE_GSU USE_SA1 USE_DSPn USE_MSU)
 fi
 for flag in "${flags[@]}";do echo "set_parameter -name $flag -entity MAIN_SNES 1" >> "$run/unit.qsf";done
 if [[ "$profile" == pal ]];then echo 'set_parameter -name PAL_PLL -entity core_top 1' >> "$run/unit.qsf";fi
fi
python3 - "$root" "$run" "$profile" <<'PY'
import hashlib,json,pathlib,subprocess,sys
root,out,profile=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2]),sys.argv[3]
files=[p for d in ['rtl','target/pocket','platform/pocket'] for p in (root/d).rglob('*') if p.is_file()]
manifest={'profile':profile,'stage':'Analysis & Elaboration ONLY','commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
 'dirty':subprocess.check_output(['git','status','--short'],cwd=root,text=True).splitlines(),
 'sources_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
(out/'source-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
set +e
(cd "$run" && "$quartus_map" unit --analysis_and_elaboration > elaborate.log 2>&1)
rc=$?
set -e
source_check=0
python3 - "$root" "$run" "$rc" <<'PY_VERIFY' || source_check=$?
import datetime,hashlib,json,pathlib,sys
root,out=pathlib.Path(sys.argv[1]),pathlib.Path(sys.argv[2])
path=out/'source-manifest.json';manifest=json.loads(path.read_text())
files=[p for d in ['rtl','target/pocket','platform/pocket'] for p in (root/d).rglob('*') if p.is_file()]
after={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
manifest['source_stable']=after==manifest['sources_sha256']
manifest['elaboration_exit_code']=int(sys.argv[3])
manifest['finished_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
path.write_text(json.dumps(manifest,indent=2)+'\n')
if not manifest['source_stable']:
    raise SystemExit('Elaboration source changed: result rejected; rerun a fixed snapshot')
PY_VERIFY
if ((rc == 0 && source_check != 0));then rc=$source_check;fi
grep -E 'Error \(|Analysis & Elaboration was|Elapsed time|Peak virtual' "$run/elaborate.log" | tail -30
printf 'Elaboration exit=%s; %s\nNo synthesis-resource, fitted timing, bitstream, or hardware claim.\n' "$rc" "$run"
exit "$rc"
