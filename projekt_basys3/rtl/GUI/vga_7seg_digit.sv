`timescale 1ns / 1ps

module vga_7seg_digit #(
    parameter POS_X = 0,       // Pozycja X lewego górnego rogu
    parameter POS_Y = 0,       // Pozycja Y lewego górnego rogu
    parameter WIDTH = 30,      // Całkowita szerokość cyfry
    parameter HEIGHT = 60,     // Całkowita wysokość cyfry
    parameter THICKNESS = 6    // Grubość pojedynczego segmentu
)(
    input  logic [3:0] digit_val,
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    output logic pixel_on
);

    // Dekodowanie 7-segmentowe (1 = segment włączony, 0 = wyłączony)
    // Kolejność bitów: {G, F, E, D, C, B, A}
    logic [6:0] segments;
    
    always_comb begin
        case (digit_val)
            4'd0: segments = 7'b0111111;
            4'd1: segments = 7'b0000110;
            4'd2: segments = 7'b1011011;
            4'd3: segments = 7'b1001111;
            4'd4: segments = 7'b1100110;
            4'd5: segments = 7'b1101101;
            4'd6: segments = 7'b1111101;
            4'd7: segments = 7'b0000111;
            4'd8: segments = 7'b1111111;
            4'd9: segments = 7'b1101111;
            default: segments = 7'b0000000; // Puste dla nieznanych wartości
        endcase
    end

    // Flagi trafienia piksela w konkretny segment
    logic seg_A, seg_B, seg_C, seg_D, seg_E, seg_F, seg_G;

    always_comb begin
        // Segment A (Górny poziomy)
        seg_A = (hcount >= POS_X && hcount <= POS_X + WIDTH) &&
                (vcount >= POS_Y && vcount <= POS_Y + THICKNESS);
                
        // Segment B (Prawy górny pionowy)
        seg_B = (hcount >= POS_X + WIDTH - THICKNESS && hcount <= POS_X + WIDTH) &&
                (vcount >= POS_Y && vcount <= POS_Y + HEIGHT/2);
                
        // Segment C (Prawy dolny pionowy)
        seg_C = (hcount >= POS_X + WIDTH - THICKNESS && hcount <= POS_X + WIDTH) &&
                (vcount >= POS_Y + HEIGHT/2 && vcount <= POS_Y + HEIGHT);
                
        // Segment D (Dolny poziomy)
        seg_D = (hcount >= POS_X && hcount <= POS_X + WIDTH) &&
                (vcount >= POS_Y + HEIGHT - THICKNESS && vcount <= POS_Y + HEIGHT);
                
        // Segment E (Lewy dolny pionowy)
        seg_E = (hcount >= POS_X && hcount <= POS_X + THICKNESS) &&
                (vcount >= POS_Y + HEIGHT/2 && vcount <= POS_Y + HEIGHT);
                
        // Segment F (Lewy górny pionowy)
        seg_F = (hcount >= POS_X && hcount <= POS_X + THICKNESS) &&
                (vcount >= POS_Y && vcount <= POS_Y + HEIGHT/2);
                
        // Segment G (Środkowy poziomy)
        seg_G = (hcount >= POS_X && hcount <= POS_X + WIDTH) &&
                (vcount >= POS_Y + HEIGHT/2 - THICKNESS/2 && vcount <= POS_Y + HEIGHT/2 + THICKNESS/2);
    end

    // Logika wyjściowa - podnieś flagę, jeśli piksel jest w zapalonym segmencie
    always_comb begin
        pixel_on = (segments[0] & seg_A) |
                   (segments[1] & seg_B) |
                   (segments[2] & seg_C) |
                   (segments[3] & seg_D) |
                   (segments[4] & seg_E) |
                   (segments[5] & seg_F) |
                   (segments[6] & seg_G);
    end

endmodule