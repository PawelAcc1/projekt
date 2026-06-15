`timescale 1ns / 1ps

module stemi_tb;

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

    logic deriv_valid_out_buff;
    logic signed [WIDTH-1:0] deriv_data_buff;
    logic ecg_valid_out_buff;
    logic signed [WIDTH-1:0] ecg_data_buff;
    logic stemi_alarm;

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

    delay_buffer #(
        .DELAY(44)
    ) u_delay_buffer_deriv (
        .clk              (clk),
        .rst_n            (rst_n),
        .data_in          (diff_out),
        .sample_valid_in  (diff_valid),
        .data_out         (deriv_data_buff),
        .sample_valid_out (deriv_valid_out_buff)
    );

    delay_buffer #(
        .DELAY(45)
    ) u_delay_buffer_ecg (
        .clk              (clk),
        .rst_n            (rst_n),
        .data_in          (raw_data_in),
        .sample_valid_in  (sample_valid_in),
        .data_out         (ecg_data_buff),
        .sample_valid_out (ecg_valid_out_buff)
    );

    stemi_detector u_stemi_detector (
        .clk              (clk),
        .rst_n            (rst_n),
        .ecg_data_in      (ecg_data_buff),
        .derivative_data_in (deriv_data_buff),
        .data_sample_valid_in (ecg_valid_out_buff),
        .derivative_sample_valid_in(deriv_valid_out_buff),
        .r_peak_detected  (r_peak_detected),
        .stemi_alarm      (stemi_alarm)
    );

    logic [7:0] bpm_out;
    logic bpm_valid_out;

    bpm_calculator u_bpm (
        .clk(clk),
        .rst_n(rst_n),
        .sample_tick(sample_valid_in), // Flaga valid działa tu jako tyknięcie zegara 500 Hz
        .r_peak_detected(r_peak_detected),
        .bpm(bpm_out),
        .bpm_valid(bpm_valid_out)
    );

    // Generator zegara
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // STYMULACJA SYGNAŁU
    initial begin
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        raw_data_in = '0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // 1. Płaska linia na start
        repeat (50) send_sample(16'd0);

        // ==========================================
        // FAZA 1: PRAWIDŁOWY SYGNAŁ EKG (Brak STEMI)
        // ==========================================
        $display("Symulacja: Prawidlowe uderzenia serca (Brak alarmu)");
        repeat (4) begin
            // Sztuczny QRS
            send_sample(16'd50);
            send_sample(16'd800);
            send_sample(16'd3000); 
            send_sample(-16'd800);
            send_sample(-16'd50);

            repeat (395) send_sample(16'd0);
        end

        // ==========================================
        // FAZA 2: PATOLOGICZNY SYGNAŁ EKG (STEMI)
        // ==========================================
        $display("Symulacja: Zawal STEMI (Alarm powinien sie aktywowac)");
        repeat (4) begin
            // Sztuczny QRS
            send_sample(16'd50);
            send_sample(16'd800);
            send_sample(16'd3000); 
            send_sample(-16'd800);
            send_sample(-16'd50);

            repeat (6) send_sample(16'd0);

            repeat (60) send_sample(16'd400);

            repeat (329) send_sample(16'd0);
        end

        repeat (150) send_sample(16'd0);

        $display("Koniec symulacji");
        $finish;
    end

    // Task wysyłający dane synchronizowane z zegarem
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