module mouse_event_generator(
    input logic clk,
    input logic rst_n,
    input logic [11:0] x_pos,
    input logic [11:0] y_pos,
    input logic right,
    input logic left,
    output logic right_flag,
    output logic left_flag,
    output logic [11:0] x_pos_latch,
    output logic [11:0] y_pos_latch
);

logic right_prev;
logic left_prev;

//previous state 1 bit memory
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        right_prev <= '0;
        left_prev <= '0;
    end
    else begin
        right_prev <= right;
        left_prev <= left;
    end
end

//rising edge event detectio 
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        right_flag <= '0;
        left_flag <= '0;
        x_pos_latch <= '0;
        y_pos_latch <= '0;
    end
    else begin
        left_flag <= '0;
        right_flag <= '0;

        // Left button pushed
        if(left_prev == 1'b0 && left == 1'b1) begin
            left_flag <= 1'b1;
        end

        // Right button pushed
        if(right_prev == 1'b0 && right == 1'b1) begin
            right_flag <= 1'b1;
            x_pos_latch <= x_pos;
            y_pos_latch <= y_pos;
        end
    end
end


endmodule