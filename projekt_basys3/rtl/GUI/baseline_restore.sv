module baseline_restore #(
    parameter int WIDTH    = 16, // szerokość słowa z FIR (signed)
    parameter int DC_SHIFT    = 9   // stała czasowa usuwania DC (większa = wolniejsza)
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,          // impuls: nowa próbka z FIR (tvalid)
    input  logic signed [WIDTH-1:0]  data_in, // probki z fir są signed
    output logic signed [WIDTH-1:0] data_out,
    output logic sample_valid_out
);

    logic signed [31:0]         dc_acc;   // akumulator estymaty DC
    logic signed [31:0]         dc_est;
    logic signed [31:0]         ac;       // próbka po usunięciu DC

    assign dc_est = dc_acc >>> DC_SHIFT;      // estymata składowej stałej
    assign ac     = 32'(data_in) - dc_est;     // składowa zmienna (AC)
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_acc <= '0;
            sample_valid_out <= '0;
            data_out <= '0;
        end 
        else begin
            sample_valid_out <= 1'b0;
            if (sample_valid_in) begin
                dc_acc <= dc_acc + ac;
                data_out <= ac[WIDTH-1:0];
                sample_valid_out <= 1'b1;
            end
        end
    end

endmodule