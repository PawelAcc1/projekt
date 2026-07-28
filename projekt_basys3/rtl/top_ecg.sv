module top_ecg #(
        // 200_000 @ 100 MHz => 500 Hz (plytka). W symulacji TB nadpisuje mniejsza wartoscia
        // (>= liczba odczepow najdluzszego FIR, ~301).
        parameter int TICK_GEN_DIV = 200_000,
        // Zachowany tylko dla kompatybilnosci ze starszym testbenchem.
        // Tor sprzetowy zawsze idzie przez FIR IP.
        parameter bit FAST_PATHOLOGY_SIM = 0
    )(
        input  logic clk_100MHz,
        input  logic clk_65MHz,
        input  logic rst_n,
        inout  logic ps2_clk,
        inout  logic ps2_data,
        input  logic [1:0] leads_off,
        input logic recording_button,
        output logic recording_status,
        input logic [4:0] mode_control,
        input logic rx,
        output logic tx,
        inout wire i2c_sda,
        output wire i2c_scl,
        output logic vs,
        output logic hs,
        output logic [3:0] r,
        output logic [3:0] g,
        output logic [3:0] b,
        output logic led_stemi
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
    wire [1:0]         effective_leads_off;
    wire [11:0] display_data;
    wire [9:0] read_address;
    wire [11:0] ecg_data_read;
    wire [15:0] ecg_data_received;

    // Record samples connections
    wire [13:0] record_read_address;
    wire [15:0] record_read_data;
    wire record_memory_full;
    wire start_recording;

    //uart connections
    wire rx_done;
    wire [7:0] rx_data;
    wire tx_done;
    wire [7:0] tx_data;
    wire tx_data_ready;
    wire uart_tick;

    //artificial samples connections
    reg [$clog2(TICK_GEN_DIV):0] in_counter;
    reg ena;
    wire [15:0] dout_tach;
    wire [15:0] dout_brady;
    wire [15:0] dout_arr;
    wire [15:0] dout_stemi;
    reg [12:0] addra;
    reg [1:0] dout_valid_delay;
    logic mux_data_valid_out;
    logic [15:0] mux_data_out;

    // Pan-Tompkins pipeline signals
    wire signed [15:0] diff_data_out;       // Differentiator output (16-bit signed)
    wire               data_ready_diff;
    wire        [31:0] sq_data_out;         // Squarer output (32-bit unsigned)
    wire               data_ready_sq;
    wire        [38:0] mwi_data_out;        // Moving window integration output (39-bit)
    wire               data_ready_mwi;
    wire               r_peak_detected_pulse;
    wire               r_peak_for_stemi;

    // AXI tready wejscia FIR (musi byc podlaczone - w sim Z/X = brak probek w torze DSP)
    wire               fir_bp_s_tready;
    wire               fir_notch_s_tready;

    wire [10:0] stemi_min_rr_samples;
    logic [10:0] stemi_rr_counter;
    logic        stemi_have_reference_peak;

    // BPM calculator signals
    wire        [7:0]  current_bpm;         // 8-bitowy wynik tętna
    wire               bpm_updated;         // Flaga nowej wartości BPM
    wire        [7:0]  current_bpm_instant;
    wire               bpm_instant_updated;

    // Delay buffers connections
    wire signed [15:0] deriv_data_buff;
    wire signed [15:0] ecg_data_buff;
    wire deriv_valid_out_buff;
    wire ecg_valid_out_buff;

    //STEMI alarm connection
    wire stemi_alarm_raw;
    wire stemi_alarm;
    wire stemi_mode_selected;
    wire stemi_detection_enabled;
    assign led_stemi = stemi_alarm;

    vga_if if_tim();
    vga_if if_grid();
    vga_if if_render();
    vga_if if_ui();
    vga_if if_mouse();

    assign vs = if_mouse.vsync;
    assign hs = if_mouse.hsync;
    assign {r,g,b} = if_mouse.rgb;
    assign effective_leads_off = mode_control[4] ? 2'b00 : leads_off;
    assign stemi_min_rr_samples = mode_control[4] ? 11'd220 : 11'd150;
    assign stemi_mode_selected = (mode_control == 5'b10001);
    assign stemi_detection_enabled = !mode_control[4] || stemi_mode_selected;
    assign stemi_alarm = stemi_detection_enabled && stemi_alarm_raw;

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
     * ============================================
     * RECORD SAMPLES SECTION START
     * ============================================
    */
   //Record samples
    recording_memory #(
        .DATA_BITS(16),
        .RECORDING_DURATION(20)
    ) u_recording_memory (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .i2c_data_ready(data_ready_notch),
        .i2c_data(filtered_data_1),
        .start_recording(start_recording),
        .read_address(record_read_address),
        .read_data(record_read_data),
        .memory_full(record_memory_full)
    );

    assign recording_status = record_memory_full;

    //Convert samples to ASCII
    hex_to_ascii #(
        .DATA_BITS(16),
        .RECORDING_DURATION(20),
        .UART_DATA_BITS(8)
    ) u_hex_to_ascii (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .rx_done(rx_done),
        .rx_data(rx_data),
        .tx_data(tx_data),
        .tx_data_ready(tx_data_ready),
        .tx_done(tx_done),
        .memory_full(record_memory_full),
        .read_address(record_read_address),
        .read_data(record_read_data)
    );

    //uart tick generator
    tick_generator u_tick_generator (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .tick(uart_tick)
    );

    //button debouncer
    debounce u_debounce (
        .clk(clk_100MHz),
        .reset(!rst_n),
        .db_tick(start_recording),
        .db_level(),
        .sw(recording_button)
    );
    //uart reciever
    uart_rx u_uart_rx (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .received_data(rx_data),
        .rx_done(rx_done),
        .tick_enable(uart_tick),
        .rx(rx)
    );

    //uart transmitter
    uart_tx u_uart_tx (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .tick_enable(uart_tick),
        .data_in(tx_data),
        .tx_start(tx_data_ready),
        .tx_done(tx_done),
        .tx(tx)
    );

    /*
     * ============================================
     * RECORD SAMPLES SECTION END
     * ============================================
    */

    /*
     * ============================================
     * ARTIFICIAL SAMPLES ROM SECTION START
     * ============================================
    */

    //enable_tick generator 500Hz and sample_valid pipeline
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if(!rst_n) begin
            in_counter <= '0;
            ena <= '0;
            dout_valid_delay <= '0;
        end else begin
            dout_valid_delay[0] <= ena;
            dout_valid_delay[1] <= dout_valid_delay[0];
            if(in_counter == TICK_GEN_DIV - 1) begin
                in_counter <= '0;
                ena <= '1;
            end
            else begin
                in_counter <= in_counter + 1;
                ena <= '0;
            end
        end
    end

    //adress counter
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if(!rst_n) begin
            addra <= '0;
        end
        else begin
            if(ena) begin
                if(addra == 13'd7559) begin
                    addra <= '0;
                end
                else begin
                    addra <= addra + 1;
                end
            end
        end
    end

    //TACHYCARDIA
    blk_mem_tachykardia u_blk_mem_tachycardia (
        .clka(clk_100MHz),    // input wire clka
        .ena(ena),      // input wire ena
        .addra(addra),  // input wire [12 : 0] addra
        .douta(dout_tach)  // output wire [15 : 0] douta
    );

    //BRADYCARDIA
    blk_mem_bradycardia u_blk_mem_bradycardia (
        .clka(clk_100MHz), // input wire clka
        .ena(ena), // input wire ena
        .addra(addra), // input wire [12:0] addra
        .douta(dout_brady) // output wire [15:0] douta
    );

    //arrhythmia
    blk_mem_arrhythmia u_blk_mem_arrhythmia (
        .clka(clk_100MHz),    // input wire clka
        .ena(ena),      // input wire ena
        .addra(addra),  // input wire [12 : 0] addra
        .douta(dout_arr)  // output wire [15 : 0] douta
    );


    //stemi
    blk_mem_stemi u_blk_mem_stemi (
    .clka(clk_100MHz),    // input wire clka
    .ena(ena),      // input wire ena
    .addra(addra),  // input wire [12 : 0] addra
    .douta(dout_stemi)  // output wire [15 : 0] douta
    );

    //mode cotrol
    always_comb begin
        casez (mode_control)
            5'b0????: begin //real time imaging
                mux_data_valid_out = data_ready;
                mux_data_out = ecg_data_received;
            end
            5'b11???: begin //tachycardia
                mux_data_valid_out = dout_valid_delay[1];
                mux_data_out = dout_tach;
            end
            5'b101??: begin //bradycardia
                mux_data_valid_out = dout_valid_delay[1];
                mux_data_out = dout_brady;
            end
            5'b1001?: begin //arrhythmia
                mux_data_valid_out = dout_valid_delay[1];
                mux_data_out = dout_arr;
            end
            5'b10001: begin //stemi
                mux_data_valid_out = dout_valid_delay[1];
                mux_data_out = dout_stemi;
            end
            default: begin
                mux_data_valid_out = data_ready;
                mux_data_out = ecg_data_received;
            end
        endcase
    end

    /*
     * ============================================
     * ARTIFICIAL SAMPLES ROM SECTION END
     * ============================================
    */

    /*
     * FIR BANDPASS FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_0 u_fir_compiler_0 (
        .aclk(clk_100MHz),
        .s_axis_data_tvalid(mux_data_valid_out),
        .s_axis_data_tready(fir_bp_s_tready),
        .s_axis_data_tdata(mux_data_out),
        .m_axis_data_tvalid(data_filtered_0),
        .m_axis_data_tdata(filtered_data_0)
    );

    /*
     * FIR NOTCH FILTER INSTANCE FROM IP CATALOG
    */
    fir_compiler_notch u_fir_compiler_notch (
        .aclk(clk_100MHz),
        .s_axis_data_tvalid(mux_data_valid_out),
        .s_axis_data_tready(fir_notch_s_tready),
        .s_axis_data_tdata(mux_data_out),
        .m_axis_data_tvalid(data_ready_notch),
        .m_axis_data_tdata(filtered_data_1)
    );

    /*
     * BASELINE RESTORE: ADJUST BASELINE LEVEL TO COMPENASTE OFFSET WANDERING
    */
    baseline_restore u_baseline_restore (
        .clk(clk_100MHz),
        .rst_n(rst_n),
        .sample_valid_in(data_ready_notch),
        .data_in($signed(filtered_data_1)),
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
        .sample_valid_in  (data_ready_notch),
        .data_in          ($signed(filtered_data_1)),
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
    // BPM liczy odstęp miedzy R-peakami w PRÓBKACH sygnału po filtrach (500 Hz
    // w torze DSP), a NIE impulsami start_sampling. Przy symulacji z mala wartoscia
    // TICK_GEN_DIV (np. 400) start_sampling nadal tyka co 2 ms, a probki BRAM co
    // 4 us -> sample_count liczony po start_sampling nie dochodzil do poprawnego RR.
    bpm_calculator u_bpm_calculator (
        .clk             (clk_100MHz),
        .rst_n           (rst_n),
        .sample_tick     (data_ready_notch),
        .r_peak_detected (r_peak_detected_pulse),
        .min_rr_samples  (mode_control[4] ? 11'd220 : 11'd150),
        .bpm             (current_bpm),
        .bpm_valid       (bpm_updated),
        .bpm_instant     (current_bpm_instant),
        .bpm_instant_valid (bpm_instant_updated)
    );

    /*
     * STEMI uses ST/T morphology, so a second local maximum in the same beat
     * must not restart the ST measurement FSM. BPM has its own RR gate; this
     * one keeps the STEMI detector on one accepted R event per cardiac beat.
    */
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            stemi_rr_counter <= 11'd220;
            stemi_have_reference_peak <= 1'b0;
        end
        else begin
            if (data_ready_mwi && stemi_rr_counter < 11'd2047)
                stemi_rr_counter <= stemi_rr_counter + 1'b1;

            if (r_peak_detected_pulse &&
                (!stemi_have_reference_peak || stemi_rr_counter >= stemi_min_rr_samples)) begin
                stemi_rr_counter <= '0;
                stemi_have_reference_peak <= 1'b1;
            end
        end
    end

    assign r_peak_for_stemi = r_peak_detected_pulse &&
                              (!stemi_have_reference_peak ||
                               stemi_rr_counter >= stemi_min_rr_samples);

    /*
     * DERIVATIVE / ECG DELAY BUFFERS
     * Wyrównują strumień EKG/pochodnej z impulsem r_peak_detected.
    */
    delay_buffer #(
        .DELAY(4)
    ) u_delay_buffer_deriv (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        .data_in          (diff_data_out),
        .sample_valid_in  (data_ready_diff),
        .data_out         (deriv_data_buff),
        .sample_valid_out (deriv_valid_out_buff)
    );

   /*
    * ECG DATA BUFFER
    * Detektor STEMI dostaje sygnal po filtrach; baseline_restore zostaje dla VGA/UART.
   */
   delay_buffer #(
        .DELAY(5)
    ) u_delay_buffer_ecg (
        .clk              (clk_100MHz),
        .rst_n            (rst_n),
        // STEMI analizuje sygnal po filtrach; baseline_restore zostaje dla VGA/UART.
        .data_in          ($signed(filtered_data_1)),
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
        .clear            (!stemi_detection_enabled),
        .ecg_data_in      (ecg_data_buff),
        .derivative_data_in (deriv_data_buff),
        .data_sample_valid_in (ecg_valid_out_buff),
        .derivative_sample_valid_in(deriv_valid_out_buff),
        .r_peak_detected  (r_peak_for_stemi),
        .stemi_alarm      (stemi_alarm_raw)
    );

    vga_ui_manager u_vga_ui (
        .clk_65MHz(clk_65MHz),      
        .clk_100MHz(clk_100MHz),    
        .rst_n(rst_n),
        .current_bpm(current_bpm),
        .bpm_valid(bpm_updated),
        .current_bpm_instant(current_bpm_instant),
        .bpm_instant_valid(bpm_instant_updated),
        .leads_off(effective_leads_off),
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
