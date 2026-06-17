module tick_generator #(
    parameter BAUDRATE_DIV = 54 // system clock / baudrate * oversampling
)(
    input logic clk,
    input logic rst_n,
    output logic tick
);

logic [$clog2(BAUDRATE_DIV)-1:0] counter;

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        counter <= 0;
        tick <= 0;
    end
    else begin
        if(counter == (BAUDRATE_DIV - 1)) begin
            tick <= 1;
            counter <= 0;
        end
        else begin
            tick <= 0;
            counter <= counter + 1;
        end
    end
end

endmodule