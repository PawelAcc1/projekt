module top_ecg (
        input  logic clk_100MHz,
        input  logic clk_65MHz,
        input  logic rst_n,
        inout  logic ps2_clk,
        inout  logic ps2_data,
        input  logic [1:0] leads_off,
        inout wire i2c_sda,
        output wire i2c_scl,
        output logic vs,
        output logic hs,
        output logic [3:0] r,
        output logic [3:0] g,
        output logic [3:0] b
    );

    timeunit 1ns;
    timeprecision 1ps;
    /*
     * INTER-MODULAR CONNECTIONS
    */
    wire start_sampling;
    wire data_ready;
    wire data_write_enable;
    wire data_ready_notch;
    wire data_ready_baseline;
    wire data_filtered_0;
    wire [15:0] filtered_data_0; //after bandpass fir filter
    wire [15:0] filtered_data_1; //after notch fir filter
    wire [15:0] data_baseline;
    wire [11:0] display_data;
    wire [9:0] read_address;
    wire [11:0] ecg_data_read;
    wire [15:0] ecg_data_received;

    // Pan-Tompkins pipeline signals
    wire signed [15:0] diff_data_out;       // Differentiator output (16-bit signed)
    wire               data_ready_diff;
    wire        [31:0] sq_data_out;         // Squarer output (32-bit unsigned)
    wire               data_ready_sq;
    wire        [38:0] mwi_data_out;        // Moving window integration output (39-bit)
    wire               data_ready_mwi;
    wire               r_peak_detected_pulse;

    // BPM calculator signals
    wire        [7:0]  current_bpm;         // 8-bitowy wynik tętna
    wire               bpm_updated;         // Flaga nowej wartości BPM

    // Delay buffers connections
    wire signed [15:0] deriv_data_buff;
    wire signed [15:0] ecg_data_buff;
    wire deriv_valid_out_buff;
    wire ecg_valid_out_buff;

    //STEMI alarm connection
    wire stemi_alarm;

    vga_if if_tim();
    vga_if if_grid();
    vga_if if_render();
    vga_if if_ui();
    vga_if if_mouse();

    assign vs = if_mouse.vsync;
    assign hs = if_mouse.hsync;
    assign {r,g,b} = if_mouse.rgb;

    /*
     * INSTANCES OF MODULES
    */
    vga_timing u_vga_timing (
        .clk     (clk_65MHz),
        .rst_n   (rst_n),
        .vga_out (if_tim)
    );

    draw_grid u_draw_grid (
        .clk      (clk_65MHz),
        .rst_n    (rst_n),
        .vga_in   (if_tim),
        .vga_out  (if_grid)
    );

    sampling_timer u_sampling_timer (
        .clk            (clk_100MHz),
        .rst_n          (rst_n),
        .start_sampling (start_sampling)
    );

    i2c_master u_i2c_master (
        .clk     (clk_100MHz),
        .rst_n   (rst_n),
        .start_sampling (start_sampling),
        .SDA     (i2c_sda),
        .SCL     (i2c_scl),
        .adc_data(ecg_data_received),
        .data_ready(data_ready)
    );

    /*
     * FIR BANDPASS FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_0 u_fir_compiler_0 (
        .aclk(clk_100MHz),                              // input wire clk
        .s_axis_data_tvalid(data_ready),  // input wire s_axis_data_tvalid
        .s_axis_data_tready(),  // output wire s_axis_data_tready
        .s_axis_data_tdata(ecg_data_received),    // input wire [15 : 0] s_axis_data_tdata
        .m_axis_data_tvalid(data_filtered_0),  // output wire m_axis_data_tvalid
        .m_axis_data_tdata(filtered_data_0)    // output wire [15 : 0] m_axis_data_tdata
    );

    /*
     * FIR NOTCH FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_notch u_fir_compiler_notch (
        .aclk(clk_100MHz),                              // input wire aclk
        .s_axis_data_tvalid(data_filtered_0),  // input wire s_axis_data_tvalid
        .s_axis_data_tready(),  // output wire s_axis_data_tready
        .s_axis_data_tdata(filtered_data_0),    // input wire [15 : 0] s_axis_data_tdata
        .m_axis_data_tvalid(data_ready_notch),  // output wire m_axis_data_tvalid
        .m_axis_data_tdata(filtered_data_1)    // output wire [15 : 0] m_axis_data_tdata
    );

    /*
     * BASELINE RESTORE: ADJUST BASELINE LEVEL TO COMPENASTE OFFSET WANDERING
    */
    baseline_restore u_baseline_restore (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .sample_valid_in(data_ready_notch),
        .data_in(filtered_data_1),
        .data_out(data_baseline),
        .sample_valid_out(data_ready_baseline)
    );

    /*
     * VGA FORMAT: PREPARE SIGNAL FOR DISPLAY ON VGA
    */
    vga_formatter u_vga_formatter (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .sample_valid_in(data_ready_baseline),
        .data_in(data_baseline),
        .data_out(display_data),
        .data_ready(data_write_enable)
    );

    ring_buffer u_ring_buffer (
        .clk_read(clk_65MHz),
        .clk_write(clk_100MHz),
        .rst_n(rst_n),
        .write_enable(data_write_enable),
        .ecg_data_write(display_data),
        .read_address(read_address),
        .ecg_data_read(ecg_data_read)
    );

    render_signal u_render_signal (
        .clk(clk_65MHz),
        .rst_n(rst_n),
        .ecg_data_read(ecg_data_read),
        .vga_in(if_grid),
        .vga_out(if_render),
        .read_address(read_address)
    );

    // ... poprzedni kod render_signal ...

    // Odbiór danych z kontrolera myszy PS/2
    wire [11:0] mouse_x_pos;
    wire [11:0] mouse_y_pos;
    wire mouse_left_click;

    MouseCtl u_mouse_ctl (
        .clk(clk_100MHz),       // Zegar 100MHz dla PS/2
        .rst(~rst_n),           // Uwaga: MouseCtl wymaga resetu w stanie wysokim
        .xpos(mouse_x_pos),
        .ypos(mouse_y_pos),
        .zpos(),
        .left(mouse_left_click),
        .middle(),
        .right(),
        .new_event(),
        .value(12'b0),
        .setx(1'b0),
        .sety(1'b0),
        .setmax_x(1'b0),
        .setmax_y(1'b0),
        .ps2_clk(ps2_clk),      // Dodaj ps2_clk do portów we/wy na górze top_ecg!
        .ps2_data(ps2_data)     // Dodaj ps2_data do portów we/wy na górze top_ecg!
    );

/*
     * PAN-TOMPKINS STEP 2: DIFFERENTIATOR
     * Takes input directly from FIR Bandpass
    */
    differentiator u_differentiator (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .sample_valid_in  (data_ready_notch), // Impuls z filtru Bandpass
        .data_in          (filtered_data_1), // Dane z filtru Bandpass
        .data_out         (diff_data_out),   // Wynik pochodnej
        .sample_valid_out (data_ready_diff)  // Impuls gotowości dla kolejnego bloku
    );

/*
     * PAN-TOMPKINS STEP 3: SQUARING
     * Takes input from Differentiator. Output is 32-bit unsigned.
    */
    squarer u_squarer (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .sample_valid_in  (data_ready_diff), // Impuls z derywatora
        .data_in          (diff_data_out),   // Dane z derywatora (16-bit)
        .data_out         (sq_data_out),     // Wynik kwadratowania (32-bit)
        .sample_valid_out (data_ready_sq)    // Impuls dla całkatora
    );

    /*
     * PAN-TOMPKINS STEP 4: MOVING WINDOW INTEGRATION
     * Merges individual sharp spikes into smooth blocks representing QRS complex duration.
    */
    moving_window_integration #(
        .WIDTH_IN(32),
        .WINDOW_SIZE(75)
    ) u_moving_window_integration (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .sample_valid_in  (data_ready_sq),   // Impuls z kwadratowania
        .data_in          (sq_data_out),     // Dane z kwadratowania (32-bit)
        .data_out         (mwi_data_out),    // Wynik całkowania (39-bit)
        .sample_valid_out (data_ready_mwi)   // Impuls gotowości dla bloku detekcji progu
    );

    /*
     * PAN-TOMPKINS STEP 5: ADAPTIVE THRESHOLD
     * Determines the exact moment of the R-peak using dynamic thresholds.
    */
    adaptive_threshold #(
        .WIDTH_IN(39),
        .BLANKING_PERIOD(100)
    ) u_adaptive_threshold (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .sample_valid_in  (data_ready_mwi),     // Impuls z całkowania
        .data_in          (mwi_data_out),       // Sygnał 39-bitowy z całkowania
        .r_peak_detected  (r_peak_detected_pulse) // IMPULS WYJŚCIOWY - ZNALEZIONO R!
    );

    /*
     * BPM CALCULATOR
     * Calculates Heart Rate based on the time distance between R-peaks.
    */
    bpm_calculator u_bpm_calculator (
        .clk             (clk_100MHz),
        .rst_n           (rst_n),
        .sample_tick     (start_sampling),        // Impuls 500 Hz z timera
        .r_peak_detected (r_peak_detected_pulse), // Wynik algorytmu Pan-Tompkinsa
        .bpm             (current_bpm),           // 8-bitowy wynik (do wyświetlenia)
        .bpm_valid       (bpm_updated)            // Flaga nowej wartości
    );

    /*
     * DERIVATIVE DELAY BUFFER
     * Synchronize signals with PAN_TOMPKINS algorithm to STEMI detector.
     * Pipeline latency = 4 cycles
     * Algorithm delay = 40 cycles
     * Combined delay = 44 cycles
    */
    delay_buffer #(
        .DELAY(44)
    ) u_delay_buffer_deriv (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .data_in          (diff_data_out),
        .sample_valid_in  (data_ready_diff),
        .data_out         (deriv_data_buff),
        .sample_valid_out (deriv_valid_out_buff)
    );

    /*
     * ECG DATA DELAY BUFFER
     * Synchronize signals with PAN_TOMPKINS algorithm to STEMI detector.
     * Pipeline latency = 5 cycles (include differentiator!)
     * Algorithm delay = 40 cycles
     * Combined delay = 45 cycles
    */
   delay_buffer #(
        .DELAY(45)
    ) u_delay_buffer_ecg (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .data_in          (filtered_data_1),
        .sample_valid_in  (data_ready_notch),
        .data_out         (ecg_data_buff),
        .sample_valid_out (ecg_valid_out_buff)
    );

    /*
     * STEMI DETECTOR
     * Detect ST-Elevation Myocardial Infarction
    */
    stemi_detector u_stemi_detector (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .ecg_data_in      (ecg_data_buff),
        .derivative_data_in (deriv_data_buff),
        .data_sample_valid_in (ecg_valid_out_buff),
        .derivative_sample_valid_in(deriv_valid_out_buff),
        .r_peak_detected  (r_peak_detected_pulse),
        .stemi_alarm      (stemi_alarm)
    );

    vga_ui_manager u_vga_ui (
        .clk_65MHz(clk_65MHz),      
        .clk_100MHz(clk_100MHz),    
        .rst_n(rst_n),
        .current_bpm(current_bpm),
        .bpm_valid(bpm_updated),
        .leads_off(leads_off),    
        .mouse_x(mouse_x_pos),
        .mouse_y(mouse_y_pos),
        .mouse_left(mouse_left_click),
        .stemi_alarm(stemi_alarm),
        .vga_in(if_render),          
        .vga_out(if_ui)              
    );

    // --- NAKŁADANIE KURSORA MYSZKI (Najwyższa warstwa) ---
    draw_mouse u_mouse_cursor (
        .clk(clk_65MHz),
        .rst_n(rst_n),
        .x_start(mouse_x_pos),
        .y_start(mouse_y_pos),
        .vga_in(if_ui),       // Pobiera gotowy obraz z okienkami
        .vga_out(if_mouse)    // Wyrzuca ostateczny obraz z nałożonym kursorem na monitor
    );

endmodule
