`timescale 1ns / 1ps

module bpm_calculator (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_tick,      // Impuls 500 Hz wyznaczający upływ czasu
    input  logic r_peak_detected,  // Impuls informujący o znalezieniu piku R
    
    output logic [7:0] bpm,        // Wyliczone i UŚREDNIONE BPM (max 255)
    output logic bpm_valid         // Flaga sygnalizująca wyliczenie nowej wartości
);

    // 11-bitowy licznik próbek wystarczy do zliczenia 2047 (timeout ustalamy na 2000)
    logic [10:0] sample_count; 

    // --- Pamięć ROM (Look-Up Table) ---
    logic [7:0] bpm_rom [0:2047];
    initial begin
        // Plik dodany do projektu przez read_mem (mem_files w project_details.tcl),
        // dzięki czemu Vivado znajduje go po samej nazwie zarówno w syntezie, jak i symulacji.
        $readmemh("bpm_rom.hex", bpm_rom);
    end

    // --- Rejestry do uśredniania (Moving Average) ---
    logic [7:0] bpm_history [0:3];
    
    // Zmienna pomocnicza (kombinacyjna) na odczyt z ROM
    logic [7:0] current_bpm_raw;
    assign current_bpm_raw = bpm_rom[sample_count];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count <= '0;
            bpm <= '0;
            bpm_valid <= 1'b0;
            for (int i = 0; i < 4; i++) bpm_history[i] <= '0;
        end 
        else begin
            bpm_valid <= 1'b0; 
            
            // 1. Zliczanie próbek (odmierzanie czasu)
            if (sample_tick) begin
                if (sample_count < 11'd2047) begin
                    sample_count <= sample_count + 1;
                end
            end

            // 2. Obsługa wykrytego piku R
            if (r_peak_detected) begin
                if (sample_count > 150 && sample_count <= 2000) begin
                    
                    // Aktualizacja historii tętna
                    bpm_history[0] <= current_bpm_raw;
                    bpm_history[1] <= bpm_history[0];
                    bpm_history[2] <= bpm_history[1];
                    bpm_history[3] <= bpm_history[2];

                    // Obliczenie średniej: wymuszamy 10-bitowe dodawanie
                    bpm <= (10'(current_bpm_raw) + 10'(bpm_history[0]) + 10'(bpm_history[1]) + 10'(bpm_history[2])) >> 2;
                    
                    bpm_valid <= 1'b1;
                end
                
                // Wyzerowanie licznika dla następnego uderzenia serca
                sample_count <= '0;
            end
            
            // 3. Timeout: brak piku R przez 4 sekundy (2000 próbek)
            if (sample_count > 2000) begin
                bpm <= 8'd0;
                bpm_valid <= 1'b1; 
                
                // Resetujemy historię, żeby przywrócenie sygnału nie uśredniało się z zerami
                for (int i = 0; i < 4; i++) bpm_history[i] <= '0;
                
                // Zatrzymujemy licznik
                sample_count <= 11'd2047; 
            end
        end
    end

endmodule