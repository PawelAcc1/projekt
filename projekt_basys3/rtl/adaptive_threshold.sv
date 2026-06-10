`timescale 1ns / 1ps

module adaptive_threshold #(
    parameter int WIDTH_IN = 39,
    // 200 ms przy f_s = 500 Hz to dokładnie 100 próbek (okres refrakcji)
    parameter int BLANKING_PERIOD = 100 
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,
    input  logic [WIDTH_IN-1:0] data_in,
    
    output logic r_peak_detected // Impuls (1 takt zegara) w momencie piku R
);

    // Rejestry historii sygnału do wykrywania "górki" (piku)
    logic [WIDTH_IN-1:0] mwi_d1;
    logic [WIDTH_IN-1:0] mwi_d2;

    // Estymaty sygnału (SPKI), szumu (NPKI) i dynamiczny próg
    logic [WIDTH_IN-1:0] spki;
    logic [WIDTH_IN-1:0] npki;
    logic [WIDTH_IN-1:0] threshold;
    
    // Licznik okresu ślepego (refrakcji)
    logic [7:0] blanking_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mwi_d1 <= '0;
            mwi_d2 <= '0;
            spki <= '0;
            npki <= '0;
            threshold <= '0;
            blanking_counter <= '0;
            r_peak_detected <= 1'b0;
        end 
        else begin
            r_peak_detected <= 1'b0; // Domyślnie brak piku
            
            if (sample_valid_in) begin
                // Przesunięcie okna historii
                mwi_d1 <= data_in;
                mwi_d2 <= mwi_d1;

                // Dekrementacja licznika refrakcji
                if (blanking_counter > 0) begin
                    blanking_counter <= blanking_counter - 1;
                end

                // Wykrycie lokalnego maksimum: sygnał rósł, a teraz maleje
                if ((mwi_d1 > data_in) && (mwi_d1 >= mwi_d2)) begin
                    
                    // Czy to prawdziwy QRS (powyżej progu)?
                    if ((mwi_d1 > threshold) && (blanking_counter == 0)) begin
                        r_peak_detected <= 1'b1;
                        blanking_counter <= BLANKING_PERIOD;
                        
                        // Aktualizacja SPKI: spki = spki - spki/8 + pik/8
                        spki <= spki - (spki >> 3) + (mwi_d1 >> 3);
                    end 
                    // Czy to tylko szum (poniżej progu)?
                    else if ((mwi_d1 <= threshold) && (blanking_counter == 0)) begin
                        // Aktualizacja NPKI: npki = npki - npki/8 + pik/8
                        npki <= npki - (npki >> 3) + (mwi_d1 >> 3);
                    end
                end

                // Aktualizacja progu w każdym takcie: threshold = npki + 0.25 * (spki - npki)
                // Zabezpieczenie na wypadek, gdyby spki < npki (zapobiega underflow na liczbach unsigned)
                if (spki > npki) begin
                    threshold <= npki + ((spki - npki) >> 2);
                end else begin
                    threshold <= npki;
                end
            end
        end
    end

endmodule