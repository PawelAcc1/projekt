module hex_to_ascii #(
    parameter DATA_BITS = 16, 
    parameter RECORDING_DURATION = 20, // recording duration in seconds
    parameter UART_DATA_BITS = 8,

    localparam SAMPLING_FREQ = 500, // sampling frequency in Hz
    localparam MAX_SAMPLES = RECORDING_DURATION * SAMPLING_FREQ,
    localparam ADDR_BITS = $clog2(MAX_SAMPLES)
)(
    input logic clk,
    input logic rst_n,

    //uart_rx signals
    input logic rx_done,
    input logic [UART_DATA_BITS-1:0] rx_data,

    //uart_tx signals
    input logic tx_done,
    output logic [UART_DATA_BITS-1:0] tx_data,
    output logic tx_data_ready,

    //BRAM signals
    input logic memory_full,
    input logic [(DATA_BITS-1):0] read_data,
    output logic [(ADDR_BITS - 1):0] read_address
);

//FSM states
enum logic [3:0] {
    IDLE, 
    TERMINAL_READY,
    FETCH, 
    NIBBLE_4, 
    NIBBLE_3, 
    NIBBLE_2, 
    NIBBLE_1,
    CARRIAGE_RETURN,
    NEW_LINE
} state, state_nxt;

//address counter
logic [ADDR_BITS-1:0] address_counter, address_counter_nxt;

//Tx buffers
logic [UART_DATA_BITS-1:0] tx_data_nxt;
logic tx_data_ready_nxt;

//Tx flag
logic tx_started, tx_started_nxt;

//HEX to ASCII converter
function automatic logic [7:0] nibble_to_ascii (input logic [3:0] nibble);
    if(nibble <= 4'h9) begin
        return nibble + 8'h30;
    end
    else begin
        return nibble + 8'h37;
    end
endfunction

//Constants for transmission
localparam logic [7:0] CARRIAGE_RETURN_CHAR = 8'h0D; // \r
localparam logic [7:0] NEW_LINE_CHAR        = 8'h0A; // \n

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= IDLE;
        tx_data <= '0;
        address_counter <= '0;
        tx_data_ready <= 1'b0;
        tx_started <= 1'b0;
    end
    else begin
        state <= state_nxt;
        address_counter <= address_counter_nxt;
        tx_data <= tx_data_nxt;
        tx_data_ready <= tx_data_ready_nxt;
        tx_started <= tx_started_nxt;
    end
end

always_comb begin
    state_nxt = state;
    address_counter_nxt = address_counter;
    tx_data_nxt = tx_data;
    tx_started_nxt = tx_started;
    tx_data_ready_nxt = 1'b0;

    case (state)
        IDLE: begin
            if(rx_done) begin
                if(rx_data == 8'h72) begin //"r" letter received means terminal is ready
                    state_nxt = TERMINAL_READY;
                end
            end
        end
        TERMINAL_READY: begin
            if(memory_full) begin
                state_nxt = FETCH;
                address_counter_nxt = '0;
            end
        end
        FETCH: begin
            state_nxt = NIBBLE_4;
            tx_started_nxt = 1'b0;
        end
        NIBBLE_4: begin
                tx_data_nxt = nibble_to_ascii(read_data[15:12]);
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1; // Generujemy impuls 1-taktowy
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0; // Resetujemy flagę przed kolejnym stanem
                    state_nxt = NIBBLE_3;
                end
            end

            NIBBLE_3: begin
                tx_data_nxt = nibble_to_ascii(read_data[11:8]);
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1;
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0;
                    state_nxt = NIBBLE_2;
                end
            end

            NIBBLE_2: begin
                tx_data_nxt = nibble_to_ascii(read_data[7:4]);
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1;
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0;
                    state_nxt = NIBBLE_1;
                end
            end

            NIBBLE_1: begin
                tx_data_nxt = nibble_to_ascii(read_data[3:0]);
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1;
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0;
                    state_nxt = CARRIAGE_RETURN;
                end
            end

            CARRIAGE_RETURN: begin
                tx_data_nxt = CARRIAGE_RETURN_CHAR;
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1;
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0;
                    state_nxt = NEW_LINE;
                end
            end

            NEW_LINE: begin
                tx_data_nxt = NEW_LINE_CHAR;
                if (!tx_started) begin
                    tx_data_ready_nxt = 1'b1;
                    tx_started_nxt = 1'b1;
                end
                
                if (tx_done) begin
                    tx_started_nxt = 1'b0;
                    if (address_counter == MAX_SAMPLES - 1) begin
                        state_nxt = IDLE;
                    end
                    else begin
                        address_counter_nxt = address_counter + 1'b1;
                        state_nxt = FETCH;
                    end
                end
            end
            
            default: state_nxt = IDLE;
        endcase
end

assign read_address = address_counter;
endmodule 