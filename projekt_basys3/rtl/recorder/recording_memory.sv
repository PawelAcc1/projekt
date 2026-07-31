module recording_memory #(
    parameter DATA_BITS = 16, 
    parameter RECORDING_DURATION = 20, // recording duration in seconds

    localparam SAMPLING_FREQ = 500, // sampling frequency in Hz
    localparam MAX_SAMPLES = RECORDING_DURATION * SAMPLING_FREQ,
    localparam ADDR_BITS = $clog2(MAX_SAMPLES) // number of bits for address counter
)(
    input logic clk,
    input logic rst_n,

    //i2c signals
    input logic i2c_data_ready,
    input logic [(DATA_BITS-1):0] i2c_data,

    //external signal
    input logic start_recording,

    //hex_to_ascii signals
    input logic [(ADDR_BITS - 1):0] read_address,
    output logic [(DATA_BITS-1):0] read_data,
    output logic memory_full
);

    // BRAM definition
    (* ram_style = "block" *) logic [(DATA_BITS-1):0] ecg_ram [0:MAX_SAMPLES-1];

    // address counter
    logic [ADDR_BITS-1:0] address_counter, address_counter_nxt;

    // FSM states
    enum logic [1:0] {IDLE, RECORD, FULL} state, state_nxt;

    // ==============================================================
    // 1. BLOK FSM I LICZNIKÓW 
    // ==============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            address_counter <= '0;
            state <= IDLE;
        end 
        else begin
            state <= state_nxt;
            address_counter <= address_counter_nxt;
        end
    end

    // ==============================================================
    // 2. DEDYKOWANY BLOK BRAM 
    // ==============================================================
    always_ff @(posedge clk) begin
        // BRAM write condition 
        if (state == RECORD && i2c_data_ready) begin
            ecg_ram[address_counter] <= i2c_data;
        end

        // memory read condition 
        if (state == FULL) begin
            read_data <= ecg_ram[read_address];
        end
    end

    // ==============================================================
    // 3. LOGIKA KOMBINACYJNA
    // ==============================================================
    assign memory_full = (state == FULL);

    always_comb begin
        state_nxt = state;
        address_counter_nxt = address_counter;

        case (state)
            // waiting for start_recording signal
            IDLE: begin
                if (start_recording) begin
                    state_nxt = RECORD;
                    address_counter_nxt = '0;
                end
            end
            
            // recording data to BRAM
            RECORD: begin
                if (i2c_data_ready) begin
                    if (address_counter == MAX_SAMPLES - 1) begin
                        state_nxt = FULL;
                    end
                    else begin
                        address_counter_nxt = address_counter + 1'b1;
                    end
                end
            end
            
            // BRAM is full
            FULL: begin
                if (start_recording) begin
                    state_nxt = RECORD;
                    address_counter_nxt = '0;
                end
            end
            
            default: state_nxt = IDLE;
        endcase
    end

endmodule