`timescale 1ns / 1ps

module bpm_calculator (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_tick,      // Impuls 500 Hz wyznaczający upływ czasu
    input  logic r_peak_detected,  // Impuls informujący o znalezieniu piku R
    
    output logic [7:0] bpm,        // Wyliczone BPM (max 255)
    output logic bpm_valid         // Flaga sygnalizująca wyliczenie nowej wartości
);

    // Licznik próbek między kolejnymi pikami R
    logic [11:0] sample_count; 

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count <= '0;
            bpm <= '0;
            bpm_valid <= 1'b0;
        end 
        else begin
            bpm_valid <= 1'b0; // Domyślnie brak nowej wartości
            
            // 1. Zliczanie próbek (odmierzanie czasu)
            if (sample_tick) begin
                // Zabezpieczenie przed przekręceniem licznika (zatrzyma się na max)
                if (sample_count < 12'hFFF) begin
                    sample_count <= sample_count + 1;
                end
            end

            // 2. Kiedy algorytm Pan-Tompkinsa wykryje pik R
            if (r_peak_detected) begin
                // Zabezpieczenie: jeśli minęło mniej niż 150 próbek (0.3 s), 
                // to tętno wynosiłoby ponad 200 BPM. Traktujemy to jako błąd/szum.
                if (sample_count > 150) begin
                    // Magiczny wzór optymalizujący dzielenie: 30000 / liczba próbek
                    bpm <= 30000 / sample_count;
                    bpm_valid <= 1'b1;
                end
                
                // Wyzerowanie licznika dla następnego uderzenia serca
                sample_count <= '0;
            end
            
            // 3. Timeout: jeżeli nie ma piku R przez 2000 próbek (4 sekundy), 
            // zakładamy brak sygnału i zerujemy wynik (0 BPM).
            if (sample_count > 2000) begin
                bpm <= 8'd0;
                bpm_valid <= 1'b1; 
                // Zatrzymujemy licznik, żeby nie wyzwalał valid w nieskończoność
                sample_count <= 12'hFFF; 
            end
        end
    end

endmodule