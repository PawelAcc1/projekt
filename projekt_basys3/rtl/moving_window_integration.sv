`timescale 1ns / 1ps

module moving_window_integration #(
    parameter int WIDTH_IN = 32,
    parameter int WINDOW_SIZE = 75 // 150 ms dla fs = 500 Hz
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,
    input  logic [WIDTH_IN-1:0] data_in,
    
    // Szerokość zwiększona o 7 bitów, ponieważ max suma 75 próbek 
    // może wzrosnąć maksymalnie o tyle (2^6 < 75 < 2^7)
    output logic [WIDTH_IN+6:0] data_out,
    output logic sample_valid_out
);

    // Linia opóźniająca do przechowywania próbek wewnątrz okna
    logic [WIDTH_IN-1:0] delay_line [0:WINDOW_SIZE-1];
    
    // Akumulator sumy kroczącej
    logic [WIDTH_IN+6:0] running_sum;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running_sum <= '0;
            data_out <= '0;
            sample_valid_out <= 1'b0;
            for (int i = 0; i < WINDOW_SIZE; i++) begin
                delay_line[i] <= '0;
            end
        end 
        else begin
            sample_valid_out <= 1'b0;
            
            if (sample_valid_in) begin
                // Obliczamy nową sumę: aktualna suma + nowe wejście - najstarsza próbka wyjściowa
                // delay_line[WINDOW_SIZE-1] to próbka x[n-N]
                running_sum <= running_sum + data_in - delay_line[WINDOW_SIZE-1];
                
                // Przesunięcie rejestru (wprowadzenie nowej próbki na początek linii)
                for (int i = WINDOW_SIZE-1; i > 0; i--) begin
                    delay_line[i] <= delay_line[i-1];
                end
                delay_line[0] <= data_in;
                
                // Wystawienie zaimportowanego i zaktualizowanego wyniku na wyjście (w pełni potokowo)
                data_out <= running_sum + data_in - delay_line[WINDOW_SIZE-1];
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule