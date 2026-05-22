/**
 * Copyright (C) 2025  AGH University of Science and Technology
 * MTM UEC2
 * Author: Piotr Kaczmarczyk
 *
 * Description:
 * Package with vga related constants.
 */

package vga_pkg;

    // Parameters for VGA Display 1024 x 768 @ 60fps using a 65 MHz clock;
    localparam HOR_PIXELS = 1024;
    localparam VER_PIXELS = 768;

    // Add VGA timing parameters here and refer to them in other modules.
    localparam HOR_TOTAL_TIME  = 1344; // 1024 (Active) + 24 (FP) + 136 (Sync) + 160 (BP)
    localparam HOR_BLANK_START = 1024;
    localparam HOR_BLANK_TIME  = 320;  // HOR_TOTAL_TIME - HOR_PIXELS
    localparam HOR_SYNC_START  = 1048; // HOR_PIXELS + Front Porch (24)
    localparam HOR_SYNC_TIME   = 136;  // Sync pulse width

    localparam VER_TOTAL_TIME  = 806;  // 768 (Active) + 3 (FP) + 6 (Sync) + 29 (BP)
    localparam VER_BLANK_START = 768;
    localparam VER_BLANK_TIME  = 38;   // VER_TOTAL_TIME - VER_PIXELS
    localparam VER_SYNC_START  = 771;  // VER_PIXELS + Front Porch (3)
    localparam VER_SYNC_TIME   = 6;    // Sync pulse width

endpackage
