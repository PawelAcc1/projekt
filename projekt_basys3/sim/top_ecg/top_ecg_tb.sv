`timescale 1ns / 1ps

// =============================================================================
// Testbench: STEMI (stemi.coe, mode_control = 5'b10001)
//
// FAST_PATHOLOGY_SIM=1 omija FIR IP (zaprojektowany na fs=500 Hz). Przy
// TICK_GEN_DIV=400 filtry FIR widza ~250 kHz i wycinaja caly sygnal EKG.
//
// Czas symulacji (probki BRAM @ TICK_DIV):
//   WARMUP (700) + POST_WARMUP (200) + uderzenia + margines
// =============================================================================
module top_ecg_tb;

    localparam int TICK_DIV           = 400;
    localparam int WARMUP_SAMPLES     = 700;
    localparam int POST_WARMUP_LEARN  = 200;
    localparam int BEAT_SPACING       = 500;
    localparam int STEMI_FIRST_BEAT   = 5;
    localparam int STEMI_LAST_BEAT    = 10;
    localparam int SIM_SAMPLES        = 7200;
    localparam int SIM_TIME_NS        = SIM_SAMPLES * TICK_DIV * 10;
    localparam logic [4:0] MODE_STEMI = 5'b10001;

    localparam int MIN_R_PEAKS        = 4;
    localparam int MIN_BPM_UPDATES    = 1;

    logic        clk_100MHz, clk_65MHz, rst_n;
    wire         ps2_clk, ps2_data;
    logic [1:0]  leads_off;
    logic        recording_button;
    wire         recording_status;
    logic [4:0]  mode_control;
    logic        rx;
    wire         tx, i2c_sda, i2c_scl, vs, hs;
    wire  [3:0]  r, g, b;
    wire         led_stemi;

    int n_r_peaks, n_bpm_updates, n_dsp_valid, n_mwi_valid;
    int max_bpm;
    longint max_mwi, max_threshold;
    bit saw_stemi_alarm, saw_stemi_logger_alarm;

    pullup(i2c_sda);
    pullup(i2c_scl);
    pullup(ps2_clk);
    pullup(ps2_data);

    initial begin
        clk_100MHz = 0;
        forever #(10.0/2) clk_100MHz = ~clk_100MHz;
    end

    initial begin
        clk_65MHz = 0;
        forever #(15.385/2) clk_65MHz = ~clk_65MHz;
    end

    top_ecg #(
        .TICK_GEN_DIV(TICK_DIV),
        .FAST_PATHOLOGY_SIM(1'b1)
    ) u_top_ecg (
        .clk_100MHz       (clk_100MHz),
        .clk_65MHz        (clk_65MHz),
        .rst_n            (rst_n),
        .ps2_clk          (ps2_clk),
        .ps2_data         (ps2_data),
        .leads_off        (leads_off),
        .recording_button (recording_button),
        .recording_status (recording_status),
        .mode_control     (mode_control),
        .rx               (rx),
        .tx               (tx),
        .i2c_sda          (i2c_sda),
        .i2c_scl          (i2c_scl),
        .vs               (vs),
        .hs               (hs),
        .r                (r),
        .g                (g),
        .b                (b),
        .led_stemi        (led_stemi)
    );

    // Aliasy do wygodnego dodania na waveform bez szukania w glebi hierarchii.
    wire signed [15:0] tb_filtered_data      = $signed(u_top_ecg.dsp_filter_data);
    wire signed [15:0] tb_data_baseline      = $signed(u_top_ecg.data_baseline);
    wire signed [15:0] tb_stemi_ecg_data_in  = u_top_ecg.u_stemi_detector.ecg_data_in;
    wire signed [15:0] tb_stemi_derivative   = u_top_ecg.u_stemi_detector.derivative_data_in;
    wire        [2:0]  tb_stemi_state        = u_top_ecg.u_stemi_detector.state;
    wire signed [15:0] tb_baseline_locked    = u_top_ecg.u_stemi_detector.baseline_locked;
    wire signed [18:0] tb_st_accumulator     = u_top_ecg.u_stemi_detector.st_accumulator;
    wire        [4:0]  tb_flat_counter       = u_top_ecg.u_stemi_detector.flat_counter;
    wire               tb_r_peak_detected    = u_top_ecg.r_peak_detected_pulse;
    wire               tb_dsp_filter_valid   = u_top_ecg.dsp_filter_valid;
    wire               tb_ecg_valid          = u_top_ecg.ecg_valid_out_buff;
    wire        [12:0] tb_addra              = u_top_ecg.addra;
    wire        [15:0] tb_dout_stemi         = u_top_ecg.dout_stemi;
    wire        [7:0]  tb_current_bpm        = u_top_ecg.current_bpm;
    wire        [2:0]  tb_current_alarm      = u_top_ecg.u_vga_ui.u_logger.current_alarm;

    initial begin : init_bpm_rom_for_xsim
        for (int rr = 0; rr < 2048; rr++) begin
            if (rr == 0)
                u_top_ecg.u_bpm_calculator.bpm_rom[rr] = 8'd0;
            else if ((30000 / rr) > 255)
                u_top_ecg.u_bpm_calculator.bpm_rom[rr] = 8'd255;
            else
                u_top_ecg.u_bpm_calculator.bpm_rom[rr] = 8'(30000 / rr);
        end
    end

    initial begin
        n_r_peaks = 0; n_bpm_updates = 0; n_dsp_valid = 0; n_mwi_valid = 0;
        max_bpm = 0; max_mwi = 0; max_threshold = 0;
        saw_stemi_alarm = 0; saw_stemi_logger_alarm = 0;

        $display("============================================================");
        $display("  SYMULACJA STEMI (FAST_PATHOLOGY_SIM=1)");
        $display("  mode_control=%b (%0d)  TICK_GEN_DIV=%0d", MODE_STEMI, MODE_STEMI, TICK_DIV);
        $display("  STEMI w probkach BRAM: beat #%0d..#%0d, spacing=%0d",
                 STEMI_FIRST_BEAT, STEMI_LAST_BEAT, BEAT_SPACING);
        $display("  razem %0d probek BRAM, czas ~%0d ms", SIM_SAMPLES, SIM_TIME_NS/1_000_000);
        $display("============================================================");

        rst_n = 0; recording_button = 0; leads_off = 2'b00;
        rx = 1'b1; mode_control = MODE_STEMI;
        #100;
        rst_n = 1;
        $display("[%0t] Reset zwolniony", $time);

        #SIM_TIME_NS;

        $display("============================================================");
        $display("  PODSUMOWANIE");
        $display("  probki toru DSP (dsp_filter_valid)   : %0d", n_dsp_valid);
        $display("  probki MWI (data_ready_mwi)          : %0d", n_mwi_valid);
        $display("  warmup_done                          : %0b",
                 u_top_ecg.u_adaptive_threshold.warmup_done);
        $display("  detect_enable                        : %0b",
                 u_top_ecg.u_adaptive_threshold.detect_enable);
        $display("  max MWI                              : %0d", max_mwi);
        $display("  max threshold                        : %0d", max_threshold);
        $display("  R-peaki                              : %0d  (min %0d)", n_r_peaks, MIN_R_PEAKS);
        $display("  aktualizacje BPM                     : %0d", n_bpm_updates);
        $display("  max BPM                              : %0d", max_bpm);
        $display("  alarm STEMI (led_stemi)              : %s", saw_stemi_alarm ? "TAK" : "NIE");
        $display("  alarm STEMI w alarm_logger           : %s", saw_stemi_logger_alarm ? "TAK" : "NIE");
        $display("============================================================");

        if (n_dsp_valid == 0)
            $error("TEST FAIL: brak probek na torze DSP");
        else if (n_mwi_valid < WARMUP_SAMPLES + POST_WARMUP_LEARN)
            $error("TEST FAIL: MWI za malo probek - wydluz symulacje");
        else if (max_mwi == 0)
            $error("TEST FAIL: MWI=0 caly czas (sprawdz tor sygnalu)");
        else if (n_r_peaks < MIN_R_PEAKS)
            $error("TEST FAIL: za malo R-peaks (%0d)", n_r_peaks);
        else if (n_bpm_updates < MIN_BPM_UPDATES)
            $error("TEST FAIL: BPM nie zaktualizowal sie");
        else if (!saw_stemi_alarm)
            $error("TEST FAIL: STEMI nie zostal wykryty na led_stemi");
        else if (!saw_stemi_logger_alarm)
            $error("TEST FAIL: alarm_logger nie pokazal alarmu STEMI");
        else
            $display("*** TEST PASS ***");

        $finish;
    end

    always @(posedge clk_100MHz) begin
        if (rst_n) begin
            if (u_top_ecg.dsp_filter_valid)
                n_dsp_valid++;
            if (u_top_ecg.data_ready_mwi) begin
                n_mwi_valid++;
                if ($unsigned(u_top_ecg.mwi_data_out) > max_mwi)
                    max_mwi = $unsigned(u_top_ecg.mwi_data_out);
            end
            if ($unsigned(u_top_ecg.u_adaptive_threshold.threshold) > max_threshold)
                max_threshold = $unsigned(u_top_ecg.u_adaptive_threshold.threshold);
        end
    end

    always @(posedge clk_100MHz) begin
        if (rst_n && u_top_ecg.r_peak_detected_pulse) begin
            n_r_peaks++;
            $display("[%0t] R-PEAK #%0d  addra=%0d", $time, n_r_peaks, u_top_ecg.addra);
        end
    end

    always @(posedge clk_100MHz) begin
        if (rst_n && u_top_ecg.bpm_updated) begin
            automatic int bpm  = u_top_ecg.current_bpm;
            automatic int alrm = u_top_ecg.u_vga_ui.u_logger.current_alarm;
            n_bpm_updates++;
            if (bpm > max_bpm) max_bpm = bpm;
            if (bpm > 0)
                $display("[%0t] BPM=%0d  alarm=%0d", $time, bpm, alrm);
        end
    end

    always @(posedge clk_100MHz) begin
        if (rst_n && led_stemi && !saw_stemi_alarm) begin
            saw_stemi_alarm = 1;
            $display("[%0t] STEMI ALARM: led_stemi=1  addra=%0d", $time, u_top_ecg.addra);
        end

        if (rst_n && u_top_ecg.u_vga_ui.u_logger.current_alarm == 3'd4)
            saw_stemi_logger_alarm = 1;
    end

endmodule
