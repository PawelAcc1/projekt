module draw_mouse (
    input logic clk,
    input logic rst_n,
    input logic [11:0] x_start,
    input logic [11:0] y_start,
    vga_if.in vga_in,
    vga_if.out vga_out
);

import vga_pkg::*;

logic [11:0] x_sync1, x_sync2;
logic [11:0] y_sync1, y_sync2;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vga_out.vcount <= '0;
        vga_out.hsync <= '0;
        vga_out.vsync <= '0;
        vga_out.hcount <= '0;
        vga_out.hblnk <= '0;
        vga_out.vblnk <= '0;

        x_sync1 <= '0;
        x_sync2 <= '0;
        y_sync1 <= '0;
        y_sync2 <= '0;
    end
    else begin
        vga_out.vcount <= vga_in.vcount;
        vga_out.hsync <= vga_in.hsync;
        vga_out.vsync <= vga_in.vsync;
        vga_out.hcount <= vga_in.hcount;
        vga_out.hblnk <= vga_in.hblnk;
        vga_out.vblnk <= vga_in.vblnk;
        x_sync1 <= x_start;
        y_sync1 <= y_start;
        x_sync2 <= x_sync1;
        y_sync2 <= y_sync1;
    end
end

MouseDisplay u_MouseDisplay (
    .pixel_clk(clk),
    .xpos(x_sync2),
    .ypos(y_sync2),
    .hcount(vga_in.hcount[10:0]),
    .vcount(vga_in.vcount[10:0]),
    .blank(vga_in.hblnk | vga_in.vblnk),
    .rgb_in(vga_in.rgb),
    .enable_mouse_display_out(),
    .rgb_out(vga_out.rgb)
);
endmodule 
