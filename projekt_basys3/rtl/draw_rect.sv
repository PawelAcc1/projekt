// draw_rect.sv
module draw_rect (
    input  logic clk,
    input  logic rst_n,
    vga_if.in    vga_in,
    vga_if.out   vga_out
);

timeunit 1ns;
timeprecision 1ps;

import vga_pkg::*;

logic [11:0] rgb_nxt;


always_ff @(posedge clk or negedge rst_n) begin : rect_ff_blk
    if (!rst_n) begin
        vga_out.vcount <= '0;
        vga_out.vsync  <= '0;
        vga_out.vblnk  <= '0;
        vga_out.hcount <= '0;
        vga_out.hsync  <= '0;
        vga_out.hblnk  <= '0;
        vga_out.rgb    <= '0;
    end else begin
        vga_out.vcount <= vga_in.vcount;
        vga_out.vsync  <= vga_in.vsync;
        vga_out.vblnk  <= vga_in.vblnk;
        vga_out.hcount <= vga_in.hcount;
        vga_out.hsync  <= vga_in.hsync;
        vga_out.hblnk  <= vga_in.hblnk;
        vga_out.rgb    <= rgb_nxt;
    end
end

function automatic logic [11:0] rectangle(
    input logic [10:0] hcount,
    input logic [10:0] vcount,
    input logic [11:0] rgb_bg
);
    localparam X_START = 50;
    localparam Y_START = 130;
    localparam WIDTH   = 100;
    localparam HEIGHT   = 120;     
    localparam RECT_COLOR = 12'hf_0_f;
    
    if ((hcount >= X_START) && (hcount <= (X_START + WIDTH)) &&
        (vcount >= Y_START) && (vcount <= (Y_START + HEIGHT))) begin
        return RECT_COLOR;
    end else begin 
        return rgb_bg;
    end
endfunction 

always_comb begin : rect_comb_blk
    if (vga_in.vblnk || vga_in.hblnk) begin
        rgb_nxt = 12'h0_0_0; 
    end else begin
        rgb_nxt = rectangle(vga_in.hcount, vga_in.vcount, vga_in.rgb);
    end
end

endmodule