/*
 * This module provides STEMI detection. STEMI stands for ST-Elevation Myocardial Infarction, which is 
 * ST segment elevation comparing to baseline level.
 * This is the most serious and sudden form of heart attack 
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
    // PRÓG DETEKCJI - dwa tryby (wybór przez USE_RATIO):
    //
    // 1) USE_RATIO=1 (domyślny, ZALECANY): próg RATIOMETRYCZNY względem amplitudy
    //    załamka R danego uderzenia:  próg = (R_amp * RATIO_NUM) >> RATIO_SHIFT.
    //    Uniesienie ST jest fizjologicznie ułamkiem amplitudy R (~0.1..0.2 R)
    // 2) USE_RATIO=0: próg STAŁY = STEMI_THRESHOLD
    parameter USE_RATIO       = 1,  // 1 = próg ratiometryczny, 0 = stały
    parameter RATIO_NUM       = 5,  // licznik: próg = R_amp * RATIO_NUM >> RATIO_SHIFT
    parameter RATIO_SHIFT     = 5,  // 5/32 ~= 0.156 * amplituda R
    parameter RATIO_FLOOR     = 12, // dolny limit progu (ochrona przy małym/ujemnym R)
    parameter STEMI_THRESHOLD = 20, // próg STAŁY (używany gdy USE_RATIO=0)
    parameter DATA_WIDTH = 16,
    parameter DERIVATIVE_MARGIN = 20, // próg "płaskości" pochodnej do śledzenia baseline
    parameter CONSECUTIVE_BEATS = 2, // stemi debounce
    parameter SAMPLES_TO_J_POINT = 76,
    parameter SAMPLES_FOR_AVERAGE = 8
)(
    input  logic clk,
    input  logic rst_n,
    input logic clear,
    input logic signed [DATA_WIDTH-1:0] ecg_data_in,
    input logic signed [DATA_WIDTH-1:0] derivative_data_in,

    //samples validation
    input logic data_sample_valid_in,
    input logic derivative_sample_valid_in,

    input logic r_peak_detected,

    //alarm
    output logic stemi_alarm
);

//baseline tracking purpose registers
logic signed [DATA_WIDTH-1:0] baseline_candidate;
logic signed [DATA_WIDTH-1:0] baseline_locked, baseline_locked_nxt;

//inner counters for fsm
logic [($clog2(SAMPLES_TO_J_POINT))-1:0] delay_counter, delay_counter_nxt;
logic [($clog2(SAMPLES_FOR_AVERAGE)):0] st_samples_counter, st_samples_counter_nxt;

//accumulator for averaging
logic signed [(DATA_WIDTH-1)+3:0] st_accumulator, st_accumulator_nxt;

//alarms variables
logic stemi_alarm_nxt;

//stemi beats counter for debouncing
logic [$clog2(CONSECUTIVE_BEATS+1)-1:0] elevated_streak, elevated_streak_nxt;

//peak-hold of R-peak amplitude
//running_max - current max ecg_data_in since last R-peak
//r_peak_amplitude - latched R amplitude above baseline
logic signed [DATA_WIDTH-1:0] running_max;
logic signed [DATA_WIDTH:0]   r_peak_amplitude;

enum logic [2:0] {IDLE, R_DETECTED, J_POINT, EVALUATE} state, state_nxt;

//baseline tracker
logic signed [DATA_WIDTH-1:0] abs_deriv;
assign abs_deriv = (derivative_data_in < 0) ? -derivative_data_in : derivative_data_in; //abs() function

logic [4:0] flat_counter;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        baseline_candidate <= '0;
        flat_counter <= '0;
    end
    else if (clear) begin
        baseline_candidate <= '0;
        flat_counter <= '0;
    end
    else begin
        if(derivative_sample_valid_in) begin
            if (abs_deriv <= DERIVATIVE_MARGIN) begin

                if (flat_counter >= 5'd20) begin
                    baseline_candidate <= ecg_data_in;
                end else begin
                    flat_counter <= flat_counter + 1'b1;
                end
                
            end
            else begin
                flat_counter <= '0;
            end
        end
    end
end

//peak-hold R amplitude tracker(max - baseline)
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        running_max      <= '0;
        r_peak_amplitude <= '0;
    end
    else if (clear) begin
        running_max      <= '0;
        r_peak_amplitude <= '0;
    end
    else begin
        if (r_peak_detected) begin
            r_peak_amplitude <= running_max - baseline_candidate; // R_amp nad linią bazową
            running_max      <= ecg_data_in;                      // start nowego uderzenia
        end
        else if (data_sample_valid_in && (ecg_data_in > running_max)) begin
            running_max <= ecg_data_in;
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
        elevated_streak <= '0;
    end
    else if (clear) begin
        state <= IDLE;
        baseline_locked <= '0;
        stemi_alarm <= 1'b0;
        delay_counter <= '0;
        st_samples_counter <= '0;
        st_accumulator <= '0;
        elevated_streak <= '0;
    end
    else begin
        state <= state_nxt;
        delay_counter <= delay_counter_nxt;
        st_samples_counter <= st_samples_counter_nxt;
        st_accumulator <= st_accumulator_nxt;
        baseline_locked <= baseline_locked_nxt;
        stemi_alarm <= stemi_alarm_nxt;
        elevated_streak <= elevated_streak_nxt;
    end
end

always_comb begin
    state_nxt = state;
    delay_counter_nxt = delay_counter;
    st_samples_counter_nxt = st_samples_counter;
    st_accumulator_nxt = st_accumulator;
    baseline_locked_nxt = baseline_locked;
    stemi_alarm_nxt = stemi_alarm;
    elevated_streak_nxt = elevated_streak;

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
        // J point average measurement
        J_POINT: begin
            if (data_sample_valid_in) begin
                st_accumulator_nxt = st_accumulator + ecg_data_in;
                if (st_samples_counter == SAMPLES_FOR_AVERAGE - 1) begin
                    state_nxt = EVALUATE;
                end
                else begin
                    st_samples_counter_nxt = st_samples_counter + 1'b1;
                end
            end
        end
        //STEMI alarm assessment (with glitch debouncing)
        EVALUATE: begin
            automatic logic signed [(DATA_WIDTH-1)+3:0] st_average;
            //dynamic treshold
            automatic logic signed [DATA_WIDTH+8:0] ratio_thr;
            automatic logic signed [DATA_WIDTH+8:0] dyn_threshold;

            st_average = st_accumulator >>> $clog2(SAMPLES_FOR_AVERAGE);
            ratio_thr  = (r_peak_amplitude * RATIO_NUM) >>> RATIO_SHIFT;

            if (USE_RATIO == 0) begin
                dyn_threshold = STEMI_THRESHOLD;
            end
            else if (r_peak_amplitude <= 0 || ratio_thr < RATIO_FLOOR) begin
                dyn_threshold = RATIO_FLOOR;          // too little treshold protection
            end
            else begin
                dyn_threshold = ratio_thr;
            end

            if (st_average - baseline_locked_nxt >= dyn_threshold) begin
                if (elevated_streak >= (CONSECUTIVE_BEATS - 1)) begin
                    stemi_alarm_nxt = 1'b1;            
                end
                else begin
                    elevated_streak_nxt = elevated_streak + 1'b1;
                end
            end
            else begin
                elevated_streak_nxt = '0;
                stemi_alarm_nxt = 1'b0;
            end
            state_nxt = IDLE;
        end
    endcase
end

endmodule
