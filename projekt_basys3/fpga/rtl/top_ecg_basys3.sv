/**
 * San Jose State University
 * EE178 Lab #4
 * Author: prof. Eric Crabilla
 *
 * Modified by:
 * 2025  AGH University of Science and Technology
 * MTM UEC2
 * Piotr Kaczmarczyk
 *
 * Description:
 * Top level synthesizable module including the project top and all the FPGA-referred modules.
 */

module top_ecg_basys3 (
        input  wire clk,
        input  wire btnC,
        inout wire [3:2] JA,
        output wire Vsync,
        output wire Hsync,
        output wire [3:0] vgaRed,
        output wire [3:0] vgaGreen,
        output wire [3:0] vgaBlue,
        output wire JA1
    );

    timeunit 1ns;
    timeprecision 1ps;

    /**
     * Local variables for clock
     */

    wire locked;
    wire clk_100MHz;
    wire clk_65MHz;
    wire pclk_mirror;
    
    /**
     * Signals assignments
     */

    assign JA1 = pclk_mirror;

    // Mirror pclk on a pin for use by the testbench;
    // not functionally required for this design to work.

    ODDR pclk_oddr (
        .Q(pclk_mirror),
        .C(clk_100MHz),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(1'b0),
        .S(1'b0)
    );

    /*
     * CLOCK IP CORE
    */
    clk_wiz_0 u_clk_wiz_0 (
        .clk_in1(clk),
        .locked(locked),
        .clk100MHz(clk_100MHz),
        .clk65MHz(clk_65MHz)
    );

    /**
     *  Project functional top module
     */

    top_ecg u_top_ecg (
        .clk_100MHz(clk_100MHz),
        .clk_65MHz(clk_65MHz),
        .rst_n(!btnC & locked),
        .i2c_sda(JA[3]),
        .i2c_scl(JA[2]),
        .vs(Vsync),
        .hs(Hsync),
        .r(vgaRed),
        .g(vgaGreen),
        .b(vgaBlue)
    );

endmodule
