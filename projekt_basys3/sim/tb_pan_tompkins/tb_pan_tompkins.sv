`timescale 1ns / 1ps

module tb_pan_tompkins;

    // Parametry
    localparam int WIDTH = 16;
    localparam int WINDOW_SIZE = 75;
    localparam int BLANKING_PERIOD = 100;
    localparam real CLK_PERIOD = 20.0; // 50 MHz zegar

    // Sygnały
    logic clk;
    logic rst_n;
    logic sample_valid_in;
    logic signed [WIDTH-1:0] raw_data_in;
    logic r_peak_detected;

    // Przewody
    logic signed [WIDTH-1:0] diff_out;
    logic diff_valid;
    logic [(2*WIDTH)-1:0] sq_out;
    logic sq_valid;
    logic [(2*WIDTH)+6:0] mwi_out;
    logic mwi_valid;

    // Instancje
    differentiator #(.WIDTH(WIDTH)) u_diff (
        .clk(clk), .rst_n(rst_n),
        .sample_valid_in(sample_valid_in), .data_in(raw_data_in),
        .data_out(diff_out), .sample_valid_out(diff_valid)
    );

    squarer #(.WIDTH_IN(WIDTH)) u_sq (
        .clk(clk), .rst_n(rst_n),
        .sample_valid_in(diff_valid), .data_in(diff_out),
        .data_out(sq_out), .sample_valid_out(sq_valid)
    );

    moving_window_integration #(.WIDTH_IN(2*WIDTH), .WINDOW_SIZE(WINDOW_SIZE)) u_mwi (
        .clk(clk), .rst_n(rst_n),
        .sample_valid_in(sq_valid), .data_in(sq_out),
        .data_out(mwi_out), .sample_valid_out(mwi_valid)
    );

    adaptive_threshold #(.WIDTH_IN((2*WIDTH)+7), .BLANKING_PERIOD(BLANKING_PERIOD)) u_ath (
        .clk(clk), .rst_n(rst_n),
        .sample_valid_in(mwi_valid), .data_in(mwi_out),
        .r_peak_detected(r_peak_detected)
    );

    // Generator zegara
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // STYMULACJA SYGNAŁU
    initial begin
        // Reset
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        raw_data_in = '0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // 1. Płaska linia (cisza)
        repeat (50) send_sample(16'd0);

        // 2. Sztuczny pik R (bardzo stromy i duży)
        send_sample(16'd50);
        send_sample(16'd800);
        send_sample(16'd3000); // Szczyt QRS
        send_sample(-16'd800);
        send_sample(-16'd50);

        // 3. Płaska linia (odczekanie na reakcję modułów)
        repeat (150) send_sample(16'd0);

        // Koniec
        $finish;
    end

    // Task wysyłający dane
    task send_sample(input logic signed [15:0] val);
        begin
            @(posedge clk);
            raw_data_in = val;
            sample_valid_in = 1'b1;
            @(posedge clk);
            sample_valid_in = 1'b0;
            repeat (20) @(posedge clk); 
        end
    endtask

endmodule