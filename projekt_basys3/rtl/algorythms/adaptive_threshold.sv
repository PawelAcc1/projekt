`timescale 1ns / 1ps

module adaptive_threshold #(
    parameter int WIDTH_IN = 39,
    parameter int BLANKING_PERIOD = 100,
    parameter int WARMUP_SAMPLES = 700,
    parameter int POST_WARMUP_LEARN = 200
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

    // Licznik rozgrzewki
    logic [$clog2(WARMUP_SAMPLES+1)-1:0] warmup_counter;
    logic [$clog2(WARMUP_SAMPLES+POST_WARMUP_LEARN+1)-1:0] learn_counter;
    logic warmup_done;
    logic detect_enable;

    assign warmup_done    = (warmup_counter >= WARMUP_SAMPLES);
    assign detect_enable  = (learn_counter >= WARMUP_SAMPLES + POST_WARMUP_LEARN);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mwi_d1 <= '0;
            mwi_d2 <= '0;
            spki <= '0;
            npki <= '0;
            threshold <= '0;
            blanking_counter <= '0;
            warmup_counter <= '0;
            learn_counter <= '0;
            r_peak_detected <= 1'b0;
        end 
        else begin
            r_peak_detected <= 1'b0; // Domyślnie brak piku
            
            if (sample_valid_in) begin
                if (learn_counter < WARMUP_SAMPLES + POST_WARMUP_LEARN)
                    learn_counter <= learn_counter + 1'b1;

                // Koniec fazy warmup: reset progu
                if (warmup_counter == WARMUP_SAMPLES - 1) begin
                    spki      <= '0;
                    npki      <= '0;
                    threshold <= '0;
                    blanking_counter <= '0;
                end

                if (!warmup_done)
                    warmup_counter <= warmup_counter + 1'b1;

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
                        // Impuls wystawiamy dopiero PO rozgrzewce, natomiast
                        // adaptację spki i refrakcję prowadzimy od początku,
                        // aby próg był już dobrze ustawiony, gdy zaczniemy ufać detekcjom.
                        if (detect_enable) begin
                            r_peak_detected <= 1'b1;
                        end
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
                // Zabezpieczenie na wypadek, gdyby spki < npki
                if (spki > npki) begin
                    threshold <= npki + ((spki - npki) >> 2);
                end else begin
                    threshold <= npki;
                end
            end
        end
    end

endmodule