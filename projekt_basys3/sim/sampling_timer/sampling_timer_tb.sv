`timescale 1ns / 1ps


module sampling_timer_tb;

    logic tb_clk;
    logic tb_rst_n;

    wire tb_start_sampling;

    sampling_timer #(
        .CLK_FREQ(10),        
        .SAMPLING_RATE(2)     
    ) uut (
        .clk(tb_clk),                         
        .rst_n(tb_rst_n),                     
        .start_sampling(tb_start_sampling)   
    );

    always begin
        #5 tb_clk = ~tb_clk; 
    end

    initial begin
        tb_clk = 0;
        tb_rst_n = 0;

        #2;             
        tb_rst_n = 1;   
        #20;            

        tb_rst_n = 0;   

        #400;         

        $finish;       
    end

endmodule
