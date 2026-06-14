`timescale 1ns / 1ps

module differentiator #(
    parameter int WIDTH = 16 // Width of the input word (signed)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,          // Tvalid from the previous block
    input  logic signed [WIDTH-1:0] data_in, // x[n]
    output logic signed [WIDTH-1:0] data_out, // y[n]
    output logic sample_valid_out
);

    // Shift register to store x[n-1], x[n-2], x[n-3], x[n-4]
    logic signed [WIDTH-1:0] shift_reg [0:3];
    
    // Internal signal to hold the sum before division
    // We add 3 extra bits to WIDTH to prevent overflow during addition/multiplication.
    // Max value is 6 * max(x), and 6 fits in 3 bits.
    logic signed [WIDTH+2:0] sum;
    
    // Sign-extended signals for safe arithmetic
    logic signed [WIDTH+2:0] ext_data_in;
    logic signed [WIDTH+2:0] ext_xn1;
    logic signed [WIDTH+2:0] ext_xn3;
    logic signed [WIDTH+2:0] ext_xn4;

    assign ext_data_in = data_in;
    assign ext_xn1     = shift_reg[0]; // x[n-1]
    assign ext_xn3     = shift_reg[2]; // x[n-3]
    assign ext_xn4     = shift_reg[3]; // x[n-4]

    // Combinational logic for the formula: 2*x[n] + x[n-1] - x[n-3] - 2*x[n-4]
    assign sum = (ext_data_in <<< 1) + ext_xn1 - ext_xn3 - (ext_xn4 <<< 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg[0] <= '0;
            shift_reg[1] <= '0;
            shift_reg[2] <= '0;
            shift_reg[3] <= '0;
            data_out <= '0;
            sample_valid_out <= 1'b0;
        end 
        else begin
            // Default pulse state
            sample_valid_out <= 1'b0; 
            
            if (sample_valid_in) begin
                // Update the shift register
                shift_reg[0] <= data_in;      // x[n-1] becomes current x[n]
                shift_reg[1] <= shift_reg[0]; // x[n-2]
                shift_reg[2] <= shift_reg[1]; // x[n-3]
                shift_reg[3] <= shift_reg[2]; // x[n-4]

                // Divide sum by 8 (shift right by 3) and assign to output
                // We truncate it back to the original WIDTH
                data_out <= sum[WIDTH+2 : 3]; 
                
                // Assert valid flag for the next module
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule