module ring_buffer #(
    parameter WIDTH = 12,
    parameter ADDR = 10
)(
    input logic clk,
    input logic rst_n,
    input logic write_enable,
    input logic [WIDTH-1:0] ecg_data_write,
    input logic [ADDR-1:0] read_address,
    output logic [WIDTH-1:0] ecg_data_read
);

//memory
localparam DEPTH = 2**ADDR;
logic [WIDTH-1:0] memory [0:DEPTH-1];

//data register


//address counter
logic [ADDR-1:0] write_address;

initial begin
    for(int i = 0; i < DEPTH; i++) begin
        memory[i] = 12'h7d0; //initilize to half of the value span
    end
end

//internal write address counter
always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        write_address <= '0;
    end
    else begin
        if(write_enable) begin
            write_address <= write_address + 1'b1;
        end
        else begin
            write_address <= write_address;
        end
    end
end

//memory read and write
always_ff @(posedge clk) begin
    if(write_enable) begin
        memory[write_address] <= ecg_data_write;
    end

    ecg_data_read <= memory[read_address];
end
endmodule