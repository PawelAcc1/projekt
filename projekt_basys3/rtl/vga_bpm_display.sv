`timescale 1ns / 1ps

module vga_bpm_display (
    input  logic clk_65MHz, // Zegar do animacji bicia
    input  logic rst_n,
    input  logic [7:0] bpm,
    input  logic bpm_valid, // Impuls do synchronizacji animacji serca
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    output logic [11:0] rgb_out
);

    // 1. ZAMIANA LICZBY NA TEKST ASCII
    logic [7:0] setki, dziesiatki, jednosci;
    
    assign setki      = (bpm / 100) + 8'h30;       
    assign dziesiatki = ((bpm % 100) / 10) + 8'h30;
    assign jednosci   = (bpm % 10) + 8'h30;

    logic [23:0] bpm_string; 
    assign bpm_string = {setki, dziesiatki, jednosci};

    logic text_pixel;
    vga_text_renderer #(.MAX_CHARS(3), .CHAR_SCALE(4)) txt_renderer (
        .clk(clk_65MHz), .hcount(hcount), .vcount(vcount),
        .pos_x(12'd820), .pos_y(12'd100), 
        .char_string(bpm_string), .string_len(4'd3), .pixel_on(text_pixel)
    );

    // 2. PIKSELOWE SERCE W SPRZĘCIE
    logic [9:0] heart_map [0:9];
    assign heart_map[0] = 10'b0011001100;
    assign heart_map[1] = 10'b0111111110;
    assign heart_map[2] = 10'b1111111111;
    assign heart_map[3] = 10'b1111111111;
    assign heart_map[4] = 10'b1111111111;
    assign heart_map[5] = 10'b0111111110;
    assign heart_map[6] = 10'b0011111100; // <--- TUTAJ BYŁA LITERÓWKA! POPRAWIONE!
    assign heart_map[7] = 10'b0001111000;
    assign heart_map[8] = 10'b0000110000;
    assign heart_map[9] = 10'b0000000000;

    localparam int HEART_X = 855; 
    localparam int HEART_Y = 180; 
    localparam int SCALE = 5;     

    logic heart_pixel;
    always_comb begin
        heart_pixel = 1'b0;
        if (hcount >= HEART_X && hcount < HEART_X + 10*SCALE &&
            vcount >= HEART_Y && vcount < HEART_Y + 10*SCALE) begin
            
            int col = (hcount - HEART_X) / SCALE;
            int row = (vcount - HEART_Y) / SCALE;
            if (heart_map[row][9 - col]) heart_pixel = 1'b1;
        end
    end

    // 3. LOGIKA PULSOWANIA 
    logic [24:0] beat_timer;
    logic is_beating;

    always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            beat_timer <= '0;
        end else begin
            if (bpm_valid) begin
                beat_timer <= 25'd10_000_000; 
            end else if (beat_timer > 0) begin
                beat_timer <= beat_timer - 1'b1; 
            end
        end
    end
    assign is_beating = (beat_timer > 0);

    // 4. MIKSER KOLORÓW WIDEO
    always_comb begin
        rgb_out = 12'h000; 
        
        if (text_pixel) begin
            rgb_out = 12'h0F0; 
        end else if (heart_pixel) begin
            if (is_beating) rgb_out = 12'hF00; 
            else            rgb_out = 12'h400; 
        end
    end
endmodule