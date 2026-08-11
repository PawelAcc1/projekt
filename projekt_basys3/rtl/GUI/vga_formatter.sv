module vga_formatter #(
    parameter int IN_WIDTH    = 16, // szerokość słowa z FIR (signed)
    parameter int OUT_WIDTH   = 12, // szerokość danych bufora/wyświetlania (unsigned)
    parameter int GAIN_LSHIFT = 0  // AC gain: x(2^GAIN); 0 = x1
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sample_valid_in,
    input  logic [2:0] gain_lshift,
    input  logic signed [IN_WIDTH-1:0]  data_in,
    output logic [OUT_WIDTH-1:0] data_out,
    output logic data_ready
);

    localparam int MID  = (1 << (OUT_WIDTH-1)); // środek zakresu (2048 dla 12 bitów)
    localparam int MAXV = (1 << OUT_WIDTH) - 1; // maksimum zakresu (4095 dla 12 bitów)

    logic signed [31:0]         centered;

    assign centered = (32'(data_in) <<< gain_lshift) + MID;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out <= '0;
            data_ready <= '0;
        end
        else begin
            data_ready <= 1'b0;
            if (sample_valid_in) begin
                if (centered < 0)
            data_out <= '0;
            else if (centered > MAXV) begin
                data_out <= OUT_WIDTH'(MAXV);
            end
            else begin
                data_out <= centered[OUT_WIDTH-1:0];
            end
                data_ready <= 1'b1;
            end
        end
    end

endmodule
