module uart_rx #(
    parameter DATA_BITS = 8,
    parameter logic PARITY_CHECK = 1'b0,
    parameter logic [1:0] STOP_BITS = 2'b01,
    parameter TICKS = 16
)(
    input logic clk,
    input logic rst_n,
    input logic tick_enable,
    input logic rx,
    output logic [DATA_BITS-1:0] received_data,
    output logic rx_done
);

enum logic [2:0] {IDLE, START, DATA, PARITY, STOP} state, state_nxt;
logic [$clog2(DATA_BITS)-1:0] bit_counter, bit_counter_nxt;
logic [$clog2(TICKS)-1:0] tick_counter, tick_counter_nxt;
logic [DATA_BITS-1:0] data_buffer;
logic write_bit;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= IDLE;
        bit_counter <= '0;
        tick_counter <= '0;
        data_buffer <= '0;
        rx_done <= 1'b0;
    end
    else begin
        rx_done <= 1'b0; 
        if(tick_enable) begin
            state <= state_nxt;
            bit_counter <= bit_counter_nxt;
            tick_counter <= tick_counter_nxt;
            
            if(write_bit) begin
                data_buffer <= {rx, data_buffer[DATA_BITS-1:1]};
            end
            
            if (state == STOP && tick_counter == 4'b1111) begin
                if(bit_counter == STOP_BITS - 1'b1) begin
                    rx_done <= 1'b1;
                end
            end
        end
    end
end

always_comb begin
    state_nxt = state;
    bit_counter_nxt = bit_counter;
    tick_counter_nxt = tick_counter;
    write_bit = 1'b0;

    case(state) 
        IDLE: begin
            if(rx == 1'b0) begin
                tick_counter_nxt = '0;
                state_nxt = START;
            end
            else begin
                state_nxt = IDLE;
            end
        end
        START: begin
            if(tick_counter == 4'b0111) begin
                if(rx == 1'b0) begin
                    state_nxt = DATA;
                    bit_counter_nxt = '0;
                    tick_counter_nxt = '0;
                end
                else begin
                    state_nxt = IDLE;
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
                state_nxt = START;
            end
        end
        DATA: begin
            if(tick_counter == 4'b1111) begin
                write_bit = 1'b1;
                tick_counter_nxt = '0;
                
                if(bit_counter == (DATA_BITS - 1)) begin
                    state_nxt = (PARITY_CHECK) ? PARITY : STOP;
                    bit_counter_nxt = '0;
                end
                else begin
                    state_nxt = DATA;
                    bit_counter_nxt = bit_counter + 1;
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
                state_nxt = DATA;
            end
        end
        PARITY: begin
            if(tick_counter == 4'b1111) begin
                tick_counter_nxt = '0;
                if(^data_buffer == rx) begin
                    state_nxt = STOP;
                end
                else begin
                    state_nxt = IDLE;
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
                state_nxt = PARITY;
            end
        end
        STOP: begin
            if(tick_counter == 4'b1111) begin
                tick_counter_nxt = '0;
                if(bit_counter == STOP_BITS - 1'b1) begin
                    state_nxt = IDLE;
                end
                else begin
                    if(rx == 1'b1) begin
                        bit_counter_nxt = bit_counter + 1;
                        state_nxt = STOP;
                    end
                    else begin
                        state_nxt = IDLE;
                    end
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
                state_nxt = STOP;
            end
        end
    endcase
end

assign received_data = data_buffer;
endmodule