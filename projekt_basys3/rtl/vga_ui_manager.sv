`timescale 1ns / 1ps

module vga_ui_manager (
    input  logic clk_65MHz,
    input  logic clk_100MHz,
    input  logic rst_n,
    
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,
    input  logic [1:0] leads_off,     
    
    input  logic [11:0] mouse_x,
    input  logic [11:0] mouse_y,
    input  logic mouse_left,

    vga_if.in  vga_in,
    vga_if.out vga_out
);

    import vga_pkg::*;

    typedef enum logic [1:0] {
        STATE_SETUP   = 2'b00,
        STATE_MONITOR = 2'b01,
        STATE_HISTORY = 2'b10
    } state_t;
    
    state_t current_state;
    logic prev_mouse_left;
    logic mouse_click;
    assign mouse_click = mouse_left && !prev_mouse_left;

    localparam logic [11:0] COLOR_BG     = 12'h000; 
    localparam logic [11:0] COLOR_BORDER = 12'h444; 
    localparam logic [11:0] COLOR_BTN    = 12'h248; 
    localparam logic [11:0] COLOR_BTN_S  = 12'h153; 
    localparam logic [11:0] COLOR_TEXT_W = 12'hFFF; 
    localparam logic [11:0] COLOR_HIST   = 12'hF80; 

    // --- REJESTRY USTAWIEŃ (Bezpieczne w domenie 65MHz) ---
    logic [4:0] setup_hour; logic [5:0] setup_min;
    logic [4:0] setup_day;  logic [3:0] setup_mon;
    logic do_set_time; 

    // --- ZEGAR REALNY (RTC) ---
    logic [4:0] rtc_hours; logic [5:0] rtc_minutes; logic [5:0] rtc_seconds;
    logic [4:0] rtc_days;  logic [3:0] rtc_months;

    rtc_clock u_clock (
        .clk_100MHz(clk_100MHz), .rst_n(rst_n),
        .set_time_trigger(do_set_time),
        .set_hour(setup_hour), .set_min(setup_min),
        .set_day(setup_day),   .set_mon(setup_mon),
        .hours(rtc_hours), .minutes(rtc_minutes), .seconds(rtc_seconds),
        .days(rtc_days), .months(rtc_months)
    );

    // --- HISTORIA ---
    logic history_pixel;
    alarm_logger u_logger (
        .clk_100MHz(clk_100MHz), 
        .clk_65MHz(clk_65MHz), 
        .rst_n(rst_n),
        .rtc_hours(rtc_hours), 
        .rtc_minutes(rtc_minutes),
        .rtc_seconds(rtc_seconds), 
        .current_bpm(current_bpm), 
        .bpm_valid(bpm_valid),
        .leads_off(leads_off),
        .hcount(vga_in.hcount), 
        .vcount(vga_in.vcount),
        .show_history(current_state == STATE_HISTORY),
        .show_monitor(current_state == STATE_MONITOR), 
        .pixel_on(history_pixel)
    );

    logic [11:0] bpm_rgb;
    vga_bpm_display u_bpm_text (
        .clk_65MHz(clk_65MHz), .rst_n(rst_n), 
        .bpm(current_bpm), .bpm_valid(bpm_valid), 
        .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .leads_off(leads_off), 
        .rgb_out(bpm_rgb)
    );

    // --- RENDEROWANIE TEKSTÓW Z ROM ---
    logic txt_header_M, txt_header_ONITOR;
    
    // Litera "M"
    vga_text_renderer #(.MAX_CHARS(1), .CHAR_SCALE(2)) t_head_m (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x(12'd30), .pos_y(12'd15),
        .char_string(8'h4D), // "M"
        .string_len(4'd1), .pixel_on(txt_header_M)
    );

    // Reszta tytułu odsunięta o 3 piksele w prawo
    vga_text_renderer #(.MAX_CHARS(10), .CHAR_SCALE(2)) t_head_onitor (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x(12'd49), .pos_y(12'd15),
        .char_string(80'h4F4E49544F5220454B47), // "ONITOR EKG"
        .string_len(4'd10), .pixel_on(txt_header_ONITOR)
    );

    // Tekst na głównym przycisku dole (START / HISTORIA / POWROT)
    logic txt_btn1;
    logic [79:0] btn_string; 
    always_comb begin
        if (current_state == STATE_SETUP)        btn_string = 80'h20205354415254202020; // "  START   "
        else if (current_state == STATE_MONITOR) btn_string = 80'h20484953544F52494120; // " HISTORIA "
        else                                     btn_string = 80'h2020504F57524F542020; // "  POWROT  "
    end

    vga_text_renderer #(.MAX_CHARS(10), .CHAR_SCALE(1)) t_btn1 (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x((current_state == STATE_SETUP) ? 12'd475 : 12'd835), 
        .pos_y((current_state == STATE_SETUP) ? 12'd422 : 12'd627),
        .char_string(btn_string), .string_len(4'd10), .pixel_on(txt_btn1)
    );

    // Nowy przycisk USTAWIENIA (tylko na ekranach MONITOR i HISTORY)
    logic txt_btn_settings;
    vga_text_renderer #(.MAX_CHARS(10), .CHAR_SCALE(1)) t_btn2 (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x(12'd835), .pos_y(12'd547), // Wyśrodkowane w nowym polu
        .char_string(80'h555354415749454E4941), // "USTAWIENIA"
        .string_len((current_state != STATE_SETUP) ? 4'd10 : 4'd0), 
        .pixel_on(txt_btn_settings)
    );

    // --- KONWERSJA ZEGARA RTC NA ASCII DLA PRAWEGO GÓRNEGO ROGU ---
    logic txt_top_clock;
    logic [7:0] t_h1, t_h2, t_m1, t_m2, t_s1, t_s2, t_d1, t_d2, t_mo1, t_mo2;
    logic [119:0] top_clock_str; // 15 znaków
    
    assign t_h1 = (rtc_hours / 10) + 8'h30;   assign t_h2 = (rtc_hours % 10) + 8'h30;
    assign t_m1 = (rtc_minutes / 10) + 8'h30; assign t_m2 = (rtc_minutes % 10) + 8'h30;
    assign t_s1 = (rtc_seconds / 10) + 8'h30; assign t_s2 = (rtc_seconds % 10) + 8'h30;
    assign t_d1 = (rtc_days / 10) + 8'h30;    assign t_d2 = (rtc_days % 10) + 8'h30;
    assign t_mo1 = (rtc_months / 10) + 8'h30; assign t_mo2 = (rtc_months % 10) + 8'h30;

    // Format: "HH:MM:SS  DD.MM"
    assign top_clock_str = {t_h1, t_h2, 8'h3A, t_m1, t_m2, 8'h3A, t_s1, t_s2, 8'h20, 8'h20, t_d1, t_d2, 8'h2E, t_mo1, t_mo2};

    vga_text_renderer #(.MAX_CHARS(15), .CHAR_SCALE(2)) t_top_clock (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x(12'd730), .pos_y(12'd15),
        .char_string(top_clock_str), .string_len(4'd15), .pixel_on(txt_top_clock)
    );

    // --- CYFROWE WYŚWIETLACZE DLA EKRANU SETUP (Zostawione duże 7-segmentowe) ---
    logic [11:0] hcount, vcount;
    assign hcount = vga_in.hcount;
    assign vcount = vga_in.vcount;

    logic setup_time_p [3:0]; logic setup_time_pixel;
    logic setup_date_p [3:0]; logic setup_date_pixel;

    vga_7seg_digit #(.POS_X(360), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sh0 (.digit_val(setup_hour/10), .* , .pixel_on(setup_time_p[0]));
    vga_7seg_digit #(.POS_X(390), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sh1 (.digit_val(setup_hour%10), .* , .pixel_on(setup_time_p[1]));
    vga_7seg_digit #(.POS_X(440), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sm0 (.digit_val(setup_min/10), .* , .pixel_on(setup_time_p[2]));
    vga_7seg_digit #(.POS_X(470), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sm1 (.digit_val(setup_min%10), .* , .pixel_on(setup_time_p[3]));
    logic setup_colon = (vga_in.hcount >= 421 && vga_in.hcount <= 425 && ((vga_in.vcount >= 290 && vga_in.vcount <= 294) || (vga_in.vcount >= 310 && vga_in.vcount <= 314)));
    assign setup_time_pixel = (current_state == STATE_SETUP) && (setup_time_p[0] | setup_time_p[1] | setup_time_p[2] | setup_time_p[3] | setup_colon);

    vga_7seg_digit #(.POS_X(540), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sd0 (.digit_val(setup_day/10), .* , .pixel_on(setup_date_p[0]));
    vga_7seg_digit #(.POS_X(570), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) sd1 (.digit_val(setup_day%10), .* , .pixel_on(setup_date_p[1]));
    vga_7seg_digit #(.POS_X(620), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) s_mo0 (.digit_val(setup_mon/10), .* , .pixel_on(setup_date_p[2]));
    vga_7seg_digit #(.POS_X(650), .POS_Y(280), .WIDTH(22), .HEIGHT(46), .THICKNESS(4)) s_mo1 (.digit_val(setup_mon%10), .* , .pixel_on(setup_date_p[3]));
    logic setup_dot = (vga_in.hcount >= 601 && vga_in.hcount <= 605 && vga_in.vcount >= 322 && vga_in.vcount <= 326);
    assign setup_date_pixel = (current_state == STATE_SETUP) && (setup_date_p[0] | setup_date_p[1] | setup_date_p[2] | setup_date_p[3] | setup_dot);

    // --- ZNAKI PLUS I MINUS (Bezpośrednie Rysowanie Pikseli) ---
    logic draw_pm_text;
    always_comb begin
        draw_pm_text = 1'b0;
        if (current_state == STATE_SETUP) begin
            if (vga_in.vcount >= 210 && vga_in.vcount <= 230) begin
                if (vga_in.hcount >= 383 && vga_in.hcount <= 387) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 463 && vga_in.hcount <= 467) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 563 && vga_in.hcount <= 567) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 643 && vga_in.hcount <= 647) draw_pm_text = 1'b1; 
            end
            if (vga_in.vcount >= 218 && vga_in.vcount <= 222) begin
                if (vga_in.hcount >= 375 && vga_in.hcount <= 395) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 455 && vga_in.hcount <= 475) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 555 && vga_in.hcount <= 575) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 635 && vga_in.hcount <= 655) draw_pm_text = 1'b1; 
            end
            
            if (vga_in.vcount >= 368 && vga_in.vcount <= 372) begin
                if (vga_in.hcount >= 375 && vga_in.hcount <= 395) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 455 && vga_in.hcount <= 475) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 555 && vga_in.hcount <= 575) draw_pm_text = 1'b1; 
                if (vga_in.hcount >= 635 && vga_in.hcount <= 655) draw_pm_text = 1'b1; 
            end
        end
    end

    // --- LOGIKA KLIKNIĘĆ (W ZEGARZE 65 MHz) ---
    always_ff @(posedge clk_65MHz or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_SETUP; prev_mouse_left <= 1'b0;
            setup_hour <= 5'd12; setup_min <= 6'd00;
            setup_day <= 5'd15; setup_mon <= 4'd06;
            do_set_time <= 1'b0;
        end else begin
            prev_mouse_left <= mouse_left;
            do_set_time <= 1'b0; 

            if (mouse_click) begin
                case (current_state)
                    STATE_SETUP: begin
                        if (mouse_x > 400 && mouse_x < 624 && mouse_y > 400 && mouse_y < 460) begin
                            current_state <= STATE_MONITOR; do_set_time <= 1'b1;
                        end
                        if (mouse_y >= 200 && mouse_y < 240) begin
                            if (mouse_x >= 360 && mouse_x < 410) setup_hour <= (setup_hour == 5'd23) ? 5'd0 : setup_hour + 1'b1;
                            if (mouse_x >= 440 && mouse_x < 490) setup_min  <= (setup_min == 6'd59) ? 6'd0 : setup_min + 1'b1;
                            if (mouse_x >= 540 && mouse_x < 590) setup_day  <= (setup_day == 5'd31) ? 5'd1 : setup_day + 1'b1;
                            if (mouse_x >= 620 && mouse_x < 670) setup_mon  <= (setup_mon == 4'd12) ? 4'd1 : setup_mon + 1'b1;
                        end
                        if (mouse_y >= 350 && mouse_y < 390) begin
                            if (mouse_x >= 360 && mouse_x < 410) setup_hour <= (setup_hour == 5'd0) ? 5'd23 : setup_hour - 1'b1;
                            if (mouse_x >= 440 && mouse_x < 490) setup_min  <= (setup_min == 6'd0) ? 6'd59 : setup_min - 1'b1;
                            if (mouse_x >= 540 && mouse_x < 590) setup_day  <= (setup_day == 5'd1) ? 5'd31 : setup_day - 1'b1;
                            if (mouse_x >= 620 && mouse_x < 670) setup_mon  <= (setup_mon == 4'd1) ? 4'd12 : setup_mon - 1'b1;
                        end
                    end
                    STATE_MONITOR: begin
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_HISTORY;
                        // Nowy przycisk przejścia do SETUP
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 520 && mouse_y < 590) current_state <= STATE_SETUP;
                    end
                    STATE_HISTORY: begin
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_MONITOR;
                        // Nowy przycisk przejścia do SETUP
                        if (mouse_x > 800 && mouse_x < 950 && mouse_y > 520 && mouse_y < 590) current_state <= STATE_SETUP;
                    end
                endcase
            end
        end
    end

    // --- GEOMETRIA TŁA ---
    logic draw_border, draw_button_main, draw_button_setup, draw_button_settings, in_ecg_zone;

    always_comb begin
        draw_border = 1'b0; draw_button_main = 1'b0; draw_button_setup = 1'b0; draw_button_settings = 1'b0; in_ecg_zone = 1'b0;
        if (vga_in.vcount == 60) draw_border = 1'b1; 

        case (current_state)
            STATE_SETUP: begin
                if (vga_in.hcount > 400 && vga_in.hcount < 624 && vga_in.vcount > 400 && vga_in.vcount < 460) draw_button_main = 1'b1;
                
                if ((vga_in.vcount >= 200 && vga_in.vcount < 240) && 
                    ((vga_in.hcount >= 360 && vga_in.hcount < 410) || (vga_in.hcount >= 440 && vga_in.hcount < 490) ||
                     (vga_in.hcount >= 540 && vga_in.hcount < 590) || (vga_in.hcount >= 620 && vga_in.hcount < 670))) draw_button_setup = 1'b1;
                     
                if ((vga_in.vcount >= 350 && vga_in.vcount < 390) && 
                    ((vga_in.hcount >= 360 && vga_in.hcount < 410) || (vga_in.hcount >= 440 && vga_in.hcount < 490) ||
                     (vga_in.hcount >= 540 && vga_in.hcount < 590) || (vga_in.hcount >= 620 && vga_in.hcount < 670))) draw_button_setup = 1'b1;
            end
            STATE_MONITOR: begin
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 520)) || (vga_in.vcount >= 90 && vga_in.vcount <= 520 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if (vga_in.hcount > 30 && vga_in.hcount < 740 && vga_in.vcount > 90 && vga_in.vcount < 520) in_ecg_zone = 1'b1;
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 550 || vga_in.vcount == 730)) || (vga_in.vcount >= 550 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990))) draw_border = 1'b1;
                
                // Przycisk HISTORIA
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
                // Przycisk USTAWIENIA
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 520 && vga_in.vcount < 590) draw_button_settings = 1'b1;
            end
            STATE_HISTORY: begin
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990))) draw_border = 1'b1;
                
                // Przycisk POWRÓT (na koordynatach HISTORII)
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
                // Przycisk USTAWIENIA
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 520 && vga_in.vcount < 590) draw_button_settings = 1'b1;
            end
        endcase
    end

    // --- KOLOROWANIE ---
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

            // Scalony warunek z nowymi tekstami
            if (txt_header_M || txt_header_ONITOR || txt_btn1 || txt_btn_settings || txt_top_clock || draw_pm_text || setup_time_pixel || setup_date_pixel) 
                                                vga_out.rgb <= COLOR_TEXT_W;
            else if (history_pixel)             vga_out.rgb <= COLOR_HIST;
            else if (current_state == STATE_MONITOR && bpm_rgb != 12'h000) vga_out.rgb <= bpm_rgb;
            else if (draw_border)               vga_out.rgb <= COLOR_BORDER;
            // Zwykły przycisk i nowy przycisk ustawień mają ten sam kolor (niebieski)
            else if (draw_button_main || draw_button_settings) vga_out.rgb <= COLOR_BTN;
            else if (draw_button_setup)         vga_out.rgb <= COLOR_BTN_S;
            else if (current_state == STATE_MONITOR && in_ecg_zone) vga_out.rgb <= vga_in.rgb;
            else                                vga_out.rgb <= COLOR_BG;
        end
    end
endmodule