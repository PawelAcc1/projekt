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
        inout wire [7:2] JA,
        inout wire PS2Clk,
        inout wire PS2Data,
        output wire Vsync,
        output wire Hsync,
        output wire [3:0] vgaRed,
        output wire [3:0] vgaGreen,
        output wire [3:0] vgaBlue
    );

    timeunit 1ns;
    timeprecision 1ps;

    /**
     * Local variables for clock
     */

    wire locked;
    wire clk_100MHz;
    wire clk_65MHz;
    
    /**
     * Signals assignments
     */
    assign JA[4] = 1'bz;
    assign JA[5] = 1'bz;
    assign JA[6] = 1'bz;
    assign JA[7] = 1'bz;

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
        .ps2_clk(PS2Clk),
        .ps2_data(PS2Data),
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
