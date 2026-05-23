// top_ecg.sv
module top_ecg (
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

    assign vs = if_rect.vsync;
    assign hs = if_rect.hsync;
    assign {r,g,b} = if_rect.rgb; //zmienic na rect na render

    vga_timing u_vga_timing (
        .clk     (clk),
        .rst_n   (rst_n),
        .vga_out (if_tim.out) 
    );

    draw_grid u_draw_grid (
        .clk      (clk),
        .rst_n    (rst_n),
        .vga_in   (if_tim.in),
        .vga_out  (if_bg.out)
    );



/*
 * FIR BANDPASS FILTER INSTANCE FROM IP CATALOG
*/
fir_compiler_0 u_fir_compiler_0 (
  .aclk(aclk),                              // input wire aclk
  .s_axis_data_tvalid(s_axis_data_tvalid),  // input wire s_axis_data_tvalid
  .s_axis_data_tready(s_axis_data_tready),  // output wire s_axis_data_tready
  .s_axis_data_tdata(s_axis_data_tdata),    // input wire [15 : 0] s_axis_data_tdata
  .m_axis_data_tvalid(m_axis_data_tvalid),  // output wire m_axis_data_tvalid
  .m_axis_data_tdata(m_axis_data_tdata)    // output wire [39 : 0] m_axis_data_tdata
);

endmodule