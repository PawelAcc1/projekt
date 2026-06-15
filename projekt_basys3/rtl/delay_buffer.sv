module delay_buffer #(
    parameter int DELAY = 4,
    parameter type DTYPE = logic signed [15:0] 
)(
    input  logic clk,
    input  logic rst_n,
    input  DTYPE data_in,     
    input  logic sample_valid_in,

    output logic sample_valid_out,
    output DTYPE data_out      
);

    DTYPE delay_line [0:DELAY-1];
    
    logic [DELAY-1:0] valid_line;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_valid_out <= 1'b0;
            data_out <= '0;
            valid_line <= '0;
            for (int i = 0; i < DELAY; i++) begin
                delay_line[i] <= '0;
            end
        end
        else begin
            sample_valid_out <= 1'b0;
            
            if (sample_valid_in) begin
                delay_line[0] <= data_in;
                for(int i = 0; i < DELAY-1; i++) begin
                    delay_line[i+1] <= delay_line[i];
                end
                data_out <= delay_line[DELAY-1];
                
                valid_line <= {valid_line[DELAY-2:0], 1'b1};
            
                sample_valid_out <= valid_line[DELAY-1];
            end
        end
    end

endmodule