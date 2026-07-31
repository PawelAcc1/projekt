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
    ../rtl/GUI/vga_pkg.sv
    ../rtl/GUI/vga_timing.sv
    ../rtl/GUI/draw_grid.sv
    ../rtl/top_ecg.sv
    ../rtl/i2c/sampling_timer.sv
    ../rtl/i2c/i2c_master.sv
    ../rtl/GUI/ring_buffer.sv
    ../rtl/GUI/baseline_restore.sv
    ../rtl/GUI/vga_formatter.sv
    ../rtl/GUI/render_signal.sv
    ../rtl/GUI/draw_mouse.sv
    ../rtl/GUI/vga_if.sv
    ../rtl/algorythms/adaptive_threshold.sv
    ../rtl/GUI/alarm_logger.sv
    ../rtl/bpm/bpm_calculator.sv
    ../rtl/algorythms/differentiator.sv
    ../rtl/algorythms/moving_window_integration.sv
    ../rtl/rtc_clock.sv
    ../rtl/algorythms/squarer.sv
    ../rtl/GUI/vga_7seg_digit.sv
    ../rtl/GUI/vga_bpm_display.sv
    ../rtl/GUI/vga_ui_manager.sv
    ../rtl/GUI/front_rom.sv
    ../rtl/GUI/vga_text_renderer.sv
    ../rtl/algorythms/delay_buffer.sv
    ../rtl/algorythms/stemi_detector.sv
    ../rtl/recorder/uart_rx.sv
    ../rtl/recorder/uart_tx.sv
    ../rtl/recorder/recording_memory.sv
    ../rtl/recorder/hex_to_ascii.sv
    ../rtl/recorder/tick_generator.sv
    rtl/top_ecg_basys3.sv
}

# Specify Verilog design files location         -- EDIT
set verilog_files {
    ../rtl/clock_domain/clk_wiz_0.v
    ../rtl/clock_domain/clk_wiz_0_clk_wiz.v
    ../rtl/recorder/debounce.v
}

# Specify IP Core files location
set ip_core_files {
    ../fir_compiler_0_1/fir_compiler_0.xci
    ../fir_compiler_notch/fir_compiler_notch.xci
    ../memory_init/blk_mem_arrhythmia/blk_mem_arrhythmia.xci
    ../memory_init/blk_mem_tachykardia/blk_mem_tachykardia.xci
    ../memory_init/blk_mem_bradycardia/blk_mem_bradycardia.xci
    ../memory_init/blk_mem_stemi/blk_mem_stemi.xci
}

# Specify VHDL design files location            -- EDIT
set vhdl_files {
   ../rtl/mouse/Ps2Interface.vhd
   ../rtl/mouse/MouseCtl.vhd
   ../rtl/mouse/MouseDisplay.vhd
}

# Specify files for a memory initialization     -- EDIT
set mem_files {
    ../rtl/bpm/bpm_rom.hex
}
