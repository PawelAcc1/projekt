`timescale 1ns / 1ps

module alarm_logger (
    input  logic clk_100MHz,
    input  logic clk_65MHz,
    input  logic rst_n,

    input  logic [4:0] rtc_hours,
    input  logic [5:0] rtc_minutes,
    input  logic [5:0] rtc_seconds,
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,
    input  logic [1:0] leads_off, // Wejście z fizycznych pinów JC

    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic show_history, 
    input  logic show_monitor, 
    output logic pixel_on
);

    // --- 1. SYNCHRONIZATOR SYGNAŁÓW ZEWNĘTRZNYCH ---
    // Zapobiega metastabilności układu od szumów na kablach
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

    // --- 2. LEADS-OFF & BLANKING TIMER (8 Sekund) ---
    logic [29:0] stable_timer;
    logic is_stable; 

    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            stable_timer <= '0;
            is_stable <= 1'b0;
        end else begin
            // Używamy zsynchronizowanego sygnału!
            if (leads_sync_2 != 2'b00) begin
                stable_timer <= '0;
                is_stable <= 1'b0;
            end else if (stable_timer < 30'd800_000_000) begin 
                stable_timer <= stable_timer + 1'b1;
                is_stable <= 1'b0;
            end else begin
                is_stable <= 1'b1;
            end
        end
    end

    // --- 3. DETEKCJA MEDYCZNA ---
    logic [7:0] prev_bpm;
    logic [7:0] bpm_diff;
    
    assign bpm_diff = (current_bpm > prev_bpm) ? (current_bpm - prev_bpm) : (prev_bpm - current_bpm);

    logic is_brady, is_tachy, is_arrhythmia;
    assign is_brady      = (current_bpm > 0 && current_bpm < 8'd50);
    assign is_tachy      = (current_bpm > 8'd100);
    assign is_arrhythmia = (bpm_diff > 8'd15 && prev_bpm != 0);

    logic [1:0] current_alarm;
    assign current_alarm = is_arrhythmia ? 2'd3 : 
                           is_tachy      ? 2'd2 : 
                           is_brady      ? 2'd1 : 2'd0;

    logic [1:0] prev_alarm;
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            prev_bpm <= 8'd0;
            prev_alarm <= 2'd0;
        end else if (!is_stable) begin
            // KRYTYCZNA POPRAWKA: Pamięć jest czyszczona podczas stabilizacji!
            prev_bpm <= 8'd0;
            prev_alarm <= 2'd0;
        end else if (bpm_valid) begin
            prev_bpm <= current_bpm;
            prev_alarm <= current_alarm;
        end
    end

    // Zapisujemy log tylko gdy układ jest stabilny
    logic trigger_log;
    assign trigger_log = bpm_valid && (current_alarm != 2'd0) && (current_alarm != prev_alarm) && is_stable;

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
        if      (is_arrhythmia) str_type = 88'h415259544D494120202020;
        else if (is_tachy)      str_type = 88'h54414348594B4152444941;
        else if (is_brady)      str_type = 88'h42524144594B4152444941;
        else                    str_type = 88'h2020202020202020202020;
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
            
            assign ren = (k < num_logs) && (show_history || (show_monitor && k < 2));

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

    assign pixel_on = |row_pixels;

endmodule