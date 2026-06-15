/*
 * This module provides STEMI detection. STEMI stands for ST-Elevation Myocardial Infarction, which is 
 * ST segment elevation myocardial infarction. This is the most serious and sudden form of heart attack 
 * in which the main coronary artery is completely blocked.
 * 
 * To detect such patology we basically measure baseline level during PQ segment, then after R wave peak detection
 * which belongs to the QRS complex, we wait enough time for S wave to pass by and get to the J point which 
 * defines beginning of ST segment. It is sometimes recommended that ST segment deviation be measured in the J-60 point,
 * or J-80 point, which is located 60 and 80 milliseconds, respectively, after the J point. Therefore we wait enough samples
 * to achieve J-60 point and then we take 8 samples and average them and afterward we compare the average to baseline level.
 * Providing the elevation of ST segment is 0.1mV above the baseline level, we signalize STEMI.
 * 
*/

module stemi_detector #(
    parameter STEMI_THRESHOLD = 10,
    parameter DATA_WIDTH = 16,
    parameter DERIVATIVE_MARGIN = 5,
    parameter SAMPLES_TO_J_POINT = 30, // from R peak to J point is 30 samples or 60ms for fs = 500Hz
    parameter SAMPLES_FOR_AVERAGE = 8
)(
    input  logic clk,
    input  logic rst_n,
    input logic signed [DATA_WIDTH-1:0] ecg_data_in,
    input logic signed [DATA_WIDTH-1:0] derivative_data_in,

    //samples validation
    input logic data_sample_valid_in,
    input logic derivative_sample_valid_in,

    input logic r_peak_detected,

    //alarms
    output logic stemi_alarm
);

//baseline tracking purpose registers
logic signed [DATA_WIDTH-1:0] baseline_candidate;
logic signed [DATA_WIDTH-1:0] baseline_locked, baseline_locked_nxt;

//inner counters for fsm
logic [($clog2(SAMPLES_TO_J_POINT))-1:0] delay_counter, delay_counter_nxt;
logic [($clog2(SAMPLES_FOR_AVERAGE))-1:0] st_samples_counter, st_samples_counter_nxt;

//accumulator for averaging
logic signed [(DATA_WIDTH-1)+3:0] st_accumulator, st_accumulator_nxt;

//alarms varaibles
logic stemi_alarm_nxt;

enum logic [2:0] {IDLE, R_DETECTED, J_POINT, EVALUATE} state, state_nxt;

//baseline tracker
logic signed [DATA_WIDTH-1:0] abs_deriv;
assign abs_deriv = (derivative_data_in < 0) ? -derivative_data_in : derivative_data_in; //abs() function

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baseline_candidate <= '0;
    end
    else begin
        if(derivative_sample_valid_in) begin
            if (abs_deriv <= DERIVATIVE_MARGIN) begin
                baseline_candidate <= ecg_data_in;
            end 
        end
    end
end

//main stemi detector FSM
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        baseline_locked <= '0;
        stemi_alarm <= 1'b0;
        delay_counter <= '0;
        st_samples_counter <= '0;
        st_accumulator <= '0;
    end
    else begin
        state <= state_nxt;
        delay_counter <= delay_counter_nxt;
        st_samples_counter <= st_samples_counter_nxt;
        st_accumulator <= st_accumulator_nxt;
        baseline_locked <= baseline_locked_nxt;
        stemi_alarm <= stemi_alarm_nxt;
    end
end

always_comb begin
    state_nxt = state;
    delay_counter_nxt = delay_counter;
    st_samples_counter_nxt = st_samples_counter;
    st_accumulator_nxt = st_accumulator;
    baseline_locked_nxt = baseline_locked;
    stemi_alarm_nxt = stemi_alarm;

    case(state) 
        //R peak detection standby
        IDLE: begin
            if(r_peak_detected) begin
                state_nxt = R_DETECTED;
                baseline_locked_nxt = baseline_candidate;
                delay_counter_nxt = '0;
            end
        end
        //Delay after R peak detection
        R_DETECTED: begin
            if(data_sample_valid_in) begin
                if(delay_counter == SAMPLES_TO_J_POINT - 1) begin
                    state_nxt = J_POINT;
                    st_samples_counter_nxt = '0;
                    st_accumulator_nxt = '0;
                end
                else begin
                    delay_counter_nxt = delay_counter + 1'b1;
                end
            end
        end
        //J point average measurement
        J_POINT: begin
            if(st_samples_counter == SAMPLES_FOR_AVERAGE) begin
                state_nxt = EVALUATE;
            end
            else begin
                if(data_sample_valid_in) begin
                    st_accumulator_nxt = st_accumulator + ecg_data_in;
                    st_samples_counter_nxt = st_samples_counter + 1'b1;
                end
            end
        end
        //STEMI and NSTEMI alarm assement
        EVALUATE: begin
            automatic logic signed [(DATA_WIDTH-1)+3:0] st_average;
            st_average = st_accumulator >>> $clog2(SAMPLES_FOR_AVERAGE);

            if (st_average - baseline_locked_nxt >= STEMI_THRESHOLD) begin
                stemi_alarm_nxt = 1'b1;
            end
            else if (baseline_locked_nxt - st_average >= STEMI_THRESHOLD) begin
                stemi_alarm_nxt = 1'b0;
            end
            else begin
                stemi_alarm_nxt = 1'b0;
            end
            state_nxt = IDLE;
        end
    endcase
end

endmodule