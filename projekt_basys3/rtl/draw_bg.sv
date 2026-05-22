// Używamy 'automatic', aby upewnić się, że funkcja jest czysto kombinacyjna
    function automatic logic [11:0] draw_grid(
        input logic [10:0] hcount,
        input logic [10:0] vcount,
        input logic [11:0] rgb_bg
    );
        // Zmienne zdefiniowane lokalnie (nie zajmują pamięci, to tylko 'etykiety' dla kodu)
        logic [11:0] small_grid_colour = 12'h8_8_8; // Szary
        logic [11:0] large_grid_colour = 12'hf_f_f; // Biały

        // PRIORYTET 1: Duża siatka (co 64 piksele)
        // Sprawdzamy, czy 6 najmłodszych bitów to zera
        if (hcount[5:0] == 6'b000000 || vcount[5:0] == 6'b000000) begin
            return large_grid_colour;
        end
        // PRIORYTET 2: Mała siatka (co 32 piksele)
        // Sprawdzamy, czy 5 najmłodszych bitów to zera
        else if (hcount[4:0] == 5'b00000 || vcount[4:0] == 5'b00000) begin
            return small_grid_colour;
        end
        
        // PRIORYTET 3: Tło (jeśli nie rysujemy siatki)
        return rgb_bg;

    endfunction