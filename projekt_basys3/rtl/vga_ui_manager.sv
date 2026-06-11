`timescale 1ns / 1ps

module vga_ui_manager (
    input  logic clk,
    input  logic rst_n,
    
    // Sygnały z myszki
    input  logic [11:0] mouse_x,
    input  logic [11:0] mouse_y,
    input  logic mouse_left,

    // Interfejsy VGA (wejście z wykresu, wyjście na ekran)
    vga_if.in  vga_in,
    vga_if.out vga_out
);

    import vga_pkg::*;

    // --- Definicja stanów FSM ---
    typedef enum logic [1:0] {
        STATE_SETUP   = 2'b00,
        STATE_MONITOR = 2'b01,
        STATE_HISTORY = 2'b10
    } state_t;
    
    state_t current_state;
    logic prev_mouse_left;

    // --- Paleta kolorów ---
    localparam logic [11:0] COLOR_BG     = 12'h000; // Czerń
    localparam logic [11:0] COLOR_BORDER = 12'h444; // Szary obrys
    localparam logic [11:0] COLOR_BTN    = 12'h225; // Ciemnoniebieski przycisk

    // --- Geometria i strefy ---
    logic draw_border, in_ecg_zone, draw_button;

    // --- Maszyna Stanów (Obsługa kliknięć myszką) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_SETUP;
            prev_mouse_left <= 1'b0;
        end else begin
            prev_mouse_left <= mouse_left;
            
            // Reakcja tylko na zbocze narastające (pojedyncze kliknięcie)
            if (mouse_left && !prev_mouse_left) begin
                case (current_state)
                    STATE_SETUP: begin
                        // Kliknięcie w przycisk "START" na środku ekranu
                        if (mouse_x > 400 && mouse_x < 624 && mouse_y > 350 && mouse_y < 420)
                            current_state <= STATE_MONITOR;
                    end
                    STATE_MONITOR: begin
                        // Kliknięcie w przycisk "HISTORIA" w prawym panelu
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670)
                            current_state <= STATE_HISTORY;
                    end
                    STATE_HISTORY: begin
                        // Kliknięcie w przycisk "POWRÓT" w prawym panelu
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670)
                            current_state <= STATE_MONITOR;
                    end
                endcase
            end
        end
    end

    // --- Logika renderowania stref przestrzennych ---
    always_comb begin
        draw_border = 1'b0;
        in_ecg_zone = 1'b0;
        draw_button = 1'b0;

        // Pasek górny (Zawsze widoczny)
        if (vga_in.vcount == 60) draw_border = 1'b1;

        case (current_state)
            STATE_SETUP: begin
                // Centralny przycisk "START"
                if (vga_in.hcount > 400 && vga_in.hcount < 624 && vga_in.vcount > 350 && vga_in.vcount < 420)
                    draw_button = 1'b1;
            end

            STATE_MONITOR: begin
                // Obszar wykresu EKG
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 520)) ||
                    (vga_in.vcount >= 90 && vga_in.vcount <= 520 && (vga_in.hcount == 30 || vga_in.hcount == 740)))
                    draw_border = 1'b1;
                    
                if (vga_in.hcount > 30 && vga_in.hcount < 740 && vga_in.vcount > 90 && vga_in.vcount < 520)
                    in_ecg_zone = 1'b1;

                // Obszar Alarmów
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 550 || vga_in.vcount == 730)) ||
                    (vga_in.vcount >= 550 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740)))
                    draw_border = 1'b1;

                // Panel Boczny i Przycisk
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) ||
                    (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990)))
                    draw_border = 1'b1;
                    
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670)
                    draw_button = 1'b1;
            end

            STATE_HISTORY: begin
                // Scalona tabela po lewej stronie
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 730)) ||
                    (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740)))
                    draw_border = 1'b1;

                // Panel Boczny i Przycisk powrotu
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) ||
                    (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990)))
                    draw_border = 1'b1;
                    
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670)
                    draw_button = 1'b1;
            end
        endcase
    end

    // --- Synchronizacja sygnałów VGA i Kolorowanie ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vga_out.hcount <= '0; vga_out.vcount <= '0;
            vga_out.hsync  <= '0; vga_out.vsync  <= '0;
            vga_out.hblnk  <= '0; vga_out.vblnk  <= '0;
            vga_out.rgb    <= 12'h000;
        end else begin
            // Przepuszczanie sygnałów synchronizacji dalej
            vga_out.hcount <= vga_in.hcount;
            vga_out.vcount <= vga_in.vcount;
            vga_out.hsync  <= vga_in.hsync;
            vga_out.vsync  <= vga_in.vsync;
            vga_out.hblnk  <= vga_in.hblnk;
            vga_out.vblnk  <= vga_in.vblnk;

            // Multiplekser kolorów w zależności od priorytetu
            if (draw_border)
                vga_out.rgb <= COLOR_BORDER;
            else if (draw_button)
                vga_out.rgb <= COLOR_BTN;
            else if (current_state == STATE_MONITOR && in_ecg_zone)
                vga_out.rgb <= vga_in.rgb; // Przepuść wykres EKG
            else
                vga_out.rgb <= COLOR_BG;
        end
    end

endmodule