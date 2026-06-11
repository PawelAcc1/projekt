`timescale 1ns / 1ps

module alarm_logger (
    input  logic clk_100MHz,          // Zegar do zapisu danych sprzętowych
    input  logic rst_n,               // Reset

    // Dane wejściowe z zegara RTC i kalkulatora BPM
    input  logic [4:0] rtc_hours,
    input  logic [5:0] rtc_minutes,
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,           // Impuls informujący o nowym wyliczeniu tętna

    // Interfejs wideo (VGA) do rysowania tabeli
    input  logic [11:0] hcount,
    input  logic [11:0] vcount,
    input  logic show_history,        // Sygnał z FSM: czy jesteśmy w trybie historii
    output logic pixel_on             // Jedynka logiczna, gdy piksel należy do tekstu historii
);

    // --- REJESTRY PAMIĘCI (Przechowają 4 ostatnie alarmy) ---
    logic [4:0] log_hours   [3:0];
    logic [5:0] log_minutes [3:0];
    logic [7:0] log_bpm     [3:0];
    
    logic [1:0] write_ptr;            // Wskaźnik zapisu (0 -> 1 -> 2 -> 3 -> 0)
    logic [2:0] num_logs;             // Licznik zapisanych alarmów (maksymalnie 4)

    // --- LOGIKA DETEKCJI ANOMALII I ZAPISU ---
    logic alarm_condition;
    // Alarm wyzwala się, gdy tętno jest poza zakresem 50-100 BPM w momencie ważnego pomiaru
    assign alarm_condition = bpm_valid && (current_bpm > 8'd100 || current_bpm < 8'd50);

    always_ff @(posedge clk_100MHz or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 2'd0;
            num_logs  <= 3'd0;
            for (int i = 0; i < 4; i++) begin
                log_hours[i]   <= 5'd0;
                log_minutes[i] <= 6'd0;
                log_bpm[i]     <= 8'd0;
            end
        end else if (alarm_condition) begin
            // Zapis danych do komórki wskazywanej przez wskaźnik
            log_hours[write_ptr]   <= rtc_hours;
            log_minutes[write_ptr] <= rtc_minutes;
            log_bpm[write_ptr]     <= current_bpm;
            
            // Przesunięcie wskaźnika kołowego
            write_ptr <= write_ptr + 1'b1;
            
            // Zwiększaj licznik wpisów tylko do osiągnięcia pojemności 4
            if (num_logs < 3'd4) begin
                num_logs <= num_logs + 1'b1;
            end
        end
    end

    // --- LOGIKA GENEROWANIA WIDOKU TABELI ---
    // Tablice przewodów łączące pętlę generate z wyjściami cyfr
    logic pixel_h1 [3:0];
    logic pixel_h2 [3:0];
    logic pixel_m1 [3:0];
    logic pixel_m2 [3:0];
    logic pixel_b1 [3:0];
    logic pixel_b2 [3:0];
    logic pixel_b3 [3:0];

    // Automatyczne wygenerowanie 4 wierszy tekstu na ekranie
    genvar k;
    generate
        for (k = 0; k < 4; k = k + 1) begin : log_row
            // Każdy wiersz rysuje się o 80 pikseli niżej (start od Y=200)
            localparam int Y_START = 200 + (k * 80);
            
            // Godziny (HH)
            vga_7seg_digit #( .POS_X(100), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_h1 (
                .digit_val(log_hours[k] / 10), .* , .pixel_on(pixel_h1[k])
            );
            vga_7seg_digit #( .POS_X(120), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_h2 (
                .digit_val(log_hours[k] % 10), .* , .pixel_on(pixel_h2[k])
            );
            // Minuty (MM)
            vga_7seg_digit #( .POS_X(150), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_m1 (
                .digit_val(log_minutes[k] / 10), .* , .pixel_on(pixel_m1[k])
            );
            vga_7seg_digit #( .POS_X(170), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_m2 (
                .digit_val(log_minutes[k] % 10), .* , .pixel_on(pixel_m2[k])
            );
            // Tętno BPM (Setki, Dziesiątki, Jedności)
            vga_7seg_digit #( .POS_X(230), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_b1 (
                .digit_val(log_bpm[k] / 100), .* , .pixel_on(pixel_b1[k])
            );
            vga_7seg_digit #( .POS_X(250), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_b2 (
                .digit_val((log_bpm[k] % 100) / 10), .* , .pixel_on(pixel_b2[k])
            );
            vga_7seg_digit #( .POS_X(270), .POS_Y(Y_START), .WIDTH(15), .HEIGHT(30), .THICKNESS(3) ) u_b3 (
                .digit_val(log_bpm[k] % 10), .* , .pixel_on(pixel_b3[k])
            );
        end
    endgenerate

    // --- MULTIPLEKSER BIEŻĄCEGO PIKSELA ---
    always_comb begin
        pixel_on = 1'b0;
        
        if (show_history) begin
            for (int i = 0; i < 4; i++) begin
                // Rysuj wiersz tylko wtedy, gdy zawiera realne dane (został zapisany)
                if (i < num_logs) begin
                    int row_y = 200 + (i * 80);
                    
                    // Sprzętowy dwukropek między godziną a minutą (dwa małe kwadraciki)
                    logic colon;
                    colon = (hcount >= 141 && hcount <= 143 && 
                            ((vcount >= row_y + 8 && vcount <= row_y + 10) || 
                             (vcount >= row_y + 20 && vcount <= row_y + 22)));
                             
                    // Sprzętowy myślnik separatora "HH:MM - BPM"
                    logic dash;
                    dash = (hcount >= 195 && hcount <= 210 && vcount >= row_y + 14 && vcount <= row_y + 16);

                    // Jeśli piksel należy do jakiejkolwiek cyfry lub znaku w tym wierszu
                    if (pixel_h1[i] || pixel_h2[i] || pixel_m1[i] || pixel_m2[i] || 
                        pixel_b1[i] || pixel_b2[i] || pixel_b3[i] || colon || dash) begin
                        pixel_on = 1'b1;
                    end
                end
            end
        end
    end

endmodule