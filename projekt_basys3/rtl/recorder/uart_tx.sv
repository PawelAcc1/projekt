module uart_tx #(
    parameter DATA_BITS = 8,
    parameter logic [1:0] STOP_BITS = 2'b01,
    parameter logic PARITY_CHECK = 1'b0,
    parameter TICKS = 16
)(
    input  logic clk,
    input  logic rst_n,
    input  logic tick_enable,
    input  logic [DATA_BITS-1:0] data_in,
    input  logic tx_start,
    output logic tx,
    output logic tx_done
);

enum logic [2:0] {IDLE, START, DATA, PARITY, STOP} state, state_nxt;
logic [$clog2(DATA_BITS)-1:0] bit_counter, bit_counter_nxt;
logic [$clog2(TICKS)-1:0] tick_counter, tick_counter_nxt;
logic [DATA_BITS-1:0] data_buffer;
logic parity;
logic shift_buffer;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= IDLE;
        bit_counter <= '0;
        tick_counter <= '0;
        data_buffer <= '0;
        parity <= 1'b0;
        tx_done <= 1'b0;
    end
    else begin
        tx_done <= 1'b0; 

        // Natychmiastowe przechwycenie sygnału startu (100MHz), omijające dzielnik zegara
        if(state == IDLE && tx_start) begin
            state <= START;
            data_buffer <= data_in;
            parity <= ^data_in;
            tick_counter <= '0;
            bit_counter <= '0;
        end
        else if(tick_enable) begin
            state <= state_nxt;
            bit_counter <= bit_counter_nxt;
            tick_counter <= tick_counter_nxt;
            
            if(shift_buffer) begin
                data_buffer <= {1'b0, data_buffer[DATA_BITS-1:1]};
            end

            if(state == STOP && tick_counter == 4'b1111 && bit_counter == (STOP_BITS - 1)) begin
                tx_done <= 1'b1;
            end
        end
    end
end

always_comb begin
    state_nxt = state;
    bit_counter_nxt = bit_counter;
    tick_counter_nxt = tick_counter;
    tx = 1'b1;
    shift_buffer = 1'b0;

    case(state) 
        IDLE: begin
            // Logika przejścia przeniesiona do bloku sekwencyjnego dla bezpiecznego przechwycenia
            state_nxt = IDLE; 
        end
        START: begin
            tx = 1'b0;
            if(tick_counter == 4'b1111) begin
                state_nxt = DATA;
                tick_counter_nxt = '0;
                bit_counter_nxt = '0;
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
            end
        end
        DATA: begin
            tx = data_buffer[0];
            
            if(tick_counter == 4'b1111) begin
                tick_counter_nxt = '0;
                if(bit_counter == (DATA_BITS - 1)) begin
                    state_nxt = (PARITY_CHECK) ? PARITY : STOP;
                    bit_counter_nxt = '0;
                end
                else begin
                    bit_counter_nxt = bit_counter + 1;
                    shift_buffer = 1'b1;
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
            end
        end
        PARITY: begin
            tx = parity;
            
            if(tick_counter == 4'b1111) begin
                state_nxt = STOP;
                tick_counter_nxt = '0;
                bit_counter_nxt = '0;
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
            end
        end
        STOP: begin
            if(tick_counter == 4'b1111) begin
                tick_counter_nxt = '0;
                if(bit_counter == (STOP_BITS - 1)) begin
                    state_nxt = IDLE;
                end
                else begin
                    bit_counter_nxt = bit_counter + 1;
                end
            end
            else begin
                tick_counter_nxt = tick_counter + 1;
            end
        end
    endcase
end
endmodule