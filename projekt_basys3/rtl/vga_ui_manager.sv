`timescale 1ns / 1ps

module vga_ui_manager (
    input  logic clk_65MHz,     // Zegar pikselowy VGA
    input  logic clk_100MHz,    // Zegar systemowy dla RTC i Loggera
    input  logic rst_n,
    
    // Sygnały EKG
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,     // Impuls nowego tętna
    
    // Sygnały z myszki
    input  logic [11:0] mouse_x,
    input  logic [11:0] mouse_y,
    input  logic mouse_left,

    // Interfejsy VGA
    vga_if.in  vga_in,
    vga_if.out vga_out
);

    import vga_pkg::*;

    // --- Definicja stanów FSM ---
    typedef enum logic [1:0] {
        STATE_SETUP   = 2'b00,
        STATE_MONITOR = 2'b01,
        STATE_HISTORY = 2'b10
    } state_t;
    
    state_t current_state;
    logic prev_mouse_left;

    // --- Paleta kolorów ---
    localparam logic [11:0] COLOR_BG     = 12'h000; // Czerń
    localparam logic [11:0] COLOR_BORDER = 12'h444; // Szary obrys
    localparam logic [11:0] COLOR_BTN    = 12'h248; // Niebieski przycisk (START/HISTORIA)
    localparam logic [11:0] COLOR_BTN_S  = 12'h333; // Szary przycisk (Do ustawiania czasu)
    localparam logic [11:0] COLOR_TEXT_W = 12'hFFF; // Biały tekst nagłówka
    localparam logic [11:0] COLOR_HIST   = 12'hF80; // Pomarańczowy tekst historii

    // --- REJESTRY STRONY STARTOWEJ ---
    logic [4:0] setup_hour;
    logic [5:0] setup_min;
    logic do_set_time; // Impuls wysyłany do zegara RTC przy wciśnięciu START

    // --- INSTANCJA ZEGARA (RTC) ---
    logic [4:0] rtc_hours;
    logic [5:0] rtc_mins;
    
    rtc_clock u_clock (
        .clk_100MHz(clk_100MHz),
        .rst_n(rst_n),
        .set_time_trigger(do_set_time), 
        .set_hour(setup_hour), 
        .set_min(setup_min), 
        .hours(rtc_hours),
        .minutes(rtc_mins),
        .seconds()
    );

    // --- INSTANCJA PAMIĘCI HISTORII ---
    logic history_pixel;
    
    alarm_logger u_logger (
        .clk_100MHz(clk_100MHz),
        .rst_n(rst_n),
        .rtc_hours(rtc_hours),
        .rtc_minutes(rtc_mins),
        .current_bpm(current_bpm),
        .bpm_valid(bpm_valid),
        .hcount(vga_in.hcount),
        .vcount(vga_in.vcount),
        .show_history(current_state == STATE_HISTORY),
        .pixel_on(history_pixel)
    );

    // --- WYŚWIETLANIE TĘTNA BPM ---
    logic [11:0] bpm_rgb;
    vga_bpm_display u_bpm_text (
        .bpm(current_bpm),
        .hcount(vga_in.hcount),
        .vcount(vga_in.vcount),
        .rgb_out(bpm_rgb)
    );

    // --- WYŚWIETLANIE ZEGARA (PRAWY GÓRNY RÓG) ---
    logic time_p1, time_p2, time_p3, time_p4, time_colon, time_pixel;
    vga_7seg_digit #(.POS_X(880), .POS_Y(15), .WIDTH(15), .HEIGHT(30), .THICKNESS(3)) u_h1 (.digit_val(rtc_hours/10), .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(time_p1));
    vga_7seg_digit #(.POS_X(900), .POS_Y(15), .WIDTH(15), .HEIGHT(30), .THICKNESS(3)) u_h2 (.digit_val(rtc_hours%10), .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(time_p2));
    vga_7seg_digit #(.POS_X(930), .POS_Y(15), .WIDTH(15), .HEIGHT(30), .THICKNESS(3)) u_m1 (.digit_val(rtc_mins/10),  .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(time_p3));
    vga_7seg_digit #(.POS_X(950), .POS_Y(15), .WIDTH(15), .HEIGHT(30), .THICKNESS(3)) u_m2 (.digit_val(rtc_mins%10),  .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(time_p4));
    
    assign time_colon = (vga_in.hcount >= 920 && vga_in.hcount <= 923 && ((vga_in.vcount >= 20 && vga_in.vcount <= 23) || (vga_in.vcount >= 35 && vga_in.vcount <= 38)));
    assign time_pixel = time_p1 | time_p2 | time_p3 | time_p4 | time_colon;

    // --- WYŚWIETLANIE ZEGARA SETUP (ŚRODEK EKRANU) ---
    logic setup_p1, setup_p2, setup_p3, setup_p4, setup_colon, setup_pixel;
    vga_7seg_digit #(.POS_X(440), .POS_Y(300), .WIDTH(20), .HEIGHT(40), .THICKNESS(4)) s_h1 (.digit_val(setup_hour/10), .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(setup_p1));
    vga_7seg_digit #(.POS_X(470), .POS_Y(300), .WIDTH(20), .HEIGHT(40), .THICKNESS(4)) s_h2 (.digit_val(setup_hour%10), .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(setup_p2));
    vga_7seg_digit #(.POS_X(520), .POS_Y(300), .WIDTH(20), .HEIGHT(40), .THICKNESS(4)) s_m1 (.digit_val(setup_min/10),  .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(setup_p3));
    vga_7seg_digit #(.POS_X(550), .POS_Y(300), .WIDTH(20), .HEIGHT(40), .THICKNESS(4)) s_m2 (.digit_val(setup_min%10),  .hcount(vga_in.hcount), .vcount(vga_in.vcount), .pixel_on(setup_p4));
    
    assign setup_colon = (vga_in.hcount >= 503 && vga_in.hcount <= 507 && ((vga_in.vcount >= 310 && vga_in.vcount <= 314) || (vga_in.vcount >= 326 && vga_in.vcount <= 330)));
    assign setup_pixel = (current_state == STATE_SETUP) & (setup_p1 | setup_p2 | setup_p3 | setup_p4 | setup_colon);

    // --- RYSOWANIE NAGŁÓWKA "EKG" ---
    logic ekg_text_pixel;
    always_comb begin
        ekg_text_pixel = 1'b0;
        // Litera E
        if (vga_in.hcount >= 30 && vga_in.hcount <= 50 && vga_in.vcount >= 15 && vga_in.vcount <= 45)
            if (vga_in.hcount <= 35 || vga_in.vcount <= 20 || vga_in.vcount >= 40 || (vga_in.vcount >= 27 && vga_in.vcount <= 32)) ekg_text_pixel = 1'b1;
        // Litera K
        if (vga_in.hcount >= 60 && vga_in.hcount <= 80 && vga_in.vcount >= 15 && vga_in.vcount <= 45)
            if (vga_in.hcount <= 65 || (vga_in.hcount >= 70 && (vga_in.vcount <= 23 || vga_in.vcount >= 37)) || (vga_in.hcount >= 65 && vga_in.hcount <= 75 && vga_in.vcount >= 25 && vga_in.vcount <= 35)) ekg_text_pixel = 1'b1;
        // Litera G
        if (vga_in.hcount >= 90 && vga_in.hcount <= 110 && vga_in.vcount >= 15 && vga_in.vcount <= 45)
            if (vga_in.hcount <= 95 || vga_in.vcount <= 20 || vga_in.vcount >= 40 || (vga_in.hcount >= 105 && vga_in.vcount >= 30) || (vga_in.hcount >= 100 && vga_in.vcount >= 28 && vga_in.vcount <= 32)) ekg_text_pixel = 1'b1;
    end

    // --- MASZYNA STANÓW I KLIKNIĘCIA ---
    always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_SETUP;
            prev_mouse_left <= 1'b0;
            setup_hour <= 5'd12;
            setup_min <= 6'd00;
            do_set_time <= 1'b0;
        end else begin
            prev_mouse_left <= mouse_left;
            do_set_time <= 1'b0; // Domyslnie wyłącz impuls

            if (mouse_left && !prev_mouse_left) begin
                case (current_state)
                    STATE_SETUP: begin
                        // Klik w przycisk START (Środek)
                        if (mouse_x > 400 && mouse_x < 624 && mouse_y > 400 && mouse_y < 460) begin
                            current_state <= STATE_MONITOR;
                            do_set_time <= 1'b1; // Zapisz czas do zegara RTC!
                        end
                        // Klik w "Godzina w górę"
                        else if (mouse_x > 430 && mouse_x < 500 && mouse_y > 240 && mouse_y < 280) begin
                            setup_hour <= (setup_hour == 5'd23) ? 5'd0 : setup_hour + 1'b1;
                        end
                        // Klik w "Minuta w górę"
                        else if (mouse_x > 510 && mouse_x < 580 && mouse_y > 240 && mouse_y < 280) begin
                            setup_min <= (setup_min == 6'd59) ? 6'd0 : setup_min + 1'b1;
                        end
                    end
                    STATE_MONITOR: if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_HISTORY;
                    STATE_HISTORY: if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_MONITOR;
                endcase
            end
        end
    end

    // --- GEOMETRIA OKIEN I MULTIPLEKSER WIDEO ---
    logic draw_border, draw_button_main, draw_button_setup, in_ecg_zone;

    always_comb begin
        draw_border = 1'b0; draw_button_main = 1'b0; draw_button_setup = 1'b0; in_ecg_zone = 1'b0;
        if (vga_in.vcount == 60) draw_border = 1'b1; // Linia paska górnego

        case (current_state)
            STATE_SETUP: begin
                // Tło przycisku START
                if (vga_in.hcount > 400 && vga_in.hcount < 624 && vga_in.vcount > 400 && vga_in.vcount < 460) draw_button_main = 1'b1;
                // Tło przycisku "Godzina w górę"
                if (vga_in.hcount > 430 && vga_in.hcount < 500 && vga_in.vcount > 240 && vga_in.vcount < 280) draw_button_setup = 1'b1;
                // Tło przycisku "Minuta w górę"
                if (vga_in.hcount > 510 && vga_in.hcount < 580 && vga_in.vcount > 240 && vga_in.vcount < 280) draw_button_setup = 1'b1;
            end
            STATE_MONITOR: begin
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 520)) || (vga_in.vcount >= 90 && vga_in.vcount <= 520 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if (vga_in.hcount > 30 && vga_in.hcount < 740 && vga_in.vcount > 90 && vga_in.vcount < 520) in_ecg_zone = 1'b1;
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 550 || vga_in.vcount == 730)) || (vga_in.vcount >= 550 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990))) draw_border = 1'b1;
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
            end
            STATE_HISTORY: begin
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990))) draw_border = 1'b1;
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
            end
        endcase
    end

    // --- KOLOROWANIE OSTATECZNE ---
    always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            vga_out.hcount <= '0; vga_out.vcount <= '0;
            vga_out.hsync  <= '0; vga_out.vsync  <= '0;
            vga_out.hblnk  <= '0; vga_out.vblnk  <= '0;
            vga_out.rgb    <= 12'h000;
        end else begin
            vga_out.hcount <= vga_in.hcount; vga_out.vcount <= vga_in.vcount;
            vga_out.hsync  <= vga_in.hsync;  vga_out.vsync  <= vga_in.vsync;
            vga_out.hblnk  <= vga_in.hblnk;  vga_out.vblnk  <= vga_in.vblnk;

            // Hierarchia ważności (co przykrywa co)
            if (ekg_text_pixel || time_pixel || setup_pixel) vga_out.rgb <= COLOR_TEXT_W;
            else if (history_pixel)             vga_out.rgb <= COLOR_HIST;
            else if (current_state == STATE_MONITOR && bpm_rgb != 12'h000) vga_out.rgb <= bpm_rgb;
            else if (draw_border)               vga_out.rgb <= COLOR_BORDER;
            else if (draw_button_main)          vga_out.rgb <= COLOR_BTN;
            else if (draw_button_setup)         vga_out.rgb <= COLOR_BTN_S;
            else if (current_state == STATE_MONITOR && in_ecg_zone) vga_out.rgb <= vga_in.rgb;
            else                                vga_out.rgb <= COLOR_BG;
        end
    end
endmodule