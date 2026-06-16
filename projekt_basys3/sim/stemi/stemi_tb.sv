`timescale 1ns / 1ps

module stemi_tb; // <-- Zmieniona nazwa, aby idealnie pasowała do skryptu!

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

    // Przewody z algorytmu
    logic signed [WIDTH-1:0] diff_out;
    logic diff_valid;
    logic [(2*WIDTH)-1:0] sq_out;
    logic sq_valid;
    logic [(2*WIDTH)+6:0] mwi_out;
    logic mwi_valid;

    // Przewody buforów opóźniających
    logic deriv_valid_out_buff;
    logic signed [WIDTH-1:0] deriv_data_buff;
    logic ecg_valid_out_buff;
    logic signed [WIDTH-1:0] ecg_data_buff;
    
    // Wyjście zawału
    logic stemi_alarm;

    // --- INSTANCJE PAN-TOMPKINS ---
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

    // --- INSTANCJE BUFORÓW SYNCHRONIZUJĄCYCH ---
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

    // --- DETEKTOR STEMI ---
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
        .sample_tick(sample_valid_in),
        .r_peak_detected(r_peak_detected),
        .bpm(bpm_out),
        .bpm_valid(bpm_valid_out)
    );

    // Generator głównego zegara 50MHz
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

    // ==========================================
    // STYMULACJA SYGNAŁU (WEKTORY TESTOWE)
    // ==========================================
    initial begin
        // Sanity check - potwierdzenie załadowania nowego pliku
        $display("========================================");
        $display("START SYMULACJI: WERSJA FIZJOLOGICZNA");
        $display("========================================");
        
        rst_n = 1'b0;
        sample_valid_in = 1'b0;
        raw_data_in = '0;
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 10);

        // Odczekanie na stabilizację sygnału
        repeat (50) send_sample(16'd0);

        // ------------------------------------------
        // FAZA 1: PRAWIDŁOWY SYGNAŁ EKG (Brak STEMI)
        // ------------------------------------------
        $display("Generowanie 4 zdrowych uderzen serca...");
        repeat (4) begin
            // Tworzenie szerokiego QRS (~40 próbek = 80ms)
            for (int i=1; i<=15; i++) send_sample(16'd200 * i);              // R-wave rosnie
            for (int i=1; i<=20; i++) send_sample(16'd3000 - (16'd190 * i)); // S-wave spada
            for (int i=1; i<=5; i++)  send_sample(-16'd800 + (16'd160 * i)); // Wraca do 0

            // Reszta uderzenia (izolinia)
            repeat (360) send_sample(16'd0);
        end

        // ------------------------------------------
        // FAZA 2: PATOLOGICZNY SYGNAŁ EKG (STEMI)
        // ------------------------------------------
        $display("Generowanie 4 uderzen z zawalem STEMI...");
        repeat (4) begin
            // Tworzenie szerokiego QRS (~40 próbek = 80ms)
            for (int i=1; i<=15; i++) send_sample(16'd200 * i); 
            for (int i=1; i<=20; i++) send_sample(16'd3000 - (16'd190 * i));
            for (int i=1; i<=5; i++)  send_sample(-16'd800 + (16'd160 * i));

            // Przerwa przed punktem J
            repeat (6) send_sample(16'd0);

            // MASYWNA ELEWACJA ST (60 próbek na wysokosci 400)
            repeat (60) send_sample(16'd400);

            // Powrót do izolinii
            repeat (294) send_sample(16'd0);
        end

        // Czekamy chwilę na opróżnienie potoku
        repeat (150) send_sample(16'd0);

        $display("========================================");
        $display("KONIEC SYMULACJI");
        $display("========================================");
        $finish; // Ważne: Zatrzymuje Vivado
    end

    // Task symulujący powolne próbkowanie 500 Hz
    task send_sample(input logic signed [15:0] val);
        begin
            @(posedge clk);
            raw_data_in = val;
            sample_valid_in = 1'b1;
            @(posedge clk);
            sample_valid_in = 1'b0;
            // Odczekujemy cykle zegara, aby zasymulować odstęp między próbkami
            repeat (20) @(posedge clk); 
        end
    endtask

endmodule