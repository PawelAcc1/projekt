module spi_slave_rx (
    input logic clk,
    input logic spi_clk,
    input logic rst_n,
    input logic mosi,
    input logic cs_n,
    output logic [11:0] ecg_data,
    output logic data_valid
);
//buffers
/*
 * variable[0] is unstable new received bit
 * variable[1] is stable new received bit
 * variable[2] is previous recieved bit
*/
logic [2:0] spi_clk_buffer;
logic [2:0] mosi_buffer;
logic [2:0] cs_n_buffer;

//spi frame consists of 16 bits
logic [15:0] data_reg;

wire spi_clk_rising_edge_detected;
wire cs_n_rising_edge_detected;

assign spi_clk_rising_edge_detected = ((spi_clk_buffer[2] == 1'b0) && (spi_clk_buffer[1] == 1'b1));
assign cs_n_rising_edge_detected = ((cs_n_buffer[2] == 1'b0) && (cs_n_buffer[1] == 1'b1));

//antimetastability buffering
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        spi_clk_buffer <= '0;
        mosi_buffer <= '0;
        cs_n_buffer <= '1;
    end
    else begin
        spi_clk_buffer <= {spi_clk_buffer[1:0],  spi_clk};
        mosi_buffer <= {mosi_buffer[1:0], mosi};
        cs_n_buffer <= {cs_n_buffer[1:0], cs_n};
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        ecg_data <= '0;
        data_reg <= '0;
        data_valid <= '0;
    end
    else begin
        data_valid <= 1'b0;

        if((cs_n_buffer[1] == 1'b0) && (spi_clk_rising_edge_detected == 1'b1)) begin
            //shifting spi data to data register
            data_reg <= {data_reg[14:0], mosi_buffer[1]};
        end
        else if(cs_n_rising_edge_detected == 1'b1) begin
            ecg_data <= data_reg[11:0]; //spi frame is 16 bits but adc data is 12 bits
            data_valid <= 1'b1;
        end
    end
end

endmodule