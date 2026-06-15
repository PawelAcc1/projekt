`timescale 1ns / 1ps

module alarm_logger (
    input  logic clk_100MHz,
    input  logic clk_65MHz,     // Zegar pikselowy do renderowania czcionki!
    input  logic rst_n,

    input  logic [4:0] rtc_hours,
    input  logic [5:0] rtc_minutes,
    input  logic [5:0] rtc_seconds, // Sekundy
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,

    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic show_history,  // Ekran Historia
    input  logic show_monitor,  // Ekran Monitor

    input logic stemi_alarm,

    output logic pixel_on
);

    // --- DETEKCJA MEDYCZNA ---
    logic [7:0] prev_bpm;
    logic [7:0] bpm_diff;
    
    // Obliczanie różnicy do wykrycia Arytmii (skok o 15 BPM między uderzeniami)
    assign bpm_diff = (current_bpm > prev_bpm) ? (current_bpm - prev_bpm) : (prev_bpm - current_bpm);

    logic is_brady, is_tachy, is_arrhythmia;
    assign is_brady      = (current_bpm > 0 && current_bpm < 8'd50);
    assign is_tachy      = (current_bpm > 8'd100);
    assign is_arrhythmia = (bpm_diff > 8'd15 && prev_bpm != 0);
    assign is_stemi      = (stemi_alarm);


    logic [2:0] current_alarm; // 0=OK, 1=BRADY, 2=TACHY, 3=ARYTMIA, 4=STEMI
    assign current_alarm = is_stemi      ? 3'd4 : 
                           is_arrhythmia ? 3'd3 : 
                           is_tachy      ? 3'd2 : 
                           is_brady      ? 3'd1 : 3'd0;

    // --- REJESTRY ŚLEDZĄCE ---
    logic [2:0] prev_alarm;
    
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            prev_bpm <= 8'd0;
            prev_alarm <= 3'd0;
        end else begin
            if (bpm_valid) begin
                prev_bpm <= current_bpm;
            end
            
            prev_alarm <= current_alarm; 
        end
    end

    // --- GENERATOR IMPULSU ZAPISU (Edge Detection) ---
    logic trigger_log;
    
    assign trigger_log = (current_alarm != prev_alarm) && (current_alarm != 3'd0);

    // --- PRZYGOTOWANIE TEKSTU DLA CZCIONKI (Kodowanie ASCII) ---
    logic [7:0] t_h1, t_h2, t_m1, t_m2, t_s1, t_s2, b1, b2, b3;
    logic [87:0] str_type; // ZMIANA: 11 liter * 8 bitów = 88 bitów

    assign t_h1 = (rtc_hours / 10) + 8'h30;   assign t_h2 = (rtc_hours % 10) + 8'h30;
    assign t_m1 = (rtc_minutes / 10) + 8'h30; assign t_m2 = (rtc_minutes % 10) + 8'h30;
    assign t_s1 = (rtc_seconds / 10) + 8'h30; assign t_s2 = (rtc_seconds % 10) + 8'h30;

    assign b1 = (current_bpm / 100) + 8'h30;
    assign b2 = ((current_bpm % 100) / 10) + 8'h30;
    assign b3 = (current_bpm % 10) + 8'h30;

    always_comb begin
        // "ARYTMIA    " (uzupełnione 4 spacjami na końcu, by miało 11 znaków)
        if      (is_arrhythmia) str_type = 88'h415259544D494120202020;
        // "TACHYKARDIA" (11 znaków)
        else if (is_tachy)      str_type = 88'h54414348594B4152444941;
        // "BRADYKARDIA" (11 znaków)
        else if (is_brady)      str_type = 88'h42524144594B4152444941;
        // "STEMI" (5 znaków uzupelnione spacjami)
        else if (is_stemi)      str_type = 88'h5354454D49202020202020;
        // Puste 11 spacji
        else                    str_type = 88'h2020202020202020202020;
    end

    // --- PAMIĘĆ LOGÓW (Shift Register bezpośrednio na Stringach) ---
    // ZMIANA: Czas (8) + Spacje(2) + BPM(3) + Spacja(1) + Stan(11) = 25 znaków (200 bitów)
    logic [199:0] log_strings_mem [0:7]; 
    logic [3:0] num_logs;

    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            num_logs <= 4'd0;
            for (int i=0; i<8; i++) log_strings_mem[i] <= 200'd0;
        end else if (trigger_log) begin
            // Przesunięcie starych alarmów w dół
            for (int i=7; i>0; i--) begin
                log_strings_mem[i] <= log_strings_mem[i-1];
            end
            // Zapisanie najnowszego alarmu na samą górę
            // Format wpisu: "HH:MM:SS  120 TACHYKARDIA"
            log_strings_mem[0] <= {t_h1, t_h2, 8'h3A, t_m1, t_m2, 8'h3A, t_s1, t_s2, 
                                   8'h20, 8'h20, b1, b2, b3, 8'h20, str_type};
            
            if (num_logs < 4'd8) num_logs <= num_logs + 1'b1;
        end
    end

    // --- SPRZĘTOWE RENDEROWANIE DO EKRANU (8 INSTANCJI CZCIONEK) ---
    logic [7:0] row_pixels;
    
    genvar k;
    generate
        for (k = 0; k < 8; k++) begin : log_renderers
            logic [11:0] rx, ry;
            logic ren;
            
            // Pozycjonowanie w zależności od ekranu
            assign rx = 12'd60; // 60 pikseli od lewej
            assign ry = show_history ? (12'd120 + k * 12'd60) :               // Pełna lista na ekranie HISTORIA
                        (show_monitor && k < 2) ? (12'd590 + k * 12'd50) :    // Tylko 2 ostatnie na ekranie MONITOR
                        12'd0;
            
            // Włącz rysowanie, jeśli wpis istnieje i pasuje do aktualnego ekranu
            assign ren = (k < num_logs) && (show_history || (show_monitor && k < 2));

            // Używamy bufora wielkości 25 znaków
            vga_text_renderer #(.MAX_CHARS(25), .CHAR_SCALE(2)) txt_log (
                .clk(clk_65MHz),
                .hcount(hcount), .vcount(vcount),
                .pos_x(rx), .pos_y(ry),
                .char_string(log_strings_mem[k]),
                .string_len(ren ? 5'd25 : 5'd0), 
                .pixel_on(row_pixels[k])
            );
        end
    endgenerate

    // Scalanie pikseli ze wszystkich 8 wierszy
    assign pixel_on = |row_pixels;

endmodule