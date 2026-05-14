/**
 * Copyright (C) 2025  AGH University of Science and Technology
 * MTM UEC2
 * Author: Piotr Kaczmarczyk
 *
 * Description:
 * Testbench for vga_timing module.
 */

 module vga_timing_tb;

    timeunit 1ns;
    timeprecision 1ps;

    import vga_pkg::*;

    /**
     * Local parameters
     */
    localparam CLK_PERIOD = 25;     // 40 MHz
    localparam RST_START_TIME  = 1.25*CLK_PERIOD;
    localparam RST_ACTIVE_TIME = 2.00*CLK_PERIOD;

    /**
     * Local variables and signals
     */
    logic clk;
    logic rst_n;

    wire [10:0] vcount, hcount;
    wire        vsync,  hsync;
    wire        vblnk,  hblnk;

    /**
     * Clock generation
     */
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

/**
     * Reset generation
     */
    initial begin
        rst_n = 1'b0; 
        #(RST_ACTIVE_TIME) rst_n = 1'b1; 
    end

    /**
     * Dut placement
     */
    vga_timing dut(
        .clk,
        .rst_n,
        .vcount,
        .vsync,
        .vblnk,
        .hcount,
        .hsync,
        .hblnk
    );

    /**
     * Assertions (AUTOMATYCZNE SPRAWDZANIE)
     */
     
    // 1. t(hcount) <= HOR_TOTAL_TIME - 1 ?
    assert property (@(posedge clk) disable iff (!rst_n) 
        hcount < HOR_TOTAL_TIME) 
        else $error("Błąd: hcount przekroczył limit %0d!", HOR_TOTAL_TIME-1);

    // 2. t(vcount) <= VER_TOTAL_TIME - 1 ?
    assert property (@(posedge clk) disable iff (!rst_n) 
        vcount < VER_TOTAL_TIME) 
        else $error("Błąd: vcount przekroczył limit %0d!", VER_TOTAL_TIME-1);

    // 3. reset after hcount == HOR_TOTAL_TIME in next clk posedge ? 
    assert property (@(posedge clk) disable iff (!rst_n) 
        (hcount == HOR_TOTAL_TIME - 1) |=> (hcount == '0)) 
        else $error("Błąd: hcount nie wyzerował się poprawnie!");

    /**
     * Main test
     */
    initial begin
        $display("Starting vga_timing simulation...");

        //waiting for reset
        @(posedge rst_n);

        //2 frames test
        @(posedge vsync);
        $display("First frame completed");
        @(posedge vsync);
        $display("Second frame completed");
        @(posedge vsync);

        $display("Test passed! No errors occured");
        $finish;
    end

endmodule
