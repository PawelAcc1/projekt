module render_signal #(
    parameter WIDTH = 12,
    parameter ADDR = 10
)(
    input logic clk,
    input logic rst_n,
    input logic [WIDTH-1:0],
    vga_if.in vga_in,
    vga_if.out vga_out,
    output logic [ADDR-1:0] read_address
);



logic [11:0] rgb_nxt;

endmodule