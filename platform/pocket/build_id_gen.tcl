# ================================================================================
# (c) 2011 Altera Corporation. All rights reserved.
# Altera products are protected under numerous U.S. and foreign patents, maskwork
# rights, copyrights and other intellectual property laws.
# 
# This reference design file, and your use thereof, is subject to and governed
# by the terms and conditions of the applicable Altera Reference Design License
# Agreement (either as signed by you, agreed by you upon download or as a
# "click-through" agreement upon installation andor found at www.altera.com).
# By using this reference design file, you indicate your acceptance of such terms
# and conditions between you and Altera Corporation.  In the event that you do
# not agree with such terms and conditions, you may not use the reference design
# file and please promptly destroy any copies you have made.
# 
# This reference design file is being provided on an "as-is" basis and as an
# accommodation and therefore all warranties, representations or guarantees of
# any kind (whether express, implied or statutory) including, without limitation,
# warranties of merchantability, non-infringement, or fitness for a particular
# purpose, are specifically disclaimed.  By making this reference design file
# available, Altera expressly does not recommend, suggest or require that this
# reference design file be used in combination with any other product not
# provided by Altera.
# ================================================================================
#
# Build ID Verilog Module Script
# Jeff Wiencrot - 8/1/2011
# 
# Generates a Verilog module that contains a timestamp, physical address, and host name
# from the current build. These values are available from the build_date, build_time,
# physical_address, and host_name output ports of the build_id module in the build_id.v
# Verilog source file.
# 
# The format for each value is as follows:
#    Date              - 32-bit decimal number of the format mmddyyyy
#    Time              - 32-bit decimal number of the format hhmmss
#    Phyiscal Address  - 48-bit hexadecimal number
#    Host name         - 120-bit hexadecimal number with pairs of digits equal to the
#                        hexadecimal code for the first 15 ASCII characters of the host
#                        name.  For added clarity, host names that have fewer than 30
#                        hexadecimal digits (15 characters) are padded on the left with
#                        zeros.
#
# Usage:
#
#    To manually execute this script, source this file using the following Tcl commands:
#       source build_id_verilog.tcl
# 
#    To have this script automatically execute each time your project is built, use the
#    following command (see: http://www.altera.com/support/examples/tcl/auto_processing.html):
#       set_global_assignment -name PRE_FLOW_SCRIPT_FILE quartus_sh:build_id_verilog.tcl
#
#    Comment out the last line to prevent the process from automatically executing when
#    the file is sourced. The process can then be executed with the following command:
#       generateBuildID_Verilog
#
#
# For more information, see "build_identification.pdf"
#
# ================================================================================
#
# 2021-01-21 Analogue
#
# Only care about generating build date/time, so the rest was removed.
# The original can be downloaded from the Intel resource page
#

proc generateBuildID_Verilog {} {
	
	# Get the timestamp (see: http://www.altera.com/support/examples/tcl/tcl-date-time-stamp.html)
	set buildDate [ clock format [ clock seconds ] -format %Y%m%d ]
	set buildTime [ clock format [ clock seconds ] -format %H%M%S ]
		
	# Create a Verilog file for output
    set outputFileName "../platform/pocket/build_id.v"
	set outputFile [open $outputFileName "w"]
	
	# Output the Verilog source
	puts $outputFile "// Build ID Verilog Module"
	puts $outputFile "//"
	puts $outputFile "// Note - these are stored as binary coded decimal"
	puts $outputFile "// Date:             $buildDate"
	puts $outputFile "// Time:             $buildTime"
	puts $outputFile ""
	puts $outputFile "module build_id"
	puts $outputFile "("
	puts $outputFile "   output \[31:0\]  build_date,"
	puts $outputFile "   output \[31:0\]  build_time"
	puts $outputFile ");"
	puts $outputFile ""
	puts $outputFile "   assign build_date     =  32'h$buildDate;"
	puts $outputFile "   assign build_time     =  32'h$buildTime;"
	puts $outputFile ""
	puts $outputFile "endmodule"
	close $outputFile
	
	
	
	# Send confirmation message to the Messages window
	#post_message "APF core build date/time generated: [pwd]/$outputFileName"
	#post_message "Date:             $buildDate"
	#post_message "Time:             $buildTime"
}


proc generateBuildID_MIF {} {
	
	# Get the timestamp (see: http://www.altera.com/support/examples/tcl/tcl-date-time-stamp.html)
	set buildDate [ clock format [ clock seconds ] -format %Y%m%d ]
	set buildTime [ clock format [ clock seconds ] -format %H%M%S ]
	set buildUnique [expr {int(rand()*(4294967295))}]
	
	set buildDateNoLeadingZeros [string trimleft $buildDate "0"]
	set buildTimeNoLeadingZeros [string trimleft $buildTime "0"]
	set buildDate4Byte          [format "%08d" $buildDateNoLeadingZeros]
	set buildTime4Byte          [format "%08d" $buildTimeNoLeadingZeros]
	set buildUnique4Byte        [format "%08x" $buildUnique]
	
	#set buildDate4Byte          \
		[concat [string range $buildDate 0 1] \
				[string range $buildDate 2 3] \
				[string range $buildDate 4 5] \
				[string range $buildDate 6 7] ]
	
	
	set buildDateNumBytes       4
	set buildTimeNumBytes       4
	
	# Calculate depth of the memory (8-bit) words
	set memoryDepth [expr $buildDateNumBytes + $buildTimeNumBytes]
	
	# Create a Memory Initialization File for output
    set outputFileName "../platform/pocket/build_id.mif"
	set outputFile [open $outputFileName "w"]
	
	# Output the MIF header (see: http://quartushelp.altera.com/current/mergedProjects/reference/glossary/def_mif.htm)
	puts $outputFile "-- Build ID Memory Initialization File"
	puts $outputFile "--"
	puts $outputFile ""
	puts $outputFile "DEPTH = 256;"
	puts $outputFile "WIDTH = 32;"
	puts $outputFile "ADDRESS_RADIX = HEX;"
	puts $outputFile "DATA_RADIX = HEX;"
	puts $outputFile ""
	puts $outputFile "CONTENT"
	puts $outputFile "BEGIN"
	puts $outputFile ""
	puts $outputFile "   0E0 : $buildDate4Byte;"
	puts $outputFile "   0E1 : $buildTime4Byte;"
	puts $outputFile "   0E2 : $buildUnique4Byte;"
	puts $outputFile ""
	puts $outputFile "END;"
	
	# Close file to complete write
	close $outputFile
	
	# Send confirmation message to the Messages window
	post_message "APF core build date/time generated: [pwd]/$outputFileName"
}

generateBuildID_MIF

# 2021-01-21 Analogue
#
# There are some circumstances where you want all parts of a FPGA flow to be deterministic, especially 
# when trying to hash out timing issues. 
# You should comment this line out and temporarily bypass buildid generation so that synthesis/par 
# have consistent working input. MIF bram contents like above won't affect the random seed or trigger
# recompilation.
# Don't forget to re-enable before you release.
#
# generateBuildID_Verilog
