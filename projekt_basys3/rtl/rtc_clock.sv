`timescale 1ns / 1ps

module rtc_clock (
    input  logic clk_100MHz,
    input  logic rst_n,

    // Impuls zapisujący wyklikaną datę i czas z UI
    input  logic set_time_trigger,
    input  logic [4:0] set_hour,
    input  logic [5:0] set_min,
    input  logic [4:0] set_day,
    input  logic [3:0] set_mon,

    // Wyjścia do wyświetlacza i historii
    output logic [4:0] hours,
    output logic [5:0] minutes,
    output logic [5:0] seconds,
    output logic [4:0] days,
    output logic [3:0] months
);

    // --- SYNCHRONIZATORY CDC (65MHz -> 100MHz) ---
    // 1. Synchronizacja sygnału wyzwalającego (z detekcją zbocza)
    logic set_time_sync1, set_time_sync2, set_time_sync3;
    logic set_time_pulse;

    // 2. Synchronizacja magistral danych
    logic [4:0] set_hour_sync1, set_hour_sync2;
    logic [5:0] set_min_sync1,  set_min_sync2;
    logic [4:0] set_day_sync1,  set_day_sync2;
    logic [3:0] set_mon_sync1,  set_mon_sync2;

    //--- Blok synchronizujący ---
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            set_time_sync1 <= 1'b0; set_time_sync2 <= 1'b0; set_time_sync3 <= 1'b0;
            set_hour_sync1 <= '0; set_hour_sync2 <= '0;
            set_min_sync1  <= '0; set_min_sync2  <= '0;
            set_day_sync1  <= '0; set_day_sync2  <= '0;
            set_mon_sync1  <= '0; set_mon_sync2  <= '0;
        end else begin
            // Przesuwanie wyzwalacza
            set_time_sync1 <= set_time_trigger;
            set_time_sync2 <= set_time_sync1;
            set_time_sync3 <= set_time_sync2;

            // Przesuwanie danych
            set_hour_sync1 <= set_hour; set_hour_sync2 <= set_hour_sync1;
            set_min_sync1  <= set_min;  set_min_sync2  <= set_min_sync1;
            set_day_sync1  <= set_day;  set_day_sync2  <= set_day_sync1;
            set_mon_sync1  <= set_mon;  set_mon_sync2  <= set_mon_sync1;
        end
    end
    // Detekcja narastającego zbocza: jeśli teraz jest 1 (sync2), a przed chwilą było 0 (sync3)
    assign set_time_pulse = set_time_sync2 && !set_time_sync3;

    
    logic [26:0] clk_divider;
    logic one_second_tick;

    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            clk_divider <= 27'd0;
            one_second_tick <= 1'b0;
        end else begin
            if (clk_divider == 27'd100_000_000 - 1) begin
                clk_divider <= 27'd0;
                one_second_tick <= 1'b1;
            end else begin
                clk_divider <= clk_divider + 1'b1;
                one_second_tick <= 1'b0;
            end
        end
    end

    // Główny licznik czasu realnego
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            hours <= 5'd12; minutes <= 6'd0; seconds <= 6'd0;
            days  <= 5'd15; months  <= 4'd6;
        end else if (set_time_pulse) begin
            hours   <= set_hour_sync2;
            minutes <= set_min_sync2;
            seconds <= 6'd0;
            days    <= set_day_sync2;
            months  <= set_mon_sync2;
        end else if (one_second_tick) begin
            if (seconds == 6'd59) begin
                seconds <= 6'd0;
                if (minutes == 6'd59) begin
                    minutes <= 6'd0;
                    if (hours == 5'd23) begin
                        hours <= 5'd0;
                        if (days == 5'd31) begin
                            days <= 5'd1;
                            months <= (months == 4'd12) ? 4'd1 : months + 1'b1;
                        end else days <= days + 1'b1;
                    end else hours <= hours + 1'b1;
                end else minutes <= minutes + 1'b1;
            end else seconds <= seconds + 1'b1;
        end
    end
endmodule