# ==============================================================================
# SPDX-License-Identifier: CC0-1.0
# SPDX-FileType: SOURCE
# SPDX-FileCopyrightText: (c) 2022, OpenGateware authors and contributors
# ==============================================================================
# 
# Platform Global/Location/Instance Assignments
# 
# ==============================================================================
# Hardware Information
# ==============================================================================
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CEBA4F23C8
set_global_assignment -name DEVICE_FILTER_PACKAGE FBGA
set_global_assignment -name DEVICE_FILTER_PIN_COUNT 484
set_global_assignment -name DEVICE_FILTER_SPEED_GRADE 8

# ==============================================================================
# Classic Timing Assignments
# ==============================================================================
set_global_assignment -name MIN_CORE_JUNCTION_TEMP 0
set_global_assignment -name MAX_CORE_JUNCTION_TEMP 85
set_global_assignment -name TIMEQUEST_MULTICORNER_ANALYSIS ON

# ==============================================================================
# Assembler Assignments
# ==============================================================================
set_global_assignment -name ENABLE_OCT_DONE OFF
set_global_assignment -name USE_CONFIGURATION_DEVICE ON
set_global_assignment -name GENERATE_RBF_FILE ON

# ==============================================================================
# Power Estimation Assignments
# ==============================================================================
set_global_assignment -name POWER_PRESET_COOLING_SOLUTION "23 MM HEAT SINK WITH 200 LFPM AIRFLOW"
set_global_assignment -name POWER_BOARD_THERMAL_MODEL "NONE (CONSERVATIVE)"

# ==============================================================================
# Signal Tap Assignments
# ==============================================================================
set_global_assignment -name ENABLE_SIGNALTAP ON

# ==============================================================================
# Pin & Location Assignments
# ==============================================================================
set_location_assignment PIN_V15 -to clk_74a
set_location_assignment PIN_H16 -to clk_74b
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to clk_74a
set_instance_assignment -name IO_STANDARD "1.8 V" -to clk_74b

# ==============================================================================
# SPI bus with Aristotle
# ==============================================================================
set_location_assignment PIN_T17 -to bridge_spiclk
set_location_assignment PIN_M21 -to bridge_spimiso
set_location_assignment PIN_M20 -to bridge_spimosi
set_location_assignment PIN_L19 -to bridge_1wire
set_location_assignment PIN_H14 -to bridge_spiss
set_instance_assignment -name IO_STANDARD "1.8 V" -to bridge_spiclk
set_instance_assignment -name IO_STANDARD "1.8 V" -to bridge_spimiso
set_instance_assignment -name IO_STANDARD "1.8 V" -to bridge_spimosi
set_instance_assignment -name IO_STANDARD "1.8 V" -to bridge_1wire
set_instance_assignment -name IO_STANDARD "1.8 V" -to bridge_spiss
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to bridge_spiclk
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to bridge_spimiso
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to bridge_spimosi
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to bridge_1wire
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to bridge_spiclk
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to bridge_spimiso
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to bridge_spimosi
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to bridge_1wire

# ==============================================================================
# Cartridge interface
# ==============================================================================
set_location_assignment PIN_AA9 -to cart_tran_bank0[7]
set_location_assignment PIN_AB8 -to cart_tran_bank0[6]
set_location_assignment PIN_AA8 -to cart_tran_bank0[5]
set_location_assignment PIN_AB7 -to cart_tran_bank0[4]
set_location_assignment PIN_AB6 -to cart_tran_bank0_dir
set_location_assignment PIN_AA10 -to cart_tran_bank1[7]
set_location_assignment PIN_AB10 -to cart_tran_bank1[6]
set_location_assignment PIN_Y10 -to cart_tran_bank1[5]
set_location_assignment PIN_AB11 -to cart_tran_bank1[4]
set_location_assignment PIN_Y11 -to cart_tran_bank1[3]
set_location_assignment PIN_AB12 -to cart_tran_bank1[2]
set_location_assignment PIN_AA12 -to cart_tran_bank1[1]
set_location_assignment PIN_AB13 -to cart_tran_bank1[0]
set_location_assignment PIN_AA13 -to cart_tran_bank1_dir
set_location_assignment PIN_AB15 -to cart_tran_bank2[7]
set_location_assignment PIN_AA15 -to cart_tran_bank2[6]
set_location_assignment PIN_AB17 -to cart_tran_bank2[5]
set_location_assignment PIN_AA17 -to cart_tran_bank2[4]
set_location_assignment PIN_AB18 -to cart_tran_bank2[3]
set_location_assignment PIN_AB20 -to cart_tran_bank2[0]
set_location_assignment PIN_AA19 -to cart_tran_bank2[1]
set_location_assignment PIN_AA18 -to cart_tran_bank2[2]
set_location_assignment PIN_AA14 -to cart_tran_bank2_dir
set_location_assignment PIN_AA20 -to cart_tran_bank3[7]
set_location_assignment PIN_AB21 -to cart_tran_bank3[6]
set_location_assignment PIN_AB22 -to cart_tran_bank3[5]
set_location_assignment PIN_AA22 -to cart_tran_bank3[4]
set_location_assignment PIN_Y21 -to cart_tran_bank3[3]
set_location_assignment PIN_Y22 -to cart_tran_bank3[2]
set_location_assignment PIN_W21 -to cart_tran_bank3[1]
set_location_assignment PIN_W22 -to cart_tran_bank3[0]
set_location_assignment PIN_V21 -to cart_tran_bank3_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank0[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank0[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank0[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank0[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank0_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank1_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank2_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_bank3_dir

# ==============================================================================
# GBA CS2#/RES#
# ==============================================================================
set_location_assignment PIN_AB5 -to cart_tran_pin30_dir
set_location_assignment PIN_L8 -to cart_tran_pin30
set_location_assignment PIN_L17 -to cart_pin30_pwroff_reset
set_instance_assignment -name IO_STANDARD "1.8 V" -to cart_pin30_pwroff_reset
set_instance_assignment -name IO_STANDARD "1.8 V" -to cart_tran_pin30
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_pin30_dir
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cart_pin30_pwroff_reset
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cart_tran_pin30

# ==============================================================================
# GBA IRQ/DRQ
# ==============================================================================
set_location_assignment PIN_K9 -to cart_tran_pin31
set_location_assignment PIN_U22 -to cart_tran_pin31_dir
set_instance_assignment -name IO_STANDARD "1.8 V" -to cart_tran_pin31
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to cart_tran_pin31_dir
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cart_tran_pin31

# ==============================================================================
# GBA link port
# ==============================================================================
set_location_assignment PIN_V10 -to port_tran_si
set_location_assignment PIN_V9 -to port_tran_si_dir
set_location_assignment PIN_J11 -to port_tran_so
set_location_assignment PIN_T13 -to port_tran_so_dir
set_location_assignment PIN_AA7 -to port_tran_sck
set_location_assignment PIN_Y9 -to port_tran_sck_dir
set_location_assignment PIN_R9 -to port_tran_sd
set_location_assignment PIN_T9 -to port_tran_sd_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_si
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_si_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_so_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_sck
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_sck_dir
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_sd
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to port_tran_sd_dir
set_instance_assignment -name IO_STANDARD "1.8 V" -to port_tran_so
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to port_tran_so

# ==============================================================================
# I/O to 6515D Breakout USB UART
# ==============================================================================
set_location_assignment PIN_K21 -to dbg_tx
set_location_assignment PIN_K22 -to dbg_rx
set_instance_assignment -name IO_STANDARD "1.8 V" -to dbg_rx
set_instance_assignment -name IO_STANDARD "1.8 V" -to dbg_tx
set_instance_assignment -name CURRENT_STRENGTH_NEW 8MA -to dbg_tx

# ==============================================================================
# Infrared
# ==============================================================================
set_location_assignment PIN_H10 -to port_ir_rx
set_location_assignment PIN_H11 -to port_ir_tx
set_location_assignment PIN_L18 -to port_ir_rx_disable
set_instance_assignment -name IO_STANDARD "1.8 V" -to port_ir_tx
set_instance_assignment -name IO_STANDARD "1.8 V" -to port_ir_rx
set_instance_assignment -name IO_STANDARD "1.8 V" -to port_ir_rx_disable
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to port_ir_tx
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to port_ir_rx_disable
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to port_ir_rx

# ==============================================================================
# RFU internal I2C bus (DNU)
# ==============================================================================
set_location_assignment PIN_M16 -to aux_scl
set_location_assignment PIN_M18 -to aux_sda
set_instance_assignment -name IO_STANDARD "1.8 V" -to aux_sda
set_instance_assignment -name IO_STANDARD "1.8 V" -to aux_scl
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to aux_sda
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to aux_scl

# ==============================================================================
# I/O pads near jtag connector user can solder to
# ==============================================================================
set_location_assignment PIN_M22 -to user1
set_location_assignment PIN_L22 -to user2
set_instance_assignment -name IO_STANDARD "1.8 V" -to user1
set_instance_assignment -name IO_STANDARD "1.8 V" -to user2

# ==============================================================================
# VBlank output to scaler
# ==============================================================================
set_location_assignment PIN_N19 -to vblank
set_instance_assignment -name IO_STANDARD "1.8 V" -to vblank

# ==============================================================================
# Video output to the scaler
# ==============================================================================
set_location_assignment PIN_H15 -to scal_audadc
set_location_assignment PIN_K19 -to scal_auddac
set_location_assignment PIN_K17 -to scal_audlrck
set_location_assignment PIN_K16 -to scal_audmclk
set_location_assignment PIN_R17 -to scal_clk
set_location_assignment PIN_N20 -to scal_de
set_location_assignment PIN_P17 -to scal_hs
set_location_assignment PIN_N21 -to scal_skip
set_location_assignment PIN_T15 -to scal_vs
set_location_assignment PIN_R16 -to scal_vid[11]
set_location_assignment PIN_R15 -to scal_vid[10]
set_location_assignment PIN_R22 -to scal_vid[9]
set_location_assignment PIN_T22 -to scal_vid[8]
set_location_assignment PIN_T18 -to scal_vid[7]
set_location_assignment PIN_T19 -to scal_vid[6]
set_location_assignment PIN_T20 -to scal_vid[5]
set_location_assignment PIN_P19 -to scal_vid[4]
set_location_assignment PIN_P18 -to scal_vid[3]
set_location_assignment PIN_N16 -to scal_vid[2]
set_location_assignment PIN_P22 -to scal_vid[1]
set_location_assignment PIN_R21 -to scal_vid[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_audadc
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_auddac
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_audlrck
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_audmclk
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_clk
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_de
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_hs
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_skip
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[10]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[11]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[2]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[3]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[4]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[5]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[6]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[7]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[8]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vid[9]
set_instance_assignment -name IO_STANDARD "1.8 V" -to scal_vs
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_auddac
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_audlrck
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_audmclk
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_clk
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_de
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_hs
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_skip
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[0]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[10]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[11]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[1]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[2]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[3]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[4]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[5]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[6]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[7]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[8]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vid[9]
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to scal_vs

# ==============================================================================
# SDRAM, 512mbit x16
# ==============================================================================
set_location_assignment PIN_J17 -to dram_a[12]
set_location_assignment PIN_F15 -to dram_a[11]
set_location_assignment PIN_C13 -to dram_a[10]
set_location_assignment PIN_G17 -to dram_a[9]
set_location_assignment PIN_J18 -to dram_a[8]
set_location_assignment PIN_F14 -to dram_a[7]
set_location_assignment PIN_E15 -to dram_a[6]
set_location_assignment PIN_E16 -to dram_a[5]
set_location_assignment PIN_F13 -to dram_a[4]
set_location_assignment PIN_E14 -to dram_a[3]
set_location_assignment PIN_F12 -to dram_a[2]
set_location_assignment PIN_D12 -to dram_a[1]
set_location_assignment PIN_D17 -to dram_a[0]
set_location_assignment PIN_E12 -to dram_ba[1]
set_location_assignment PIN_C16 -to dram_ba[0]
set_location_assignment PIN_K20 -to dram_dq[15]
set_location_assignment PIN_G11 -to dram_dq[14]
set_location_assignment PIN_J19 -to dram_dq[13]
set_location_assignment PIN_H13 -to dram_dq[12]
set_location_assignment PIN_G13 -to dram_dq[11]
set_location_assignment PIN_G16 -to dram_dq[10]
set_location_assignment PIN_G15 -to dram_dq[9]
set_location_assignment PIN_J13 -to dram_dq[8]
set_location_assignment PIN_A12 -to dram_dq[7]
set_location_assignment PIN_A13 -to dram_dq[6]
set_location_assignment PIN_B12 -to dram_dq[5]
set_location_assignment PIN_A14 -to dram_dq[4]
set_location_assignment PIN_B13 -to dram_dq[3]
set_location_assignment PIN_A15 -to dram_dq[2]
set_location_assignment PIN_B15 -to dram_dq[1]
set_location_assignment PIN_C15 -to dram_dq[0]
set_location_assignment PIN_D13 -to dram_dqm[0]
set_location_assignment PIN_H18 -to dram_dqm[1]
set_location_assignment PIN_B16 -to dram_cas_n
set_location_assignment PIN_G18 -to dram_cke
set_location_assignment PIN_G12 -to dram_clk
set_location_assignment PIN_B11 -to dram_ras_n
set_location_assignment PIN_C11 -to dram_we_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[10]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[11]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[12]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[2]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[3]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[4]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[5]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[6]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[7]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[8]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_a[9]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_ba[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_ba[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_cas_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_cke
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_clk
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[10]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[11]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[12]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[13]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[14]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[15]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[2]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[3]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[4]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[5]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[6]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[7]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[8]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dq[9]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dqm[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_dqm[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_ras_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to dram_we_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[10]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[11]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[12]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[4]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[5]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[6]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[7]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[8]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_a[9]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_ba[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_ba[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_cas_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_cke
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[10]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[11]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[12]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[13]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[14]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[15]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[4]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[5]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[6]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[7]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[8]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dq[9]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dqm[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_dqm[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_ras_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to dram_we_n
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to dram_clk

# These should be enabled, but it's been 2.5 years with them off, so I'm not going to change it now
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[0]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[1]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[2]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[3]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[4]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[5]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[6]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[7]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[8]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[9]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[10]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[11]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[12]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[13]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[14]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dq[15]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[0]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[1]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[2]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[3]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[4]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[5]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[6]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[7]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[8]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[9]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[10]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[11]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_a[12]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_ba[0]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_ba[1]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dqm[0]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_dqm[1]
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_ras_n
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_cas_n
# set_instance_assignment -name FAST_OUTPUT_REGISTER ON -to dram_we_n
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[0]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[1]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[2]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[3]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[4]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[5]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[6]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[7]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[8]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[9]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[10]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[11]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[12]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[13]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[14]
# set_instance_assignment -name FAST_OUTPUT_ENABLE_REGISTER ON -to dram_dq[15]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[0]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[1]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[2]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[3]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[4]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[5]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[6]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[7]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[8]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[9]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[10]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[11]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[12]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[13]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[14]
# set_instance_assignment -name FAST_INPUT_REGISTER ON -to dram_dq[15]

# ==============================================================================
# Cellular PSRAM 0 - 64mbit x2 dual die per chip
# ==============================================================================
set_location_assignment PIN_H8 -to cram0_a[21]
set_location_assignment PIN_H9 -to cram0_a[20]
set_location_assignment PIN_B7 -to cram0_a[19]
set_location_assignment PIN_B6 -to cram0_a[18]
set_location_assignment PIN_C6 -to cram0_a[17]
set_location_assignment PIN_H6 -to cram0_a[16]
set_location_assignment PIN_J9 -to cram0_dq[15]
set_location_assignment PIN_L7 -to cram0_dq[14]
set_location_assignment PIN_F9 -to cram0_dq[13]
set_location_assignment PIN_E7 -to cram0_dq[12]
set_location_assignment PIN_A8 -to cram0_dq[11]
set_location_assignment PIN_D9 -to cram0_dq[10]
set_location_assignment PIN_A10 -to cram0_dq[9]
set_location_assignment PIN_C9 -to cram0_dq[8]
set_location_assignment PIN_J7 -to cram0_dq[7]
set_location_assignment PIN_G6 -to cram0_dq[6]
set_location_assignment PIN_F10 -to cram0_dq[5]
set_location_assignment PIN_E9 -to cram0_dq[4]
set_location_assignment PIN_D7 -to cram0_dq[3]
set_location_assignment PIN_A9 -to cram0_dq[2]
set_location_assignment PIN_C8 -to cram0_dq[1]
set_location_assignment PIN_B10 -to cram0_dq[0]
set_location_assignment PIN_J8 -to cram0_adv_n
set_location_assignment PIN_B5 -to cram0_ce0_n
set_location_assignment PIN_E10 -to cram0_ce1_n
set_location_assignment PIN_G10 -to cram0_clk
set_location_assignment PIN_F7 -to cram0_cre
set_location_assignment PIN_A5 -to cram0_lb_n
set_location_assignment PIN_D6 -to cram0_oe_n
set_location_assignment PIN_A7 -to cram0_ub_n
set_location_assignment PIN_K7 -to cram0_wait
set_location_assignment PIN_G8 -to cram0_we_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[2]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[3]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[4]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[5]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[6]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[7]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[8]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[9]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[10]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[11]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[12]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[13]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[14]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_dq[15]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[16]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[17]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[18]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[19]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[20]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_a[21]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_adv_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_ce0_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_ce1_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_clk
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_cre
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_lb_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_oe_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_ub_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_wait
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram0_we_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[4]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[5]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[6]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[7]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[8]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[9]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[10]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[11]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[12]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[13]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[14]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_dq[15]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[16]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[17]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[18]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[19]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[20]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_a[21]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_adv_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_ce0_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_ce1_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_cre
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_lb_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_oe_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_ub_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_wait
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram0_we_n
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to cram0_clk

# ==============================================================================
# Cellular PSRAM 1 - 64mbit x2 dual die per chip
# ==============================================================================
set_location_assignment PIN_Y3 -to cram1_a[21]
set_location_assignment PIN_AA2 -to cram1_a[20]
set_location_assignment PIN_L2 -to cram1_a[19]
set_location_assignment PIN_N1 -to cram1_a[18]
set_location_assignment PIN_U1 -to cram1_a[17]
set_location_assignment PIN_U2 -to cram1_a[16]
set_location_assignment PIN_W8 -to cram1_dq[15]
set_location_assignment PIN_U6 -to cram1_dq[14]
set_location_assignment PIN_R7 -to cram1_dq[13]
set_location_assignment PIN_R6 -to cram1_dq[12]
set_location_assignment PIN_P7 -to cram1_dq[11]
set_location_assignment PIN_N6 -to cram1_dq[10]
set_location_assignment PIN_C2 -to cram1_dq[9]
set_location_assignment PIN_D3 -to cram1_dq[8]
set_location_assignment PIN_V6 -to cram1_dq[7]
set_location_assignment PIN_U7 -to cram1_dq[6]
set_location_assignment PIN_M6 -to cram1_dq[5]
set_location_assignment PIN_R5 -to cram1_dq[4]
set_location_assignment PIN_P6 -to cram1_dq[3]
set_location_assignment PIN_E2 -to cram1_dq[2]
set_location_assignment PIN_G2 -to cram1_dq[1]
set_location_assignment PIN_C1 -to cram1_dq[0]
set_location_assignment PIN_U8 -to cram1_adv_n
set_location_assignment PIN_N2 -to cram1_ce0_n
set_location_assignment PIN_T8 -to cram1_ce1_n
set_location_assignment PIN_W2 -to cram1_clk
set_location_assignment PIN_T7 -to cram1_cre
set_location_assignment PIN_L1 -to cram1_lb_n
set_location_assignment PIN_M7 -to cram1_oe_n
set_location_assignment PIN_G1 -to cram1_ub_n
set_location_assignment PIN_W9 -to cram1_wait
set_location_assignment PIN_AA1 -to cram1_we_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[0]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[1]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[2]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[3]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[4]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[5]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[6]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[7]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[8]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[9]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[10]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[11]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[12]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[13]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[14]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_dq[15]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[16]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[17]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[18]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[19]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[20]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_a[21]
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_adv_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_ce0_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_ce1_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_clk
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_cre
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_lb_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_oe_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_ub_n
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_wait
set_instance_assignment -name IO_STANDARD "1.8 V" -to cram1_we_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[0]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[1]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[2]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[3]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[4]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[5]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[6]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[7]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[8]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[9]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[10]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[11]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[12]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[13]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[14]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_dq[15]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[16]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[17]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[18]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[19]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[20]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_a[21]
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_adv_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_ce0_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_ce1_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_cre
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_lb_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_oe_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_ub_n
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_wait
set_instance_assignment -name CURRENT_STRENGTH_NEW 4MA -to cram1_we_n
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to cram1_clk

# ==============================================================================
# SRAM, 1mbit x16
# ==============================================================================
set_location_assignment PIN_V16 -to sram_a[16]
set_location_assignment PIN_U12 -to sram_a[15]
set_location_assignment PIN_U15 -to sram_a[14]
set_location_assignment PIN_R10 -to sram_a[13]
set_location_assignment PIN_V14 -to sram_a[12]
set_location_assignment PIN_T10 -to sram_a[11]
set_location_assignment PIN_U11 -to sram_a[10]
set_location_assignment PIN_Y14 -to sram_a[9]
set_location_assignment PIN_U13 -to sram_a[8]
set_location_assignment PIN_Y19 -to sram_a[7]
set_location_assignment PIN_P8 -to sram_a[6]
set_location_assignment PIN_V19 -to sram_a[5]
set_location_assignment PIN_N9 -to sram_a[4]
set_location_assignment PIN_U21 -to sram_a[3]
set_location_assignment PIN_M8 -to sram_a[2]
set_location_assignment PIN_M9 -to sram_a[1]
set_location_assignment PIN_T14 -to sram_a[0]
set_location_assignment PIN_Y15 -to sram_dq[15]
set_location_assignment PIN_W16 -to sram_dq[14]
set_location_assignment PIN_Y16 -to sram_dq[13]
set_location_assignment PIN_Y17 -to sram_dq[12]
set_location_assignment PIN_V20 -to sram_dq[11]
set_location_assignment PIN_V18 -to sram_dq[10]
set_location_assignment PIN_U20 -to sram_dq[9]
set_location_assignment PIN_U16 -to sram_dq[8]
set_location_assignment PIN_R12 -to sram_dq[7]
set_location_assignment PIN_V13 -to sram_dq[6]
set_location_assignment PIN_T12 -to sram_dq[5]
set_location_assignment PIN_W19 -to sram_dq[4]
set_location_assignment PIN_Y20 -to sram_dq[3]
set_location_assignment PIN_P14 -to sram_dq[2]
set_location_assignment PIN_P9 -to sram_dq[1]
set_location_assignment PIN_N8 -to sram_dq[0]
set_location_assignment PIN_U17 -to sram_ub_n
set_location_assignment PIN_R11 -to sram_we_n
set_location_assignment PIN_R14 -to sram_oe_n
set_location_assignment PIN_P12 -to sram_lb_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[10]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[11]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[12]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[13]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[14]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[15]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[16]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[8]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_a[9]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[10]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[11]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[12]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[13]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[14]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[15]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[2]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[3]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[4]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[5]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[6]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[7]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[8]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_dq[9]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_lb_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_oe_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_ub_n
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to sram_we_n

# ==============================================================================
# Powerup self test (DO NOT USE)
# ==============================================================================
set_location_assignment PIN_P16 -to vpll_feed
set_location_assignment PIN_U10 -to bist
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to bist
set_instance_assignment -name IO_STANDARD "1.8 V" -to vpll_feed
set_instance_assignment -name OUTPUT_TERMINATION "SERIES 50 OHM WITHOUT CALIBRATION" -to vpll_feed

# ==============================================================================
# Advanced I/O Timing Assignments
# ==============================================================================
set_global_assignment -name OUTPUT_IO_TIMING_NEAR_END_VMEAS "HALF VCCIO" -rise
set_global_assignment -name OUTPUT_IO_TIMING_NEAR_END_VMEAS "HALF VCCIO" -fall
set_global_assignment -name OUTPUT_IO_TIMING_FAR_END_VMEAS "HALF SIGNAL SWING" -rise
set_global_assignment -name OUTPUT_IO_TIMING_FAR_END_VMEAS "HALF SIGNAL SWING" -fall

# ==============================================================================
# Scripts
# ==============================================================================
set_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:../platform/pocket/build_id_gen.tcl"
set_global_assignment -name POST_FLOW_SCRIPT_FILE "quartus_sh:../platform/pocket/build_cdf.tcl"

# ==============================================================================
# Framework Files
# ==============================================================================
set_global_assignment -name QIP_FILE ../platform/pocket/apf.qip
set_global_assignment -name QIP_FILE ../target/pocket/core.qip
