`timescale 1ns / 1ps

module alarm_logger (
    input  logic clk_100MHz,
    input  logic clk_65MHz,
    input  logic rst_n,

    input  logic [4:0] rtc_hours,
    input  logic [5:0] rtc_minutes,
    input  logic [5:0] rtc_seconds,
    input  logic [7:0] current_bpm,
    input  logic [7:0] current_bpm_instant,
    input  logic bpm_instant_valid,
    input  logic suppress_rhythm_alarms,
    input  logic [1:0] leads_off,

    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic show_history, 
    input  logic show_monitor,
    
    input logic stemi_alarm,
    
    output logic pixel_on
);

    // --- 1. SYNCHRONIZATOR SYGNAŁÓW ZEWNĘTRZNYCH ---
    logic [1:0] leads_sync_1, leads_sync_2;
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            leads_sync_1 <= 2'b00;
            leads_sync_2 <= 2'b00;
        end else begin
            leads_sync_1 <= leads_off;
            leads_sync_2 <= leads_sync_1;
        end
    end

    // --- 2. LEADS-OFF ---
    logic leads_connected;
    assign leads_connected = (leads_sync_2 == 2'b00);

    // --- 3. DETEKCJA MEDYCZNA (KOMBINACYJNA) ---
    logic [7:0] prev_bpm_instant;
    logic [7:0] bpm_instant_diff;
    
    assign bpm_instant_diff = (current_bpm_instant > prev_bpm_instant)
                            ? (current_bpm_instant - prev_bpm_instant)
                            : (prev_bpm_instant - current_bpm_instant);

    logic is_brady_c, is_tachy_c, is_arrhythmia_c, is_stemi_c;
    assign is_brady_c      = (leads_connected && !suppress_rhythm_alarms && current_bpm > 0 && current_bpm < 8'd50);
    assign is_tachy_c      = (leads_connected && !suppress_rhythm_alarms && current_bpm > 8'd100);
    assign is_arrhythmia_c = (leads_connected && !suppress_rhythm_alarms && bpm_instant_valid && current_bpm_instant != 0 && prev_bpm_instant != 0 && bpm_instant_diff > 8'd15);
    assign is_stemi_c      = (leads_connected && stemi_alarm);

    logic [2:0] alarm_code_comb; // 0=OK, 1=BRADY, 2=TACHY, 3=ARYTMIA, 4=STEMI
    assign alarm_code_comb = is_stemi_c      ? 3'd4 : 
                             is_arrhythmia_c ? 3'd3 :
                             is_tachy_c      ? 3'd2 : 
                             is_brady_c      ? 3'd1 : 3'd0;

    // --- REJESTRY ŚLEDZĄCE (PIPELINE ZMNIEJSZAJĄCY TIMING) ---
    logic [2:0] current_alarm;
    logic [2:0] prev_alarm;
    
    // Zatrzaskujemy flagi alarmów do pamięci, aby układ zdążył wygenerować stringa
    logic is_brady_reg, is_tachy_reg, is_arrhythmia_reg, is_stemi_reg;
    
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            prev_bpm_instant <= 8'd0;
            current_alarm <= 3'd0;
            prev_alarm <= 3'd0;
            is_brady_reg <= 1'b0;
            is_tachy_reg <= 1'b0;
            is_arrhythmia_reg <= 1'b0;
            is_stemi_reg <= 1'b0;
        end else begin
            if (bpm_instant_valid && current_bpm_instant != 0) begin
                prev_bpm_instant <= current_bpm_instant;
            end
            
            // PIPELINE: Ucinamy ścieżkę z 10 poziomów na zaledwie 4.
            // Najpierw bezpiecznie zatrzaskujemy wyliczony przed chwilą kod.
            current_alarm <= alarm_code_comb;
            prev_alarm <= current_alarm;
            
            is_brady_reg <= is_brady_c;
            is_tachy_reg <= is_tachy_c;
            is_arrhythmia_reg <= is_arrhythmia_c;
            is_stemi_reg <= is_stemi_c;
        end
    end

    // --- GENERATOR IMPULSU ZAPISU ---
    logic trigger_log;
    assign trigger_log = (current_alarm != prev_alarm) && (current_alarm != 3'd0);

    // --- 4. PRZYGOTOWANIE TEKSTU DLA CZCIONKI ---
    logic [7:0] t_h1, t_h2, t_m1, t_m2, t_s1, t_s2, b1, b2, b3;
    logic [87:0] str_type;

    assign t_h1 = (rtc_hours / 10) + 8'h30;   assign t_h2 = (rtc_hours % 10) + 8'h30;
    assign t_m1 = (rtc_minutes / 10) + 8'h30; assign t_m2 = (rtc_minutes % 10) + 8'h30;
    assign t_s1 = (rtc_seconds / 10) + 8'h30; assign t_s2 = (rtc_seconds % 10) + 8'h30;

    assign b1 = (current_bpm / 100) + 8'h30;
    assign b2 = ((current_bpm % 100) / 10) + 8'h30;
    assign b3 = (current_bpm % 10) + 8'h30;

    always_comb begin
        // Używamy zrejestrowanych flag, by napis czekał na trigger zapisu do pamięci
        if      (is_stemi_reg)      str_type = 88'h5354454D49202020202020;
        else if (is_arrhythmia_reg) str_type = 88'h415259544D494120202020;
        else if (is_tachy_reg)      str_type = 88'h54414348594B4152444941;
        else if (is_brady_reg)      str_type = 88'h42524144594B4152444941;
        else                        str_type = 88'h2020202020202020202020;
    end

    // --- 5. PAMIĘĆ LOGÓW ---
    logic [199:0] log_strings_mem [0:7]; 
    logic [3:0] num_logs;

    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            num_logs <= 4'd0;
            for (int i=0; i<8; i++) log_strings_mem[i] <= 200'd0;
        end else if (trigger_log) begin
            for (int i=7; i>0; i--) begin
                log_strings_mem[i] <= log_strings_mem[i-1];
            end
            log_strings_mem[0] <= {t_h1, t_h2, 8'h3A, t_m1, t_m2, 8'h3A, t_s1, t_s2, 
                                   8'h20, 8'h20, b1, b2, b3, 8'h20, str_type};
            
            if (num_logs < 4'd8) num_logs <= num_logs + 1'b1;
        end
    end

    // =========================================================================
    // 5.5 SYNCHRONIZATOR DOMENY WIDEO (CDC: 100 MHz -> 65 MHz)
    // Zabezpieczamy pamięć logów przed uderzeniem w niestabilną sieć VGA
    // =========================================================================
    logic [199:0] log_strings_vga_sync [0:7]; 
    logic [3:0]   num_logs_vga_sync;
    
    always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            num_logs_vga_sync <= 4'd0;
            for (int i=0; i<8; i++) log_strings_vga_sync[i] <= 200'd0;
        end else begin
            // UWAGA: To jest transfer wielobitowy (Bus CDC). 
            // Ponieważ logi dla oka zmieniają się ekstremalnie rzadko, 
            // można bezpiecznie użyć pojedynczego rejestru w nowym zegarze.
            num_logs_vga_sync <= num_logs;
            for (int i=0; i<8; i++) log_strings_vga_sync[i] <= log_strings_mem[i];
        end
    end

    // --- 6. SPRZĘTOWE RENDEROWANIE DO EKRANU ---
    logic [7:0] row_pixels;
    
    genvar k;
    generate
        for (k = 0; k < 8; k++) begin : log_renderers
            logic [11:0] rx, ry;
            logic ren;
            
            assign rx = 12'd60;
            assign ry = show_history ? (12'd120 + k * 12'd60) :               
                        (show_monitor && k < 2) ? (12'd590 + k * 12'd50) :    
                        12'd0;
            
            // Zmiana na zsynchronizowaną zmienną!
            assign ren = (k < num_logs_vga_sync) && (show_history || (show_monitor && k < 2));

            vga_text_renderer #(.MAX_CHARS(25), .CHAR_SCALE(2)) txt_log (
                .clk(clk_65MHz),
                .hcount(hcount), .vcount(vcount),
                .pos_x(rx), .pos_y(ry),
                // Zmiana na zsynchronizowaną zmienną!
                .char_string(log_strings_vga_sync[k]),
                .string_len(ren ? 5'd25 : 5'd0), 
                .pixel_on(row_pixels[k])
            );
        end
    endgenerate

    assign pixel_on = |row_pixels;

endmodule