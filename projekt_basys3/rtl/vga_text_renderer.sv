`timescale 1ns / 1ps

module vga_text_renderer #(
    parameter MAX_CHARS = 20,       // Długość stringa w znakach
    parameter CHAR_SCALE = 1        // Skala czcionki
)(
    input  logic clk,
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic [11:0] pos_x,
    input  logic [11:0] pos_y,
    input  logic [(MAX_CHARS*8)-1:0] char_string, 
    input  logic [4:0]  string_len, // ZMIANA NA 5 BITÓW (pozwala na 31 znaków)
    output logic pixel_on
);

    logic [10:0] font_addr;
    logic [7:0]  font_pixels;

    font_rom u_font (
        .clk(clk),
        .addr(font_addr),
        .char_line_pixels(font_pixels)
    );

    localparam int CHAR_W = 8 * CHAR_SCALE;
    localparam int CHAR_H = 16 * CHAR_SCALE;

    logic [11:0] rel_x, rel_y;
    assign rel_x = (hcount >= pos_x) ? (hcount - pos_x) : 12'd4095;
    assign rel_y = (vcount >= pos_y) ? (vcount - pos_y) : 12'd4095;

    logic [4:0] current_char_idx;
    logic [6:0] ascii_code;
    logic [3:0] font_row;
    logic [2:0] font_col;

    always_comb begin
        pixel_on = 1'b0;
        font_addr = 11'd0;
        
        if (string_len > 0 && vcount >= pos_y && vcount < pos_y + CHAR_H &&
            hcount >= pos_x && hcount < pos_x + (string_len * CHAR_W)) begin
            
            current_char_idx = rel_x / CHAR_W;
            ascii_code = char_string[((MAX_CHARS - 1 - current_char_idx) * 8) +: 8];
            
            font_row = rel_y / CHAR_SCALE;
            font_col = 3'd7 - (int'(rel_x % CHAR_W) / CHAR_SCALE);
            
            font_addr = {ascii_code, font_row};
            pixel_on = font_pixels[font_col];
        end
    end
endmodule
