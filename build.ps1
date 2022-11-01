if (($args.count -ne 1) -or ($args[0] -eq "")) {
  Write-Output "Expected build type arg"
  exit 1
}

$build_type = $args[0]

quartus_sh -t generate.tcl $build_type

$exitcode = $LASTEXITCODE
if ($exitcode -ne 0) {
  Write-Output "Build failed with $exitcode"
  exit $exitcode
}

$output_file = "snes_main.rev"

if (($build_type -eq "ntsc") -or ($build_type -eq "none")) {
  $output_file = "snes_main.rev"
} elseif (($build_type -eq "pal") -or ($build_type -eq "none_pal")) {
  $output_file = "snes_pal.rev"
} elseif ($build_type -eq "ntsc_spc") {
  $output_file = "snes_spc.rev"
}

C:\Users\adam\code\pocket-text\tools\reverse.exe C:\Users\adam\code\fpga\snes\src\fpga\output_files\ap_core.rbf "C:\Users\adam\code\fpga\snes\dist\Cores\agg23.SNES\$output_file";