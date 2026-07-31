module draw_grid #(
    parameter WIDTH = 12
)(
    input logic clk,
    input logic rst_n,
    vga_if.in vga_in,
    vga_if.out vga_out
);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        vga_out.hblnk <= '0;
        vga_out.vblnk <= '0;
        vga_out.hsync <= '0;
        vga_out.vsync <= '0;
        vga_out.vcount <= '0;
        vga_out.hcount <= '0;
        vga_out.rgb <= '0;
    end else begin
        // one stage pipeline
        vga_out.hblnk <= vga_in.hblnk;
        vga_out.vblnk <= vga_in.vblnk;
        vga_out.hsync <= vga_in.hsync;
        vga_out.vsync <= vga_in.vsync;
        vga_out.vcount <= vga_in.vcount;
        vga_out.hcount <= vga_in.hcount;
        vga_out.rgb <= get_grid(vga_in.hcount, vga_in.vcount, vga_in.hblnk, vga_in.vblnk, vga_in.rgb);
    end
end

    function automatic logic [11:0] get_grid(
        input logic [WIDTH-1:0] hcount,
        input logic [WIDTH-1:0] vcount,
        input logic hblnk,
        input logic vblnk,
        input logic [11:0] rgb_bg
    );

        logic [11:0] small_grid_colour = 12'h8_8_8; // Szary
        logic [11:0] large_grid_colour = 12'hf_f_f; // Biały
        logic [11:0] dead_zone_colour = 12'h0_0_0; // Czarny

        if(hblnk || vblnk) begin
            return dead_zone_colour;
        end else begin
            if (hcount[5:0] == 6'b000000 || vcount[5:0] == 6'b000000) begin
                return large_grid_colour;
            end
            else if (hcount[4:0] == 5'b00000 || vcount[4:0] == 5'b00000) begin
                return small_grid_colour;
            end
            else begin
                return rgb_bg;
            end
        end
    endfunction
endmodule