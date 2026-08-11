`timescale 1ns / 1ps

module bpm_calculator (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_tick,
    input  logic r_peak_detected,
    input  logic [10:0] min_rr_samples,

    output logic [7:0] bpm,
    output logic bpm_valid,
    output logic [7:0] bpm_instant,
    output logic bpm_instant_valid
);

    localparam logic [10:0] MAX_RR_SAMPLES = 11'd2000;

    logic [10:0] active_min_rr_samples;
    assign active_min_rr_samples = (min_rr_samples == 11'd0) ? 11'd150 : min_rr_samples;

    logic [10:0] sample_count;
    logic [7:0]  bpm_history [0:7];
    logic [3:0]  bpm_history_count;
    logic [11:0] bpm_history_sum;
    logic        timeout_fired;
    logic        have_reference_peak;

    logic [7:0] bpm_rom [0:2047];
    initial begin
        $readmemh("bpm_rom.hex", bpm_rom);
    end

    // --- REJESTRY TYMCZASOWE (PIPELINE) ---
    logic [10:0] captured_count;
    logic        calc_stage_1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_count  <= '0;
            bpm           <= '0;
            bpm_valid     <= 1'b0;
            bpm_instant   <= '0;
            bpm_instant_valid <= 1'b0;
            timeout_fired <= 1'b0;
            have_reference_peak <= 1'b0;
            bpm_history_count <= '0;
            bpm_history_sum   <= '0;
            captured_count    <= '0;
            calc_stage_1      <= 1'b0;
            for (int i = 0; i < 8; i++)
                bpm_history[i] <= '0;
        end
        else begin
            bpm_valid <= 1'b0;
            bpm_instant_valid <= 1'b0;

            if (sample_tick) begin
                if (sample_count < 11'd2047)
                    sample_count <= sample_count + 1;

                // timeout: brak R przez 2000 probek
                if (!timeout_fired && (sample_count > MAX_RR_SAMPLES)) begin
                    bpm           <= 8'd0;
                    bpm_valid     <= 1'b1;
                    bpm_instant   <= 8'd0;
                    timeout_fired <= 1'b1;
                    have_reference_peak <= 1'b0;
                    bpm_history_count <= '0;
                    bpm_history_sum   <= '0;
                    calc_stage_1      <= 1'b0;
                    for (int i = 0; i < 8; i++)
                        bpm_history[i] <= '0;
                end
            end

            if (r_peak_detected) begin
                if (sample_count >= active_min_rr_samples && sample_count <= MAX_RR_SAMPLES) begin
                    timeout_fired <= 1'b0;
                    if (!have_reference_peak) begin
                        have_reference_peak <= 1'b1;
                        sample_count <= '0;
                    end
                    else begin
                        // STEP1: Latch data for following clock cycle
                        captured_count <= sample_count;
                        calc_stage_1   <= 1'b1;
                        sample_count   <= '0;
                    end
                end
                else if (sample_count > MAX_RR_SAMPLES) begin
                    timeout_fired <= 1'b0;
                    have_reference_peak <= 1'b1;
                    bpm_history_count <= '0;
                    bpm_history_sum   <= '0;
                    calc_stage_1      <= 1'b0;
                    for (int i = 0; i < 8; i++)
                        bpm_history[i] <= '0;
                    sample_count <= '0;
                end
            end
            else if (calc_stage_1) begin
                // STEP2: Calculate BPM
                automatic logic [7:0] current_bpm_raw;
                automatic logic [11:0] next_history_sum;
                automatic logic [3:0] next_history_count;

                current_bpm_raw = bpm_rom[captured_count];
                bpm_instant <= current_bpm_raw;
                bpm_instant_valid <= 1'b1;

                next_history_sum = bpm_history_sum + {4'b0, current_bpm_raw};
                next_history_count = (bpm_history_count < 4'd8)
                                   ? (bpm_history_count + 4'd1)
                                   : 4'd8;
                                   
                if (bpm_history_count == 4'd8)
                    next_history_sum = next_history_sum - {4'b0, bpm_history[7]};

                for (int i = 7; i > 0; i--)
                    bpm_history[i] <= bpm_history[i-1];
                bpm_history[0] <= current_bpm_raw;

                bpm_history_sum   <= next_history_sum;
                bpm_history_count <= next_history_count;
                
                bpm <= (next_history_count == 4'd8)
                     ? ((next_history_sum + 12'd4) >> 3)
                     : current_bpm_raw;

                bpm_valid    <= 1'b1;
                calc_stage_1 <= 1'b0; // Zero math stage flag
            end
        end
    end

endmodule