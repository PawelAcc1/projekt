`timescale 1ns / 1ps

module squarer #(
    parameter int WIDTH_IN = 16 // Szerokość słowa z derywatora
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,
    input  logic signed [WIDTH_IN-1:0] data_in,
    
    // Wynik mnożenia ma dwukrotnie większą szerokość bitową.
    // Ponieważ kwadrat liczby jest zawsze dodatni/zerowy, używamy logic (unsigned).
    output logic [(2*WIDTH_IN)-1:0] data_out,
    output logic sample_valid_out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= '0;
            sample_valid_out <= 1'b0;
        end 
        else begin
            // Domyślny stan flagi valid (impuls 1-taktowy)
            sample_valid_out <= 1'b0; 
            
            if (sample_valid_in) begin
                // Mnożenie sygnału przez samego siebie
                data_out <= data_in * data_in;
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule