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
        end else if (set_time_trigger) begin
            hours   <= set_hour;
            minutes <= set_min;
            seconds <= 6'd0;
            days    <= set_day;
            months  <= set_mon;
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