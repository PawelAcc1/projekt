module gui_event_control (
    input logic clk,
    input logic rst_n,

    input logic [11:0] x_pos,
    input logic [11:0] y_pos,
    input logic right_click_pulse,
    input logic left_click_pulse,

    //information form hitbox layer
    input logic in_set_time_hitbox,
    input logic in_confirm_time_hitbox,
    input logic in_time_menu_hitbox,
    
    //enabling flags to hitbox layer
    output logic enable_menu,
    output logic enable_time,

    //vga control signals
    output logic [11:0] x_draw_init,
    output logic [11:0] y_draw_init,
    output logic [2:0] draw_gui,
    output logic load_time

);

enum logic [2:0] {
    IDLE, 
    CONTEXT_MENU,
    SET_TIME
} state, state_nxt;

logic enable_menu_nxt;
logic enable_time_nxt;
logic [2:0] draw_gui_nxt;
logic [11:0] x_draw_init_nxt;
logic [11:0] y_draw_init_nxt;
logic load_time_nxt;


always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        enable_menu <= '0;
        enable_time <= '0;
        x_draw_init <= '0;
        y_draw_init <= '0;
        draw_gui <= '0;
        load_time <= '0;
    end
    else begin
        state <= state_nxt;
        enable_menu <= enable_menu_nxt;
        enable_time <= enable_time_nxt;
        draw_gui <= draw_gui_nxt;
        load_time <= load_time_nxt;
        x_draw_init <= x_draw_init_nxt;
        y_draw_init <= y_draw_init_nxt;
    end
end

always_comb begin
    state_nxt = state;
    enable_menu_nxt = enable_menu;
    enable_time_nxt = enable_time;
    draw_gui_nxt = draw_gui;
    x_draw_init_nxt = x_draw_init;
    y_draw_init_nxt = y_draw_init;
    load_time_nxt = 1'b0;

    case (state) 
        IDLE: begin
            enable_menu_nxt = 1'b0;
            enable_time_nxt = 1'b0;
            draw_gui_nxt = 4'b0000; //code for pass through view
            if(right_click_pulse) begin
                state_nxt = CONTEXT_MENU;
                enable_menu_nxt = '1;
                enable_time_nxt = '0;
                draw_gui_nxt = 4'b0001; //code for context menu view
                x_draw_init_nxt = x_pos;
                y_draw_init_nxt = y_pos;
            end
            else begin
                state_nxt = IDLE;
            end
        end

        CONTEXT_MENU: begin
            if (left_click_pulse == 1'b1) begin
                if (in_set_time_hitbox == 1'b1) begin
                    state_nxt = SET_TIME;
                    enable_menu_nxt = 1'b0;
                    enable_time_nxt = 1'b1;
                    draw_gui_nxt = 4'b0010; //code for time menu view
                end
                else begin
                    state_nxt = IDLE;
                end
            end
            else if (right_click_pulse == 1'b1) begin
                state_nxt = CONTEXT_MENU;
                x_draw_init_nxt = x_pos;
                y_draw_init_nxt = y_pos;
            end
        end

        SET_TIME: begin
            if (left_click_pulse == 1'b1) begin
                if (in_confirm_time_hitbox == 1'b1) begin
                    load_time_nxt = 1'b1;
                    state_nxt = IDLE; 
                end
                else if (in_time_menu_hitbox == 1'b0) begin
                    state_nxt = IDLE;
                end
            end
            else if (right_click_pulse == 1'b1) begin
                state_nxt = CONTEXT_MENU;
                enable_menu_nxt = 1'b1;
                enable_time_nxt = 1'b0;
                draw_gui_nxt = 3'b001; //code for context menu view
                x_draw_init_nxt = x_pos;
                y_draw_init_nxt = y_pos;
            end
        end
    endcase
end
endmodule