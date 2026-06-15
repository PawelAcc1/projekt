`timescale 1ns / 1ps

module vga_ui_manager (
    input  logic clk_65MHz,
    input  logic clk_100MHz,
    input  logic rst_n,
    
    input  logic [7:0] current_bpm,
    input  logic bpm_valid,     
    
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
    logic do_set_time; // Wyzwalacz transferu do RTC

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
        .clk_65MHz(clk_65MHz), // DODANE: Zegar do czcionki
        .rst_n(rst_n),
        .rtc_hours(rtc_hours), 
        .rtc_minutes(rtc_minutes),
        .rtc_seconds(rtc_seconds), // DODANE: Przekazanie sekund do logów
        .current_bpm(current_bpm), 
        .bpm_valid(bpm_valid),
        .hcount(vga_in.hcount), 
        .vcount(vga_in.vcount),
        .show_history(current_state == STATE_HISTORY),
        .show_monitor(current_state == STATE_MONITOR), // DODANE: Logi na ekranie głównym
        .pixel_on(history_pixel)
    );

    logic [11:0] bpm_rgb;
    vga_bpm_display u_bpm_text (
        .clk_65MHz(clk_65MHz), .rst_n(rst_n), 
        .bpm(current_bpm), .bpm_valid(bpm_valid), 
        .hcount(vga_in.hcount), .vcount(vga_in.vcount), 
        .rgb_out(bpm_rgb)
    );

    // --- RENDEROWANIE TEKSTÓW Z ROM ---
    logic txt_header, txt_btn1;
    
    vga_text_renderer #(.MAX_CHARS(11), .CHAR_SCALE(2)) t_head (
        .clk(clk_65MHz), .hcount(vga_in.hcount), .vcount(vga_in.vcount),
        .pos_x(12'd30), .pos_y(12'd15),
        .char_string(88'h4D4F4E49544F5220454B47), // "MONITOR EKG" w ASCII HEX
        .string_len(4'd11), .pixel_on(txt_header)
    );

    // Tekst na głównym przycisku
    logic [79:0] btn_string; // 10 znaków * 8 bitów
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

    // --- CYFROWE WYŚWIETLACZE (7-SEG) ---
    logic main_time_p [5:0]; logic main_time_pixel;
    logic main_date_p [3:0]; logic main_date_pixel;
    logic setup_time_p [3:0]; logic setup_time_pixel;
    logic setup_date_p [3:0]; logic setup_date_pixel;

    // Zegar Prawy Górny Róg (HH:MM:SS)
    vga_7seg_digit #(.POS_X(800), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt0 (.digit_val(rtc_hours/10), .* , .pixel_on(main_time_p[0]));
    vga_7seg_digit #(.POS_X(815), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt1 (.digit_val(rtc_hours%10), .* , .pixel_on(main_time_p[1]));
    vga_7seg_digit #(.POS_X(835), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt2 (.digit_val(rtc_minutes/10), .* , .pixel_on(main_time_p[2]));
    vga_7seg_digit #(.POS_X(850), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt3 (.digit_val(rtc_minutes%10), .* , .pixel_on(main_time_p[3]));
    vga_7seg_digit #(.POS_X(870), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt4 (.digit_val(rtc_seconds/10), .* , .pixel_on(main_time_p[4]));
    vga_7seg_digit #(.POS_X(885), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) mt5 (.digit_val(rtc_seconds%10), .* , .pixel_on(main_time_p[5]));
    logic main_colon1, main_colon2;
    assign main_colon1 = (vga_in.hcount >= 829 && vga_in.hcount <= 831 && ((vga_in.vcount == 21) || (vga_in.vcount == 31)));
    assign main_colon2 = (vga_in.hcount >= 864 && vga_in.hcount <= 866 && ((vga_in.vcount == 21) || (vga_in.vcount == 31)));
    assign main_time_pixel = main_time_p[0] | main_time_p[1] | main_time_p[2] | main_time_p[3] | main_time_p[4] | main_time_p[5] | main_colon1 | main_colon2;

    // Data Prawy Górny Róg (DD.MM)
    vga_7seg_digit #(.POS_X(920), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) md0 (.digit_val(rtc_days/10), .* , .pixel_on(main_date_p[0]));
    vga_7seg_digit #(.POS_X(935), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) md1 (.digit_val(rtc_days%10), .* , .pixel_on(main_date_p[1]));
    vga_7seg_digit #(.POS_X(960), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) md2 (.digit_val(rtc_months/10), .* , .pixel_on(main_date_p[2]));
    vga_7seg_digit #(.POS_X(975), .POS_Y(15), .WIDTH(12), .HEIGHT(24), .THICKNESS(3)) md3 (.digit_val(rtc_months%10), .* , .pixel_on(main_date_p[3]));
    logic main_dot = (vga_in.hcount >= 951 && vga_in.hcount <= 953 && vga_in.vcount >= 36 && vga_in.vcount <= 38);
    assign main_date_pixel = main_date_p[0] | main_date_p[1] | main_date_p[2] | main_date_p[3] | main_dot;

    // --- SETUP: Zegar i Data Centralna ---
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
            // PLUSY na górze (Y=218..222) pozioma kreska, (Y=210..230) pionowa
            if (vga_in.vcount >= 210 && vga_in.vcount <= 230) begin
                if (vga_in.hcount >= 383 && vga_in.hcount <= 387) draw_pm_text = 1'b1; // H
                if (vga_in.hcount >= 463 && vga_in.hcount <= 467) draw_pm_text = 1'b1; // M
                if (vga_in.hcount >= 563 && vga_in.hcount <= 567) draw_pm_text = 1'b1; // D
                if (vga_in.hcount >= 643 && vga_in.hcount <= 647) draw_pm_text = 1'b1; // Mo
            end
            if (vga_in.vcount >= 218 && vga_in.vcount <= 222) begin
                if (vga_in.hcount >= 375 && vga_in.hcount <= 395) draw_pm_text = 1'b1; // H
                if (vga_in.hcount >= 455 && vga_in.hcount <= 475) draw_pm_text = 1'b1; // M
                if (vga_in.hcount >= 555 && vga_in.hcount <= 575) draw_pm_text = 1'b1; // D
                if (vga_in.hcount >= 635 && vga_in.hcount <= 655) draw_pm_text = 1'b1; // Mo
            end
            
            // MINUSY na dole (Y=368..372) pozioma kreska
            if (vga_in.vcount >= 368 && vga_in.vcount <= 372) begin
                if (vga_in.hcount >= 375 && vga_in.hcount <= 395) draw_pm_text = 1'b1; // H
                if (vga_in.hcount >= 455 && vga_in.hcount <= 475) draw_pm_text = 1'b1; // M
                if (vga_in.hcount >= 555 && vga_in.hcount <= 575) draw_pm_text = 1'b1; // D
                if (vga_in.hcount >= 635 && vga_in.hcount <= 655) draw_pm_text = 1'b1; // Mo
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
                    STATE_MONITOR: if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_HISTORY;
                    STATE_HISTORY: if (mouse_x > 800 && mouse_x < 950 && mouse_y > 600 && mouse_y < 670) current_state <= STATE_MONITOR;
                endcase
            end
        end
    end

    // --- GEOMETRIA TŁA ---
    logic draw_border, draw_button_main, draw_button_setup, in_ecg_zone;

    always_comb begin
        draw_border = 1'b0; draw_button_main = 1'b0; draw_button_setup = 1'b0; in_ecg_zone = 1'b0;
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
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
            end
            STATE_HISTORY: begin
                if ((vga_in.hcount >= 30 && vga_in.hcount <= 740 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 30 || vga_in.hcount == 740))) draw_border = 1'b1;
                if ((vga_in.hcount >= 780 && vga_in.hcount <= 990 && (vga_in.vcount == 90 || vga_in.vcount == 730)) || (vga_in.vcount >= 90 && vga_in.vcount <= 730 && (vga_in.hcount == 780 || vga_in.hcount == 990))) draw_border = 1'b1;
                if (vga_in.hcount > 800 && vga_in.hcount < 950 && vga_in.vcount > 600 && vga_in.vcount < 670) draw_button_main = 1'b1;
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

            if (txt_header || txt_btn1 || draw_pm_text || main_time_pixel || main_date_pixel || setup_time_pixel || setup_date_pixel) 
                                                vga_out.rgb <= COLOR_TEXT_W;
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