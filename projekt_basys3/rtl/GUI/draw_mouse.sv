module draw_mouse (
    input logic clk,
    input logic rst_n,
    input logic [11:0] x_start,
    input logic [11:0] y_start,
    vga_if.in vga_in,
    vga_if.out vga_out
);

import vga_pkg::*;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vga_out.vcount <= '0;
        vga_out.hsync <= '0;
        vga_out.vsync <= '0;
        vga_out.hcount <= '0;
        vga_out.hblnk <= '0;
        vga_out.vblnk <= '0;
    end
    else begin
        vga_out.vcount <= vga_in.vcount;
        vga_out.hsync <= vga_in.hsync;
        vga_out.vsync <= vga_in.vsync;
        vga_out.hcount <= vga_in.hcount;
        vga_out.hblnk <= vga_in.hblnk;
        vga_out.vblnk <= vga_in.vblnk;
    end
end

MouseDisplay u_MouseDisplay (
    .pixel_clk(clk),
    .xpos(x_start),
    .ypos(y_start),
    .hcount(vga_in.hcount),
    .vcount(vga_in.vcount),
    .blank(vga_in.hblnk | vga_in.vblnk),
    .rgb_in(vga_in.rgb),
    .enable_mouse_display_out(),
    .rgb_out(vga_out.rgb)
);
endmodule 