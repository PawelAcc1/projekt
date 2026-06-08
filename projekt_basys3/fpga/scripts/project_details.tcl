# Copyright (C) 2025  AGH University of Science and Technology
# MTM UEC2
# Author: Piotr Kaczmarczyk
#
# Description:
# Project detiles required for generate_bitstream.tcl
# Make sure that project_name, top_module and target are correct.
# Provide paths to all the files required for synthesis and implementation.
# Depending on the file type, it should be added in the corresponding section.
# If the project does not use files of some type, leave the corresponding section commented out.

#-----------------------------------------------------#
#                   Project details                   #
#-----------------------------------------------------#
# Project name                                  -- EDIT
set project_name ecg_project

# Top module name                               -- EDIT
set top_module top_ecg_basys3

# FPGA device
set target xc7a35tcpg236-1

#-----------------------------------------------------#
#                    Design sources                   #
#-----------------------------------------------------#
# Specify .xdc files location                   -- EDIT
set xdc_files {
    constraints/top_ecg_basys3.xdc
    constraints/clk_wiz_0.xdc
    constraints/clk_wiz_0_board.xdc
}

# Specify SystemVerilog design files location   -- EDIT
set sv_files {
    ../rtl/vga_pkg.sv
    ../rtl/vga_timing.sv
    ../rtl/draw_grid.sv
    ../rtl/top_ecg.sv
    ../rtl/sampling_timer.sv
    ../rtl/i2c_master.sv
    ../rtl/ring_buffer.sv
    ../rtl/baseline_restore.sv
    ../rtl/vga_formatter.sv
    ../rtl/render_signal.sv
    ../rtl/draw_mouse.sv
    ../rtl/vga_if.sv
    rtl/top_ecg_basys3.sv
}

# Specify Verilog design files location         -- EDIT
set verilog_files {
    ../rtl/clk_wiz_0.v
    ../rtl/clk_wiz_0_clk_wiz.v
}

# Specify IP Core files location
set ip_core_files {
    ../fir_compiler_0_1/fir_compiler_0.xci
    ../fir_compiler_notch/fir_compiler_notch.xci
}

# Specify VHDL design files location            -- EDIT
set vhdl_files {
   ../rtl/Ps2Interface.vhd
   ../rtl/MouseCtl.vhd
   ../rtl/MouseDisplay.vhd
}

# Specify files for a memory initialization     -- EDIT
# set mem_files {
#    path/to/file.data
# }
