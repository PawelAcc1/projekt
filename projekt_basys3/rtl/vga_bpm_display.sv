`timescale 1ns / 1ps

module vga_bpm_display (
    input  logic [7:0] bpm,
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    output logic [11:0] rgb_out
);

    // 1. Konwersja liczby binarnej na cyfry dziesiętne (BCD)
    // Ponieważ to tylko 8-bitów i operujemy na małych liczbach (max 255), 
    // Vivado bez problemu zsyntezuje te dzielenia jako prostą logikę.
    logic [3:0] digit_h; // Setki
    logic [3:0] digit_t; // Dziesiątki
    logic [3:0] digit_u; // Jedności

    always_comb begin
        digit_h = bpm / 100;
        digit_t = (bpm % 100) / 10;
        digit_u = bpm % 10;
    end

    // 2. Sygnały wyjściowe z poszczególnych cyfr
    logic pixel_h, pixel_t, pixel_u;

    // 3. Instancje cyfr (ustawione w prawym panelu bocznym)
    // Cyfra setek (wyłączamy ją, jeśli wynosi 0, żeby np. "072" wyświetlało się jako " 72")
    vga_7seg_digit #( .POS_X(820), .POS_Y(150), .WIDTH(30), .HEIGHT(60), .THICKNESS(6) ) u_dig_h (
        .digit_val(digit_h), .hcount(hcount), .vcount(vcount), 
        .pixel_on(pixel_h)
    );

    // Cyfra dziesiątek
    vga_7seg_digit #( .POS_X(860), .POS_Y(150), .WIDTH(30), .HEIGHT(60), .THICKNESS(6) ) u_dig_t (
        .digit_val(digit_t), .hcount(hcount), .vcount(vcount), 
        .pixel_on(pixel_t)
    );

    // Cyfra jedności
    vga_7seg_digit #( .POS_X(900), .POS_Y(150), .WIDTH(30), .HEIGHT(60), .THICKNESS(6) ) u_dig_u (
        .digit_val(digit_u), .hcount(hcount), .vcount(vcount), 
        .pixel_on(pixel_u)
    );

    // 4. Kolorowanie cyfr na jaskrawy zielony (medyczny) kolor
    always_comb begin
        if ((pixel_h && digit_h > 0) || pixel_t || pixel_u)
            rgb_out = 12'h0_F_0; // Jasnozielony
        else
            rgb_out = 12'h0_0_0; // Przezroczysty/Czarny
    end

endmodule