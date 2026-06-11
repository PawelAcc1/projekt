`timescale 1ns / 1ps

module rtc_clock (
    input  logic clk_100MHz,
    input  logic rst_n,
    input  logic set_time_trigger, // Impuls do ustawiania godziny (z myszki)
    input  logic [5:0] set_min,
    input  logic [4:0] set_hour,
    
    output logic [5:0] minutes,
    output logic [4:0] hours,
    output logic [5:0] seconds
);

    logic [26:0] prescaler; // Licznik do odliczenia 1 sekundy (100 000 000 taktów)
    logic one_second_tick;

    // 1. Generator impulsu 1-sekundowego
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            prescaler <= 0;
            one_second_tick <= 0;
        end else if (prescaler == 100_000_000 - 1) begin
            prescaler <= 0;
            one_second_tick <= 1;
        end else begin
            prescaler <= prescaler + 1;
            one_second_tick <= 0;
        end
    end

    // 2. Liczenie czasu
    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            seconds <= 0; minutes <= 0; hours <= 0;
        end else if (set_time_trigger) begin
            minutes <= set_min;
            hours   <= set_hour;
            seconds <= 0;
        end else if (one_second_tick) begin
            if (seconds == 59) begin
                seconds <= 0;
                if (minutes == 59) begin
                    minutes <= 0;
                    if (hours == 23) hours <= 0;
                    else hours <= hours + 1;
                end else minutes <= minutes + 1;
            end else seconds <= seconds + 1;
        end
    end
endmodule