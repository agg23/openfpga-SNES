# ==============================================================================
# SPDX-License-Identifier: CC0-1.0
# SPDX-FileType: SOURCE
# SPDX-FileCopyrightText: (c) 2022, OpenGateware authors and contributors
# ==============================================================================
# @file: build_cd.h
# @brief: Generate a JTAG Chain Description File.
# Create a .cdf file to be used with Quartus Prime Programmer
# ==============================================================================
proc createChainDescriptionFile {revision device outpath project_name} {
    set outputFileName "$project_name.cdf"
    set outputFile [open $outputFileName "w"]

    puts $outputFile "JedecChain;"
    puts $outputFile "	FileRevision(JESD32A);"
    puts $outputFile "	DefaultMfr(6E);"
    puts $outputFile ""
    puts $outputFile "	P ActionCode(Cfg)"
    puts $outputFile "		Device PartName($device) Path(\"$outpath/\") File(\"$revision.sof\") MfrSpec(OpMask(1));"
    puts $outputFile "ChainEnd;"
    puts $outputFile ""
    puts $outputFile "AlteraBegin;"
    puts $outputFile "	ChainType(JTAG);"
    puts $outputFile "AlteraEnd;"
}

set project_name [lindex $quartus(args) 1]
set revision [lindex $quartus(args) 2]

if {[project_exists $project_name]} {
    if {[string equal "" $revision]} {
        project_open $project_name -revision [get_current_revision $project_name]
    } else {
        project_open $project_name -revision $revision
    }
} else {
    post_message -type error "Project $project_name does not exist"
    exit
}

set device  [get_global_assignment -name DEVICE]
set outpath [get_global_assignment -name PROJECT_OUTPUT_DIRECTORY]

if [is_project_open] {
    project_close
}

createChainDescriptionFile $revision $device $outpath $project_name
