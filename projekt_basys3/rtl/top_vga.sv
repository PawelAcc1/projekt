// top_vga.sv
module top_vga (
        input  logic clk,
        input  logic rst_n,
        output logic vs,
        output logic hs,
        output logic [3:0] r,
        output logic [3:0] g,
        output logic [3:0] b
    );

    timeunit 1ns;
    timeprecision 1ps;

    vga_if if_tim();
    vga_if if_bg();
    vga_if if_rect();

    assign vs = if_rect.vsync;
    assign hs = if_rect.hsync;
    assign {r,g,b} = if_rect.rgb;

    vga_timing u_vga_timing (
        .clk     (clk),
        .rst_n   (rst_n),
        .vga_out (if_tim.out) 
    );

    draw_bg u_draw_bg (
        .clk      (clk),
        .rst_n    (rst_n),
        .vga_in   (if_tim.in),
        .vga_out  (if_bg.out)
    );

    draw_rect u_draw_rect (
        .clk      (clk),
        .rst_n    (rst_n),
        .vga_in   (if_bg.in),
        .vga_out  (if_rect.out)
    );

endmodule