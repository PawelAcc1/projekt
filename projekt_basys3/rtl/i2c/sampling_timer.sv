`timescale 1ns / 1ps

/* ==============================================================================
   Moduł: sampling_timer
   Przeznaczenie: Generowanie cyklicznego impulsu wyzwalającego (tick) dla układu I2C.
   ============================================================================== */

module sampling_timer #(
    parameter CLK_FREQ = 100_000_000, // Częstotliwość głównego zegara (100 MHz)
    parameter SAMPLING_RATE = 500    // Żądana częstotliwość pobierania próbek EKG (500 Hz)
)(
    input wire clk,           // Wejście: Główny sygnał zegarowy (100 MHz)
    input wire rst_n,         // Asynchroniczny reset aktywny nisko
    output logic start_sampling // Wyjście: Impuls wyzwalający maszynę stanów I2C
);

    /* ==========================================================================
       Obliczenia wewnętrzne (localparam):
       Wzór: (100 000 000 / 1000) = 100 000 taktów zegara.
       ========================================================================== */
    localparam MAX_COUNT = (CLK_FREQ / SAMPLING_RATE) - 1;

    /* ==========================================================================
       Definicja rejestru licznika:
       Funkcja $clog2 oblicza automatycznie minimalną szerokość magistrali.
       ========================================================================== */
    logic [$clog2(MAX_COUNT+1)-1:0] counter = 0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            start_sampling <= 1'b0;
        end else begin
            if (counter == MAX_COUNT) begin
                counter <= 0;            
                start_sampling <= 1'b1;  
            end else begin
                counter <= counter + 1;
                start_sampling <= 1'b0;   
            end
        end
    end

endmodule
