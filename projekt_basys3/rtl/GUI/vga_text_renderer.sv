`timescale 1ns / 1ps

module vga_text_renderer #(
    parameter MAX_CHARS = 25,       // Maksymalna pojemność pamięci modułu
    parameter CHAR_SCALE = 1        // Skala czcionki
)(
    input  logic clk,
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic [11:0] pos_x,
    input  logic [11:0] pos_y,
    input  logic [(MAX_CHARS*8)-1:0] char_string, 
    input  logic [4:0]  string_len, // Ilosc znaków do narysowania
    output logic pixel_on
);

    logic [10:0] font_addr;
    logic [7:0]  font_pixels;

    // Pamięć znaków
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

    // Faza 1: Żądanie adresu (bez opóźnienia)
    always_comb begin
        font_addr = 11'd0;
        
        if (string_len > 0 && vcount >= pos_y && vcount < pos_y + CHAR_H &&
            hcount >= pos_x && hcount < pos_x + (string_len * CHAR_W)) begin
            
            current_char_idx = rel_x / CHAR_W;
            ascii_code = char_string[((MAX_CHARS - 1 - current_char_idx) * 8) +: 8];
            font_row = rel_y / CHAR_SCALE;
            
            font_addr = {ascii_code, font_row};
        end
    end

    // Faza 2: Synchronizacja 1-taktowego opóźnienia (Pipeline)
    logic [2:0] delayed_font_col;
    logic delayed_active;

    always_ff @(posedge clk) begin
        if (string_len > 0 && vcount >= pos_y && vcount < pos_y + CHAR_H &&
            hcount >= pos_x && hcount < pos_x + (string_len * CHAR_W)) begin
            
            delayed_active <= 1'b1;
            // Zapisujemy, którą kolumnę piskeli należy wybrać, gdy ROM wyrzuci linię
            delayed_font_col <= 3'd7 - (int'(rel_x % CHAR_W) / CHAR_SCALE);
        end else begin
            delayed_active <= 1'b0;
        end
    end

    // Faza 3: Wyświetlenie piksela
    assign pixel_on = delayed_active ? font_pixels[delayed_font_col] : 1'b0;

endmodule